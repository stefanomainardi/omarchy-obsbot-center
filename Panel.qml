import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.stefanomainardi.obsbot-center"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool connected: false
  property bool previewRequested: false
  property string device: ""
  property string modelName: "OBSBOT camera"
  property string section: "basic"
  property string advancedPage: "optics"
  property string audioPage: "level"
  property string errorMessage: ""
  property var controlInfo: ({})
  property int brightness: 50
  property int contrast: 50
  property int saturation: 50
  property int hue: 50
  property int sharpness: 50
  property int gain: 1
  property int backlightCompensation: 9
  property int zoom: 0
  property int focusValue: 0
  property bool autofocus: true
  property bool autoExposure: true
  property int exposure: 330
  property bool autoWhiteBalance: true
  property int whiteBalanceTemperature: 5000
  property int redBalance: 1024
  property int blueBalance: 1024
  property int powerLineFrequency: 1
  property string fovMode: "wide"
  property string autoFramingMode: "off"
  property bool gestureControlEnabled: false
  property string gestureZoom: "2x"
  property bool mirrorEnabled: false
  property bool verticalEnabled: false
  property bool ledEnabled: true
  property bool keepAwakeEnabled: false
  property string autoSleep: "off"
  property bool hdrEnabled: false
  property bool microphoneEnabled: true
  property bool audioAgcEnabled: true
  property bool sleepMicrophoneEnabled: false
  property string audioDistance: "standard"
  property string audioMode: "omni"
  property bool audioSourceAvailable: false
  property int micVolume: 100
  property bool micMuted: false
  property var previewPending: null

  readonly property string helper: Qt.resolvedUrl("bin/obsbot-control").toString().replace("file://", "")
  readonly property color themeForeground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color themeBackground: root.bar ? root.bar.background : Color.background
  readonly property color themeAccent: Color.accent
  readonly property color themeUrgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property color themeMuted: Qt.darker(root.themeForeground, 1.5)
  readonly property int refreshIntervalSec: Math.max(2, Math.min(60, Number(setting("refreshIntervalSec", 5)) || 5))
  readonly property bool previewSetting: setting("preview", true) !== false
  readonly property bool previewEnabled: previewPending === null ? previewSetting : previewPending
  readonly property var obsbotCamera: {
    var inputs = mediaDevices.videoInputs
    for (var j = 0; j < inputs.length; j++) {
      if (root.device && String(inputs[j].id) === root.device) return inputs[j]
    }
    for (var i = 0; i < inputs.length; i++) {
      var name = String(inputs[i].description || "").toLowerCase()
      if (name.indexOf("obsbot") >= 0 || name.indexOf("meet 2") >= 0) return inputs[i]
    }
    return null
  }
  onPreviewSettingChanged: if (previewPending === previewSetting) previewPending = null

  function setPreviewEnabled(enabled) {
    previewPending = enabled
    previewSettingTimeout.restart()
    Quickshell.execDetached(["omarchy", "bar", "set", root.moduleName, "preview", enabled ? "true" : "false", "--json"])
    if (enabled && root.opened) previewStart.restart()
    if (!enabled) root.previewRequested = false
  }

  function open() {
    root.controller.show()
    refresh()
    previewStart.restart()
  }

  function close() {
    previewStart.stop()
    root.previewRequested = false
    root.controller.hide()
  }

  function toggle() { root.opened ? close() : open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function runAction(args) {
    if (actionProc.running) return
    root.errorMessage = ""
    actionProc.command = [root.helper].concat(args)
    actionProc.running = true
  }

  function setControl(name, value) { runAction(["set", name, String(Math.round(value))]) }
  function resetAdvanced() { runAction(["reset", root.advancedPage]) }
  function setAudio(name, value) { runAction(["audio", name, String(value)]) }
  function applyPreset(name) { runAction(["preset", name]) }
  function setCameraFeature(name, value) {
    if (name === "fov") root.fovMode = value
    if (name === "auto-framing") root.autoFramingMode = value
    if (name === "microphone") root.previewRequested = false
    runAction(["camera", name, value])
  }
  function supported(name) { return controlInfo[name + "_available"] === "1" }
  function controlMin(name, fallback) { return Number(controlInfo[name + "_min"] || fallback) }
  function controlMax(name, fallback) { return Number(controlInfo[name + "_max"] || fallback) }
  function controlStep(name, fallback) { return Number(controlInfo[name + "_step"] || fallback) }
  function hasMeet2Presets() { return controlInfo.product_id === "fefb" }
  function hasVendorControls() { return controlInfo.vendor_controls === "1" }

  Process {
    id: stateProc
    command: [root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var values = {}
        var lines = String(text || "").trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          var separator = lines[i].indexOf("=")
          if (separator > 0) values[lines[i].slice(0, separator)] = lines[i].slice(separator + 1)
        }
        root.connected = values.connected === "1"
        root.device = values.device || ""
        root.modelName = values.model || "OBSBOT camera"
        root.controlInfo = values
        root.brightness = Number(values.brightness || 50)
        root.contrast = Number(values.contrast || 50)
        root.saturation = Number(values.saturation || 50)
        root.hue = Number(values.hue || 50)
        root.sharpness = Number(values.sharpness || 50)
        root.gain = Number(values.gain || 1)
        root.backlightCompensation = Number(values.backlight_compensation || 9)
        root.zoom = Number(values.zoom_absolute || 0)
        root.focusValue = Number(values.focus_absolute || 0)
        root.autofocus = values.focus_automatic_continuous === "1"
        root.autoExposure = values.auto_exposure === "0"
        root.exposure = Number(values.exposure_time_absolute || 330)
        root.autoWhiteBalance = values.white_balance_automatic === "1"
        root.whiteBalanceTemperature = Number(values.white_balance_temperature || 5000)
        root.redBalance = Number(values.red_balance || 1024)
        root.blueBalance = Number(values.blue_balance || 1024)
        root.powerLineFrequency = Number(values.power_line_frequency || 1)
        root.fovMode = values.fov || root.fovMode
        root.autoFramingMode = values.auto_framing || root.autoFramingMode
        root.gestureControlEnabled = (values.gesture_control || "off") === "on"
        root.gestureZoom = values.gesture_zoom || "2x"
        root.mirrorEnabled = (values.mirror || "off") === "on"
        root.verticalEnabled = (values.vertical || "off") === "on"
        root.ledEnabled = (values.led || "on") === "on"
        root.keepAwakeEnabled = (values.keep_awake || "off") === "on"
        root.autoSleep = values.auto_sleep || "off"
        root.hdrEnabled = (values.hdr || "off") === "on"
        root.microphoneEnabled = (values.microphone || "on") === "on"
        root.audioAgcEnabled = (values.audio_agc || "on") === "on"
        root.sleepMicrophoneEnabled = (values.sleep_microphone || "off") === "on"
        root.audioDistance = values.audio_distance || "standard"
        root.audioMode = values.audio_mode || "omni"
        root.audioSourceAvailable = values.audio_source_available === "1"
        root.micVolume = Number(values.mic_volume || 100)
        root.micMuted = (values.mic_muted || "off") === "on"
        root.errorMessage = values.error || ""
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.errorMessage = String(text || "").trim()
    }
    onRunningChanged: if (!running) {
      root.refresh()
      if (root.opened && !root.previewRequested) previewStart.restart()
    }
  }

  Timer { id: previewStart; interval: 180; onTriggered: root.previewRequested = root.opened }
  Timer { id: previewSettingTimeout; interval: 2000; onTriggered: root.previewPending = null }
  Timer { interval: root.refreshIntervalSec * 1000; running: root.opened; repeat: true; onTriggered: root.refresh() }
  MediaDevices { id: mediaDevices }

  Loader {
    id: cameraLoader
    active: root.previewEnabled && root.previewRequested && root.connected && root.obsbotCamera !== null
    sourceComponent: Camera {
      cameraDevice: root.obsbotCamera
      active: true
      onErrorOccurred: function(error, message) { root.errorMessage = message }
    }
  }

  CaptureSession { camera: cameraLoader.item; videoOutput: preview }

  component CameraSlider: ControlSlider {
    bar: root.bar
    enabled: root.connected
  }

  component TabButton: Button {
    bordered: true
    focusable: true
    foreground: root.barForeground
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(Math.min(scrollContent.implicitHeight, Style.space(780)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: scrollContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: scrollContent
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: 10
            Rectangle {
              width: 10; height: 10; radius: 5
              anchors.verticalCenter: parent.verticalCenter
              color: root.connected ? root.themeForeground : root.themeUrgent
            }
            Column {
              width: parent.width - 20
              Text {
                text: root.modelName
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
              Text {
                text: root.connected ? root.device : "Camera not detected"
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          Rectangle {
            width: parent.width
            visible: root.previewEnabled
            height: visible ? Math.min(width * 9 / 16, Style.space(190)) : 0
            radius: 8
            color: Qt.darker(root.themeBackground, 1.2)
            border.width: Style.normalBorderWidth
            border.color: Style.normalBorderFor(root.themeForeground, root.themeAccent, root.themeUrgent)
            clip: true
            VideoOutput {
              id: preview
              anchors.fill: parent
              visible: cameraLoader.item && cameraLoader.item.active && cameraLoader.item.error === Camera.NoError
              fillMode: VideoOutput.PreserveAspectCrop
            }
            Text {
              anchors.centerIn: parent
              visible: !preview.visible
              text: root.connected ? ((cameraLoader.item && cameraLoader.item.errorString) || "Starting live preview...") : "Connect OBSBOT Meet 2"
              color: root.themeForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }

          Toggle {
            width: parent.width
            label: "Live preview"
            description: root.previewEnabled ? "Active only while this panel is open" : "Disabled · camera remains free for other applications"
            checked: root.previewEnabled
            foreground: root.barForeground
            onClicked: root.setPreviewEnabled(!root.previewEnabled)
          }

          Row {
            width: parent.width
            spacing: 6
            TabButton {
              width: root.hasVendorControls() ? (parent.width - 18) / 4 : (parent.width - 6) / 2
              text: "Basic"
              selected: root.section === "basic"
              onClicked: root.section = "basic"
            }
            TabButton {
              width: root.hasVendorControls() ? (parent.width - 18) / 4 : (parent.width - 6) / 2
              text: "Advanced"
              selected: root.section === "advanced"
              onClicked: root.section = "advanced"
            }
            TabButton {
              visible: root.hasVendorControls()
              width: (parent.width - 18) / 4
              text: "AI"
              selected: root.section === "ai"
              onClicked: root.section = "ai"
            }
            TabButton {
              visible: root.hasVendorControls()
              width: (parent.width - 18) / 4
              text: "Audio"
              selected: root.section === "audio"
              onClicked: root.section = "audio"
            }
          }

          PanelSectionHeader { text: root.section === "basic" ? "IMAGE" : (root.section === "advanced" ? "CAMERA" : (root.section === "ai" ? "INTELLIGENT FRAMING" : "MICROPHONE")); foreground: root.barForeground }

          Row {
            visible: root.section === "advanced"
            width: parent.width
            spacing: 6
            Repeater {
              model: [{ value: "optics", label: "Optics" }, { value: "color", label: "Color" }, { value: "device", label: "Device" }]
              TabButton {
                required property var modelData
                width: (parent.width - 18) / 4
                text: modelData.label
                selected: root.advancedPage === modelData.value
                onClicked: root.advancedPage = modelData.value
              }
            }
            Button {
              width: (parent.width - 18) / 4
              bordered: true
              focusable: true
              foreground: root.barForeground
              text: "Reset"
              enabled: root.connected && !actionProc.running
              onClicked: root.resetAdvanced()
            }
          }

          Row {
            visible: root.section === "audio"
            width: parent.width
            spacing: 6
            Repeater {
              model: [{ value: "level", label: "Level" }, { value: "processing", label: "Processing" }]
              TabButton {
                required property var modelData
                width: (parent.width - 6) / 2
                text: modelData.label
                selected: root.audioPage === modelData.value
                onClicked: root.audioPage = modelData.value
              }
            }
          }

          CameraSlider { visible: root.section === "basic" && root.supported("brightness"); label: "Brightness"; value: root.brightness; from: root.controlMin("brightness", 0); to: root.controlMax("brightness", 100); step: root.controlStep("brightness", 1); onCommitted: function(v) { root.setControl("brightness", v) } }
          CameraSlider { visible: root.section === "basic" && root.supported("contrast"); label: "Contrast"; value: root.contrast; from: root.controlMin("contrast", 0); to: root.controlMax("contrast", 100); step: root.controlStep("contrast", 1); onCommitted: function(v) { root.setControl("contrast", v) } }
          CameraSlider { visible: root.section === "basic" && root.supported("saturation"); label: "Saturation"; value: root.saturation; from: root.controlMin("saturation", 0); to: root.controlMax("saturation", 100); step: root.controlStep("saturation", 1); onCommitted: function(v) { root.setControl("saturation", v) } }
          CameraSlider { visible: root.section === "basic" && root.supported("sharpness"); label: "Sharpness"; value: root.sharpness; from: root.controlMin("sharpness", 0); to: root.controlMax("sharpness", 100); step: root.controlStep("sharpness", 1); onCommitted: function(v) { root.setControl("sharpness", v) } }
          CameraSlider { visible: root.section === "basic" && root.supported("zoom_absolute"); label: root.autoFramingMode === "off" ? "Zoom" : "Zoom · controlled by auto framing"; value: root.zoom; from: root.controlMin("zoom_absolute", 0); to: root.controlMax("zoom_absolute", 100); step: root.controlStep("zoom_absolute", 1); enabled: root.connected && root.autoFramingMode === "off"; onCommitted: function(v) { root.setControl("zoom_absolute", v) } }

          Column {
            visible: root.section === "ai" && root.hasVendorControls()
            width: parent.width
            spacing: 6
            Text {
              text: "Auto framing"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
            Row {
              width: parent.width
              spacing: 6
              Repeater {
                model: [{ value: "off", label: "Off" }, { value: "solo", label: "Solo" }, { value: "group", label: "Group" }]
                TabButton {
                  required property var modelData
                  width: (parent.width - 12) / 3
                  text: modelData.label
                  selected: root.autoFramingMode === modelData.value
                  onClicked: root.setCameraFeature("auto-framing", modelData.value)
                }
              }
            }
            Text {
              text: "Field of view"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
            Row {
              width: parent.width
              spacing: 6
              Repeater {
                model: [{ value: "wide", label: "Wide" }, { value: "medium", label: "Medium" }, { value: "narrow", label: "Narrow" }]
                TabButton {
                  required property var modelData
                  width: (parent.width - 12) / 3
                  text: modelData.label
                  selected: root.fovMode === modelData.value
                  onClicked: root.setCameraFeature("fov", modelData.value)
                }
              }
            }
          }
          Toggle {
            visible: root.section === "ai" && root.hasVendorControls(); width: parent.width
            label: "Gesture control"; description: "Use hand gestures for subject selection and zoom"
            checked: root.gestureControlEnabled; foreground: root.barForeground
            onClicked: root.setCameraFeature("gesture-control", root.gestureControlEnabled ? "off" : "on")
          }
          Column {
            visible: root.section === "ai" && root.hasVendorControls()
            width: parent.width
            spacing: 6
            enabled: root.gestureControlEnabled
            Text {
              text: root.gestureControlEnabled ? "L-gesture zoom" : "L-gesture zoom · enable gestures first"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
            Row {
              width: parent.width
              spacing: 6
              Repeater {
                model: ["1x", "2x", "3x", "4x"]
                TabButton {
                  required property string modelData
                  width: (parent.width - 18) / 4
                  text: modelData
                  selected: root.gestureZoom === modelData
                  onClicked: root.setCameraFeature("gesture-zoom", modelData)
                }
              }
            }
          }

          Toggle {
            visible: root.section === "audio" && root.audioPage === "level" && root.hasVendorControls(); width: parent.width
            label: "Microphone"; description: "Enable the built-in microphone · restarts the camera briefly"
            checked: root.microphoneEnabled; foreground: root.barForeground
            enabled: root.connected && !actionProc.running
            onClicked: root.setCameraFeature("microphone", root.microphoneEnabled ? "off" : "on")
          }
          Toggle {
            visible: root.section === "audio" && root.audioPage === "level"; width: parent.width
            label: "Mute microphone"; description: root.audioSourceAvailable ? "Mute the OBSBOT input in PipeWire" : "OBSBOT audio input not available"
            checked: root.micMuted; foreground: root.barForeground
            enabled: root.audioSourceAvailable && root.microphoneEnabled
            onClicked: root.setAudio("mute", root.micMuted ? "off" : "on")
          }
          CameraSlider {
            visible: root.section === "audio" && root.audioPage === "level"
            label: "Microphone volume"; value: root.micVolume; from: 0; to: 150; step: 1; suffix: "%"
            enabled: root.audioSourceAvailable && root.microphoneEnabled
            onCommitted: function(v) { root.setAudio("volume", Math.round(v)) }
          }
          Toggle {
            visible: root.section === "audio" && root.audioPage === "processing" && root.hasVendorControls(); width: parent.width
            label: "Automatic gain"; description: "Adjust microphone gain automatically"
            checked: root.audioAgcEnabled; foreground: root.barForeground
            enabled: root.connected && root.microphoneEnabled
            onClicked: root.setCameraFeature("audio-agc", root.audioAgcEnabled ? "off" : "on")
          }
          Toggle {
            visible: root.section === "audio" && root.audioPage === "processing" && root.hasVendorControls(); width: parent.width
            label: "Microphone during sleep"; description: "Keep capturing audio while the camera sleeps"
            checked: root.sleepMicrophoneEnabled; foreground: root.barForeground
            enabled: root.connected && root.microphoneEnabled
            onClicked: root.setCameraFeature("sleep-microphone", root.sleepMicrophoneEnabled ? "off" : "on")
          }
          Column {
            visible: root.section === "audio" && root.audioPage === "processing" && root.hasVendorControls()
            width: parent.width
            spacing: 6
            Text {
              text: "Capture distance"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
            Row {
              width: parent.width
              spacing: 6
              Repeater {
                model: [{ value: "near", label: "Near" }, { value: "standard", label: "Standard" }, { value: "far", label: "Far" }]
                TabButton {
                  required property var modelData
                  width: (parent.width - 12) / 3
                  text: modelData.label
                  selected: root.audioDistance === modelData.value
                  enabled: root.connected && root.microphoneEnabled
                  onClicked: root.setCameraFeature("audio-distance", modelData.value)
                }
              }
            }
          }
          Column {
            visible: root.section === "audio" && root.audioPage === "processing" && root.hasVendorControls()
            width: parent.width
            spacing: 6
            Text {
              text: "Audio mode"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
            Grid {
              width: parent.width
              columns: 2
              columnSpacing: 6
              rowSpacing: 6
              Repeater {
                model: [
                  { value: "pure", label: "Pure audio" },
                  { value: "omni", label: "Smart omni" },
                  { value: "directional", label: "Directional" },
                  { value: "dual-directional", label: "Front / rear" }
                ]
                TabButton {
                  required property var modelData
                  width: (parent.width - 6) / 2
                  text: modelData.label
                  selected: root.audioMode === modelData.value
                  enabled: root.connected && root.microphoneEnabled
                  onClicked: root.setCameraFeature("audio-mode", modelData.value)
                }
              }
            }
          }

          Toggle {
            visible: root.section === "advanced" && root.advancedPage === "optics" && root.supported("focus_automatic_continuous"); width: parent.width
            label: "Autofocus"; description: "Keep the subject in focus automatically"
            checked: root.autofocus; foreground: root.barForeground
            onClicked: root.setControl("focus_automatic_continuous", root.autofocus ? 0 : 1)
          }
          CameraSlider { visible: root.section === "advanced" && root.advancedPage === "optics" && root.supported("focus_absolute"); label: "Manual focus"; value: root.focusValue; from: root.controlMin("focus_absolute", 0); to: root.controlMax("focus_absolute", 100); step: root.controlStep("focus_absolute", 1); enabled: root.connected && !root.autofocus; onCommitted: function(v) { root.setControl("focus_absolute", v) } }
          Toggle {
            visible: root.section === "advanced" && root.advancedPage === "optics" && root.supported("auto_exposure"); width: parent.width
            label: "Auto exposure"; description: "Adapt exposure when lighting changes"
            checked: root.autoExposure; foreground: root.barForeground
            onClicked: root.setControl("auto_exposure", root.autoExposure ? 1 : 0)
          }
          CameraSlider { visible: root.section === "advanced" && root.advancedPage === "optics" && root.supported("exposure_time_absolute"); label: "Exposure time"; value: root.exposure; from: root.controlMin("exposure_time_absolute", 1); to: root.controlMax("exposure_time_absolute", 2500); step: root.controlStep("exposure_time_absolute", 1); enabled: root.connected && !root.autoExposure; onCommitted: function(v) { root.setControl("exposure_time_absolute", v) } }
          Toggle {
            visible: root.section === "advanced" && root.advancedPage === "color" && root.supported("white_balance_automatic"); width: parent.width
            label: "Auto white balance"; description: "Adapt color temperature to ambient light"
            checked: root.autoWhiteBalance; foreground: root.barForeground
            onClicked: root.setControl("white_balance_automatic", root.autoWhiteBalance ? 0 : 1)
          }
          CameraSlider { visible: root.section === "advanced" && root.advancedPage === "color" && root.supported("white_balance_temperature"); label: "Color temperature"; value: root.whiteBalanceTemperature; from: root.controlMin("white_balance_temperature", 2000); to: root.controlMax("white_balance_temperature", 10000); step: root.controlStep("white_balance_temperature", 100); suffix: " K"; enabled: root.connected && !root.autoWhiteBalance; onCommitted: function(v) { root.setControl("white_balance_temperature", v) } }
          CameraSlider { visible: root.section === "advanced" && root.advancedPage === "color" && root.supported("red_balance"); label: "Red balance"; value: root.redBalance; from: root.controlMin("red_balance", 0); to: root.controlMax("red_balance", 2048); step: root.controlStep("red_balance", 1); enabled: root.connected && !root.autoWhiteBalance; onCommitted: function(v) { root.setControl("red_balance", v) } }
          CameraSlider { visible: root.section === "advanced" && root.advancedPage === "color" && root.supported("blue_balance"); label: "Blue balance"; value: root.blueBalance; from: root.controlMin("blue_balance", 0); to: root.controlMax("blue_balance", 2048); step: root.controlStep("blue_balance", 1); enabled: root.connected && !root.autoWhiteBalance; onCommitted: function(v) { root.setControl("blue_balance", v) } }
          Column {
            visible: root.section === "advanced" && root.advancedPage === "color" && root.supported("power_line_frequency")
            width: parent.width; spacing: 6
            Text { text: "Anti-flicker"; color: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body }
            Row {
              width: parent.width; spacing: 6
              Repeater {
                model: [{ value: 0, label: "Off" }, { value: 1, label: "50 Hz" }, { value: 2, label: "60 Hz" }]
                TabButton { required property var modelData; width: (parent.width - 12) / 3; text: modelData.label; selected: root.powerLineFrequency === modelData.value; onClicked: root.setControl("power_line_frequency", modelData.value) }
              }
            }
          }
          CameraSlider { visible: root.section === "advanced" && root.advancedPage === "color" && root.supported("hue"); label: "Hue"; value: root.hue; from: root.controlMin("hue", 0); to: root.controlMax("hue", 100); step: root.controlStep("hue", 1); onCommitted: function(v) { root.setControl("hue", v) } }
          CameraSlider { visible: root.section === "advanced" && root.advancedPage === "optics" && root.supported("gain"); label: "Gain"; value: root.gain; from: root.controlMin("gain", 1); to: root.controlMax("gain", 64); step: root.controlStep("gain", 1); onCommitted: function(v) { root.setControl("gain", v) } }
          CameraSlider { visible: root.section === "advanced" && root.advancedPage === "optics" && root.supported("backlight_compensation"); label: "Backlight compensation"; value: root.backlightCompensation; from: root.controlMin("backlight_compensation", 0); to: root.controlMax("backlight_compensation", 18); step: root.controlStep("backlight_compensation", 1); onCommitted: function(v) { root.setControl("backlight_compensation", v) } }

          Toggle {
            visible: root.section === "advanced" && root.advancedPage === "device" && root.hasVendorControls(); width: parent.width
            label: "Mirror image"; description: "Flip the image horizontally"
            checked: root.mirrorEnabled; foreground: root.barForeground
            onClicked: root.setCameraFeature("mirror", root.mirrorEnabled ? "off" : "on")
          }
          Toggle {
            visible: root.section === "advanced" && root.advancedPage === "color" && root.hasVendorControls(); width: parent.width
            label: "HDR"; description: "Preserve detail in bright and dark areas"
            checked: root.hdrEnabled; foreground: root.barForeground
            onClicked: root.setCameraFeature("hdr", root.hdrEnabled ? "off" : "on")
          }
          Toggle {
            visible: root.section === "advanced" && root.advancedPage === "device" && root.hasVendorControls(); width: parent.width
            label: "Portrait orientation"; description: "Switch the camera to vertical video mode"
            checked: root.verticalEnabled; foreground: root.barForeground
            onClicked: root.setCameraFeature("vertical", root.verticalEnabled ? "off" : "on")
          }
          Toggle {
            visible: root.section === "advanced" && root.advancedPage === "device" && root.hasVendorControls(); width: parent.width
            label: "Status LED"; description: "Enable the camera indicator light"
            checked: root.ledEnabled; foreground: root.barForeground
            onClicked: root.setCameraFeature("led", root.ledEnabled ? "off" : "on")
          }
          Toggle {
            visible: root.section === "advanced" && root.advancedPage === "device" && root.hasVendorControls(); width: parent.width
            label: "Keep camera awake"; description: "Prevent sleep when no application is streaming"
            checked: root.keepAwakeEnabled; foreground: root.barForeground
            onClicked: root.setCameraFeature("keep-awake", root.keepAwakeEnabled ? "off" : "on")
          }
          Column {
            visible: root.section === "advanced" && root.advancedPage === "device" && root.hasVendorControls()
            width: parent.width; spacing: 6; enabled: !root.keepAwakeEnabled
            Text { text: root.keepAwakeEnabled ? "Auto sleep · disabled by Keep camera awake" : "Auto sleep"; color: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body }
            Flow {
              width: parent.width; spacing: 6
              Repeater {
                model: [{ value: "off", label: "Off" }, { value: "30s", label: "30 sec" }, { value: "2m", label: "2 min" }, { value: "10m", label: "10 min" }]
                TabButton { required property var modelData; text: modelData.label; selected: root.autoSleep === modelData.value; onClicked: root.setCameraFeature("auto-sleep", modelData.value) }
              }
            }
          }

          PanelSectionHeader { visible: root.section === "basic" && root.hasMeet2Presets(); text: "MEET 2 PRESETS"; foreground: root.barForeground }
          Flow {
            visible: root.section === "basic" && root.hasMeet2Presets()
            width: parent.width
            spacing: 6
            Repeater {
              model: [{ value: "default", label: "Default" }, { value: "natural", label: "Natural" }, { value: "low-light", label: "Low light" }, { value: "streaming", label: "Streaming" }]
              TabButton {
                required property var modelData
                text: modelData.label
                onClicked: root.applyPreset(modelData.value)
              }
            }
          }

          Text {
            visible: actionProc.running
            width: parent.width
            text: "Applying camera setting…"
            color: root.barForeground
            wrapMode: Text.WordWrap
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.errorMessage !== ""
            width: parent.width
            text: root.errorMessage
            color: root.themeUrgent
            wrapMode: Text.WordWrap
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
