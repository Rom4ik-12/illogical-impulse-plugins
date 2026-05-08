// Example user module — entry point.
//
// A module's entry file is loaded as-is into the shell. The root element
// can be any QtObject. Inside you may declare PanelWindows, GlobalShortcuts,
// IpcHandlers, Timers, Processes, etc.
//
// You have full access to the shell's services and widgets:
//   import qs.services
//   import qs.modules.common
//   import qs.modules.common.widgets

import QtQuick
import Quickshell
import Quickshell.Hyprland

QtObject {
    Component.onCompleted: console.log("[example-hello] loaded")
    Component.onDestruction: console.log("[example-hello] unloaded")

    property var shortcut: GlobalShortcut {
        name: "exampleHelloPing"
        description: "Example module: prints hello to the log"
        onPressed: console.log("[example-hello] hello!")
    }
}
