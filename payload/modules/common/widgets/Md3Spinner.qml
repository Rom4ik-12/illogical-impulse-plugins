import QtQuick
import QtQuick.Shapes
import qs.modules.common

// MD3 indeterminate circular progress indicator.
// The arc sweeps open and closed while the whole shape rotates,
// matching the Material Design 3 spec behaviour.
Item {
    id: root

    property bool running: true
    property color color: Appearance.colors.colPrimary
    property int lineWidth: 2.5
    property int implicitSize: 18

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    readonly property real _cx: width / 2
    readonly property real _cy: height / 2
    readonly property real _r: Math.min(width, height) / 2 - lineWidth

    // Two independent phase clocks drive the animation:
    //   _rot  — overall rotation, one full turn every 1333 ms
    //   _phase — sweep open/close cycle, also 1333 ms, offset by ¼ period
    property real _rot: 0
    property real _phase: 0

    NumberAnimation on _rot {
        from: 0; to: 360
        duration: 1333
        loops: Animation.Infinite
        running: root.running
    }
    NumberAnimation on _phase {
        from: 0; to: 1
        duration: 1333
        loops: Animation.Infinite
        running: root.running
    }

    // Derived arc angles.
    // sweepAngle oscillates 20°→280°→20° using a smooth sine curve.
    // startAngle trails sweep so the arc appears to chase itself.
    readonly property real _sweep: 20 + 260 * Math.abs(Math.sin(Math.PI * _phase))
    readonly property real _startAngle: _rot - 90 - (_sweep * (1 - Math.abs(Math.sin(Math.PI * _phase))) * 0.5)

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.lineWidth
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: root._cx
                centerY: root._cy
                radiusX: root._r
                radiusY: root._r
                startAngle: root._startAngle
                sweepAngle: root._sweep
            }
        }
    }
}
