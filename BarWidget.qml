import QtQuick
import qs.Commons
import qs.Ui as Ui

// Bar icon that hosts the shorten-url popup. Shape contract for
// shell.summon/hide/toggle routing: Bar.findPanelWidget requires
// open/close/opened on the bar-widget root. Panel.qml is loaded directly
// below rather than through a second manifest entry point, since the shell
// only ever resolves a bar-widget plugin's "barWidget" entry point.
Ui.BarWidget {
    id: root

    moduleName: "io.github.dmreiland.shorten-url"

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function open() {
        if (panelLoader.item) panelLoader.item.open()
    }

    function close() {
        if (panelLoader.item) panelLoader.item.close()
    }

    function toggle() {
        if (panelLoader.item) panelLoader.item.toggle()
    }

    function closeForPopoutSwitch() {
        if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
    }

    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        target.bar = root.bar
        target.settings = root.settings
        target.anchorItem = button
        target.hostWidget = root
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()

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

    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "" // Nerd Font fa-link glyph, matches the rest of the bar's icon set
        fontSize: Style.font.icon
        tooltipText: "Shorten URL"

        onPressed: function(b) {
            if (b === Qt.LeftButton) root.toggle()
        }
    }
}
