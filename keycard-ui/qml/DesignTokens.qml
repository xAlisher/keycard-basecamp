// Design Tokens - Logos Design System (Dark Theme)
// Based on Design/Keycard.pen

pragma Singleton
import QtQuick 2.15

QtObject {
    // Colors
    readonly property color background: "#1a1a1a"
    readonly property color foreground: "#ffffff"
    readonly property color foregroundSecondary: "#a0a0a0"
    readonly property color foregroundTertiary: "#707070"
    readonly property color mutedForeground: "#888888"
    readonly property color border: "#333333"

    readonly property color primary: "#ff5722"        // Orange accent
    readonly property color primaryHover: "#ff6e40"
    readonly property color secondary: "#424242"
    readonly property color secondaryHover: "#525252"

    readonly property color success: "#4caf50"        // Green
    readonly property color warning: "#ffc107"        // Yellow
    readonly property color error: "#f44336"          // Red
    readonly property color info: "#888888"           // Gray

    // Typography
    readonly property string fontPrimary: "Public Sans"
    readonly property int fontSizeTitle: 20
    readonly property int fontSizeBody: 14
    readonly property int fontSizeSmall: 12

    readonly property int fontWeightRegular: 400
    readonly property int fontWeightMedium: 500
    readonly property int fontWeightBold: 700

    // Spacing
    readonly property int spacingXs: 4
    readonly property int spacingS: 8
    readonly property int spacingM: 12
    readonly property int spacingL: 16
    readonly property int spacingXl: 24
    readonly property int spacing2xl: 32
    readonly property int spacing3xl: 48

    // Border radius
    readonly property int radiusS: 4
    readonly property int radiusM: 8
    readonly property int radiusL: 12

    // Component sizes
    readonly property int headerHeight: 56
    readonly property int buttonHeight: 36
    readonly property int pinDigitSize: 48
    readonly property int activityLogHeight: 160
}
