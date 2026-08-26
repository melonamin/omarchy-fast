import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "melonamin.fast"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      if (!panelLoader.item || !panelLoader.item.running) return "󰓅"
      if (panelLoader.item.phase === "down") return "↓"
      if (panelLoader.item.phase === "up") return "↑"
      return "󰒋"
    }
    slotSize: Style.bar.statusSlot
    opacity: panelLoader.item && panelLoader.item.running ? 1 : 0.82
    tooltipText: panelLoader.item ? panelLoader.item.barTooltip : "Fast network speed test"

    Behavior on opacity { NumberAnimation { duration: 180 } }

    onPressed: function(b) {
      var panel = panelLoader.item
      if (!panel) return
      if (b === Qt.MiddleButton) panel.runFromBar()
      else if (b === Qt.LeftButton) root.togglePanel()
    }
  }
}
