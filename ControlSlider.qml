import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Column {
  id: root

  property string label: ""
  property real value: 0
  property real from: 0
  property real to: 100
  property real step: 1
  property string suffix: ""
  property var bar: null
  signal committed(real value)

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(2)

  Row {
    width: parent.width
    Text {
      width: parent.width - valueLabel.width
      text: root.label
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      id: valueLabel
      text: String(Math.round(slider.liveValue)) + root.suffix
      color: Commons.Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  PanelSlider {
    id: slider
    width: parent.width
    bar: root.bar
    minimum: root.from
    maximum: root.to
    step: root.step
    integer: root.step >= 1
    value: root.value
    opacity: root.enabled ? 1 : 0.35
    onReleased: function(newValue) { if (root.enabled) root.committed(newValue) }
  }
}
