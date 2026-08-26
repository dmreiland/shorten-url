import QtQuick
import Quickshell.Io

Item {
    id: root

    property var shell: null
    readonly property string moduleName: "io.github.dmreiland.shorten-url"

    function open(): string {
        return root.shell && root.shell.bar
            && root.shell.bar.summonBarWidget(root.moduleName) ? "ok" : "unknown"
    }

    function close(): string {
        return root.shell && root.shell.bar
            && root.shell.bar.hideBarWidget(root.moduleName) ? "ok" : "unknown"
    }

    function toggle(): string {
        if (!root.shell || !root.shell.bar) return "unknown"
        if (root.shell.bar.isBarWidgetOpen(root.moduleName)) return root.close()
        return root.open()
    }

    IpcHandler {
        target: root.moduleName

        function open(): string { return root.open() }
        function close(): string { return root.close() }
        function toggle(): string { return root.toggle() }
    }
}
