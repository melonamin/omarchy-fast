import QtQuick

Canvas {
  id: root

  required property var values
  required property real maximum
  required property real rate
  required property int flowDirection
  required property color accentColor
  required property color foreground
  property bool live: false
  property real shimmer: 0
  property real motion: 0
  readonly property real intensity: Math.max(0.18, Math.min(1,
    Math.log(1 + Math.max(0, rate)) / Math.log(2501)))

  antialiasing: true

  onValuesChanged: requestPaint()
  onMaximumChanged: requestPaint()
  onRateChanged: requestPaint()
  onAccentColorChanged: requestPaint()
  onForegroundChanged: requestPaint()
  onLiveChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onShimmerChanged: if (live) requestPaint()

  NumberAnimation on shimmer {
    from: 0
    to: 1
    duration: 1150
    loops: Animation.Infinite
    running: root.live
  }

  NumberAnimation on motion {
    from: 0
    to: 1
    duration: 620
    loops: Animation.Infinite
    running: root.live
  }

  onMotionChanged: if (live) requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)

    var left = 2
    var right = Math.max(left + 1, width - 2)
    var top = 3
    var bottom = Math.max(top + 1, height - 3)

    ctx.save()
    ctx.strokeStyle = root.foreground
    ctx.lineWidth = 1
    ctx.globalAlpha = 0.10
    ctx.setLineDash([1, 5])
    ctx.beginPath()
    ctx.moveTo(left, bottom)
    ctx.lineTo(right, bottom)
    ctx.stroke()
    ctx.restore()

    var series = Array.isArray(root.values) ? root.values : []
    if (series.length === 0 || root.maximum <= 0) return

    var points = []
    for (var i = 0; i < series.length; i++) {
      var value = Number(series[i])
      if (!isFinite(value) || value < 0) value = 0
      var ratio = Math.max(0, Math.min(1, value / root.maximum))
      points.push({
        x: series.length === 1 ? right : left + (right - left) * i / (series.length - 1),
        y: bottom - (bottom - top) * ratio
      })
    }

    // A speed-reactive particle field: download flows toward the left, upload
    // toward the right. Faster rates grow both the density and comet tails.
    if (root.live) {
      var particleCount = 8 + Math.round(root.intensity * 16)
      var direction = root.flowDirection < 0 ? -1 : 1
      ctx.save()
      ctx.strokeStyle = root.accentColor
      ctx.fillStyle = root.accentColor
      ctx.lineCap = "round"
      for (var particle = 0; particle < particleCount; particle++) {
        var seed = (particle * 0.61803398875) % 1
        var travel = (root.motion + seed) % 1
        var position = direction > 0 ? travel : 1 - travel
        var streak = 4 + root.intensity * 17 + (particle % 4) * 1.7
        var x = left - streak + position * (right - left + streak * 2)
        var lane = ((particle * 11 + particle * particle * 3) % 29) / 29
        var y = top + lane * (bottom - top)
        var twinkle = 0.55 + 0.45 * Math.sin((travel + seed) * Math.PI * 2)
        ctx.globalAlpha = (0.06 + root.intensity * 0.16) * twinkle
        ctx.lineWidth = particle % 5 === 0 ? 1.5 : 0.8
        ctx.beginPath()
        ctx.moveTo(x - direction * streak, y)
        ctx.lineTo(x, y)
        ctx.stroke()
        ctx.globalAlpha = (0.16 + root.intensity * 0.32) * twinkle
        ctx.beginPath()
        ctx.arc(x, y, particle % 5 === 0 ? 1.25 : 0.65, 0, Math.PI * 2)
        ctx.fill()
      }
      ctx.restore()
    }

    function curvePath(context) {
      context.moveTo(points[0].x, points[0].y)
      for (var p = 1; p < points.length - 1; p++) {
        var midX = (points[p].x + points[p + 1].x) / 2
        var midY = (points[p].y + points[p + 1].y) / 2
        context.quadraticCurveTo(points[p].x, points[p].y, midX, midY)
      }
      if (points.length > 1) {
        var last = points[points.length - 1]
        context.quadraticCurveTo(last.x, last.y, last.x, last.y)
      }
    }

    ctx.save()
    ctx.beginPath()
    curvePath(ctx)
    ctx.lineTo(points[points.length - 1].x, bottom)
    ctx.lineTo(points[0].x, bottom)
    ctx.closePath()
    ctx.fillStyle = root.accentColor
    ctx.globalAlpha = root.live ? 0.14 : 0.08
    ctx.fill()
    ctx.restore()

    var glowWidths = root.live ? [7, 4, 1.7] : [3, 1.4]
    var glowAlpha = root.live ? [0.07, 0.16, 0.95] : [0.08, 0.62]
    for (var pass = 0; pass < glowWidths.length; pass++) {
      ctx.save()
      ctx.beginPath()
      curvePath(ctx)
      ctx.strokeStyle = root.accentColor
      ctx.lineWidth = glowWidths[pass]
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      ctx.globalAlpha = glowAlpha[pass]
      ctx.stroke()
      ctx.restore()
    }

    // A diagonal scanner races across the data and lights the trace where it
    // crosses, giving the otherwise stable graph a continuous sense of pace.
    if (root.live && points.length > 1) {
      var scanPhase = root.flowDirection > 0 ? root.motion : 1 - root.motion
      var scanX = left + scanPhase * (right - left)
      var scanIndex = Math.max(0, Math.min(points.length - 1,
        Math.round(scanPhase * (points.length - 1))))
      var scanPoint = points[scanIndex]
      ctx.save()
      ctx.strokeStyle = root.accentColor
      ctx.lineCap = "round"
      ctx.globalAlpha = 0.10 + root.intensity * 0.14
      ctx.lineWidth = 5
      ctx.beginPath()
      ctx.moveTo(scanX - 5, bottom)
      ctx.lineTo(scanX + 5, top)
      ctx.stroke()
      ctx.globalAlpha = 0.78
      ctx.fillStyle = root.accentColor
      ctx.beginPath()
      ctx.arc(scanPoint.x, scanPoint.y, 1.4 + root.intensity, 0, Math.PI * 2)
      ctx.fill()
      ctx.globalAlpha = 0.30
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.arc(scanPoint.x, scanPoint.y, 3.5 + root.shimmer * 3, 0, Math.PI * 2)
      ctx.stroke()
      ctx.restore()
    }

    var endpoint = points[points.length - 1]
    ctx.save()
    ctx.strokeStyle = root.accentColor
    ctx.fillStyle = root.accentColor
    ctx.globalAlpha = root.live ? 0.92 : 0.60
    ctx.beginPath()
    ctx.arc(endpoint.x, endpoint.y, root.live ? 2.4 : 1.8, 0, Math.PI * 2)
    ctx.fill()

    if (root.live) {
      var ring = 3 + root.shimmer * 5
      ctx.globalAlpha = 0.38 * (1 - root.shimmer)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.arc(endpoint.x, endpoint.y, ring, 0, Math.PI * 2)
      ctx.stroke()

      for (var s = 0; s < 12; s++) {
        var phase = (root.shimmer + s * 0.083) % 1
        var angle = Math.PI * (0.58 + s * 0.137)
        var distance = 4 + phase * (14 + root.intensity * 10)
        var sx = endpoint.x + Math.cos(angle) * distance
        var sy = endpoint.y + Math.sin(angle) * distance * 0.48
        var size = (2.2 + root.intensity) * (1 - phase) + 0.35
        ctx.globalAlpha = (0.55 + root.intensity * 0.35) * (1 - phase)
        ctx.beginPath()
        if (s % 3 === 0) {
          ctx.arc(sx, sy, Math.max(0.45, size * 0.46), 0, Math.PI * 2)
        } else {
          ctx.moveTo(sx - size, sy)
          ctx.lineTo(sx + size, sy)
          ctx.moveTo(sx, sy - size)
          ctx.lineTo(sx, sy + size)
        }
        ctx.stroke()
      }
    }
    ctx.restore()
  }
}
