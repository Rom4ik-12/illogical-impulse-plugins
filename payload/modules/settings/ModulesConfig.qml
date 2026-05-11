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
        // Exposed so child StyledToolTip {} can show on hover — the tooltip
        // checks `parent.hovered` and Rectangle has no such property by default.
        property alias hovered: ma.containsMouse
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 6
        color: ma.containsMouse
            ? Appearance.colors.colSecondaryContainerHover
            : "transparent"
        Loader {
            anchors.centerIn: parent
            active: parent.spinning
            sourceComponent: Md3Spinner {
                width: 18; height: 18
                lineWidth: 2
                running: true
                color: Appearance.colors.colPrimary
            }
        }
        MaterialSymbol {
            id: iconSym
            anchors.centerIn: parent
            visible: !parent.spinning
            text: parent.icon
            iconSize: 18
            color: parent.iconColor
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

    // RippleButtonWithIcon wrapper that overlays Md3Spinner at the icon
    // position while keeping StyledToolTip inside the button (which has
    // `hovered`) so tooltips still work.
    component SpinBtn: Item {
        property string icon
        property string label
        property bool spinning: false
        property bool extraEnabled: true
        signal clicked()
        default property alias extras: innerBtn.data
        implicitWidth: innerBtn.implicitWidth
        implicitHeight: innerBtn.implicitHeight
        RippleButtonWithIcon {
            id: innerBtn
            anchors.fill: parent
            materialIcon: parent.icon
            mainText: parent.label
            spinning: parent.spinning
            enabled: parent.extraEnabled && !parent.spinning
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
            id: tileBtn
            Layout.fillWidth: true
            materialIcon: tile.icon
            mainText: tile.label
            spinning: tile.spinning
            enabled: tile.enabled && !tile.spinning
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
            SpinBtn {
                icon: "system_update"
                label: Translation.tr("Update modules system")
                spinning: UserModules.loaderUpdating
                onClicked: UserModules.updateLoader()
                StyledToolTip {
                    text: Translation.tr("Reinstall the loader from the latest release")
                }
            }
            SpinBtn {
                icon: "cloud_download"
                label: Translation.tr("Update all plugins")
                spinning: UserModules.updatingModuleId !== ""
                    || (UserModules._updateQueue && UserModules._updateQueue.length > 0)
                onClicked: UserModules.updateAll()
                StyledToolTip {
                    text: Translation.tr("Re-fetch every installed plugin")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Install module")

            Flow {
                Layout.fillWidth: true
                spacing: 4
                SpinBtn {
                    icon: "folder_open"
                    label: Translation.tr("Choose file…")
                    spinning: UserModules.installing
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
                SpinBtn {
                    icon: "download"
                    label: Translation.tr("Install")
                    spinning: UserModules.installing
                    extraEnabled: installPathField.text.trim().length > 0
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

            // Pick a specific loader release to install (defaults to latest
            // via the main "Update modules system" button).
            ConfigRow {
                visible: devSubsection.open
                uniform: false
                StyledComboBox {
                    id: versionPicker
                    Layout.fillWidth: true
                    buttonIcon: "history"
                    textRole: "displayName"
                    enabled: !UserModules.fetchingLoaderVersions
                        && UserModules.availableLoaderVersions.length > 0
                    model: UserModules.availableLoaderVersions.map(t => ({
                        displayName: t === ("v" + UserModules.loaderVersion)
                                  || t === UserModules.loaderVersion
                            ? t + " (" + Translation.tr("current") + ")"
                            : t,
                        value: t
                    }))
                    displayText: UserModules.fetchingLoaderVersions
                        ? Translation.tr("Loading…")
                        : (UserModules.availableLoaderVersions.length === 0
                            ? Translation.tr("Click refresh to list versions")
                            : (currentIndex >= 0 ? model[currentIndex].displayName : ""))
                }
                SpinBtn {
                    icon: "refresh"
                    label: Translation.tr("List")
                    spinning: UserModules.fetchingLoaderVersions
                    onClicked: UserModules.fetchLoaderVersions()
                    StyledToolTip {
                        text: Translation.tr("Fetch the list of loader versions from GitHub")
                    }
                }
                SpinBtn {
                    icon: "download"
                    label: Translation.tr("Install version")
                    spinning: UserModules.loaderUpdating
                    extraEnabled: versionPicker.currentIndex >= 0
                        && UserModules.availableLoaderVersions.length > 0
                    onClicked: UserModules.updateLoader(
                        UserModules.availableLoaderVersions[versionPicker.currentIndex])
                    StyledToolTip {
                        text: Translation.tr("Reinstall the loader at the selected version")
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
                    + (changelogBanner.visible ? changelogBanner.implicitHeight + 8 : 0)
                    + (noteBox.visible ? noteBox.implicitHeight + 8 : 0)
                    + (settingsLoader.active && settingsLoader.implicitHeight > 0
                        ? settingsLoader.implicitHeight + 12 : 0)

                property bool settingsOpen: false
                property bool notesOpen: false

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
                        // Reload warning for patched modules
                        RowLayout {
                            visible: UserModules.hasPatches(row.modelData.id)
                            Layout.fillWidth: true
                            spacing: 4
                            MaterialSymbol {
                                text: "restart_alt"
                                iconSize: 14
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.small
                                text: Translation.tr("Requires Quickshell reload to apply changes")
                            }
                        }
                        // Compatibility badge — small warning when the
                        // module's requiresLoader doesn't match the current
                        // loader, or when the field is absent (untested).
                        RowLayout {
                            visible: !UserModules.isCompatible(row.modelData.id)
                                || !row.modelData.manifest.requiresLoader
                            Layout.fillWidth: true
                            spacing: 4
                            MaterialSymbol {
                                text: "warning"
                                iconSize: 14
                                color: Appearance.m3colors.m3error
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Appearance.m3colors.m3error
                                font.pixelSize: Appearance.font.pixelSize.small
                                text: !row.modelData.manifest.requiresLoader
                                    ? Translation.tr("Not tested with the modules system")
                                    : Translation.tr("Not tested for loader v%1 (declares requiresLoader: %2)")
                                        .arg(UserModules.loaderVersion)
                                        .arg(row.modelData.manifest.requiresLoader)
                            }
                        }
                        // Author-declared known issues — yellow bullet list.
                        Repeater {
                            model: Array.isArray(row.modelData.manifest.knownIssues)
                                ? row.modelData.manifest.knownIssues : []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4
                                MaterialSymbol {
                                    text: "bug_report"
                                    iconSize: 14
                                    color: Appearance.m3colors.m3error
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 2
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    color: Appearance.m3colors.m3error
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    text: modelData
                                }
                            }
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
                        icon: "sticky_note_2"
                        iconColor: row.notesOpen || UserModules.getNote(row.modelData.id).length > 0
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnSurfaceVariant
                        onClicked: row.notesOpen = !row.notesOpen
                        StyledToolTip {
                            text: Translation.tr("Personal note (saves to Config)")
                        }
                    }
                    IconBtn {
                        visible: !!row.modelData.settingsPage
                        icon: "settings"
                        iconColor: row.settingsOpen
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnSurfaceVariant
                        onClicked: row.settingsOpen = !row.settingsOpen
                        StyledToolTip {
                            text: Translation.tr("Open the module's settings page")
                        }
                    }
                    IconBtn {
                        visible: UserModules.hasUpdateUrl(row.modelData.id)
                        icon: "cloud_download"
                        spinning: UserModules.updatingModuleId === row.modelData.id
                        onClicked: UserModules.updateModule(row.modelData.id)
                        StyledToolTip {
                            text: Translation.tr("Check the module's source for a newer version and reinstall")
                        }
                    }
                    IconBtn {
                        icon: "ios_share"
                        onClicked: UserModules.exportModule(row.modelData.id, "")
                        StyledToolTip {
                            text: Translation.tr("Export this module as a .qsmod archive")
                        }
                    }
                    IconBtn {
                        icon: "folder"
                        onClicked: UserModules.openModuleFolder(row.modelData.id)
                        StyledToolTip {
                            text: Translation.tr("Open this module's folder in the file manager")
                        }
                    }
                    IconBtn {
                        icon: "delete"
                        onClicked: UserModules.uninstall(row.modelData.id)
                        StyledToolTip {
                            text: Translation.tr("Uninstall this module")
                        }
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

                // Personal note for the module — toggle the sticky-note
                // icon to expand. Auto-saves when focus is lost.
                ColumnLayout {
                    id: noteBox
                    visible: row.notesOpen
                        || UserModules.getNote(row.modelData.id).length > 0
                    anchors.top: changelogBanner.visible
                        ? changelogBanner.bottom : rowLayout.bottom
                    anchors.topMargin: 4
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 2

                    ContentSubsectionLabel {
                        text: Translation.tr("Your note")
                    }
                    MaterialTextArea {
                        id: noteField
                        Layout.fillWidth: true
                        wrapMode: TextEdit.Wrap
                        placeholderText: Translation.tr("Doesn't work, has bugs, breaks on …")
                        text: UserModules.getNote(row.modelData.id)
                        onEditingFinished: {
                            UserModules.setNote(row.modelData.id, noteField.text)
                        }
                    }
                }

                Loader {
                    id: settingsLoader
                    anchors.top: noteBox.visible
                        ? noteBox.bottom
                        : (changelogBanner.visible
                            ? changelogBanner.bottom : rowLayout.bottom)
                    anchors.topMargin: 8
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    active: row.settingsOpen && !!row.modelData.settingsPage
                    source: active
                        ? `file://${row.modelData.dir}/${row.modelData.settingsPage}`
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
