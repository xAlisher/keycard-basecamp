import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    width: 950
    height: 733
    color: DesignTokens.background

    property bool debugMode: false

    // Keyboard shortcuts
    Keys.onPressed: (event) => {
        // Ctrl+D: Toggle debug mode
        if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            debugMode = !debugMode
            Qt.callLater(function() {
                if (debugMode && debugLoader.item) {
                    debugLoader.item.forceActiveFocus()
                } else if (!debugMode && productionLoader.item) {
                    productionLoader.item.forceActiveFocus()
                }
            })
            event.accepted = true
        }
        // Ctrl+R: Create random authorization request (for testing)
        else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            var moduleNames = ["wallet", "storage", "messaging", "contacts", "calendar", "notes", "tasks", "files"]
            var domainPrefixes = ["key", "data", "encryption", "private", "secure", "vault", "store"]

            var randomModule = moduleNames[Math.floor(Math.random() * moduleNames.length)]
            var randomPrefix = domainPrefixes[Math.floor(Math.random() * domainPrefixes.length)]
            var randomDomain = randomPrefix + "_" + randomModule

            var result = logos.callModule("keycard", "requestAuth", [randomDomain, randomModule])
            processActivity(result)
            event.accepted = true
        }
    }

    focus: true
    activeFocusOnTab: true

    Component.onCompleted: {
        forceActiveFocus()
    }

    // Helper to process activity log entries from API responses
    function processActivity(responseJson) {
        try {
            var response = JSON.parse(responseJson)
            if (response._activity && Array.isArray(response._activity)) {
                var screen = productionLoader.item
                if (screen && screen.activityLog) {
                    for (var i = 0; i < response._activity.length; i++) {
                        var entry = response._activity[i]
                        screen.activityLog.addEntry(entry.timestamp, entry.message, entry.level)
                    }
                }
            }
        } catch (e) {
            console.error("Failed to process activity:", e)
        }
    }

    // Production UI — single screen only
    Loader {
        id: productionLoader
        anchors.fill: parent
        visible: !debugMode
        source: "PinEntryScreen.qml"

        onLoaded: {
            if (item) {
                item.focus = true
                item.forceActiveFocus()
            }
        }
    }

    // Debug UI (Ctrl+D to toggle)
    Loader {
        id: debugLoader
        anchors.fill: parent
        visible: debugMode
        source: debugMode ? "DebugPanel.qml" : ""

        onLoaded: {
            if (item) {
                item.focus = true
                item.forceActiveFocus()
            }
        }
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

}
