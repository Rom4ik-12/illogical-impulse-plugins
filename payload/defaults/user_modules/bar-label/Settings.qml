import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    property string moduleDataDir
    property string moduleId

    spacing: 0

    FileView {
        id: cfgFile
        path: moduleDataDir + "/config.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: cfgFile.writeAdapter()
        onLoadFailed: cfgFile.writeAdapter()
        JsonAdapter {
            id: cfg
            property string text: "★"
            property bool useAccent: false
        }
    }

    ConfigRow {
        Layout.fillWidth: true
        StyledText {
            text: Translation.tr("Bar label text")
            Layout.fillWidth: true
        }
        MaterialTextArea {
            id: textField
            implicitWidth: 160
            wrapMode: TextEdit.NoWrap
            text: cfg.text
            onTextChanged: if (text !== cfg.text) cfg.text = text
        }
    }

    ConfigSwitch {
        text: Translation.tr("Use accent colour")
        checked: cfg.useAccent
        onCheckedChanged: cfg.useAccent = checked
    }
}
