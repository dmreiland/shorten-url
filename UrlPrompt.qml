import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui

Item {
    id: root

    property bool opened: false
    property var shell: null
    property string selectedProfile: ""
    property string defaultProfile: ""
    property string pendingClipboardText: ""
    property bool busy: false
    property string scriptPath: Qt.resolvedUrl("bin/omarchy-shorten-url").toString().replace("file://", "")
    property string configHelperPath: Qt.resolvedUrl("bin/omarchy-shorten-url-config").toString().replace("file://", "")

    readonly property var promptScreen: {
        var screens = Quickshell.screens
        var focusedName = ""
        if (root.shell && root.shell.bar && typeof root.shell.bar.focusedScreenName === "function")
            focusedName = root.shell.bar.focusedScreenName()
        for (var i = 0; i < screens.length; i++)
            if (String(screens[i].name || "") === focusedName) return screens[i]
        return screens.length > 0 ? screens[0] : null
    }

    function normalizeProviderHost(value) {
        var candidate = String(value || "").trim().toLowerCase()
        candidate = candidate.replace(/^[a-z]+:\/\//, "")
        candidate = candidate.split("/")[0]
        candidate = candidate.split("@").pop()
        return candidate.replace(/:\d+$/, "")
    }

    function isProviderUrl(value) {
        var candidate = normalizeProviderHost(value)
        if (!candidate) return false
        if (candidate === "bitly.is") return true
        for (var i = 0; i < profileModel.count; i++) {
            if (candidate === normalizeProviderHost(profileModel.get(i).apiUrl)) return true
        }
        return false
    }

    function applyClipboardText(value) {
        var clipped = String(value || "").trim()
        if (!/^https?:\/\//.test(clipped) || root.isProviderUrl(clipped)) return
        urlField.text = clipped
    }

    function focusUrlField() {
        if (!root.opened) return
        Qt.callLater(function() {
            if (root.opened) urlField.forceActiveFocus()
        })
    }

    function submitUrl() {
        if (root.busy || !root.selectedProfile || !urlField.text.length) return
        root.busy = true
        shortener.command = [root.scriptPath, urlField.text, "--profile", root.selectedProfile]
        shortener.running = true
    }

    function open(payloadJson) {
        root.opened = true
        urlField.text = ""
        root.pendingClipboardText = ""
        profileReader.running = true
        clipboardReader.running = true
        focusUrlField()
    }

    function close() {
        root.opened = false
    }

    ListModel { id: profileModel }

    Process {
        id: profileReader
        command: [root.configHelperPath, "--list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var records = []
                try { records = JSON.parse(text.trim() || "[]") } catch (e) {}
                profileModel.clear()
                for (const record of records) profileModel.append(record)
                root.defaultProfile = ""
                for (const record of records) if (record.isDefault) root.defaultProfile = record.name
                root.selectedProfile = root.defaultProfile || (records.length > 0 ? records[0].name : "")
                root.applyClipboardText(root.pendingClipboardText)
                root.pendingClipboardText = ""
                root.focusUrlField()
            }
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) root.close()
        }
    }

    Process {
        id: clipboardReader
        command: ["wl-paste", "-n"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.pendingClipboardText = text.trim()
                root.applyClipboardText(root.pendingClipboardText)
            }
        }
    }

    Process {
        id: shortener
        onExited: {
            root.busy = false
            if (exitCode === 0) {
                root.close()
            }
        }
    }

    PanelWindow {
        id: window
        visible: root.opened
        screen: root.promptScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-shorten-url-prompt"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Color.menu.scrim
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        Ui.BorderSurface {
            id: card
            anchors.centerIn: parent
            width: Math.min(Style.space(620), window.width - Style.gapsOut * 2)
            height: Math.min(Style.space(100), window.height - Style.gapsOut * 2)
            radius: Style.cornerRadius
            color: Color.menu.background
            borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
            padding: Style.spacing.panelPadding

            MouseArea { anchors.fill: parent }

            Ui.PanelKeyCatcher {
                id: keyCatcher
                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset
                anchors.rightMargin: card.contentRightInset
                blocked: urlField.activeFocus
                onCloseRequested: root.close()

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Style.spacing.md

                    Ui.TextField {
                        id: urlField
                        Layout.fillWidth: true
                        placeholderText: "https://example.com/very/long/url"
                        enabled: root.selectedProfile !== ""
                        Keys.onEscapePressed: root.close()
                        onAccepted: root.submitUrl()
                    }
                }
            }
        }
    }
}
