import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: buttonWithIconRoot
    property string nerdIcon
    property string materialIcon
    property bool materialIconFill: true
    property string mainText: "Button text"
    property bool spinning: false
    property Component mainContentComponent: Component {
        StyledText {
            visible: text !== ""
            text: buttonWithIconRoot.mainText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
    implicitHeight: 35
    horizontalPadding: 10
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2

    contentItem: RowLayout {
        Item {
            Layout.fillWidth: false
            implicitWidth: Math.max(
                spinningLoader.active ? spinningLoader.implicitWidth : 0,
                Math.max(materialIconLoader.implicitWidth, nerdIconLoader.implicitWidth))
            implicitHeight: Math.max(
                spinningLoader.active ? spinningLoader.implicitHeight : 0,
                Math.max(materialIconLoader.implicitHeight, nerdIconLoader.implicitHeight))
            Loader {
                id: spinningLoader
                anchors.centerIn: parent
                active: buttonWithIconRoot.spinning
                sourceComponent: Md3Spinner {
                    implicitSize: Appearance.font.pixelSize.larger
                    lineWidth: 2
                    running: buttonWithIconRoot.spinning
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            Loader {
                id: materialIconLoader
                anchors.centerIn: parent
                active: !buttonWithIconRoot.spinning && !nerdIcon
                sourceComponent: MaterialSymbol {
                    text: buttonWithIconRoot.materialIcon
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                    fill: buttonWithIconRoot.materialIconFill ? 1 : 0
                }
            }
            Loader {
                id: nerdIconLoader
                anchors.centerIn: parent
                active: !buttonWithIconRoot.spinning && nerdIcon
                sourceComponent: StyledText {
                    text: buttonWithIconRoot.nerdIcon
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.family: Appearance.font.family.iconNerd
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
        Loader {
            Layout.fillWidth: true
            sourceComponent: buttonWithIconRoot.mainContentComponent
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
