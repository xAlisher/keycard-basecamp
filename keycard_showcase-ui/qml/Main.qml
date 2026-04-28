import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 800
    height: 600
    color: "#1e1e1e"

    // Auth state
    property string authRequestId: ""
    property string authStatus: "idle"  // "idle", "pending", "complete", "error"
    property string derivedKey: ""
    property string authError: ""

    // Sign state
    property string signRequestId: ""
    property string signStatus: "idle"  // "idle", "pending", "complete", "error"
    property string signature: ""
    property string signError: ""

    // XPUB state
    property string xpubRequestId: ""
    property string xpubStatus: "idle"  // "idle", "pending", "complete", "error"
    property string xpub: ""
    property string xpubError: ""

    // logos.callModule wraps C++ QString in an extra JSON layer — parse twice
    // See: https://github.com/xAlisher/keycard-basecamp/issues/121
    function callModuleParse(raw) {
        try {
            var tmp = JSON.parse(raw)
            return (typeof tmp === 'string') ? JSON.parse(tmp) : tmp
        } catch (e) { return null }
    }

    function resetAuth() {
        root.authRequestId = ""
        root.derivedKey = ""
        root.authError = ""
        root.authStatus = "idle"
    }

    function resetSign() {
        root.signRequestId = ""
        root.signature = ""
        root.signError = ""
        root.signStatus = "idle"
    }

    function resetXPUB() {
        root.xpubRequestId = ""
        root.xpub = ""
        root.xpubError = ""
        root.xpubStatus = "idle"
    }

    Timer {
        id: authPoller
        interval: 1000
        running: root.authStatus === "pending"
        repeat: true
        onTriggered: checkAuthStatus()
    }

    Timer {
        id: signPoller
        interval: 1000
        running: root.signStatus === "pending"
        repeat: true
        onTriggered: checkSignStatus()
    }

    Timer {
        id: xpubPoller
        interval: 1000
        running: root.xpubStatus === "pending"
        repeat: true
        onTriggered: checkXPUBStatus()
    }

    function requestAuth() {
        root.authError = ""
        var result = logos.callModule("keycard", "requestAuth", ["basic_auth", "keycard_showcase"])
        var response = callModuleParse(result)
        if (!response) {
            root.authError = "No response from keycard module"
            root.authStatus = "error"
            return
        }
        if (response.authId) {
            root.authRequestId = response.authId
            root.authStatus = "pending"
        } else {
            root.authError = response.error || "Unexpected response"
            root.authStatus = "error"
        }
    }

    function checkAuthStatus() {
        if (!root.authRequestId) return
        var result = logos.callModule("keycard", "checkAuthStatus", [root.authRequestId])
        var response = callModuleParse(result)
        if (!response) return
        if (response.status === "complete" && response.key) {
            root.derivedKey = response.key
            root.authStatus = "complete"
        } else if (response.status === "failed") {
            root.authError = response.error || "Authorization failed"
            root.authStatus = "error"
        } else if (response.status === "rejected") {
            root.authError = "Authorization rejected"
            root.authStatus = "error"
        } else if (response.error) {
            root.authError = response.error
            root.authStatus = "error"
        }
    }

    function requestSign() {
        root.signError = ""
        // Hash the message via keycard_showcase core plugin
        var hashResult = logos.callModule("keycard", "hashMessage", [messageInput.text])
        var hashResponse = callModuleParse(hashResult)
        if (!hashResponse || !hashResponse.hash) {
            root.signError = "Failed to hash message"
            root.signStatus = "error"
            return
        }
        var args = JSON.stringify({
            domain: "keycard_showcase",
            payloadHash: hashResponse.hash,
            caller: "keycard_showcase",
            scheme: "schnorr"
        })
        var result = logos.callModule("keycard", "requestSign", [args])
        var response = callModuleParse(result)
        if (!response) {
            root.signError = "No response from keycard module"
            root.signStatus = "error"
            return
        }
        if (response.signId) {
            root.signRequestId = response.signId
            root.signStatus = "pending"
        } else {
            root.signError = response.error || "Unexpected response"
            root.signStatus = "error"
        }
    }

    function checkSignStatus() {
        if (!root.signRequestId) return
        var result = logos.callModule("keycard", "checkSignStatus", [root.signRequestId])
        var response = callModuleParse(result)
        if (!response) return
        if (response.status === "complete" && response.signature) {
            root.signature = response.signature
            root.signStatus = "complete"
        } else if (response.status === "failed") {
            root.signError = response.error || "Signing failed"
            root.signStatus = "error"
        } else if (response.status === "rejected") {
            root.signError = "Signing rejected"
            root.signStatus = "error"
        } else if (response.error) {
            root.signError = response.error
            root.signStatus = "error"
        }
    }

    function requestXPUB() {
        root.xpubError = ""
        var args = JSON.stringify({
            bip32_path: "m/44'/60'/0'/0",
            caller: "keycard_showcase"
        })
        var result = logos.callModule("keycard", "requestXPUB", [args])
        var response = callModuleParse(result)
        if (!response) {
            root.xpubError = "No response from keycard module"
            root.xpubStatus = "error"
            return
        }
        if (response.xpubId) {
            root.xpubRequestId = response.xpubId
            root.xpubStatus = "pending"
        } else {
            root.xpubError = response.error || "Unexpected response"
            root.xpubStatus = "error"
        }
    }

    function checkXPUBStatus() {
        if (!root.xpubRequestId) return
        var result = logos.callModule("keycard", "checkXPUBStatus", [root.xpubRequestId])
        var response = callModuleParse(result)
        if (!response) return
        if (response.status === "complete" && response.xpub) {
            root.xpub = response.xpub
            root.xpubStatus = "complete"
        } else if (response.status === "failed") {
            root.xpubError = response.error || "XPUB export failed"
            root.xpubStatus = "error"
        } else if (response.status === "rejected") {
            root.xpubError = "XPUB export rejected"
            root.xpubStatus = "error"
        } else if (response.error) {
            root.xpubError = response.error
            root.xpubStatus = "error"
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width

        ColumnLayout {
            width: parent.width
            spacing: 0

            // ── Header ──────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 48
                Layout.bottomMargin: 32
                spacing: 8

                Text {
                    text: "Keycard Showcase"
                    font.pixelSize: 32
                    font.weight: Font.Bold
                    color: "#ffffff"
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: "End-to-end Keycard auth and signing demo"
                    font.pixelSize: 14
                    color: "#888888"
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // ── Auth section ──────────────────────────────────────────────
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 40
                spacing: 16

                Text {
                    text: "Authentication"
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    color: "#cccccc"
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.preferredWidth: 360
                    height: 48
                    radius: 8
                    color: {
                        if (root.authStatus === "complete") return "#1a3a1a"
                        if (root.authStatus === "pending")  return "#3a2a0a"
                        if (root.authStatus === "error")    return "#3a0a0a"
                        return "#2a2a2a"
                    }
                    border.color: {
                        if (root.authStatus === "complete") return "#4caf50"
                        if (root.authStatus === "pending")  return "#ff9800"
                        if (root.authStatus === "error")    return "#f44336"
                        return "#444444"
                    }
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (root.authStatus === "complete") return "✓ Key received"
                            if (root.authStatus === "pending")  return "Waiting for approval in Keycard UI..."
                            if (root.authStatus === "error")    return "✗ " + root.authError
                            return "Not connected"
                        }
                        color: {
                            if (root.authStatus === "complete") return "#4caf50"
                            if (root.authStatus === "pending")  return "#ff9800"
                            if (root.authStatus === "error")    return "#f44336"
                            return "#888888"
                        }
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        width: parent.width - 24
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Rectangle {
                    visible: root.authStatus === "complete" && root.derivedKey.length > 0
                    Layout.preferredWidth: 360
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

                Rectangle {
                    Layout.preferredWidth: 360
                    height: 44
                    radius: 22
                    visible: root.authStatus === "idle" || root.authStatus === "error"
                    color: authConnectArea.containsMouse ? "#e64a19" : "#ff5722"

                    Text {
                        anchors.centerIn: parent
                        text: "Connect with Keycard"
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: authConnectArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: requestAuth()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 360
                    height: 36
                    radius: 18
                    visible: root.authStatus === "complete" || root.authStatus === "error"
                    color: authResetArea.containsMouse ? "#333333" : "#2a2a2a"
                    border.color: "#555555"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Try Again"
                        color: "#aaaaaa"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: authResetArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: resetAuth()
                    }
                }

                Text {
                    visible: root.authStatus === "pending"
                    Layout.preferredWidth: 360
                    text: "Open the Keycard panel in the sidebar — the request will appear in the activity log"
                    color: "#666666"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            // ── Divider ───────────────────────────────────────────────────
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 360
                height: 1
                color: "#333333"
                Layout.bottomMargin: 40
            }

            // ── Sign section ──────────────────────────────────────────────
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 48
                spacing: 16

                Text {
                    text: "Message Signing"
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    color: "#cccccc"
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.preferredWidth: 360
                    height: 44
                    radius: 8
                    color: "#2a2a2a"
                    border.color: messageInput.activeFocus ? "#1976d2" : "#444444"
                    border.width: 1

                    TextInput {
                        id: messageInput
                        anchors.fill: parent
                        anchors.margins: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.family: "monospace"
                        text: "hello world"
                        enabled: root.signStatus === "idle" || root.signStatus === "error"
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 360
                    height: 44
                    radius: 22
                    visible: root.signStatus === "idle" || root.signStatus === "error"
                    color: signArea.containsMouse ? "#1565c0" : "#1976d2"
                    opacity: messageInput.text.length > 0 ? 1.0 : 0.5

                    Text {
                        anchors.centerIn: parent
                        text: "Sign with Keycard"
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: signArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: messageInput.text.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: messageInput.text.length > 0
                        onClicked: requestSign()
                    }
                }

                Rectangle {
                    visible: root.signStatus === "pending"
                    Layout.preferredWidth: 360
                    height: 48
                    radius: 8
                    color: "#3a2a0a"
                    border.color: "#ff9800"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Waiting for signature in Keycard UI..."
                        color: "#ff9800"
                        font.pixelSize: 13
                    }
                }

                Rectangle {
                    visible: root.signStatus === "complete" && root.signature.length > 0
                    Layout.preferredWidth: 360
                    implicitHeight: sigCol.implicitHeight + 24
                    radius: 8
                    color: "#0d1a2e"
                    border.color: "#1976d2"
                    border.width: 1

                    Column {
                        id: sigCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 6

                        Text {
                            text: "Schnorr signature (64 bytes)"
                            color: "#64b5f6"
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.signature
                            color: "#90caf9"
                            font.pixelSize: 11
                            font.family: "monospace"
                            wrapMode: Text.WrapAnywhere
                            width: parent.width
                        }
                    }
                }

                Text {
                    visible: root.signStatus === "error"
                    Layout.preferredWidth: 360
                    text: "✗ " + root.signError
                    color: "#f44336"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    Layout.preferredWidth: 360
                    height: 36
                    radius: 18
                    visible: root.signStatus === "complete" || root.signStatus === "error"
                    color: signResetArea.containsMouse ? "#333333" : "#2a2a2a"
                    border.color: "#555555"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Sign Again"
                        color: "#aaaaaa"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: signResetArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: resetSign()
                    }
                }

                Text {
                    visible: root.signStatus === "pending"
                    Layout.preferredWidth: 360
                    text: "Open the Keycard panel in the sidebar — enter your PIN and press Sign"
                    color: "#666666"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            // ── Divider ───────────────────────────────────────────────────
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 360
                height: 1
                color: "#333333"
                Layout.bottomMargin: 40
            }

            // ── XPUB section ──────────────────────────────────────────────
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 48
                spacing: 16

                Text {
                    text: "XPUB Export"
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    color: "#cccccc"
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    Layout.preferredWidth: 360
                    text: "Export the extended public key for offline child key derivation (BIP32)"
                    color: "#666666"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.preferredWidth: 360
                    height: 44
                    radius: 22
                    visible: root.xpubStatus === "idle" || root.xpubStatus === "error"
                    color: xpubArea.containsMouse ? "#1b5e20" : "#2e7d32"

                    Text {
                        anchors.centerIn: parent
                        text: "Export XPUB"
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: xpubArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: requestXPUB()
                    }
                }

                Rectangle {
                    visible: root.xpubStatus === "pending"
                    Layout.preferredWidth: 360
                    height: 48
                    radius: 8
                    color: "#3a2a0a"
                    border.color: "#ff9800"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Waiting for XPUB approval in Keycard UI..."
                        color: "#ff9800"
                        font.pixelSize: 13
                    }
                }

                Rectangle {
                    visible: root.xpubStatus === "complete" && root.xpub.length > 0
                    Layout.preferredWidth: 360
                    implicitHeight: xpubCol.implicitHeight + 24
                    radius: 8
                    color: "#0d1f0d"
                    border.color: "#2e7d32"
                    border.width: 1

                    Column {
                        id: xpubCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 6

                        Text {
                            text: "Public key (65 bytes) + chain code (32 bytes)"
                            color: "#81c784"
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.xpub
                            color: "#a5d6a7"
                            font.pixelSize: 11
                            font.family: "monospace"
                            wrapMode: Text.WrapAnywhere
                            width: parent.width
                        }
                    }
                }

                Text {
                    visible: root.xpubStatus === "error"
                    Layout.preferredWidth: 360
                    text: "✗ " + root.xpubError
                    color: "#f44336"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    Layout.preferredWidth: 360
                    height: 36
                    radius: 18
                    visible: root.xpubStatus === "complete" || root.xpubStatus === "error"
                    color: xpubResetArea.containsMouse ? "#333333" : "#2a2a2a"
                    border.color: "#555555"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Export Again"
                        color: "#aaaaaa"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: xpubResetArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: resetXPUB()
                    }
                }

                Text {
                    visible: root.xpubStatus === "pending"
                    Layout.preferredWidth: 360
                    text: "Open the Keycard panel in the sidebar — enter your PIN and press Approve XPUB"
                    color: "#666666"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
