import QtQuick 2.15
import QtQuick.Layouts 1.15

/**
 * KeycardAuth — Drop-in Keycard authentication component for Basecamp modules.
 *
 * Usage:
 *   KeycardAuth {
 *       domain: "my_encryption_domain"
 *       caller: "my_module_name"
 *       onKeyReceived: function(hexKey) { /* use the 32-byte hex key */ }
 *       onError: function(message) { /* show error */ }
 *   }
 *
 * Handles: requestAuth → polling → key delivery.
 * Renders: "Connect with Keycard" button with pending/error states.
 * Developer sets domain + caller + callbacks — nothing else needed.
 */
Item {
    id: root

    // ── Required properties ────────────────────────────────────────
    property string domain: ""
    property string caller: ""

    // ── Signals ────────────────────────────────────────────────────
    signal keyReceived(string hexKey)
    signal error(string message)
    signal statusChanged(string status)

    // ── State ──────────────────────────────────────────────────────
    property string authId: ""
    property string status: "disconnected"  // "disconnected", "pending", "connected", "error"
    property string errorMessage: ""

    // ── Customizable appearance ────────────────────────────────────
    property color buttonColor: "#FF5722"
    property color buttonHoverColor: "#E64A19"
    property color pendingColor: "#FF9800"
    property color errorTextColor: "#F44336"
    property color textColor: "#FFFFFF"
    property color secondaryTextColor: "#888888"
    property int buttonHeight: 44
    property int buttonRadius: 22
    property int fontSize: 14
    property string connectText: "Connect with Keycard"
    property string pendingText: "Waiting for approval..."
    property string statusText: "Switch to Keycard module to approve"

    implicitHeight: layout.implicitHeight
    implicitWidth: layout.implicitWidth

    // ── Polling timer ──────────────────────────────────────────────
    Timer {
        id: poller
        interval: 1000
        repeat: true
        running: root.status === "pending"
        onTriggered: root._checkStatus()
    }

    // logos.callModule wraps C++ QString in an extra JSON layer — parse twice
    function callModuleParse(raw) {
        try {
            var tmp = JSON.parse(raw)
            return (typeof tmp === 'string') ? JSON.parse(tmp) : tmp
        } catch (e) { return null }
    }

    // ── Public API ─────────────────────────────────────────────────

    function connect() {
        if (typeof logos === "undefined" || !logos.callModule) {
            root._setError("Keycard module not available")
            return
        }
        if (!root.domain || !root.caller) {
            root._setError("domain and caller must be set")
            return
        }

        root.errorMessage = ""
        var result = logos.callModule("keycard", "requestAuth", [root.domain, root.caller])
        try {
            var response = callModuleParse(result)
            if (response.authId) {
                root.authId = response.authId
                root._setStatus("pending")
            } else if (response.error) {
                root._setError(response.error)
            } else {
                root._setError("Unexpected response from keycard")
            }
        } catch (e) {
            root._setError("Failed to request keycard auth")
        }
    }

    function reset() {
        poller.stop()
        root.authId = ""
        root.errorMessage = ""
        root._setStatus("disconnected")
    }

    // ── Internal ───────────────────────────────────────────────────

    function _checkStatus() {
        if (!root.authId) return
        var result = logos.callModule("keycard", "checkAuthStatus", [root.authId])
        try {
            var response = callModuleParse(result)
            if (response.status === "complete" && response.key) {
                root._setStatus("connected")
                root.keyReceived(response.key)
                // Auto-reset after delivering key
                Qt.callLater(root.reset)
            } else if (response.status === "failed") {
                root._setError(response.error || "Authorization failed")
            } else if (response.status === "rejected") {
                root._setError("Authorization rejected")
            } else if (response.error) {
                root._setError(response.error)
            }
            // "pending" → keep polling
        } catch (e) {
            root._setError("Keycard communication error")
        }
    }

    function _setStatus(s) {
        root.status = s
        root.statusChanged(s)
    }

    function _setError(msg) {
        root.errorMessage = msg
        root._setStatus("error")
        root.error(msg)
        // Return to disconnected after showing error
        Qt.callLater(function() {
            root.authId = ""
            root.status = "disconnected"
        })
    }

    Component.onDestruction: {
        poller.stop()
    }

    // ── Visual ─────────────────────────────────────────────────────

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        // Status text (only visible when pending)
        Text {
            Layout.fillWidth: true
            visible: root.status === "pending"
            text: root.statusText
            color: root.pendingColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }

        // Error text
        Text {
            Layout.fillWidth: true
            visible: root.errorMessage.length > 0
            text: root.errorMessage
            color: root.errorTextColor
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // Button
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.buttonHeight
            radius: root.buttonRadius
            color: {
                if (root.status === "pending") return root.pendingColor
                return buttonArea.containsMouse ? root.buttonHoverColor : root.buttonColor
            }
            opacity: root.status === "disconnected" ? 1.0 : 0.8

            Text {
                anchors.centerIn: parent
                text: root.status === "pending" ? root.pendingText : root.connectText
                color: root.textColor
                font.pixelSize: root.fontSize
                font.weight: Font.Medium
            }

            MouseArea {
                id: buttonArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.status === "disconnected"
                onClicked: root.connect()
            }
        }
    }
}
