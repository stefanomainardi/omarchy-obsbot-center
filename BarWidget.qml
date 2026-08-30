import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.stefanomainardi.obsbot-center"

  property bool connected: false
  readonly property bool hideWhenAbsent: setting("hideWhenAbsent", false) === true
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (root.opened && panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function setCameraFeature(name, value) {
    if (panelLoader.item) panelLoader.item.setCameraFeature(name, value)
  }

  function setControl(name, value) {
    if (panelLoader.item) panelLoader.item.setControl(name, Number(value))
  }

  function setAudio(name, value) {
    if (panelLoader.item) panelLoader.item.setAudio(name, value)
  }

  function resetAdvanced(group) {
    if (!panelLoader.item) return
    panelLoader.item.advancedPage = group
    panelLoader.item.resetAdvanced()
  }

  function applyPreset(name) {
    if (panelLoader.item) panelLoader.item.applyPreset(name)
  }

  function setPreviewEnabled(enabled) {
    if (panelLoader.item) panelLoader.item.setPreviewEnabled(enabled)
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: !root.hideWhenAbsent || root.connected

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: refresh()

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: if (!statusProc.running) statusProc.running = true
  }

  Process {
    id: statusProc
    command: [Qt.resolvedUrl("bin/obsbot-control").toString().replace("file://", ""), "detect"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.connected = String(text || "").trim().indexOf("connected=1") >= 0
    }
  }

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

  IpcHandler {
    target: root.moduleName
    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function previewOn(): void { root.setPreviewEnabled(true) }
    function previewOff(): void { root.setPreviewEnabled(false) }
    function framing(mode: string): void { root.setCameraFeature("auto-framing", mode) }
    function fov(mode: string): void { root.setCameraFeature("fov", mode) }
    function gesture(enabled: string): void { root.setCameraFeature("gesture-control", enabled) }
    function gestureZoom(factor: string): void { root.setCameraFeature("gesture-zoom", factor) }
    function audioMode(mode: string): void { root.setCameraFeature("audio-mode", mode) }
    function microphoneVolume(value: string): void { root.setAudio("volume", value) }
    function microphoneMute(value: string): void { root.setAudio("mute", value) }
    function camera(feature: string, value: string): void { root.setCameraFeature(feature, value) }
    function control(name: string, value: string): void { root.setControl(name, value) }
    function reset(group: string): void { root.resetAdvanced(group) }
    function preset(name: string): void { root.applyPreset(name) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄀"
    tooltipText: root.connected ? "OBSBOT Meet 2 connected" : "OBSBOT Meet 2 not detected"
    dimmed: !root.connected
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      if (buttonCode === Qt.RightButton) root.refresh()
    }
  }
}
