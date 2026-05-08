import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

    // Light icon button — no ripple, no tooltip Loader. Used 3× per module row.
    component IconBtn: Rectangle {
        property string icon
        property color iconColor: Appearance.colors.colOnSurfaceVariant
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 6
        color: ma.containsMouse
            ? Appearance.colors.colSecondaryContainerHover
            : "transparent"
        MaterialSymbol {
            anchors.centerIn: parent
            text: parent.icon
            iconSize: 18
            color: parent.iconColor
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    ContentSection {
        icon: "extension"
        title: Translation.tr("User Modules")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnSecondaryContainer
            text: Translation.tr("Drop a module folder or .qsmod file into the user modules folder, then enable it here. See MODULES.md for the format.")
        }

        Flow {
            Layout.fillWidth: true
            spacing: 4
            RippleButtonWithIcon {
                materialIcon: "folder_open"
                mainText: Translation.tr("Open modules folder")
                onClicked: UserModules.openFolder()
            }
            RippleButtonWithIcon {
                materialIcon: "refresh"
                mainText: Translation.tr("Refresh")
                onClicked: UserModules.refresh()
            }
            RippleButtonWithIcon {
                materialIcon: "menu_book"
                mainText: Translation.tr("Docs (MODULES.md)")
                onClicked: Qt.openUrlExternally("file://" + Quickshell.shellPath("MODULES.md"))
            }
            RippleButtonWithIcon {
                materialIcon: "restart_alt"
                mainText: Translation.tr("Rebaseline patches")
                onClicked: UserModules.rebaselinePatches()
            }
            RippleButtonWithIcon {
                materialIcon: "cloud_download"
                mainText: Translation.tr("Update all")
                onClicked: UserModules.updateAll()
            }
            RippleButtonWithIcon {
                materialIcon: "system_update"
                mainText: Translation.tr("Update loader")
                onClicked: UserModules.updateLoader()
            }
        }

        ContentSubsection {
            title: Translation.tr("Install module")

            Flow {
                Layout.fillWidth: true
                spacing: 4
                RippleButtonWithIcon {
                    materialIcon: "folder_open"
                    mainText: Translation.tr("Choose file…")
                    onClicked: UserModules.pickAndInstall()
                }
            }

            ConfigRow {
                uniform: false
                MaterialTextArea {
                    id: installPathField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("…or paste a path / URL (.qsmod, .zip, github.com/foo/bar)")
                    wrapMode: TextEdit.NoWrap
                }
                RippleButtonWithIcon {
                    materialIcon: "download"
                    mainText: Translation.tr("Install")
                    enabled: installPathField.text.trim().length > 0
                    onClicked: {
                        UserModules.installFromUrlOrPath(installPathField.text);
                        installPathField.text = "";
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "deployed_code"
        title: Translation.tr("Installed (%1)").arg(UserModules.modules.length)

        StyledText {
            visible: UserModules.modules.length === 0
            text: Translation.tr("No modules installed yet.")
            color: Appearance.colors.colSubtext
        }

        StyledText {
            visible: UserModules.lastError.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.m3colors.m3error
            text: UserModules.lastError
        }

        StyledText {
            visible: UserModules.lastExportPath.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Exported: %1").arg(UserModules.lastExportPath)
        }

        Repeater {
            model: UserModules.modules
            delegate: Rectangle {
                id: row
                required property var modelData
                Layout.fillWidth: true
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surfaceContainer
                implicitHeight: rowLayout.implicitHeight + 16

                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            text: (row.modelData.manifest.name || row.modelData.id)
                                + (row.modelData.manifest.version ? "  v" + row.modelData.manifest.version : "")
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSecondaryContainer
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        StyledText {
                            visible: !!row.modelData.manifest.description
                            text: row.modelData.manifest.description || ""
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            visible: !!row.modelData.manifest.author
                            text: row.modelData.manifest.author ? Translation.tr("by %1").arg(row.modelData.manifest.author) : ""
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }

                    StyledSwitch {
                        checked: UserModules.isEnabled(row.modelData.id)
                        onClicked: UserModules.setEnabled(row.modelData.id, !UserModules.isEnabled(row.modelData.id))
                    }

                    IconBtn {
                        visible: !!row.modelData.manifest.link
                        icon: "link"
                        onClicked: Qt.openUrlExternally(row.modelData.manifest.link)
                    }
                    IconBtn {
                        visible: UserModules.hasUpdateUrl(row.modelData.id)
                        icon: "cloud_download"
                        onClicked: UserModules.updateModule(row.modelData.id)
                    }
                    IconBtn {
                        icon: "ios_share"
                        onClicked: UserModules.exportModule(row.modelData.id, "")
                    }
                    IconBtn {
                        icon: "folder"
                        onClicked: UserModules.openModuleFolder(row.modelData.id)
                    }
                    IconBtn {
                        icon: "delete"
                        onClicked: UserModules.uninstall(row.modelData.id)
                    }
                }
            }
        }
    }
}
