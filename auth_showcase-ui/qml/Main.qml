import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 800
    height: 600
    color: "#1e1e1e"

    property string authRequestId: ""
    property string connectionStatus: "disconnected"  // "disconnected", "pending", "connected", "error"
    property string derivedKey: ""
    property string errorMessage: ""

    // logos.callModule wraps C++ QString in an extra JSON layer — parse twice
    // See: https://github.com/xAlisher/keycard-basecamp/issues/121
    function callModuleParse(raw) {
        try {
            var tmp = JSON.parse(raw)
            return (typeof tmp === 'string') ? JSON.parse(tmp) : tmp
        } catch (e) { return null }
    }

    function reset() {
        root.authRequestId = ""
        root.derivedKey = ""
        root.errorMessage = ""
        root.connectionStatus = "disconnected"
    }

    // Poll for auth status when request is pending
    Timer {
        id: statusPoller
        interval: 1000
        running: root.connectionStatus === "pending"
        repeat: true
        onTriggered: checkAuthStatus()
    }

    function requestAuth() {
        root.errorMessage = ""
        var result = logos.callModule("keycard", "requestAuth", ["basic_auth", "auth_showcase"])
        var response = callModuleParse(result)
        if (!response) {
            root.errorMessage = "No response from keycard module"
            root.connectionStatus = "error"
            return
        }
        if (response.authId) {
            root.authRequestId = response.authId
            root.connectionStatus = "pending"
        } else {
            root.errorMessage = response.error || "Unexpected response"
            root.connectionStatus = "error"
        }
    }

    function checkAuthStatus() {
        if (!root.authRequestId) return

        var result = logos.callModule("keycard", "checkAuthStatus", [root.authRequestId])
        var response = callModuleParse(result)
        if (!response) return

        if (response.status === "complete" && response.key) {
            root.derivedKey = response.key
            root.connectionStatus = "connected"
        } else if (response.status === "failed") {
            root.errorMessage = response.error || "Authorization failed"
            root.connectionStatus = "error"
        } else if (response.status === "rejected") {
            root.errorMessage = "Authorization rejected"
            root.connectionStatus = "error"
        } else if (response.error) {
            root.errorMessage = response.error
            root.connectionStatus = "error"
        }
        // "pending" → keep polling
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24
        width: 360

        Text {
            text: "Auth Showcase"
            font.pixelSize: 32
            font.weight: Font.Bold
            color: "#ffffff"
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Tests the full Keycard auth flow"
            font.pixelSize: 14
            color: "#888888"
            Layout.alignment: Qt.AlignHCenter
        }

        // Status indicator
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            height: 48
            radius: 8
            color: {
                if (root.connectionStatus === "connected") return "#1a3a1a"
                if (root.connectionStatus === "pending")   return "#3a2a0a"
                if (root.connectionStatus === "error")     return "#3a0a0a"
                return "#2a2a2a"
            }
            border.color: {
                if (root.connectionStatus === "connected") return "#4caf50"
                if (root.connectionStatus === "pending")   return "#ff9800"
                if (root.connectionStatus === "error")     return "#f44336"
                return "#444444"
            }
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: {
                    if (root.connectionStatus === "connected") return "✓ Key received"
                    if (root.connectionStatus === "pending")   return "Waiting for approval in Keycard UI..."
                    if (root.connectionStatus === "error")     return "✗ " + root.errorMessage
                    return "Not connected"
                }
                color: {
                    if (root.connectionStatus === "connected") return "#4caf50"
                    if (root.connectionStatus === "pending")   return "#ff9800"
                    if (root.connectionStatus === "error")     return "#f44336"
                    return "#888888"
                }
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                width: parent.width - 24
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Key preview (only when connected)
        Rectangle {
            visible: root.connectionStatus === "connected" && root.derivedKey.length > 0
            Layout.fillWidth: true
            height: 56
            radius: 8
            color: "#0d1f0d"
            border.color: "#2d5a2d"
            border.width: 1

            Column {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    text: "Derived Key (first 16 bytes)"
                    color: "#4caf50"
                    font.pixelSize: 11
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: root.derivedKey.substring(0, 32) + "..."
                    color: "#88dd88"
                    font.pixelSize: 12
                    font.family: "monospace"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // Connect button
        Rectangle {
            Layout.fillWidth: true
            height: 44
            radius: 22
            visible: root.connectionStatus === "disconnected" || root.connectionStatus === "error"
            color: connectArea.containsMouse ? "#e64a19" : "#ff5722"

            Text {
                anchors.centerIn: parent
                text: "Connect with Keycard"
                color: "#ffffff"
                font.pixelSize: 15
                font.weight: Font.Medium
            }

            MouseArea {
                id: connectArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: requestAuth()
            }
        }

        // Try Again button (after success or error)
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 18
            visible: root.connectionStatus === "connected" || root.connectionStatus === "error"
            color: tryAgainArea.containsMouse ? "#333333" : "#2a2a2a"
            border.color: "#555555"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "Try Again"
                color: "#aaaaaa"
                font.pixelSize: 13
            }

            MouseArea {
                id: tryAgainArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: reset()
            }
        }

        // Instructions
        Text {
            visible: root.connectionStatus === "pending"
            Layout.fillWidth: true
            text: "1. Open the Keycard panel in the sidebar\n2. The request will appear in the activity log\n3. Enter your PIN to approve"
            color: "#666666"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
