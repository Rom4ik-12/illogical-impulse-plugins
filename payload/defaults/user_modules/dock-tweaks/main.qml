// Dock Tweaks — example user module that modifies the dock at runtime.
//
// What it does:
//   • Super+Shift+D  — toggle dock on/off (writes Config.options.dock.enable)
//   • Super+Shift+P  — append your favourite app to dock pinned list (and
//                      remove it if already pinned)
//   • Auto-enables the dock when no window is focused (handy for empty
//     workspaces). Disable by toggling the module off in Settings.
//
// Everything here is just regular shell QML — `Config.options` is the same
// store the Settings app writes to, so changes persist immediately.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common
import qs.services

QtObject {
    id: root

    // App ID that the "pin/unpin" shortcut toggles. Tweak to taste.
    readonly property string toggleApp: "kitty"

    Component.onCompleted: console.log("[dock-tweaks] loaded")
    Component.onDestruction: console.log("[dock-tweaks] unloaded")

    property var toggleDockShortcut: GlobalShortcut {
        name: "dockTweaksToggle"
        description: "Toggle dock enable"
        onPressed: {
            Config.options.dock.enable = !Config.options.dock.enable;
            console.log("[dock-tweaks] dock.enable =", Config.options.dock.enable);
        }
    }

    property var togglePinShortcut: GlobalShortcut {
        name: "dockTweaksTogglePin"
        description: "Pin/unpin " + root.toggleApp + " in the dock"
        onPressed: {
            const list = (Config.options.dock.pinnedApps ?? []).slice();
            const idx = list.indexOf(root.toggleApp);
            if (idx === -1) list.push(root.toggleApp);
            else list.splice(idx, 1);
            Config.options.dock.pinnedApps = list;
            console.log("[dock-tweaks] pinned =", JSON.stringify(list));
        }
    }

    // Auto-show dock when nothing is focused
    property var autoReveal: Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            if (!ToplevelManager.activeToplevel && !Config.options.dock.enable) {
                Config.options.dock.enable = true;
            }
        }
    }
}
