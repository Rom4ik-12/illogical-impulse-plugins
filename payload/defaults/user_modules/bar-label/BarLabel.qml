import QtQuick
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    implicitWidth: label.implicitWidth + 8
    implicitHeight: label.implicitHeight

    FileView {
        id: cfgFile
        path: `${Directories.shellConfig}/user_modules_state/bar-label/config.json`
        watchChanges: true
    }

    property var cfg: {
        try { return JSON.parse(cfgFile.text || "{}") } catch(e) { return {} }
    }

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.cfg.text || "★"
        color: root.cfg.useAccent
            ? Appearance.colors.colPrimary
            : Appearance.colors.colOnLayer0
        font.pixelSize: Appearance.font.pixelSize.normal
    }
}
