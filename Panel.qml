import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui

Ui.Panel {
    id: root

    moduleName: "io.github.dmreiland.shorten-url"
    ipcTarget: root.moduleName
    // This panel is loaded once inside each bar widget instance. The shell
    // routes bar-widget IPC through the live widget, so registering the same
    // target here once per monitor creates duplicate handlers.
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null

    readonly property string scriptPath: Qt.resolvedUrl("bin/omarchy-shorten-url").toString().replace("file://", "")

    property string statusText: ""
    property bool busy: false
    property string profileError: ""
    property string pendingClipboardText: ""
    property string selectedProfile: ""
    property string defaultProfile: ""
    property bool editorOpen: false
    property bool settingsOpen: false
    property bool editingProfile: false
    property bool deleteConfirmOpen: false
    property string editingProfileName: ""
    property string editorName: ""
    property string editorType: "shlink"
    property string editorApiUrl: ""
    property string editorApiKey: ""
    property string editorAccessToken: ""
    property string editorSignature: ""
    property string editorUsername: ""
    property string editorPassword: ""
    property string pendingProfileJson: ""
    readonly property string configHelperPath: Qt.resolvedUrl("bin/omarchy-shorten-url-config").toString().replace("file://", "")
    readonly property var profileNames: profileModel.getNames()
    readonly property var profileRecords: profileModel
    readonly property bool hasProfiles: profileNames.length > 0

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
        for (var i = 0; i < profileModel.count; i++) {
            if (candidate === normalizeProviderHost(profileModel.get(i).apiUrl)) return true
        }
        return false
    }

    function applyClipboardText(value) {
        var clipped = String(value || "").trim()
        if (!/^https?:\/\//.test(clipped)) return
        if (root.isProviderUrl(clipped)) {
            if (urlField.text === clipped) urlField.text = ""
            return
        }
        urlField.text = clipped
    }

    function openSettings() {
        root.settingsOpen = true
        root.refreshProfiles()
    }

    // The bar identifies a mounted panel by its bar-widget slot, not this
    // nested item, so hand switchPanel the host widget's identity instead
    // of this panel's own (see Bar.findPanelWidget).
    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, direction)
        return false
    }

    function focusUrlField() {
        if (!root.opened || !root.hasProfiles) return
        Qt.callLater(function() {
            if (root.opened && root.hasProfiles) urlField.forceActiveFocus()
        })
    }

    function submitUrl() {
        if (root.busy || !root.selectedProfile || !urlField.text.length) return
        root.busy = true
        root.statusText = ""
        resultField.text = ""
        shortener.command = [root.scriptPath, urlField.text, "--profile", root.selectedProfile]
        shortener.running = true
    }

    onOpenedChanged: {
        if (root.opened) {
            clipboardReader.running = true
            root.refreshProfiles()
            root.refreshHistory()
            root.focusUrlField()
        }
    }

    function refreshHistory() {
        historyReader.command = [root.scriptPath, "--history"]
        historyReader.running = true
    }

    function refreshProfiles() {
        profileReader.running = true
    }

    function profileJson() {
        var value = { type: root.editorType, apiUrl: root.editorApiUrl }
        if (root.editorType === "yourls") {
            if (root.editorSignature.length > 0) value.signature = root.editorSignature
            else { value.username = root.editorUsername; value.password = root.editorPassword }
        } else if (root.editorType === "bitly") value.accessToken = root.editorAccessToken
        else value.apiKey = root.editorApiKey
        return JSON.stringify(value)
    }

    function beginAddProfile() {
        root.editorOpen = true
        root.editingProfile = false
        root.editingProfileName = ""
        root.editorName = ""
        root.editorType = "shlink"
        root.editorApiUrl = ""
        root.editorApiKey = ""
        root.editorAccessToken = ""
        root.editorSignature = ""
        root.editorUsername = ""
        root.editorPassword = ""
        root.profileError = ""
    }

    function beginEditProfile(profileName) {
        var target = profileName || root.selectedProfile
        if (!target) return
        root.editingProfileName = target
        editReader.command = [root.configHelperPath, "--get", target]
        editReader.running = true
    }

    function saveProfile() {
        if (!root.editorName.trim()) { root.profileError = "Profile name is required"; return }
        profileWriter.command = [root.configHelperPath,
            root.editingProfile && root.editorName.trim() !== root.selectedProfile ? "--rename-profile" : "--save-profile"]
        if (root.editingProfile && root.editorName.trim() !== root.editingProfileName)
            profileWriter.command.push(root.editingProfileName)
        profileWriter.command.push(root.editorName.trim())
        root.pendingProfileJson = root.profileJson()
        profileWriter.running = true
    }

    function setDefaultProfile(profileName) {
        var target = profileName || root.selectedProfile
        if (!target) return
        profileAction.command = [root.configHelperPath, "--set-default", target]
        profileAction.running = true
    }

    function deleteProfile(profileName) {
        var target = profileName || root.selectedProfile
        if (!target) return
        profileAction.command = [root.configHelperPath, "--delete", target]
        profileAction.running = true
        root.deleteConfirmOpen = false
    }

    ListModel {
        id: historyModel
    }

    ListModel {
        id: profileModel
        function getNames() {
            var names = []
            for (var i = 0; i < count; i++) names.push(get(i).name)
            return names
        }
    }

    Process {
        id: profileReader
        command: [root.configHelperPath, "--list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var records = []
                try { records = JSON.parse(text.trim() || "[]") } catch (e) { root.profileError = "Could not read provider profiles" }
                profileModel.clear()
                for (const record of records) profileModel.append(record)
                root.defaultProfile = ""
                for (const record of records) if (record.isDefault) root.defaultProfile = record.name
                if (!root.selectedProfile || profileNames.indexOf(root.selectedProfile) < 0) {
                    root.selectedProfile = root.defaultProfile || (profileNames.length > 0 ? profileNames[0] : "")
                }
                root.applyClipboardText(root.pendingClipboardText)
                root.pendingClipboardText = ""
                root.focusUrlField()
            }
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) root.profileError = "No provider profiles configured"
        }
    }

    Process {
        id: editReader
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var value = JSON.parse(text.trim())
                    root.editorOpen = true
                    root.editingProfile = true
                    root.editorName = root.editingProfileName
                    root.editorType = value.type || "shlink"
                    root.editorApiUrl = value.apiUrl || ""
                    root.editorApiKey = value.apiKey || ""
                    root.editorAccessToken = value.accessToken || ""
                    root.editorSignature = value.signature || ""
                    root.editorUsername = value.username || ""
                    root.editorPassword = value.password || ""
                } catch (e) { root.profileError = "Could not load selected profile" }
            }
        }
    }

    Process {
        id: profileWriter
        stdinEnabled: true
        stderr: StdioCollector { id: profileWriterError; waitForEnd: true }
        onStarted: profileWriter.write(root.pendingProfileJson + "\n")
        onExited: {
            root.pendingProfileJson = ""
            if (exitCode !== 0) root.profileError = profileWriterError.text.trim() || "Could not save provider profile"
            else {
                root.selectedProfile = root.editorName.trim()
                root.editorOpen = false
                root.profileError = "Profile saved"
                root.refreshProfiles()
            }
        }
    }

    Process {
        id: profileAction
        stderr: StdioCollector { id: profileActionError; waitForEnd: true }
        onExited: {
            if (exitCode !== 0) root.profileError = profileActionError.text.trim() || "Provider profile action failed"
            else { root.profileError = ""; root.refreshProfiles() }
        }
    }

    Process {
        id: historyReader
        stdout: StdioCollector {
            onStreamFinished: {
                historyModel.clear()
                let entries = []
                try {
                    entries = JSON.parse(text.trim() || "[]")
                } catch (e) {
                    entries = []
                }
                for (const entry of entries) {
                    historyModel.append({
                        shortUrl: entry.shortUrl || "",
                        longUrl: entry.longUrl || "",
                        provider: entry.provider || ""
                    })
                }
            }
        }
    }

    Process {
        id: historyCopier
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
        stdout: StdioCollector {
            id: shortenerOut
        }
        stderr: StdioCollector {
            id: shortenerErr
        }
        onExited: (exitCode, exitStatus) => {
            root.busy = false
            if (exitCode === 0) {
                resultField.text = shortenerOut.text.trim()
                urlField.text = ""
                root.statusText = "Copied to clipboard"
                root.refreshHistory()
            } else {
                resultField.text = ""
                root.statusText = shortenerErr.text.trim() || "Failed to shorten URL"
            }
        }
    }

    ProviderSettings {
        id: providerSettings
        controller: root
        open: root.settingsOpen
    }

    Ui.KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.spacing.dropdownWidth)
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        Ui.PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            // The URL/result fields are free-text entry, not a navigable
            // list, so keys must reach them normally instead of being
            // read as j/k/h/l/x navigation shortcuts.
            blocked: urlField.activeFocus || resultField.activeFocus
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }

            ColumnLayout {
                id: content
                width: parent.width
                spacing: Style.spacing.md

                Ui.PanelSectionHeader {
                    text: "Shorten URL"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacing.controlGap

                    Ui.Dropdown {
                        id: profileDropdown
                        Layout.fillWidth: true
                        visible: root.hasProfiles
                        label: "Profile"
                        options: root.profileNames
                        value: root.selectedProfile
                        onValueChanged: root.selectedProfile = value
                    }

                    Ui.Button {
                        text: "Add"
                        visible: !root.hasProfiles
                        onClicked: root.beginAddProfile()
                    }

                    Ui.Button {
                        id: settingsButton
                        text: ""
                        visible: root.hasProfiles
                        fontSize: Style.font.icon
                        tooltipText: "Providers"
                        onClicked: root.openSettings()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacing.controlGap
                    visible: false

                    Ui.Button {
                        text: "Set default"
                        enabled: root.selectedProfile !== "" && root.selectedProfile !== root.defaultProfile
                        onClicked: root.setDefaultProfile()
                    }

                    Ui.Button {
                        text: root.deleteConfirmOpen ? "Confirm delete" : "Delete"
                        enabled: root.selectedProfile !== ""
                        onClicked: {
                            if (root.deleteConfirmOpen) root.deleteProfile()
                            else root.deleteConfirmOpen = true
                        }
                    }

                    Ui.Button {
                        text: "Cancel"
                        visible: root.deleteConfirmOpen
                        onClicked: root.deleteConfirmOpen = false
                    }
                }

                Text {
                    id: profileSetupText
                    text: "Add a provider profile to get started."
                    visible: !root.hasProfiles && !root.editorOpen
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    text: root.deleteConfirmOpen
                        ? (root.selectedProfile === root.defaultProfile
                            ? "Deleting the default will select another profile. Confirm?"
                            : "Delete this provider profile?")
                        : root.profileError
                    visible: !root.hasProfiles && text.length > 0
                    color: root.deleteConfirmOpen ? Color.urgent : Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.editorOpen && !root.hasProfiles
                    spacing: Style.spacing.controlGap

                    Ui.PanelSectionHeader {
                        text: root.editingProfile ? "Edit provider profile" : "Add provider profile"
                    }

                    Ui.TextField {
                        id: editorNameField
                        Layout.fillWidth: true
                        placeholderText: "Profile name"
                        text: root.editorName
                        onTextChanged: root.editorName = text
                    }

                    Ui.Dropdown {
                        id: editorTypeDropdown
                        Layout.fillWidth: true
                        label: "Provider type"
                        options: ["shlink", "yourls", "kutt", "polr", "bitly"]
                        value: root.editorType
                        enabled: !root.editingProfile
                        onValueChanged: root.editorType = value
                    }

                    Ui.TextField {
                        Layout.fillWidth: true
                        placeholderText: "API URL"
                        text: root.editorApiUrl
                        onTextChanged: root.editorApiUrl = text
                    }

                    Ui.TextField {
                        Layout.fillWidth: true
                        visible: root.editorType !== "yourls" && root.editorType !== "bitly"
                        placeholderText: "API key"
                        echoMode: TextInput.Password
                        text: root.editorApiKey
                        echoMode: TextInput.Password
                        onTextChanged: root.editorApiKey = text
                    }

                    Ui.TextField {
                        Layout.fillWidth: true
                        visible: root.editorType === "bitly"
                        placeholderText: "Access token"
                        text: root.editorAccessToken
                        echoMode: TextInput.Password
                        onTextChanged: root.editorAccessToken = text
                    }

                    Ui.TextField {
                        Layout.fillWidth: true
                        visible: root.editorType === "yourls"
                        placeholderText: "Signature (or leave blank for username/password)"
                        text: root.editorSignature
                        echoMode: TextInput.Password
                        onTextChanged: root.editorSignature = text
                    }

                    Ui.TextField {
                        Layout.fillWidth: true
                        visible: root.editorType === "yourls" && root.editorSignature === ""
                        placeholderText: "YOURLS username"
                        text: root.editorUsername
                        onTextChanged: root.editorUsername = text
                    }

                    Ui.TextField {
                        Layout.fillWidth: true
                        visible: root.editorType === "yourls" && root.editorSignature === ""
                        placeholderText: "YOURLS password"
                        text: root.editorPassword
                        echoMode: TextInput.Password
                        onTextChanged: root.editorPassword = text
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Ui.Button { text: "Save profile"; onClicked: root.saveProfile() }
                        Ui.Button { text: "Cancel"; onClicked: root.editorOpen = false }
                    }
                }

                Ui.PanelSeparator {
                    Layout.fillWidth: true
                    visible: root.hasProfiles
                }

                Ui.TextField {
                    id: urlField
                    Layout.fillWidth: true
                    visible: root.hasProfiles
                    placeholderText: "https://example.com/very/long/url"
                    Keys.onEscapePressed: root.close()
                    onAccepted: root.submitUrl()
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacing.controlGap
                    visible: root.hasProfiles

                    Ui.Button {
                        text: root.busy ? "Shortening…" : "Shorten"
                        enabled: !root.busy && urlField.text.length > 0 && root.selectedProfile !== ""
                        onClicked: root.submitUrl()
                    }

                }

                Ui.TextField {
                    id: resultField
                    Layout.fillWidth: true
                    visible: root.hasProfiles
                    readOnly: true
                    placeholderText: "Shortened URL will appear here"
                    Keys.onEscapePressed: root.close()
                }

                Text {
                    text: root.statusText
                    visible: root.hasProfiles && root.statusText.length > 0
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Ui.PanelSeparator {
                    Layout.fillWidth: true
                    visible: root.hasProfiles && historyModel.count > 0
                }

                Ui.PanelSectionHeader {
                    text: "Recent links"
                    visible: root.hasProfiles && historyModel.count > 0
                }

                Repeater {
                    model: historyModel
                    visible: root.hasProfiles

                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacing.controlGap

                        Text {
                            Layout.fillWidth: true
                            text: shortUrl
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    historyCopier.command = [root.scriptPath, "--copy", shortUrl]
                                    historyCopier.running = true
                                    root.statusText = "Copied to clipboard"
                                }
                            }
                        }

                    }
                }
            }
        }
    }
}
