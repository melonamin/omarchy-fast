const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")
const Model = require("../Model.js")

test("appendSample rejects invalid readings and caps history", () => {
  assert.strictEqual(Model.number(null), null)
  assert.strictEqual(Model.number(""), null)
  assert.deepStrictEqual(Model.appendSample([1, 2], "nope", 3), [1, 2])
  assert.deepStrictEqual(Model.appendSample([1, 2, 3], "4.5", 3), [2, 3, 4.5])
})

test("history parses defensively, prepends, and caps", () => {
  const first = { timestamp: 1000, down: 100, up: 20, ping: 8 }
  const second = { timestamp: 2000, down: 200, up: 40, ping: null }
  assert.deepStrictEqual(Model.parseHistory("not json", 8), [])
  assert.deepStrictEqual(Model.parseHistory(JSON.stringify([first, { nope: true }]), 8), [first])
  assert.deepStrictEqual(Model.addHistory([first], second, 2), [second, first])
  assert.deepStrictEqual(
    Model.parseHistory(JSON.stringify([{ ...first, automatic: true }]), 8),
    [{ ...first, automatic: true }]
  )
  assert.deepStrictEqual(Model.addHistory([first, second], { timestamp: 3000, down: 3, up: 4, ping: 5 }, 2), [
    { timestamp: 3000, down: 3, up: 4, ping: 5 },
    first
  ])
})

test("settledAverage drops warm-up once enough samples exist", () => {
  assert.strictEqual(Model.settledAverage([10, 20]), 15)
  assert.strictEqual(Model.settledAverage([1, 20, 40]), 30)
  assert.strictEqual(Model.settledAverage([...Array(10).fill(1), ...Array(40).fill(101)]), 101)
  assert.strictEqual(Model.peak([1, 20, 4]), 20)
})

test("rate and ping formatting scale cleanly", () => {
  assert.deepStrictEqual(Model.formatRate(82.349), { value: "82.3", unit: "Mbps" })
  assert.deepStrictEqual(Model.formatRate(1250), { value: "1.3", unit: "Gbps" })
  assert.strictEqual(Model.formatPing(7.25), "7.3 ms")
  assert.strictEqual(Model.formatPing(22.8), "23 ms")
})

test("connection and verbose details parse Omarchy output", () => {
  assert.deepStrictEqual(Model.parseConnection("wifi\tMoon Base\t93\t5180\n"), { kind: "wifi", label: "Moon Base" })
  assert.deepStrictEqual(Model.parseConnection("ethernet\tenp5s0\t\t\n"), { kind: "ethernet", label: "Ethernet" })
  assert.deepStrictEqual(
    Model.parseDetails("iface\twlan0\ntype\twifi\ninternet_ping_ms\t12.4\n"),
    { ping: 12.4, iface: "wlan0", kind: "wifi" }
  )
})

test("sparkline returns fixed-width braille and responds to shape", () => {
  assert.strictEqual(Model.sparkline([], 0, 4), "    ")
  const rising = Model.sparkline([0, 25, 50, 100], 100, 6)
  assert.strictEqual(rising.length, 6)
  assert.notStrictEqual(rising.trim(), "")
  assert.notStrictEqual(rising[0], rising[rising.length - 1])
})

test("tooltip reports idle, running, and completed states", () => {
  assert.match(Model.tooltip(false, "", 0, 0, null), /click to test/)
  assert.match(Model.tooltip(true, "down", 120, 0, null), /downloading.*120\.0 Mbps/)
  assert.match(Model.tooltip(false, "", 120, 18, 11), /↓ 120\.0 Mbps.*↑ 18\.0 Mbps.*11 ms/)
})

test("signal trace repaints when paint-only inputs change", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "SignalTrace.qml"), "utf8")
  assert.match(qml, /onAccentColorChanged:\s*requestPaint\(\)/)
  assert.match(qml, /onForegroundChanged:\s*requestPaint\(\)/)
  assert.match(qml, /onLiveChanged:\s*requestPaint\(\)/)
})

test("panel keeps download and upload in one interactive process", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert.match(qml, /run-interactive-test/)
  assert.match(qml, /__MELONAMIN_FAST_PHASE__:up/)
  assert.match(qml, /speedProc\.command = \[interactiveHelperPath, "5"\]/)
})
