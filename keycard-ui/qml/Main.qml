import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    width: 950
    height: 733
    color: DesignTokens.background

    // UI Mode: "pin", "dashboard", "debug"
    property string mode: "pin"
    property bool debugMode: false

    // Keyboard shortcuts
    Keys.onPressed: (event) => {
        // Ctrl+D: Toggle debug mode
        if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            debugMode = !debugMode
            event.accepted = true
        }
        // Ctrl+L: Lock session (when in dashboard)
        else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
            if (mode === "dashboard") {
                lockSession()
            }
            event.accepted = true
        }
    }

    focus: true  // Enable keyboard input

    function lockSession() {
        console.log("Locking session...")
        // TODO: Call backend lockSession()
        mode = "pin"
    }

    // Production UI
    Loader {
        id: productionLoader
        anchors.fill: parent
        visible: !debugMode
        source: {
            if (mode === "pin") return "PinEntryScreen.qml"
            if (mode === "dashboard") return "ManagementDashboard.qml"
            return ""
        }

        onLoaded: {
            // Wire up signals from loaded component
            if (item && item.unlocked) {
                item.unlocked.connect(function() {
                    root.mode = "dashboard"
                })
            }
        }
    }

    // Debug UI (Ctrl+D to toggle)
    Loader {
        id: debugLoader
        anchors.fill: parent
        visible: debugMode
        source: debugMode ? "DebugPanel.qml" : ""
    }

    // Debug mode indicator
    Rectangle {
        visible: debugMode
        anchors.top: parent.top
        anchors.right: parent.right
        width: 120
        height: 30
        color: DesignTokens.warning
        opacity: 0.9
        radius: DesignTokens.radiusS

        Text {
            anchors.centerIn: parent
            text: "DEBUG MODE"
            color: DesignTokens.background
            font.pixelSize: DesignTokens.fontSizeSmall
            font.weight: Font.Bold
            font.family: DesignTokens.fontPrimary
        }
    }

    // Instructions overlay (top-left corner)
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 8
        width: instructionsText.width + 16
        height: instructionsText.height + 12
        color: DesignTokens.background
        border.color: DesignTokens.border
        border.width: 1
        radius: DesignTokens.radiusS
        opacity: 0.8
        visible: !debugMode

        Text {
            id: instructionsText
            anchors.centerIn: parent
            text: "Ctrl+D: Debug  |  Ctrl+L: Lock"
            color: DesignTokens.mutedForeground
            font.pixelSize: DesignTokens.fontSizeSmall
            font.family: DesignTokens.fontPrimary
        }
    }
}
