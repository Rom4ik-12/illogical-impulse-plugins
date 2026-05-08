import QtQuick
import Quickshell
import qs.services
import qs.modules.common

// Instantiates every enabled user module as a child Loader.
// Modules are top-level QtObject (or Item) files whose contents may
// declare PanelWindows, GlobalShortcuts, IpcHandlers, etc.
Item {
    id: root
    visible: false

    // Repeater iterates ALL modules (so toggling one doesn't tear down the
    // others). Each Loader becomes active only when its module is enabled.
    Repeater {
        model: UserModules.modules
        delegate: Loader {
            id: modLoader
            required property var modelData
            active: Config.ready && UserModules.isEnabled(modelData.id)
            asynchronous: true
            source: active ? modelData.entryUrl : ""
            onStatusChanged: {
                if (status === Loader.Error) {
                    console.warn(`[UserModules] Failed to load '${modelData.id}' from ${source}`);
                }
            }
        }
    }
}
