// Design Tokens - Logos Design System (Dark Theme)
// Based on Design/Keycard.pen

pragma Singleton
import QtQuick 2.15
import Logos.Theme  // logos-design-system (native on RC3+ Basecamp) — skill: logos-design-system-adoption

QtObject {
    // Colors
    readonly property color background: Theme.palette.background
    readonly property color foreground: Theme.palette.text
    readonly property color foregroundSecondary: Theme.palette.textSecondary
    readonly property color foregroundTertiary: Theme.palette.textTertiary
    readonly property color mutedForeground: Theme.palette.textMuted
    readonly property color border: Theme.palette.border

    readonly property color primary: Theme.palette.primary        // Orange accent
    readonly property color primaryHover: Theme.palette.primaryHover
    readonly property color secondary: Theme.palette.surface
    readonly property color secondaryHover: Theme.palette.hover

    readonly property color success: Theme.palette.success        // Green
    readonly property color warning: Theme.palette.warning        // Yellow
    readonly property color error: Theme.palette.error          // Red
    readonly property color info: Theme.palette.info           // Gray

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
