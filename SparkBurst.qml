import QtQuick

Canvas {
  id: root

  required property color primaryColor
  required property color secondaryColor
  required property color foreground
  property real progress: 1

  enabled: false
  visible: progress < 1
  antialiasing: true

  function burst() {
    progress = 0
    burstAnimation.restart()
    requestPaint()
  }

  onProgressChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  NumberAnimation {
    id: burstAnimation
    target: root
    property: "progress"
    from: 0
    to: 1
    duration: 1250
    easing.type: Easing.OutCubic
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    if (root.progress >= 1) return

    var originX = width * 0.55
    var originY = Math.min(height * 0.34, 112)
    var fade = 1 - root.progress

    ctx.save()
    ctx.strokeStyle = root.progress < 0.5 ? root.primaryColor : root.secondaryColor
    ctx.lineWidth = 1.5
    ctx.globalAlpha = fade * 0.42
    ctx.beginPath()
    ctx.arc(originX, originY, 10 + root.progress * 92, 0, Math.PI * 2)
    ctx.stroke()
    ctx.globalAlpha = fade * 0.22
    ctx.lineWidth = 5
    ctx.beginPath()
    ctx.arc(originX, originY, 5 + root.progress * 58, 0, Math.PI * 2)
    ctx.stroke()
    ctx.restore()

    for (var i = 0; i < 38; i++) {
      var delay = i % 2 === 0 ? 0 : 0.12
      var localProgress = Math.max(0, (root.progress - delay) / (1 - delay))
      if (localProgress <= 0) continue
      var localFade = 1 - localProgress
      var angle = -Math.PI * 0.96 + i * Math.PI * 1.92 / 37
      var reach = (24 + (i % 7) * 10) * (0.18 + localProgress)
      var x = originX + Math.cos(angle) * reach
      var y = originY + Math.sin(angle) * reach * 0.58 + localProgress * localProgress * 22
      var size = (i % 4 === 0 ? 4.1 : 2.5) * localFade + 0.45

      ctx.save()
      ctx.translate(x, y)
      ctx.rotate(angle + localProgress * 1.8)
      ctx.strokeStyle = i % 5 === 0 ? root.foreground
        : i % 2 === 0 ? root.primaryColor : root.secondaryColor
      ctx.lineWidth = i % 5 === 0 ? 1.6 : 1
      ctx.globalAlpha = localFade * (i % 5 === 0 ? 0.78 : 0.96)
      ctx.beginPath()
      if (i % 6 === 0) {
        ctx.moveTo(-size * 2.4, 0)
        ctx.lineTo(size, 0)
      } else {
        ctx.moveTo(-size, 0)
        ctx.lineTo(size, 0)
        ctx.moveTo(0, -size)
        ctx.lineTo(0, size)
      }
      ctx.stroke()
      ctx.restore()
    }
  }
}
