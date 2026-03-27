import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    color: DesignTokens.background

    signal lockRequested()
    signal requestApprove(string requestId, string moduleName, string domain)
    signal requestDecline(string requestId)
    signal moduleDisconnect(string moduleName)
    property alias activityLog: activityLog

    property var pendingRequests: []
    property var connectedModules: []

    property string cardHash: "0a2b3c5fh4g4e5d"
    property string version: "0.1"
    property int sessionRemainingMs: 0

    // Poll for pending requests
    Timer {
        id: requestPoller
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            checkPendingRequests()
            updateSessionTime()
        }
    }

    function updateSessionTime() {
        var result = logos.callModule("keycard", "getSessionInfo", [])
        try {
            var response = JSON.parse(result)
            if (response.remainingSeconds !== undefined) {
                root.sessionRemainingMs = response.remainingSeconds * 1000
            }
        } catch (e) {
            console.error("Failed to get session info:", e)
        }
    }

    function formatTime(ms) {
        var totalSeconds = Math.floor(ms / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    function checkPendingRequests() {
        // Get pending auth requests
        var result = logos.callModule("keycard", "getPendingAuths", [])
        try {
            var response = JSON.parse(result)

            // Process activity log
            if (response._activity && Array.isArray(response._activity)) {
                for (var k = 0; k < response._activity.length; k++) {
                    var entry = response._activity[k]
                    activityLog.addEntry(entry.timestamp, entry.message, entry.level)
                }
            }

            if (response.pending && Array.isArray(response.pending)) {
                // Update pending requests
                var newRequests = []
                for (var i = 0; i < response.pending.length; i++) {
                    var req = response.pending[i]
                    newRequests.push({
                        id: req.authId,
                        name: req.caller,
                        domain: req.domain
                    })
                }
                root.pendingRequests = newRequests
            }
        } catch (e) {
            console.error("Failed to check pending requests:", e)
        }

        // Get authorized modules (connected)
        var authResult = logos.callModule("keycard", "getAuthorizedModules", [])
        try {
            var authResponse = JSON.parse(authResult)
            if (authResponse.modules && Array.isArray(authResponse.modules)) {
                // Update connected modules
                var newConnected = []
                for (var j = 0; j < authResponse.modules.length; j++) {
                    var mod = authResponse.modules[j]
                    newConnected.push({
                        name: mod.name,
                        domains: mod.domain
                    })
                }
                root.connectedModules = newConnected
            }
        } catch (e) {
            console.error("Failed to check authorized modules:", e)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: DesignTokens.background

            // Bottom border only
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: DesignTokens.border
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 16

                // Left: Title + Version
                RowLayout {
                    spacing: 4

                    Text {
                        text: "Keycard for Basecamp"
                        color: DesignTokens.foreground
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        font.family: DesignTokens.fontPrimary
                    }

                    Text {
                        text: root.version
                        color: "#707070"
                        font.pixelSize: 11
                        font.weight: Font.Normal
                        font.family: DesignTokens.fontPrimary
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 2
                    }
                }

                Item { Layout.fillWidth: true }

                // Right: Countdown + Card hash + Lock + Settings
                RowLayout {
                    spacing: 16

                    // Countdown timer
                    Text {
                        text: formatTime(root.sessionRemainingMs)
                        color: DesignTokens.mutedForeground
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        font.family: DesignTokens.fontPrimary
                    }

                    // Hash
                    Text {
                        text: root.cardHash
                        color: DesignTokens.mutedForeground
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        font.family: DesignTokens.fontPrimary
                    }

                    // Lock + Ctrl+L (group 2)
                    RowLayout {
                        spacing: 4

                        Rectangle {
                            width: 20
                            height: 20
                            color: "transparent"

                            Image {
                                id: lockIcon
                                anchors.fill: parent
                                source: "icons/lock.svg"
                                sourceSize: Qt.size(20, 20)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    console.log("Lock icon clicked!")
                                    lockSession()
                                }
                            }
                        }

                        Rectangle {
                            width: ctrlLText.implicitWidth
                            height: ctrlLText.implicitHeight
                            color: "transparent"

                            Text {
                                id: ctrlLText
                                text: "Ctrl+L"
                                color: DesignTokens.foreground
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                font.family: DesignTokens.fontPrimary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    console.log("Ctrl+L clicked!")
                                    lockSession()
                                }
                            }
                        }
                    }

                    // Settings (group 3)
                    Image {
                        id: settingsIcon
                        width: 20
                        height: 20
                        source: "icons/bolt.svg"
                        sourceSize: Qt.size(20, 20)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: console.log("Settings clicked")
                        }
                    }
                }
            }
        }

        // Body: Two columns
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 24

                // Left column: Pending Requests
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 400
                    Layout.fillHeight: true
                    spacing: 24

                    Text {
                        text: root.pendingRequests.length > 0 ? "Pending requests" : "No pending requests"
                        color: DesignTokens.foreground
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        font.family: DesignTokens.fontPrimary
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 16
                        clip: true
                        model: root.pendingRequests
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 64
                            color: "#2a2a2a"
                            radius: 8

                            // Yellow marker (left border) with clip
                            Item {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 8
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 16
                                    color: DesignTokens.warning
                                    radius: 8
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 10
                                spacing: 8

                                // Module info
                                ColumnLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 4

                                    Text {
                                        text: modelData.name
                                        color: DesignTokens.foreground
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    Text {
                                        text: "domain: " + modelData.domain
                                        color: DesignTokens.foregroundSecondary
                                        font.pixelSize: 12
                                        font.family: DesignTokens.fontPrimary
                                    }
                                }

                                Item { Layout.fillWidth: true }  // Spacer to push buttons right

                                // Approve button
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 85
                                    height: 32
                                    color: approveArea.containsMouse ? "#e64a19" : DesignTokens.primary
                                    radius: 16  // Pill shape

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Approve"
                                        color: DesignTokens.foreground
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    MouseArea {
                                        id: approveArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.requestApprove(modelData.id, modelData.name, modelData.domain)
                                    }
                                }

                                // Decline button
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 85
                                    height: 32
                                    color: declineArea.containsMouse ? "#3a3a3a" : "transparent"
                                    border.color: DesignTokens.border
                                    border.width: 1
                                    radius: 16  // Pill shape

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Decline"
                                        color: DesignTokens.foreground
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    MouseArea {
                                        id: declineArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.requestDecline(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // Right column: Connected Modules
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 400
                    Layout.fillHeight: true
                    spacing: 24

                    Text {
                        text: root.connectedModules.length > 0 ? "Connected modules" : "No connected modules"
                        color: DesignTokens.foreground
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        font.family: DesignTokens.fontPrimary
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 16
                        clip: true
                        model: root.connectedModules
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 64
                            color: "#2a2a2a"
                            radius: 8

                            // Green marker (left border) with clip
                            Item {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 8
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 16
                                    color: DesignTokens.success
                                    radius: 8
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 10
                                spacing: 8

                                // Module info
                                ColumnLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 4

                                    Text {
                                        text: modelData.name
                                        color: DesignTokens.foreground
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    Text {
                                        text: "domains: " + modelData.domains
                                        color: DesignTokens.foregroundSecondary
                                        font.pixelSize: 12
                                        font.family: DesignTokens.fontPrimary
                                    }
                                }

                                Item { Layout.fillWidth: true }  // Spacer to push button right

                                // Disconnect button
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 105
                                    height: 32
                                    color: disconnectArea.containsMouse ? "#3a3a3a" : "transparent"
                                    border.color: DesignTokens.border
                                    border.width: 1
                                    radius: 16  // Pill shape

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Disconnect"
                                        color: DesignTokens.foreground
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    MouseArea {
                                        id: disconnectArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.moduleDisconnect(modelData.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Activity Log (bottom)
        ActivityLog {
            id: activityLog
            Layout.fillWidth: true
            Layout.preferredHeight: 167
        }
    }

    Component.onCompleted: {
        var timestamp = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(timestamp, "Session active", "success")

        // Check for pending requests and log them
        var result = logos.callModule("keycard", "getPendingAuths", [])
        try {
            var response = JSON.parse(result)
            if (response.pending && Array.isArray(response.pending) && response.pending.length > 0) {
                for (var i = 0; i < response.pending.length; i++) {
                    var req = response.pending[i]
                    activityLog.addEntry(timestamp, "Pending request from module " + req.caller + " for domain " + req.domain, "warning")
                }
            }
        } catch (e) {
            console.error("Failed to check pending requests on load:", e)
        }

        checkPendingRequests()
        updateSessionTime()
    }

    function lockSession() {
        console.log("Locking session...")
        lockRequested()
    }
}
