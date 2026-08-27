import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui

Item {
    id: root

    required property var controller
    property bool open: false

    PanelWindow {
        id: window
        visible: root.open
        screen: root.controller.anchorItem ? root.controller.anchorItem.QsWindow.window.screen : null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-shorten-url-settings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Color.menu.scrim
            MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
        }

        Ui.BorderSurface {
            id: card
            anchors.centerIn: parent
            width: Math.min(Style.space(620), window.width - Style.gapsOut * 2)
            radius: Style.cornerRadius
            color: Color.menu.background
            borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
            padding: Style.spacing.panelPadding
            height: Math.min(
                Math.max(Style.space(220), settingsContent.implicitHeight + card.contentTopInset + card.contentBottomInset),
                window.height - Style.gapsOut * 2
            )

            MouseArea { anchors.fill: parent }

            Ui.PanelKeyCatcher {
                id: keyCatcher
                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset
                anchors.rightMargin: card.contentRightInset
                blocked: editorNameField.activeFocus || editorApiUrlField.activeFocus
                onCloseRequested: root.dismiss()

                ColumnLayout {
                    id: settingsContent
                    anchors.fill: parent
                    spacing: Style.spacing.md

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Providers"
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                            font.weight: Font.Medium
                        }

                        Ui.Button {
                            id: settingsAddButton
                            text: "Add"
                            visible: !root.controller.editorOpen
                            onClicked: root.controller.beginAddProfile()
                        }
                    }

                    Ui.PanelSeparator { Layout.fillWidth: true }

                    ListView {
                        id: profileList
                        Layout.fillWidth: true
                        visible: !root.controller.editorOpen && root.controller.hasProfiles
                        model: root.controller.profileRecords
                        spacing: Style.spacing.xs
                        clip: true
                        implicitHeight: visible ? Math.min(contentHeight, Style.space(280)) : 0

                        delegate: Ui.BorderSurface {
                            id: profileRow
                            width: profileList.width
                            implicitHeight: profileRowContent.implicitHeight + Style.spacing.sm * 2
                            radius: Style.cornerRadius
                            color: model.name === root.controller.selectedProfile
                                ? Color.menu.selectedBackground : Color.menu.background
                            borderSpec: Border.flat(
                                model.name === root.controller.selectedProfile
                                    ? Color.menu.selectedBorder : Color.popups.border,
                                Math.max(1, Style.space(1))
                            )

                            RowLayout {
                                id: profileRowContent
                                anchors.fill: parent
                                anchors.margins: Style.spacing.sm
                                spacing: Style.spacing.sm

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.spacing.xxs

                                    Text {
                                        Layout.fillWidth: true
                                        text: model.name
                                        color: Color.foreground
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.body
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: model.type + " · " + model.apiUrl
                                        color: Color.muted
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideMiddle
                                    }
                                }

                                Text {
                                    text: "Default"
                                    visible: model.isDefault
                                    color: Color.muted
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                }

                                Ui.Button {
                                    text: "Set default"
                                    visible: !model.isDefault
                                    onClicked: root.controller.setDefaultProfile(model.name)
                                }

                                Ui.Button {
                                    text: "Edit"
                                    onClicked: root.controller.beginEditProfile(model.name)
                                }

                                Ui.Button {
                                    text: root.controller.deleteConfirmOpen
                                        && root.controller.selectedProfile === model.name
                                        ? "Confirm delete" : "Delete"
                                    onClicked: {
                                        if (root.controller.deleteConfirmOpen
                                            && root.controller.selectedProfile === model.name)
                                            root.controller.deleteProfile(model.name)
                                        else {
                                            root.controller.selectedProfile = model.name
                                            root.controller.deleteConfirmOpen = true
                                        }
                                    }
                                }

                                Ui.Button {
                                    text: "Cancel"
                                    visible: root.controller.deleteConfirmOpen
                                        && root.controller.selectedProfile === model.name
                                    onClicked: root.controller.deleteConfirmOpen = false
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !root.controller.editorOpen && root.controller.hasProfiles
                            && root.controller.deleteConfirmOpen
                        text: root.controller.selectedProfile === root.controller.defaultProfile
                            ? "Deleting the default will select another profile. Confirm?"
                            : "Delete this provider profile?"
                        color: Color.urgent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.controller.editorOpen
                        spacing: Style.spacing.controlGap

                        Ui.PanelSectionHeader {
                            text: root.controller.editingProfile ? "Edit provider profile" : "Add provider profile"
                        }

                        Ui.TextField {
                            id: editorNameField
                            Layout.fillWidth: true
                            placeholderText: "Profile name"
                            text: root.controller.editorName
                            onTextChanged: root.controller.editorName = text
                        }

                        Ui.Dropdown {
                            Layout.fillWidth: true
                            label: "Provider type"
                            options: ["shlink", "yourls", "kutt", "polr", "bitly"]
                            value: root.controller.editorType
                            enabled: !root.controller.editingProfile
                            onValueChanged: root.controller.editorType = value
                        }

                        Ui.TextField {
                            id: editorApiUrlField
                            Layout.fillWidth: true
                            placeholderText: "API URL"
                            text: root.controller.editorApiUrl
                            onTextChanged: root.controller.editorApiUrl = text
                        }

                        Ui.TextField {
                            Layout.fillWidth: true
                            visible: root.controller.editorType !== "yourls"
                                && root.controller.editorType !== "bitly"
                            placeholderText: "API key"
                            echoMode: TextInput.Password
                            text: root.controller.editorApiKey
                            echoMode: TextInput.Password
                            onTextChanged: root.controller.editorApiKey = text
                        }

                        Ui.TextField {
                            Layout.fillWidth: true
                            visible: root.controller.editorType === "bitly"
                            placeholderText: "Access token"
                            text: root.controller.editorAccessToken
                            echoMode: TextInput.Password
                            onTextChanged: root.controller.editorAccessToken = text
                        }

                        Ui.TextField {
                            Layout.fillWidth: true
                            visible: root.controller.editorType === "yourls"
                            placeholderText: "Signature (or leave blank for username/password)"
                            text: root.controller.editorSignature
                            echoMode: TextInput.Password
                            onTextChanged: root.controller.editorSignature = text
                        }

                        Ui.TextField {
                            Layout.fillWidth: true
                            visible: root.controller.editorType === "yourls"
                                && root.controller.editorSignature === ""
                            placeholderText: "YOURLS username"
                            text: root.controller.editorUsername
                            onTextChanged: root.controller.editorUsername = text
                        }

                        Ui.TextField {
                            Layout.fillWidth: true
                            visible: root.controller.editorType === "yourls"
                                && root.controller.editorSignature === ""
                            placeholderText: "YOURLS password"
                            text: root.controller.editorPassword
                            echoMode: TextInput.Password
                            onTextChanged: root.controller.editorPassword = text
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Ui.Button { text: "Save profile"; onClicked: root.controller.saveProfile() }
                            Ui.Button { text: "Cancel"; onClicked: root.cancelEditor() }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.controller.profileError !== ""
                        text: root.controller.profileError
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    function dismiss() {
        root.controller.deleteConfirmOpen = false
        root.controller.editorOpen = false
        root.controller.settingsOpen = false
    }

    function cancelEditor() {
        root.controller.editorOpen = false
        root.controller.deleteConfirmOpen = false
    }
}
