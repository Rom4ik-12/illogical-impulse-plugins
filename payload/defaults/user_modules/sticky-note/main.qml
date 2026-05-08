// Sticky Note — sample user module.
//
// Drops a small draggable note onto every screen. Text auto-saves to
// ~/.local/state/quickshell/user/sticky-note.txt; position is stored next
// to it. The window sits on the wlr Bottom layer so it stays under all
// regular windows, like a desktop widget.
//
// Use Super+drag (or just drag the title bar) to move. Click-through
// outside of the note's pill area.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Variants {
    model: Quickshell.screens
    PanelWindow {
        id: win
        required property ShellScreen modelData
        screen: modelData

        readonly property string baseDir: `${Directories.state}/user`
        readonly property string textPath: `${baseDir}/sticky-note.txt`
        readonly property string posPath:  `${baseDir}/sticky-note.pos.json`

        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:sticky-note"
        color: "transparent"
        exclusiveZone: 0

        // The window covers the screen so we can position the note anywhere
        // and let the rest pass clicks through.
        anchors { top: true; bottom: true; left: true; right: true }
        mask: Region { item: card; intersection: Intersection.Combine }

        Component.onCompleted: {
            ensureDirProc.command = ["mkdir", "-p", win.baseDir];
            ensureDirProc.running = true;
        }

        Process { id: ensureDirProc }

        // ---- text persistence ----
        FileView {
            id: textFile
            path: win.textPath
            watchChanges: true
            onLoaded: textArea.text = textFile.text
            onLoadFailed: (e) => {
                if (e === FileViewError.FileNotFound) {
                    textFile.setText("Click to edit me…");
                }
            }
        }
        Timer {
            id: saveTimer
            interval: 350
            repeat: false
            onTriggered: textFile.setText(textArea.text)
        }

        // ---- position persistence (one entry per screen name) ----
        property real cardX: 80
        property real cardY: 80
        FileView {
            id: posFile
            path: win.posPath
            watchChanges: true
            onLoaded: {
                try {
                    const all = JSON.parse(posFile.text || "{}");
                    const me  = all[win.modelData.name];
                    if (me) { win.cardX = me.x; win.cardY = me.y; }
                } catch (_) {}
            }
            onLoadFailed: (e) => {
                if (e === FileViewError.FileNotFound) posFile.setText("{}");
            }
        }
        Timer {
            id: savePosTimer
            interval: 200
            repeat: false
            onTriggered: {
                let all = {};
                try { all = JSON.parse(posFile.text || "{}"); } catch (_) {}
                all[win.modelData.name] = { x: win.cardX, y: win.cardY };
                posFile.setText(JSON.stringify(all));
            }
        }

        // ---- the note card ----
        Rectangle {
            id: card
            x: win.cardX
            y: win.cardY
            width: 280
            height: 200
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.color: Appearance.colors.colSecondaryContainer
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                // Drag handle / title
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 22
                    radius: Appearance.rounding.small
                    color: dragArea.pressed
                        ? Appearance.colors.colSecondaryContainerActive
                        : Appearance.colors.colSecondaryContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 4
                        MaterialSymbol {
                            text: "drag_indicator"
                            iconSize: 14
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Sticky Note"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property real grabX: 0
                        property real grabY: 0
                        onPressed: (m) => { grabX = m.x; grabY = m.y; }
                        onPositionChanged: (m) => {
                            if (!pressed) return;
                            win.cardX = Math.max(0, Math.min(
                                win.modelData.width  - card.width,
                                win.cardX + (m.x - grabX)));
                            win.cardY = Math.max(0, Math.min(
                                win.modelData.height - card.height,
                                win.cardY + (m.y - grabY)));
                            savePosTimer.restart();
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    TextArea {
                        id: textArea
                        wrapMode: TextEdit.Wrap
                        font.family: Appearance.font.family.reading
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        selectByMouse: true
                        background: null
                        onTextChanged: saveTimer.restart()
                    }
                }
            }
        }
    }
}
