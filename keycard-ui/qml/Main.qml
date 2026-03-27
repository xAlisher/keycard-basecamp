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
        // Ctrl+A: Create real authorization request (for testing)
        else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            var result = logos.callModule("keycard", "requestAuth", ["notes_private", "notes"])
            processActivity(result)

            try {
                var obj = JSON.parse(result)
                if (obj.authId) {
                    showAuthorizationRequest(
                        obj.authId,
                        "notes",
                        "notes_private",
                        "m/43'/60'/1581'/1437890605'/512438859'"
                    )
                }
            } catch (e) {
                console.error("Failed to create auth request:", e)
            }
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

            try {
                var obj = JSON.parse(result)
                if (obj.authId) {
                    if (mode === "dashboard") {
                        // Add to dashboard pending requests as card
                        var dashboard = productionLoader.item
                        if (dashboard && dashboard.pendingRequests) {
                            var newRequests = dashboard.pendingRequests.slice()
                            newRequests.push({
                                id: obj.authId,
                                name: randomModule,
                                domain: randomDomain
                            })
                            dashboard.pendingRequests = newRequests
                        }
                    } else {
                        // Show as modal if not in dashboard
                        showAuthorizationRequest(
                            obj.authId,
                            randomModule,
                            randomDomain,
                            "m/43'/60'/1581'/1437890605'/512438859'"
                        )
                    }
                }
            } catch (e) {
                console.error("Failed to create random auth request:", e)
            }
            event.accepted = true
        }
    }

    focus: true  // Enable keyboard input
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
            if (item && item.requestApprove) {
                item.requestApprove.connect(function(requestId, moduleName, domain) {
                    console.log("Request approve:", requestId, moduleName, domain)

                    // Derive key directly (session is active, no PIN needed)
                    var result = logos.callModule("keycard", "deriveKey", [domain])
                    processActivity(result)

                    try {
                        var obj = JSON.parse(result)
                        if (obj.key) {
                            // Success - mark auth request as complete in backend
                            var completeResult = logos.callModule("keycard", "completeAuthRequest", [requestId, obj.key])
                            processActivity(completeResult)

                            // Add to activity log
                            var timestamp = Qt.formatTime(new Date(), "[HH:mm:ss]")
                            if (item.activityLog) {
                                item.activityLog.addEntry(timestamp, "Request from module " + moduleName + " approved", "success")
                            }

                            // Note: Don't manually update pending/connected lists here
                            // The polling timer will update them from backend state
                        }
                    } catch (e) {
                        console.error("Failed to approve request:", e)
                    }
                })
            }
            if (item && item.requestDecline) {
                item.requestDecline.connect(function(requestId) {
                    console.log("Request decline:", requestId)

                    // Find module name from pending requests
                    var moduleName = "Unknown"
                    if (item && item.pendingRequests) {
                        for (var i = 0; i < item.pendingRequests.length; i++) {
                            if (item.pendingRequests[i].id === requestId) {
                                moduleName = item.pendingRequests[i].name
                                break
                            }
                        }
                    }

                    // Add to activity log
                    var timestamp = Qt.formatTime(new Date(), "[HH:mm:ss]")
                    if (item.activityLog) {
                        item.activityLog.addEntry(timestamp, "Request from module " + moduleName + " declined", "success")
                    }

                    var result = logos.callModule("keycard", "rejectRequest", [requestId])
                    processActivity(result)

                    // Remove from pending requests
                    if (item && item.pendingRequests) {
                        var filtered = item.pendingRequests.filter(function(req) {
                            return req.id !== requestId
                        })
                        item.pendingRequests = filtered
                    }
                })
            }
            if (item && item.moduleDisconnect) {
                item.moduleDisconnect.connect(function(moduleName) {
                    console.log("Module disconnect:", moduleName)

                    // Revoke module in backend
                    var result = logos.callModule("keycard", "revokeModule", [moduleName])
                    processActivity(result)

                    // Add to activity log
                    var timestamp = Qt.formatTime(new Date(), "[HH:mm:ss]")
                    if (item.activityLog) {
                        item.activityLog.addEntry(timestamp, "Module " + moduleName + " disconnected", "success")
                    }

                    // Note: Don't manually update connectedModules here
                    // The polling timer will update it from backend state
                })
            }
            if (item && item.approved) {
                item.approved.connect(function(authRequestId, pin) {
                    console.log("Authorization approved, ID:", authRequestId, "PIN:", pin)

                    var result = logos.callModule("keycard", "authorizeRequest", [authRequestId, pin])
                    processActivity(result)

                    try {
                        var obj = JSON.parse(result)
                        if (obj.status === "complete") {
                            root.currentAuthRequest = null
                            root.mode = "dashboard"

                            // Remove from pending requests
                            Qt.callLater(function() {
                                var dashboard = productionLoader.item
                                if (dashboard && dashboard.pendingRequests) {
                                    var filtered = dashboard.pendingRequests.filter(function(req) {
                                        return req.id !== authRequestId
                                    })
                                    dashboard.pendingRequests = filtered
                                }
                            })
                        }
                    } catch (e) {
                        console.error("Failed to authorize request:", e)
                    }
                })
            }
            if (item && item.declined) {
                item.declined.connect(function(authRequestId) {
                    console.log("Authorization declined, ID:", authRequestId)

                    var result = logos.callModule("keycard", "rejectRequest", [authRequestId])
                    processActivity(result)

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
