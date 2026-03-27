import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 800
    height: 600
    color: "#1e1e1e"

    property string authRequestId: ""
    property string connectionStatus: "disconnected"  // "disconnected", "pending", "connected"
    property string derivedKey: ""

    // Poll for auth status when request is pending
    Timer {
        id: statusPoller
        interval: 1000
        running: root.connectionStatus === "pending"
        repeat: true
        onTriggered: checkAuthStatus()
    }

    function checkAuthStatus() {
        if (!root.authRequestId) return

        var result = logos.callModule("keycard", "checkAuthStatus", [root.authRequestId])
        try {
            var response = JSON.parse(result)
            if (response.status === "complete" && response.key) {
                root.connectionStatus = "connected"
                root.derivedKey = response.key
                statusText.text = "Connected! Key: " + response.key.substring(0, 16) + "..."
                statusText.color = "#4caf50"
            } else if (response.status === "failed") {
                root.connectionStatus = "disconnected"
                root.authRequestId = ""
                statusText.text = "Connection failed: " + (response.error || "Unknown error")
                statusText.color = "#f44336"
            } else if (response.status === "rejected") {
                root.connectionStatus = "disconnected"
                root.authRequestId = ""
                statusText.text = "Connection rejected"
                statusText.color = "#f44336"
            }
        } catch (e) {
            console.error("Failed to check auth status:", e)
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 32

        Text {
            text: "Auth Showcase"
            font.pixelSize: 32
            font.weight: Font.Bold
            color: "#ffffff"
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Demonstrates Keycard integration"
            font.pixelSize: 16
            color: "#888888"
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 240
            height: 56
            color: {
                if (root.connectionStatus === "connected") return "#4caf50"
                if (root.connectionStatus === "pending") return "#ff9800"
                return connectArea.containsMouse ? "#e64a19" : "#ff5722"
            }
            radius: 28

            Text {
                anchors.centerIn: parent
                text: {
                    if (root.connectionStatus === "connected") return "Connected ✓"
                    if (root.connectionStatus === "pending") return "Pending..."
                    return "Connect with Keycard"
                }
                color: "#ffffff"
                font.pixelSize: 16
                font.weight: Font.Medium
            }

            MouseArea {
                id: connectArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.connectionStatus === "disconnected"
                onClicked: {
                    console.log("Requesting auth from Keycard for domain: basic_auth")
                    var result = logos.callModule("keycard", "requestAuth", ["basic_auth", "auth_showcase"])
                    console.log("Result:", result)

                    try {
                        var response = JSON.parse(result)
                        console.log("Parsed response:", JSON.stringify(response))
                        if (response.authId) {
                            root.authRequestId = response.authId
                            root.connectionStatus = "pending"
                            statusText.text = "Switch to Keycard to approve"
                            statusText.color = "#ff9800"
                        } else if (response.error) {
                            statusText.text = "Error: " + response.error
                            statusText.color = "#f44336"
                        } else {
                            // No authId and no error - show what we got
                            statusText.text = "Unexpected response: " + result.substring(0, 50)
                            statusText.color = "#f44336"
                        }
                    } catch (e) {
                        console.error("Parse error:", e, "Raw result:", result)
                        // Even if parsing failed, try to show a helpful message
                        statusText.text = "Error: " + (result ? result.substring(0, 100) : "No response")
                        statusText.color = "#f44336"
                    }
                }
            }
        }

        Text {
            id: statusText
            text: "Click button to request authorization"
            font.pixelSize: 14
            color: "#888888"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 400
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
