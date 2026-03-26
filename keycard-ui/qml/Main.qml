import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    width: 950
    height: 733
    color: DesignTokens.background

    // UI Mode: "pin", "dashboard", "authorization"
    property string mode: "pin"
    property bool debugMode: false

    // Current authorization request (when mode === "authorization")
    property var currentAuthRequest: null

    // Keyboard shortcuts
    Keys.onPressed: (event) => {
        // Ctrl+D: Toggle debug mode
        if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            debugMode = !debugMode
            // Restore focus after toggle
            Qt.callLater(function() {
                if (debugMode && debugLoader.item) {
                    debugLoader.item.forceActiveFocus()
                } else if (!debugMode && productionLoader.item) {
                    productionLoader.item.forceActiveFocus()
                }
            })
            event.accepted = true
        }
        // Ctrl+L: Lock session (when in dashboard)
        else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
            if (mode === "dashboard") {
                lockSession()
            }
            event.accepted = true
        }
        // Ctrl+A: Show mock authorization request (for testing)
        else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            // Create backend request first
            var result = logos.callModule("keycard", "requestAuth", ["notes_private", "notes"])
            console.log("requestAuth result:", result)

            try {
                var obj = JSON.parse(result)
                if (obj.authId) {
                    // Use the real authId from backend
                    showAuthorizationRequest(
                        obj.authId,
                        "notes",
                        "notes_private",
                        obj.path || "m/43'/60'/1581'/1437890605'/512438859'"
                    )
                }
            } catch (e) {
                console.error("Failed to create auth request:", e)
            }
            event.accepted = true
        }
    }

    focus: true  // Enable keyboard input
    activeFocusOnTab: true

    Component.onCompleted: {
        forceActiveFocus()
    }

    function lockSession() {
        console.log("Locking session...")
        // TODO: Call backend lockSession()
        mode = "pin"
    }

    function showAuthorizationRequest(requestId, moduleName, domain, path) {
        console.log("Showing authorization request:", requestId, moduleName, domain, path)
        currentAuthRequest = {
            id: requestId,
            moduleName: moduleName,
            domain: domain,
            path: path
        }
        mode = "authorization"
    }

    // Production UI
    Loader {
        id: productionLoader
        anchors.fill: parent
        visible: !debugMode
        source: {
            if (mode === "pin") return "PinEntryScreen.qml"
            if (mode === "dashboard") return "ManagementDashboard.qml"
            if (mode === "authorization") return "AuthorizationScreen.qml"
            return ""
        }

        onLoaded: {
            // Wire up signals from loaded component
            if (item && item.unlocked) {
                item.unlocked.connect(function() {
                    root.mode = "dashboard"
                })
            }
            if (item && item.lockRequested) {
                item.lockRequested.connect(function() {
                    root.lockSession()
                })
            }
            if (item && item.approved) {
                item.approved.connect(function(authRequestId, pin) {
                    console.log("Authorization approved, ID:", authRequestId, "PIN:", pin)

                    // Call backend authorizeRequest
                    var result = logos.callModule("keycard", "authorizeRequest", [authRequestId, pin])
                    console.log("authorizeRequest result:", result)

                    try {
                        var obj = JSON.parse(result)
                        if (obj.error) {
                            console.error("Authorization failed:", obj.error)
                            // TEMPORARY: Show error in alert for debugging
                            logos.showMessage("Authorization Error", obj.error)
                        } else if (obj.status === "complete") {
                            console.log("Authorization successful, key derived")
                            logos.showMessage("Success", "Authorization completed!")
                            root.currentAuthRequest = null
                            root.mode = "dashboard"
                        } else {
                            logos.showMessage("Debug", "Status: " + obj.status + ", Result: " + result)
                        }
                    } catch (e) {
                        console.error("Failed to parse authorizeRequest response:", e)
                        logos.showMessage("Error", "Parse error: " + e)
                    }
                })
            }
            if (item && item.declined) {
                item.declined.connect(function(authRequestId) {
                    console.log("Authorization declined, ID:", authRequestId)

                    // Call backend rejectRequest
                    var result = logos.callModule("keycard", "rejectRequest", [authRequestId])
                    console.log("rejectRequest result:", result)

                    try {
                        var obj = JSON.parse(result)
                        if (obj.error) {
                            console.error("Rejection failed:", obj.error)
                        } else if (obj.status === "rejected") {
                            console.log("Authorization request rejected")
                        }
                    } catch (e) {
                        console.error("Failed to parse rejectRequest response:", e)
                    }

                    // Always return to dashboard after decline
                    root.currentAuthRequest = null
                    root.mode = "dashboard"
                })
            }
            // Set request data for authorization screen
            if (item && item.authRequestId !== undefined && root.currentAuthRequest) {
                item.authRequestId = root.currentAuthRequest.id
                item.moduleName = root.currentAuthRequest.moduleName
                item.domain = root.currentAuthRequest.domain
                item.path = root.currentAuthRequest.path
            }
            // Give focus to loaded item
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
            // Give focus to debug panel
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
