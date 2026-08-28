import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "melonamin.fast"
  ipcTarget: "melonamin.fast"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.popups.text
  readonly property color mutedText: Util.alpha(foreground, 0.55)
  readonly property bool darkSurface: Color.popups.background.hslLightness < 0.5
  readonly property color downloadColor: darkSurface ? "#2EF8BB" : "#087F5B"
  readonly property color uploadColor: darkSurface ? "#BD52FF" : "#7B2CBF"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/melonamin.fast"
  readonly property string interactiveHelperPath: pluginPath + "/run-interactive-test"
  readonly property string stateHelperPath: pluginPath + "/safe-state"
  readonly property int historyLimit: 8

  property bool running: false
  property bool aborting: false
  property bool runPending: false
  property bool hasResult: false
  property string phase: "" // down | up | ping | ""
  property string error: ""
  property string stderrText: ""
  property string connectionName: ""
  property var downloadSamples: []
  property var uploadSamples: []
  property real downloadResult: 0
  property real uploadResult: 0
  property real downloadPeak: 0
  property real uploadPeak: 0
  property real pingMs: -1
  property double finishedAt: 0
  property var history: []
  property real animatedDownload: currentDownload
  property real animatedUpload: currentUpload

  readonly property real currentDownload: phase === "down" && downloadSamples.length > 0
    ? downloadSamples[downloadSamples.length - 1] : downloadResult
  readonly property real currentUpload: phase === "up" && uploadSamples.length > 0
    ? uploadSamples[uploadSamples.length - 1] : uploadResult
  readonly property var downloadRate: Model.formatRate(animatedDownload)
  readonly property var uploadRate: Model.formatRate(animatedUpload)
  readonly property string barTooltip: Model.tooltip(running, phase, currentDownload, currentUpload, pingMs)
  readonly property color phaseColor: phase === "down" ? downloadColor
    : phase === "up" ? uploadColor : Color.accent
  readonly property string phaseToken: {
    if (error !== "") return "ERROR"
    if (phase === "down") return "DOWNLOAD " + Math.min(100, downloadSamples.length * 2) + "%"
    if (phase === "up") return "UPLOAD " + Math.min(100, uploadSamples.length * 2) + "%"
    if (phase === "ping") return "PING"
    if (hasResult) return "COMPLETE"
    return "READY"
  }

  Behavior on animatedDownload {
    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
  }

  Behavior on animatedUpload {
    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
  }
  readonly property string statusLine: {
    if (error !== "") return error
    if (phase === "down") return "receiving from the nearest Netflix edge…"
    if (phase === "up") return "sending to the nearest Netflix edge…"
    if (phase === "ping") return "measuring internet latency…"
    if (hasResult) return "finished " + Qt.formatDateTime(new Date(finishedAt), "h:mm AP")
    return "press enter to start"
  }

  function setCenterHoverRevealSuppressed(value) {
    if (bar && "centerHoverRevealSuppressed" in bar) bar.centerHoverRevealSuppressed = value
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    controller.show()
    refreshConnection()
    refreshHistory()
    if (!hasResult && !running) runTest()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    controller.show()
    refreshConnection()
    refreshHistory()
    if (!hasResult && !running) runTest()
    Qt.callLater(function() {
      if (root.opened) root.setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    runPending = false
    if (running) abortTest()
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else openFromHotkey()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function refreshConnection() {
    if (!connectionProc.running) connectionProc.running = true
  }

  function applyConnection(raw) {
    var connection = Model.parseConnection(raw)
    connectionName = connection.label
  }

  function runFromBar() {
    if (!opened) openFromHotkey()
    if (!running) runTest()
  }

  function runTest() {
    if (running) return
    if (speedProc.running || pingProc.running) {
      runPending = true
      return
    }
    runPending = false
    aborting = false
    hasResult = false
    error = ""
    stderrText = ""
    downloadSamples = []
    uploadSamples = []
    downloadResult = 0
    uploadResult = 0
    downloadPeak = 0
    uploadPeak = 0
    pingMs = -1
    finishedAt = 0
    running = true
    refreshConnection()
    startSpeedTest()
  }

  function startSpeedTest() {
    phase = "down"
    stderrText = ""
    speedProc.command = [interactiveHelperPath, "5"]
    speedProc.running = true
  }

  function acceptSpeedOutput(line) {
    var output = String(line || "").trim()
    if (output === "__MELONAMIN_FAST_PHASE__:down") {
      phase = "down"
      return
    }
    if (output === "__MELONAMIN_FAST_PHASE__:up") {
      if (downloadSamples.length === 0) {
        failTest("No download samples received")
        return
      }
      downloadResult = Model.settledAverage(downloadSamples)
      phase = "up"
      return
    }

    if (phase === "down") {
      downloadSamples = Model.appendSample(downloadSamples, output, 50)
      downloadPeak = Model.peak(downloadSamples)
    } else if (phase === "up") {
      uploadSamples = Model.appendSample(uploadSamples, output, 50)
      uploadPeak = Model.peak(uploadSamples)
    }
  }

  function finishSpeedTest() {
    if (!running || aborting) return
    if (phase !== "up" || uploadSamples.length === 0) {
      failTest("No upload samples received")
      return
    }
    uploadResult = Model.settledAverage(uploadSamples)
    phase = "ping"
    pingProc.running = true
  }

  function finishPing(raw) {
    if (!running || aborting || phase !== "ping") return
    var details = Model.parseDetails(raw)
    pingMs = details.ping === null ? -1 : details.ping
    phase = ""
    running = false
    hasResult = true
    finishedAt = Date.now()
    history = Model.addHistory(history, {
      timestamp: finishedAt,
      down: downloadResult,
      up: uploadResult,
      ping: pingMs >= 0 ? pingMs : null
    }, historyLimit)
    persistHistoryEntry()
    completionBurst.burst()
  }

  function failTest(message) {
    phase = ""
    running = false
    error = String(message || "Speed test failed")
    if (speedProc.running) speedProc.running = false
    if (pingProc.running) pingProc.running = false
  }

  function abortTest() {
    aborting = true
    running = false
    phase = ""
    if (speedProc.running) speedProc.running = false
    if (pingProc.running) pingProc.running = false
    if (!speedProc.running && !pingProc.running) aborting = false
  }

  function loadHistory(raw) {
    history = Model.parseHistory(raw, historyLimit)
  }

  function refreshHistory() {
    if (historyReadProc.running || historyWriteProc.running) return
    historyReadProc.command = [stateHelperPath, "history-read"]
    historyReadProc.running = true
  }

  function persistHistoryEntry() {
    var command = [
      stateHelperPath,
      "history-add",
      "--timestamp", String(finishedAt),
      "--down", String(downloadResult),
      "--up", String(uploadResult)
    ]
    if (pingMs >= 0) command.push("--ping", String(pingMs))
    historyWriteProc.command = command
    historyWriteProc.running = true
  }

  Component.onCompleted: refreshHistory()

  Process {
    id: historyReadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadHistory(text)
    }
  }

  Process {
    id: historyWriteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadHistory(text)
    }
  }

  Process {
    id: connectionProc
    command: ["omarchy-network-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyConnection(text)
    }
  }

  Process {
    id: speedProc
    stdout: SplitParser { onRead: function(line) { root.acceptSpeedOutput(line) } }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.stderrText = String(text || "").trim()
        if (root.error !== "" && root.stderrText !== "") root.error = root.stderrText
      }
    }
    onExited: function(exitCode) {
      if (root.aborting) {
        root.aborting = false
        if (root.runPending) Qt.callLater(root.runTest)
        return
      }
      if (!root.running) return
      if (exitCode !== 0) {
        root.failTest(root.stderrText || "Speed test failed")
        return
      }
      root.finishSpeedTest()
    }
  }

  Process {
    id: pingProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishPing(text)
    }
    onExited: function(exitCode) {
      if (root.aborting) {
        root.aborting = false
        if (root.runPending) Qt.callLater(root.runTest)
        return
      }
      if (root.running && root.phase === "ping" && exitCode !== 0)
        root.finishPing("")
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open() { root.openFromHotkey() }
    function close() { root.close() }
    function show() { root.openFromHotkey() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function run() { root.runFromBar() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(terminal.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: if (!root.running) root.runTest()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if ((text === "r" || text === "R") && !root.running) root.runTest()
      }

      Column {
        id: terminal
        width: parent.width
        spacing: Style.space(12)

        Item {
          width: parent.width
          implicitHeight: Math.max(commandRow.implicitHeight, stateColumn.implicitHeight)

          Row {
            id: commandRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(7)

            Text {
              text: "$"
              color: root.downloadColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: "fast"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: root.connectionName === "" ? "" : "— " + root.connectionName
              textFormat: Text.PlainText
              color: root.mutedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.baseline: parent.children[1].baseline
            }
          }

          Column {
            id: stateColumn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              anchors.right: parent.right
              text: root.phaseToken
              color: root.error !== "" ? Color.urgent : root.phaseColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }

            Text {
              anchors.right: parent.right
              text: root.statusLine
              color: root.error !== "" ? Color.urgent : root.mutedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: Math.min(implicitWidth, Style.space(250))
              horizontalAlignment: Text.AlignRight
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.spacing.hairline)
          color: Util.alpha(root.foreground, 0.12)
        }

        SpeedRow {
          width: parent.width
          label: "download"
          symbol: "↓"
          valueText: root.downloadRate.value
          unitText: root.downloadRate.unit
          samples: root.downloadSamples
          maximum: Math.max(root.downloadPeak, 1)
          rate: root.animatedDownload
          flowDirection: -1
          peakText: Model.formatPeak(root.downloadPeak)
          accentColor: root.downloadColor
          foreground: root.foreground
          muted: root.mutedText
          fontFamily: root.fontFamily
          live: root.phase === "down"
        }

        SpeedRow {
          width: parent.width
          label: "upload"
          symbol: "↑"
          valueText: root.uploadRate.value
          unitText: root.uploadRate.unit
          samples: root.uploadSamples
          maximum: Math.max(root.uploadPeak, 1)
          rate: root.animatedUpload
          flowDirection: 1
          peakText: Model.formatPeak(root.uploadPeak)
          accentColor: root.uploadColor
          foreground: root.foreground
          muted: root.mutedText
          fontFamily: root.fontFamily
          live: root.phase === "up"
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.spacing.hairline)
          color: Util.alpha(root.foreground, 0.12)
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(pingRow.implicitHeight, runButton.implicitHeight)

          Row {
            id: pingRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              text: "•"
              color: root.phase === "ping" ? Color.accent : root.mutedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }

            Text {
              text: "PING"
              color: root.mutedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }

            Text {
              text: Model.formatPing(root.pingMs)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          Button {
            id: runButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.running ? "RUNNING…" : root.hasResult ? "RUN AGAIN" : "RUN"
            tooltipText: root.running ? "Speed test in progress" : "Run a Fast.com speed test"
            bordered: true
            enabled: !root.running
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(4)
            onClicked: root.runTest()
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.history.length > 0

          Row {
            width: parent.width

            Text {
              text: "HISTORY · LAST " + root.historyLimit
              color: root.mutedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }

            Text {
              width: parent.width - x
              text: root.history.length + (root.history.length === 1 ? " RUN" : " RUNS")
              color: Util.alpha(root.foreground, 0.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
            }
          }

          Repeater {
            model: root.history

            Item {
              required property int index
              required property var modelData
              width: parent.width
              height: Style.space(20)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.automatic === true
                  ? "A" + String(index + 1)
                  : (index + 1 < 10 ? "0" : "") + String(index + 1)
                color: modelData.automatic === true
                  ? Util.alpha(Color.accent, 0.72)
                  : Util.alpha(root.foreground, 0.32)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                x: Style.space(28)
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(new Date(modelData.timestamp), "MMM d  h:mm AP")
                color: root.mutedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                x: Style.space(145)
                anchors.verticalCenter: parent.verticalCenter
                text: "↓ " + Model.formatRate(modelData.down).value + " " + Model.formatRate(modelData.down).unit
                color: root.downloadColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                x: Style.space(260)
                anchors.verticalCenter: parent.verticalCenter
                text: "↑ " + Model.formatRate(modelData.up).value + " " + Model.formatRate(modelData.up).unit
                color: root.uploadColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Model.formatPing(modelData.ping)
                color: root.mutedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "enter/r  run again    esc  close    middle-click  quick run"
          textFormat: Text.PlainText
          color: Util.alpha(root.foreground, 0.38)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }

      SparkBurst {
        id: completionBurst
        anchors.fill: parent
        z: 20
        primaryColor: root.downloadColor
        secondaryColor: root.uploadColor
        foreground: root.foreground
      }
    }
  }
}
