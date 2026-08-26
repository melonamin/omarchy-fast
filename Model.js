// Pure formatting and parsing helpers for the Fast bar widget. Kept free of
// QML objects so the measurement model can be exercised with Node as well.

var BRAILLE_DOTS = [
  [0x01, 0x08],
  [0x02, 0x10],
  [0x04, 0x20],
  [0x40, 0x80]
]

function number(raw) {
  if (raw === undefined || raw === null) return null
  var text = String(raw).trim()
  if (text === "") return null
  var value = Number(text)
  return isFinite(value) && value >= 0 ? value : null
}

function appendSample(samples, raw, limit) {
  var value = number(raw)
  if (value === null) return Array.isArray(samples) ? samples.slice() : []

  var out = Array.isArray(samples) ? samples.slice() : []
  out.push(value)
  var cap = Math.max(1, parseInt(limit, 10) || 24)
  while (out.length > cap) out.shift()
  return out
}

function peak(samples) {
  var values = Array.isArray(samples) ? samples : []
  var result = 0
  for (var i = 0; i < values.length; i++) {
    var value = number(values[i])
    if (value !== null) result = Math.max(result, value)
  }
  return result
}

// Leave out the first second of a 10 Hz run while retaining the old small-set
// behavior for callers with coarse samples. Connection warm-up otherwise
// makes the settled result pessimistic and much jumpier than the trace.
function settledAverage(samples) {
  var values = Array.isArray(samples) ? samples : []
  var start = values.length >= 20 ? Math.min(10, Math.floor(values.length / 5))
    : values.length >= 3 ? 1 : 0
  var total = 0
  var count = 0
  for (var i = start; i < values.length; i++) {
    var value = number(values[i])
    if (value === null) continue
    total += value
    count++
  }
  return count > 0 ? total / count : 0
}

function formatRate(mbps) {
  var value = number(mbps)
  if (value === null) return { value: "—", unit: "Mbps" }
  if (value >= 999.95) return { value: (value / 1000).toFixed(1), unit: "Gbps" }
  return { value: value.toFixed(1), unit: "Mbps" }
}

function formatPeak(mbps) {
  var rate = formatRate(mbps)
  return rate.value === "—" ? "peak —" : "peak " + rate.value + " " + rate.unit
}

function formatPing(ms) {
  var value = number(ms)
  if (value === null) return "—"
  return (value < 10 ? value.toFixed(1) : String(Math.round(value))) + " ms"
}

function parseConnection(raw) {
  var parts = String(raw || "").replace(/\r?\n+$/, "").split("\t")
  var kind = parts[0] || "disconnected"
  if (kind === "wifi") return { kind: kind, label: parts[1] || "Wi-Fi" }
  if (kind === "ethernet") return { kind: kind, label: "Ethernet" }
  return { kind: "disconnected", label: "No connection" }
}

function parseDetails(raw) {
  var result = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var split = lines[i].indexOf("\t")
    if (split === -1) continue
    result[lines[i].slice(0, split)] = lines[i].slice(split + 1).trim()
  }
  return {
    ping: number(result.internet_ping_ms),
    iface: result.iface || "",
    kind: result.type || ""
  }
}

function normalizeHistoryEntry(entry) {
  if (!entry || typeof entry !== "object") return null
  var timestamp = number(entry.timestamp)
  var down = number(entry.down)
  var up = number(entry.up)
  var ping = number(entry.ping)
  if (timestamp === null || timestamp <= 0 || down === null || up === null) return null
  var normalized = { timestamp: timestamp, down: down, up: up, ping: ping }
  if (entry.automatic === true) normalized.automatic = true
  return normalized
}

function parseHistory(raw, limit) {
  var parsed
  try { parsed = JSON.parse(String(raw || "[]")) } catch (error) { return [] }
  if (!Array.isArray(parsed)) return []

  var out = []
  var cap = Math.max(1, parseInt(limit, 10) || 8)
  for (var i = 0; i < parsed.length && out.length < cap; i++) {
    var entry = normalizeHistoryEntry(parsed[i])
    if (entry) out.push(entry)
  }
  return out
}

function addHistory(history, entry, limit) {
  var next = normalizeHistoryEntry(entry)
  var out = next ? [next] : []
  var existing = Array.isArray(history) ? history : []
  var cap = Math.max(1, parseInt(limit, 10) || 8)
  for (var i = 0; i < existing.length && out.length < cap; i++) {
    var normalized = normalizeHistoryEntry(existing[i])
    if (normalized) out.push(normalized)
  }
  return out
}

// A one-row braille chart, matching the terminal Fast app: each glyph is a
// 2x4 pixel cell and the series is interpolated across the available columns.
function sparkline(values, maximum, width) {
  var series = Array.isArray(values) ? values : []
  var maxValue = number(maximum)
  var cellsWide = Math.max(0, parseInt(width, 10) || 0)
  if (cellsWide === 0) return ""

  var columns = cellsWide * 2
  var rows = 4
  var cells = []
  for (var c = 0; c < cellsWide; c++) cells.push(0)

  if (series.length > 1 && maxValue !== null && maxValue > 0) {
    for (var px = 0; px < columns; px++) {
      var pos = px / (columns - 1) * (series.length - 1)
      var index = Math.floor(pos)
      var value = number(series[index]) || 0
      if (index + 1 < series.length) {
        var next = number(series[index + 1]) || 0
        value += (next - value) * (pos - index)
      }

      var ratio = Math.max(0, Math.min(1, value / maxValue))
      var height = Math.floor(ratio * rows + 0.5)
      for (var y = rows - height; y < rows; y++)
        cells[Math.floor(px / 2)] |= BRAILLE_DOTS[y][px % 2]
    }
  }

  var result = ""
  for (var i = 0; i < cells.length; i++)
    result += cells[i] === 0 ? " " : String.fromCharCode(0x2800 + cells[i])
  return result
}

function tooltip(running, phase, down, up, ping) {
  if (running) {
    var active = phase === "down" ? formatRate(down) : formatRate(up)
    var label = phase === "down" ? "downloading" : phase === "up" ? "uploading" : "measuring ping"
    return "Fast — " + label + (active.value === "—" ? "…" : " · " + active.value + " " + active.unit)
  }
  if (down > 0 || up > 0)
    return "Fast — ↓ " + formatRate(down).value + " " + formatRate(down).unit
      + " · ↑ " + formatRate(up).value + " " + formatRate(up).unit
      + " · " + formatPing(ping)
  return "Fast — click to test"
}

if (typeof module !== "undefined") {
  module.exports = {
    number: number,
    appendSample: appendSample,
    peak: peak,
    settledAverage: settledAverage,
    formatRate: formatRate,
    formatPeak: formatPeak,
    formatPing: formatPing,
    parseConnection: parseConnection,
    parseDetails: parseDetails,
    normalizeHistoryEntry: normalizeHistoryEntry,
    parseHistory: parseHistory,
    addHistory: addHistory,
    sparkline: sparkline,
    tooltip: tooltip
  }
}
