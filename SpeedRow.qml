import QtQuick
import qs.Commons

Item {
  id: root

  required property string label
  required property string symbol
  required property string valueText
  required property string unitText
  required property var samples
  required property real maximum
  required property real rate
  required property int flowDirection
  required property string peakText
  required property color accentColor
  required property color foreground
  required property color muted
  required property string fontFamily
  property bool live: false

  implicitHeight: Style.space(66)

  Rectangle {
    width: Style.space(2)
    height: parent.height
    radius: width / 2
    color: root.accentColor
    opacity: root.live ? 1 : 0.28

    Behavior on opacity { NumberAnimation { duration: 180 } }
  }

  Item {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: parent.right
    height: parent.height

    Row {
      id: heading
      anchors.left: parent.left
      anchors.top: parent.top
      spacing: Style.space(7)

      Text {
        text: root.symbol
        color: root.accentColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        text: root.label.toUpperCase()
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.4
        anchors.baseline: parent.children[0].baseline
      }
    }

    Row {
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(5)

      Text {
        text: root.valueText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Text {
        text: root.unitText
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.baseline: parent.children[0].baseline
      }
    }

    SignalTrace {
      anchors.left: parent.left
      anchors.right: peakLabel.left
      anchors.rightMargin: Style.space(14)
      anchors.bottom: parent.bottom
      height: Style.space(27)
      values: root.samples
      maximum: root.maximum
      rate: root.rate
      flowDirection: root.flowDirection
      accentColor: root.accentColor
      foreground: root.foreground
      live: root.live
    }

    Text {
      id: peakLabel
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      text: root.peakText
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }
  }
}
