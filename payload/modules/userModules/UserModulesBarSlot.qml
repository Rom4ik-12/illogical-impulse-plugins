// Drop this anywhere in the bar layout to expose a single extension point.
// Any enabled user-module can contribute widgets here by declaring:
//
//   { "barWidgets": [ { "source": "MyWidget.qml" } ] }
//
// in its module.json. Widgets appear in module-load order.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common

RowLayout {
    id: root
    spacing: 4
    Layout.alignment: Qt.AlignVCenter
    visible: repeater.count > 0

    Repeater {
        id: repeater
        model: UserModules.barWidgets
        delegate: Loader {
            required property var modelData
            asynchronous: true
            source: modelData.url
            onStatusChanged: {
                if (status === Loader.Error) {
                    console.warn(`[UserModules] bar widget '${modelData.moduleId}' failed: ${modelData.url}`);
                }
            }
        }
    }
}
