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
        property bool spinning: false
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 6
        color: ma.containsMouse
            ? Appearance.colors.colSecondaryContainerHover
            : "transparent"
        MaterialSymbol {
            id: iconSym
            anchors.centerIn: parent
            text: parent.spinning ? "progress_activity" : parent.icon
            iconSize: 18
            color: parent.spinning ? Appearance.colors.colPrimary : parent.iconColor
            RotationAnimator on rotation {
                from: 0; to: 360; duration: 1000
                loops: Animation.Infinite
                running: iconSym.parent.spinning
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            enabled: !parent.spinning
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    // Action button + small caption beneath. Used in the top row and the
    // Developer subsection so every button has a one-line description.
    component ActionTile: ColumnLayout {
        id: tile
        property string icon
        property string label
        property string caption
        property bool spinning: false
        signal clicked()
        spacing: 2
        Layout.preferredWidth: 200

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: tile.spinning ? "progress_activity" : tile.icon
            mainText: tile.label
            enabled: tile.enabled
            onClicked: tile.clicked()
        }
        StyledText {
            Layout.fillWidth: true
            text: tile.caption
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
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
                materialIcon: UserModules.loaderUpdating ? "progress_activity" : "system_update"
                mainText: Translation.tr("Update modules system")
                enabled: !UserModules.loaderUpdating
                onClicked: UserModules.updateLoader()
            }
            RippleButtonWithIcon {
                materialIcon: (UserModules.updatingModuleId !== ""
                    || (UserModules._updateQueue && UserModules._updateQueue.length > 0))
                    ? "progress_activity" : "cloud_download"
                mainText: Translation.tr("Update all plugins")
                enabled: UserModules.updatingModuleId === ""
                    && (!UserModules._updateQueue || UserModules._updateQueue.length === 0)
                onClicked: UserModules.updateAll()
            }
        }

        ContentSubsection {
            title: Translation.tr("Install module")

            Flow {
                Layout.fillWidth: true
                spacing: 4
                RippleButtonWithIcon {
                    materialIcon: UserModules.installing ? "progress_activity" : "folder_open"
                    mainText: Translation.tr("Choose file…")
                    enabled: !UserModules.installing
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
                    materialIcon: UserModules.installing ? "progress_activity" : "download"
                    mainText: Translation.tr("Install")
                    enabled: installPathField.text.trim().length > 0 && !UserModules.installing
                    onClicked: {
                        UserModules.installFromUrlOrPath(installPathField.text);
                        installPathField.text = "";
                    }
                }
            }
        }

        // Collapsible "Developer" subsection — rare/maintenance actions
        // (open folder, rescan, docs, rebaseline patches).
        ContentSubsection {
            id: devSubsection
            property bool open: false
            Layout.fillWidth: true

            Rectangle {
                Layout.fillWidth: true
                radius: Appearance.rounding.small
                color: devHeaderMa.containsMouse
                    ? Appearance.colors.colSecondaryContainerHover
                    : "transparent"
                implicitHeight: devHeaderRow.implicitHeight + 8

                RowLayout {
                    id: devHeaderRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    spacing: 6
                    MaterialSymbol {
                        text: "code"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Developer")
                        color: Appearance.colors.colSubtext
                        font.weight: Font.Medium
                    }
                    MaterialSymbol {
                        text: devSubsection.open ? "expand_less" : "expand_more"
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                    }
                }
                MouseArea {
                    id: devHeaderMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: devSubsection.open = !devSubsection.open
                }
            }

            Flow {
                visible: devSubsection.open
                Layout.fillWidth: true
                spacing: 8
                ActionTile {
                    icon: "folder_open"
                    label: Translation.tr("Open modules folder")
                    caption: Translation.tr("Open the user_modules folder in the file manager")
                    onClicked: UserModules.openFolder()
                }
                ActionTile {
                    icon: "refresh"
                    label: Translation.tr("Refresh")
                    caption: Translation.tr("Re-scan the modules folder for manual changes")
                    spinning: UserModules.refreshing
                    enabled: !UserModules.refreshing
                    onClicked: UserModules.refresh()
                }
                ActionTile {
                    icon: "menu_book"
                    label: Translation.tr("Docs (MODULES.md)")
                    caption: Translation.tr("Open the module format documentation")
                    onClicked: Qt.openUrlExternally("file://" + Quickshell.shellPath("MODULES.md"))
                }
                ActionTile {
                    icon: "restart_alt"
                    label: Translation.tr("Rebaseline patches")
                    caption: Translation.tr("Capture current shell files as the patch baseline")
                    spinning: UserModules.rebaselining
                    enabled: !UserModules.rebaselining
                    onClicked: UserModules.rebaselinePatches()
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
                    + (changelogBanner.visible ? changelogBanner.implicitHeight + 8 : 0)
                    + (settingsLoader.active && settingsLoader.implicitHeight > 0
                        ? settingsLoader.implicitHeight + 12 : 0)

                property bool settingsOpen: false

                RowLayout {
                    id: rowLayout
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: 8
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 10

                    StyledSwitch {
                        Layout.alignment: Qt.AlignVCenter
                        checked: UserModules.isEnabled(row.modelData.id)
                        onClicked: UserModules.setEnabled(row.modelData.id, !UserModules.isEnabled(row.modelData.id))
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        StyledText {
                            text: (row.modelData.manifest.name || row.modelData.id)
                                + (row.modelData.manifest.version ? "  v" + row.modelData.manifest.version : "")
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSecondaryContainer
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        StyledText {
                            visible: !!row.modelData.manifest.description
                            text: row.modelData.manifest.description || ""
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        Item {
                            visible: !!row.modelData.manifest.author
                            Layout.fillWidth: true
                            implicitHeight: authorText.implicitHeight
                            StyledText {
                                id: authorText
                                width: parent.width
                                text: row.modelData.manifest.author ? Translation.tr("by %1").arg(row.modelData.manifest.author) : ""
                                color: !!row.modelData.manifest.link
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                                font.underline: !!row.modelData.manifest.link
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            MouseArea {
                                anchors.fill: parent
                                visible: !!row.modelData.manifest.link
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally(row.modelData.manifest.link)
                            }
                        }
                    }

                    IconBtn {
                        visible: !!row.modelData.manifest.settingsPage
                        icon: "settings"
                        iconColor: row.settingsOpen
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnSurfaceVariant
                        onClicked: row.settingsOpen = !row.settingsOpen
                    }
                    IconBtn {
                        visible: UserModules.hasUpdateUrl(row.modelData.id)
                        icon: "cloud_download"
                        spinning: UserModules.updatingModuleId === row.modelData.id
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

                // Changelog banner — shown when module version wasn't seen yet
                ColumnLayout {
                    id: changelogBanner
                    visible: UserModules.isNewVersion(row.modelData.id)
                    anchors.top: rowLayout.bottom
                    anchors.topMargin: 4
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Updated to %1").arg(row.modelData.manifest.version || "?")
                            font.weight: Font.Medium
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colPrimary
                        }
                        IconBtn {
                            icon: "close"
                            implicitWidth: 22
                            implicitHeight: 22
                            onClicked: UserModules.markSeen(row.modelData.id)
                        }
                    }

                    Repeater {
                        model: Array.isArray(row.modelData.manifest.changelog)
                            ? row.modelData.manifest.changelog : []
                        delegate: StyledText {
                            required property var modelData
                            Layout.fillWidth: true
                            text: "• " + modelData
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }

                Loader {
                    id: settingsLoader
                    anchors.top: changelogBanner.visible
                        ? changelogBanner.bottom : rowLayout.bottom
                    anchors.topMargin: 8
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    active: row.settingsOpen && !!row.modelData.manifest.settingsPage
                    source: active
                        ? `file://${row.modelData.dir}/${row.modelData.manifest.settingsPage}`
                        : ""
                    onLoaded: {
                        if (!item) return;
                        if (item.hasOwnProperty("moduleDataDir"))
                            item.moduleDataDir = UserModules.moduleDataDir(row.modelData.id);
                        if (item.hasOwnProperty("moduleId"))
                            item.moduleId = row.modelData.id;
                    }
                }
            }
        }
    }

    // Always-visible loader update changelog at bottom — shown in subdued
    // text. Replaced whenever the loader self-updates.
    ContentSection {
        visible: UserModules.loaderNotice !== null
        icon: "new_releases"
        title: Translation.tr("What's new — loader %1").arg(
            UserModules.loaderNotice?.version ?? "")

        StyledText {
            visible: (UserModules.loaderNotice?.body ?? "").length > 0
            Layout.fillWidth: true
            text: UserModules.loaderNotice?.body ?? ""
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
