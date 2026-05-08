import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Anything you put as the root element here gets dropped into the bar's
// UserModulesBarSlot. Pick whatever fits — a button, an icon, a tiny
// status indicator. Use existing shell widgets to look native.
StyledText {
    text: ":)"
    font.pixelSize: Appearance.font.pixelSize.normal
    color: Appearance.colors.colOnLayer0
}
