import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 1000
    height: 800
    color: "#2b2b2b"

    property string currentState: "READER_NOT_FOUND"
    property bool readerFound: false
    property bool cardFound: false
    property string cardUID: ""
    property bool cardPaired: false
    property int pairingSlot: -1
    property bool autoDetectionStarted: false
    property var pendingAuthRequests: []

    // Add property to hold result message (accessible from anywhere)
    property string authResultMessage: "Test flow:\n1. 'Create Fake Request' → adds to Pending Authorizations\n2. Click 'Authorize' in pending list → opens modal\n3. 'Show Auth Window' → direct test (no pending request)"
    property string authResultColor: "#88ccff"

    // Auto-start detection on load
    Component.onCompleted: {
        // Initialize reader detection
        var result = logos.callModule("keycard", "discoverReader", [])
        try {
            var obj = JSON.parse(result)
            root.readerFound = obj.found === true
        } catch (e) {}

        // Load pending auth requests
        refreshPendingAuths()
    }

    function refreshPendingAuths() {
        var result = logos.callModule("keycard", "getPendingAuths", [])
        try {
            var obj = JSON.parse(result)
            if (obj.pending) {
                root.pendingAuthRequests = obj.pending
            }
        } catch (e) {
            console.log("Error fetching pending auths:", e)
        }
    }

    // Poll state and auto-detect card every 500ms
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            // Get current state
            var result = logos.callModule("keycard", "getState", [])
            try {
                var obj = JSON.parse(result)
                if (obj.state) {
                    root.currentState = obj.state
                }
            } catch (e) {}

            // Auto-detect card if reader is present
            if (root.currentState !== "READER_NOT_FOUND") {
                var cardResult = logos.callModule("keycard", "discoverCard", [])
                try {
                    var cardObj = JSON.parse(cardResult)
                    root.cardFound = cardObj.found === true
                    if (cardObj.uid) {
                        root.cardUID = cardObj.uid
                    } else {
                        root.cardUID = ""
                    }

                    // Check pairing status if card found
                    if (cardObj.found) {
                        var pairingResult = logos.callModule("keycard", "checkPairing", [])
                        try {
                            var pairObj = JSON.parse(pairingResult)
                            root.cardPaired = pairObj.paired === true
                            root.pairingSlot = pairObj.pairingIndex || -1
                        } catch (e) {
                            root.cardPaired = false
                            root.pairingSlot = -1
                        }
                    } else {
                        root.cardPaired = false
                        root.pairingSlot = -1
                    }
                } catch (e) {
                    root.cardFound = false
                    root.cardUID = ""
                }
            } else {
                // Reader not found - clear card status
                root.cardFound = false
                root.cardUID = ""
                root.cardPaired = false
            }
        }
    }

    // Refresh pending auth requests every 2 seconds
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            refreshPendingAuths()
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 20
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 10

            // Header
            Text {
                text: "Keycard Debug UI - Test Harness"
                font.pixelSize: 24
                font.bold: true
                color: "#ffffff"
                Layout.alignment: Qt.AlignHCenter
            }

            // Live State Indicator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                color: "#1a1a1a"
                border.color: "#555555"
                border.width: 2
                radius: 5

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: "Current State:"
                        font.pixelSize: 14
                        color: "#888888"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: root.currentState
                        font.pixelSize: 28
                        font.bold: true
                        color: getStateColor(root.currentState)
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // Status Displays (auto-detected)
            StatusRow {
                id: readerStatus
                title: "Reader Status"
                statusText: root.currentState !== "READER_NOT_FOUND" ? "✓ Reader found" : "✗ Reader not found"
                statusGood: root.currentState !== "READER_NOT_FOUND"
                resultText: root.readerFound ? '{"found":true,"name":"Smart card reader"}' : '{"found":false}'
            }

            StatusRow {
                id: cardStatus
                title: "Card Status"
                statusText: {
                    if (root.cardFound && root.cardUID) {
                        return "✓ Card detected (UID: " + root.cardUID.substring(0, 16) + "...)"
                    }
                    if (root.currentState === "READER_NOT_FOUND") return "✗ Reader not found"
                    if (!root.cardFound) return "✗ No card inserted"
                    return "Checking..."
                }
                statusGood: root.cardFound
                resultText: root.cardFound ? '{"found":true,"uid":"' + root.cardUID + '"}' : '{"found":false}'
            }

            // Custom Pairing Row (shows Pair or Unpair based on status)
            Rectangle {
                id: pairCardRow
                Layout.fillWidth: true
                Layout.preferredHeight: root.cardPaired ? 100 : 140
                color: "#1a1a1a"
                border.color: "#555555"
                border.width: 1
                radius: 5

                property alias inputValue: pairingPasswordField.text

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 10

                    // Title and Status
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 15

                        Text {
                            text: "1. Pair Card"
                            font.pixelSize: 16
                            font.bold: true
                            color: "#ffffff"
                            Layout.preferredWidth: 200
                        }

                        Text {
                            text: {
                                if (root.cardPaired) {
                                    if (root.currentState === "AUTHORIZED" || root.currentState === "SESSION_ACTIVE") {
                                        return "✓ Paired (slot " + root.pairingSlot + ") - Authorized"
                                    } else {
                                        return "✓ Paired (slot " + root.pairingSlot + ") - Authorize to unpair"
                                    }
                                }
                                if (root.currentState === "CARD_PRESENT" ||
                                    root.currentState === "AUTHORIZED" ||
                                    root.currentState === "SESSION_ACTIVE") return "Ready to pair"
                                if (root.currentState === "CARD_NOT_PRESENT") return "✗ Card not present"
                                if (root.currentState === "READER_NOT_FOUND") return "✗ Reader not found"
                                return "Ready to pair"
                            }
                            font.pixelSize: 13
                            color: {
                                if (root.cardPaired) {
                                    if (root.currentState === "AUTHORIZED" || root.currentState === "SESSION_ACTIVE") {
                                        return "#00ff00"  // Green when can unpair
                                    } else {
                                        return "#ffaa00"  // Orange when need to authorize
                                    }
                                }
                                return (root.currentState === "CARD_PRESENT" ||
                                        root.currentState === "AUTHORIZED" ||
                                        root.currentState === "SESSION_ACTIVE") ? "#00ff00" : "#ff4444"
                            }
                            Layout.fillWidth: true
                        }

                        Button {
                            text: root.cardPaired ? "Unpair" : "Pair"
                            enabled: {
                                if (root.cardPaired) {
                                    // Unpair requires authorization
                                    return root.currentState === "AUTHORIZED" || root.currentState === "SESSION_ACTIVE"
                                } else {
                                    // Pair works when card present
                                    return root.currentState === "CARD_PRESENT" ||
                                           root.currentState === "AUTHORIZED" ||
                                           root.currentState === "SESSION_ACTIVE"
                                }
                            }
                            Layout.preferredWidth: 100
                            onClicked: {
                                var result
                                if (root.cardPaired) {
                                    // Unpair
                                    result = logos.callModule("keycard", "unpairCard", [])
                                    pairResultDisplay.text = result
                                    try {
                                        var obj = JSON.parse(result)
                                        if (obj.unpaired === true) {
                                            root.cardPaired = false
                                            root.pairingSlot = -1
                                            pairResultDisplay.color = "#00ff00"
                                        } else {
                                            pairResultDisplay.color = "#ff4444"
                                        }
                                    } catch (e) {
                                        pairResultDisplay.color = "#ffaa00"
                                    }
                                } else {
                                    // Pair
                                    var password = pairingPasswordField.text || "KeycardDefaultPairing"
                                    if (password.length < 5 || password.length > 25) {
                                        result = '{"error":"Pairing password must be 5-25 characters"}'
                                        pairResultDisplay.text = result
                                        pairResultDisplay.color = "#ff4444"
                                        return
                                    }
                                    result = logos.callModule("keycard", "pairCard", [password])
                                    pairResultDisplay.text = result
                                    try {
                                        var obj = JSON.parse(result)
                                        if (obj.paired === true) {
                                            root.cardPaired = true
                                            root.pairingSlot = obj.pairingIndex || -1
                                            pairResultDisplay.color = "#00ff00"
                                        } else {
                                            pairResultDisplay.color = "#ff4444"
                                        }
                                    } catch (e) {
                                        pairResultDisplay.color = "#ffaa00"
                                    }
                                }
                            }

                            background: Rectangle {
                                color: parent.enabled ? (parent.down ? "#555555" : "#3a3a3a") : "#2a2a2a"
                                border.color: parent.enabled ? "#666666" : "#444444"
                                border.width: 1
                                radius: 3
                            }

                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? "#ffffff" : "#666666"
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // Password Input (only show when not paired)
                    RowLayout {
                        visible: !root.cardPaired
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "Pairing Password:"
                            color: "#aaaaaa"
                            font.pixelSize: 13
                        }

                        TextField {
                            id: pairingPasswordField
                            placeholderText: "KeycardDefaultPairing"
                            text: "KeycardDefaultPairing"
                            Layout.fillWidth: true
                            color: "#ffffff"
                            background: Rectangle {
                                color: "#0a0a0a"
                                border.color: "#555555"
                                border.width: 1
                                radius: 3
                            }
                        }
                    }

                    // Result Display
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            color: "#0a0a0a"
                            border.color: "#555555"
                            border.width: 1
                            radius: 3

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 5
                                clip: true

                                TextEdit {
                                    id: pairResultDisplay
                                    text: "No result yet"
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    color: "#888888"
                                    wrapMode: TextEdit.Wrap
                                    readOnly: true
                                    selectByMouse: true
                                }
                            }
                        }

                        Button {
                            text: "Copy"
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: 30
                            enabled: pairResultDisplay.text.length > 0 && pairResultDisplay.text !== "No result yet"
                            onClicked: {
                                pairResultDisplay.selectAll()
                                pairResultDisplay.copy()
                                pairResultDisplay.deselect()
                                this.text = "✓ Copied"
                                pairCopyTimer.restart()
                            }

                            Timer {
                                id: pairCopyTimer
                                interval: 1000
                                onTriggered: {
                                    parent.text = "Copy"
                                }
                            }

                            background: Rectangle {
                                color: parent.enabled ? (parent.down ? "#4a7ba7" : "#5a8fc7") : "#3a3a3a"
                                border.color: parent.enabled ? "#6a9fd7" : "#555555"
                                border.width: 1
                                radius: 3
                            }

                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? "#ffffff" : "#666666"
                                font.pixelSize: 11
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }

            ActionRow {
                id: authorizeRow
                title: "2. Authorize (Enter PIN)"
                prereqText: {
                    if (root.currentState === "CARD_PRESENT") return "✓ Card present"
                    if (root.currentState === "SESSION_CLOSED") return "✓ Card present (re-auth allowed)"
                    if (root.currentState === "AUTHORIZED" || root.currentState === "SESSION_ACTIVE") return "Already authorized"
                    if (root.currentState === "CARD_NOT_PRESENT") return "✗ Card not present"
                    if (root.currentState === "READER_NOT_FOUND") return "✗ Reader not found"
                    if (root.currentState === "BLOCKED") return "✗ Card blocked"
                    return "✗ Not authorized"
                }
                prereqMet: root.currentState === "CARD_PRESENT" || root.currentState === "SESSION_CLOSED"
                showPinInput: true
                executeFunc: function() {
                    var pin = authorizeRow.inputValue
                    if (pin.length === 0) {
                        return '{"error":"PIN required"}'
                    }
                    // Validate PIN format: exactly 6 digits
                    if (pin.length !== 6 || !/^\d+$/.test(pin)) {
                        return '{"error":"Wrong PIN format - should be 6 digits"}'
                    }
                    var result = logos.callModule("keycard", "authorize", [pin])
                    authorizeRow.clearInput()
                    return result
                }
            }

            ActionRow {
                id: deriveKeyRow
                title: "3. Derive Key"
                prereqText: (root.currentState === "AUTHORIZED" || root.currentState === "SESSION_ACTIVE")
                    ? "✓ Authorized" : "✗ Not authorized"
                prereqMet: root.currentState === "AUTHORIZED" || root.currentState === "SESSION_ACTIVE"
                showDomainInput: true
                inputPlaceholder: "logos-notes-encryption"
                executeFunc: function() {
                    var domain = deriveKeyRow.inputValue || "logos-notes-encryption"
                    return logos.callModule("keycard", "deriveKey", [domain])
                }
            }

            ActionRow {
                title: "4. Test PC/SC (Debug)"
                alwaysEnabled: true
                prereqText: "Direct PC/SC test"
                prereqMet: true
                executeFunc: function() {
                    return logos.callModule("keycard", "testPCSC", [])
                }
            }

            ActionRow {
                title: "5. Get State"
                alwaysEnabled: true
                prereqText: "No prerequisites"
                prereqMet: true
                executeFunc: function() {
                    return logos.callModule("keycard", "getState", [])
                }
            }

            ActionRow {
                title: "6. Get Last Error"
                alwaysEnabled: true
                prereqText: "No prerequisites"
                prereqMet: true
                executeFunc: function() {
                    return logos.callModule("keycard", "getLastError", [])
                }
            }

            ActionRow {
                title: "7. Close Session"
                prereqText: {
                    if (root.currentState === "SESSION_ACTIVE") return "✓ Session active"
                    if (root.currentState === "AUTHORIZED") return "✓ Authorized (can close)"
                    return "✗ No active session"
                }
                prereqMet: root.currentState === "SESSION_ACTIVE" || root.currentState === "AUTHORIZED"
                executeFunc: function() {
                    return logos.callModule("keycard", "closeSession", [])
                }
            }

            // Pending Authorization Requests
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.pendingAuthRequests.length > 0 ? 150 + (root.pendingAuthRequests.length * 60) : 80
                color: "#1a2a1a"
                border.color: root.pendingAuthRequests.length > 0 ? "#88ff88" : "#555555"
                border.width: 2
                radius: 5
                visible: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "⏳ Pending Authorization Requests"
                            font.pixelSize: 16
                            font.bold: true
                            color: root.pendingAuthRequests.length > 0 ? "#88ff88" : "#888888"
                            Layout.preferredWidth: 350
                        }

                        Text {
                            text: root.pendingAuthRequests.length > 0 ?
                                  ("(" + root.pendingAuthRequests.length + " pending)") : "(No pending requests)"
                            font.pixelSize: 13
                            color: root.pendingAuthRequests.length > 0 ? "#88ff88" : "#666666"
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        visible: root.pendingAuthRequests.length === 0
                        text: "No apps are currently requesting authorization.\nWhen an app needs access, it will appear here."
                        font.pixelSize: 12
                        color: "#666666"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: root.pendingAuthRequests

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 50
                            color: "#2a3a2a"
                            border.color: "#4a9a4a"
                            border.width: 1
                            radius: 3

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 15

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        text: "App: " + modelData.caller
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#ffffff"
                                    }

                                    Text {
                                        text: "Domain: " + modelData.domain
                                        font.pixelSize: 11
                                        font.family: "monospace"
                                        color: "#88ff88"
                                    }
                                }

                                Button {
                                    text: "Authorize"
                                    Layout.preferredWidth: 100

                                    background: Rectangle {
                                        color: parent.down ? "#3a7a3a" : "#4a9a4a"
                                        border.color: "#6aff6a"
                                        border.width: 1
                                        radius: 3
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        color: "#ffffff"
                                        font.pixelSize: 12
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: {
                                        // Open auth window with this request's details
                                        console.log("DEBUG: Authorize button clicked, authId:", modelData.authId)
                                        authWindow.currentAuthId = modelData.authId
                                        authWindow.domain = modelData.domain
                                        authWindow.requestingModule = modelData.caller
                                        authWindow.remainingAttempts = 3

                                        // Test if modalAuthResult is accessible
                                        console.log("DEBUG: modalAuthResult accessible?", typeof modalAuthResult !== 'undefined')

                                        // Connect success/failure signals to update UI
                                        authWindow.authorizationComplete.connect(function(success, key) {
                                            console.log("DEBUG: authorizationComplete signal fired! success=", success, "key=", key ? key.substring(0, 16) : "null")
                                            try {
                                                if (success) {
                                                    console.log("DEBUG: Setting success message on modalAuthResult")
                                                    root.authResultMessage = "✅ Authorization successful!\nKey: " + key.substring(0, 32) + "..."
                                                    root.authResultColor = "#00ff00"
                                                    console.log("DEBUG: Success message set!")
                                                } else {
                                                    console.log("DEBUG: Setting failure message")
                                                    root.authResultMessage = "❌ Authorization failed"
                                                    root.authResultColor = "#ff4444"
                                                }
                                            } catch(e) {
                                                console.log("DEBUG ERROR in signal handler:", e)
                                            }
                                        })

                                        authWindow.cancelled.connect(function() {
                                            console.log("DEBUG: cancelled signal fired!")
                                            try {
                                                root.authResultMessage = "⚠️ User cancelled authorization"
                                                root.authResultColor = "#ffaa00"
                                            } catch(e) {
                                                console.log("DEBUG ERROR in cancelled handler:", e)
                                            }
                                        })

                                        console.log("DEBUG: Opening auth window")
                                        authWindow.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // NEW: Modal Auth Window Test
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                color: "#1a2a3a"
                border.color: "#4a9eff"
                border.width: 2
                radius: 5

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 15

                        Text {
                            text: "8. Test Modal Auth Window"
                            font.pixelSize: 16
                            font.bold: true
                            color: "#4a9eff"
                            Layout.preferredWidth: 250
                        }

                        Text {
                            text: "NEW: OAuth-like authorization flow (Strategy 2)"
                            font.pixelSize: 13
                            color: "#88ccff"
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "Create Fake Request"
                            Layout.preferredWidth: 150

                            background: Rectangle {
                                color: parent.down ? "#7a5a3a" : "#9a7a4a"
                                border.color: "#ffaa66"
                                border.width: 1
                                radius: 3
                            }

                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.pixelSize: 13
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                var result = logos.callModule("keycard", "requestAuth", ["notes-encryption", "notes"])
                                try {
                                    var parsed = JSON.parse(result)
                                    if (parsed.authId) {
                                        root.authResultMessage = "📝 Pending request created!\nAuth ID: " + parsed.authId.substring(0, 16) + "...\n\nCheck 'Pending Authorization Requests' section above."
                                        root.authResultColor = "#ffaa00"
                                        refreshPendingAuths()
                                    } else {
                                        root.authResultMessage = "❌ Failed: " + (parsed.error || "Unknown error")
                                        root.authResultColor = "#ff4444"
                                    }
                                } catch (e) {
                                    root.authResultMessage = "❌ Error: " + e.toString()
                                    root.authResultColor = "#ff4444"
                                }
                            }
                        }

                        Button {
                            text: "Show Auth Window"
                            Layout.preferredWidth: 150
                            enabled: root.currentState === "CARD_PRESENT" || root.currentState === "SESSION_CLOSED"

                            background: Rectangle {
                                color: parent.enabled ? (parent.down ? "#3a7acc" : "#4a9eff") : "#2a4a6a"
                                border.color: parent.enabled ? "#6ab0ff" : "#445566"
                                border.width: 1
                                radius: 3
                            }

                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? "#ffffff" : "#666666"
                                font.pixelSize: 13
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                authWindow.currentAuthId = ""  // Clear auth ID - this is a test, not a real request
                                authWindow.domain = "notes-encryption"
                                authWindow.requestingModule = "notes"
                                authWindow.remainingAttempts = 3

                                authWindow.authorizationComplete.connect(function(success, key) {
                                    if (success) {
                                        root.authResultMessage = "✅ Authorization successful!\nKey: " + key.substring(0, 32) + "..."
                                        root.authResultColor = "#00ff00"
                                    } else {
                                        root.authResultMessage = "❌ Authorization failed"
                                        root.authResultColor = "#ff4444"
                                    }
                                })

                                authWindow.cancelled.connect(function() {
                                    root.authResultMessage = "⚠️ User cancelled authorization"
                                    root.authResultColor = "#ffaa00"
                                })

                                authWindow.open()
                            }
                        }
                    }

                    Text {
                        id: modalAuthResult
                        Layout.fillWidth: true
                        text: root.authResultMessage
                        font.pixelSize: 12
                        font.family: "monospace"
                        color: root.authResultColor
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Instructions
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                color: "#1a1a1a"
                border.color: "#555555"
                border.width: 1
                radius: 5

                Text {
                    anchors.fill: parent
                    anchors.margins: 15
                    text: "Test Flow:\n" +
                          "1. Discover Reader → Insert reader if needed\n" +
                          "2. Discover Card → Insert card\n" +
                          "3. Authorize → Enter PIN (default: 000000)\n" +
                          "4. Derive Key → Test multiple domains\n" +
                          "5. Close Session → Cleanup\n\n" +
                          "State changes update automatically every 500ms"
                    font.pixelSize: 12
                    font.family: "monospace"
                    color: "#888888"
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    function getStateColor(state) {
        switch(state) {
            case "READER_NOT_FOUND": return "#ff4444"
            case "CARD_NOT_PRESENT": return "#ff8844"
            case "CARD_PRESENT": return "#ffaa00"
            case "AUTHORIZED": return "#88ff88"
            case "SESSION_ACTIVE": return "#00ff00"
            case "SESSION_CLOSED": return "#8888ff"
            case "BLOCKED": return "#ff0000"
            default: return "#ffffff"
        }
    }

    // AuthWindow Dialog (inline to avoid file loading issues)
    Dialog {
        id: authWindow
        title: "Keycard Authorization"
        width: 520
        height: 520
        modal: true
        closePolicy: Popup.CloseOnEscape
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        property string domain: ""
        property string requestingModule: ""
        property int remainingAttempts: 3
        property string currentAuthId: ""  // Track which auth request we're fulfilling

        signal authorizationComplete(bool success, string key)
        signal cancelled()

        onVisibleChanged: {
            if (visible) {
                pinField.text = ""
                pinField.forceActiveFocus()
                errorText.text = ""
            }
        }

        contentItem: Rectangle {
            color: "#2b2b2b"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                Text {
                    text: requestingModule ? 'Module "' + requestingModule + '" requests access' : "Authorization required"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#ffffff"
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Domain: " + authWindow.domain
                    font.pixelSize: 12
                    color: "#88ff88"
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#444444"
                }

                // OAuth-style permission explanation (technical details for power users)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    color: "#1a1a1a"
                    border.color: "#444444"
                    border.width: 1
                    radius: 4

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 5

                        Text {
                            text: "This will allow " + (authWindow.requestingModule || "the app") + " to:"
                            font.pixelSize: 12
                            font.bold: true
                            color: "#ffffff"
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "• Derive keys for domain: " + authWindow.domain
                            font.pixelSize: 11
                            color: "#aaaaaa"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            text: "• Derivation path: m/43'/60'/1581'/[SHA256(logos-" + authWindow.domain + ")]'/...'"
                            font.pixelSize: 10
                            font.family: "monospace"
                            color: "#888888"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            text: "• Isolated - no access to other domains"
                            font.pixelSize: 11
                            color: "#aaaaaa"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            text: "• Your PIN never leaves the card"
                            font.pixelSize: 11
                            color: "#aaaaaa"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#444444"
                }

                Text {
                    text: "Enter PIN:"
                    font.pixelSize: 13
                    color: "#ffffff"
                }

                TextField {
                    id: pinField
                    Layout.fillWidth: true
                    placeholderText: "6-digit PIN"
                    echoMode: TextInput.Password
                    font.pixelSize: 14

                    background: Rectangle {
                        color: "#1a1a1a"
                        border.color: pinField.activeFocus ? "#4a9eff" : "#444444"
                        border.width: 2
                        radius: 4
                    }

                    color: "#ffffff"

                    Keys.onReturnPressed: authorizeBtn.clicked()
                }

                Text {
                    id: errorText
                    Layout.fillWidth: true
                    text: ""
                    font.pixelSize: 12
                    color: "#ff4444"
                    wrapMode: Text.WordWrap
                    visible: text !== ""
                }

                Text {
                    text: remainingAttempts > 0 ? "Remaining attempts: " + remainingAttempts : ""
                    font.pixelSize: 11
                    color: remainingAttempts <= 2 ? "#ff8844" : "#aaaaaa"
                    visible: remainingAttempts > 0 && remainingAttempts <= 5
                }

                Item { Layout.preferredHeight: 10 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Button {
                        text: "Cancel"
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: parent.pressed ? "#3a3a3a" : parent.hovered ? "#444444" : "#2a2a2a"
                            border.color: "#555555"
                            radius: 4
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#aaaaaa"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            authWindow.cancelled()
                            authWindow.close()
                        }
                    }

                    Button {
                        id: authorizeBtn
                        text: "Authorize"
                        Layout.fillWidth: true
                        enabled: pinField.text.length > 0

                        background: Rectangle {
                            color: !parent.enabled ? "#1a1a1a" : parent.pressed ? "#3a7acc" : parent.hovered ? "#5a9eff" : "#4a9eff"
                            border.color: !parent.enabled ? "#333333" : "#6ab0ff"
                            radius: 4
                        }

                        contentItem: Text {
                            text: parent.text
                            font.bold: true
                            color: parent.enabled ? "#ffffff" : "#555555"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            errorText.text = ""

                            // SECURITY: Use authorizeRequest if this is from a pending request
                            // This ensures only keycard module can derive legitimate keys
                            if (authWindow.currentAuthId) {
                                // Secure path: authorizeRequest verifies PIN and derives key internally
                                var result = logos.callModule("keycard", "authorizeRequest",
                                    [authWindow.currentAuthId, pinField.text])

                                try {
                                    var parsed = JSON.parse(result)

                                    if (parsed.status === "complete") {
                                        // Success - legitimate key from hardware
                                        refreshPendingAuths()
                                        authWindow.currentAuthId = ""
                                        authWindow.authorizationComplete(true, parsed.key)
                                        authWindow.close()
                                    } else if (parsed.status === "failed") {
                                        errorText.text = parsed.error || "Authorization failed"

                                        if (parsed.remainingAttempts !== undefined) {
                                            authWindow.remainingAttempts = parsed.remainingAttempts

                                            if (authWindow.remainingAttempts === 0) {
                                                errorText.text = "Card blocked"
                                                authorizeBtn.enabled = false
                                                pinField.enabled = false
                                            }
                                        }

                                        pinField.clear()
                                        pinField.forceActiveFocus()
                                    } else {
                                        errorText.text = parsed.error || "Unknown error"
                                    }
                                } catch (e) {
                                    errorText.text = "Error: " + e.toString()
                                }
                            } else {
                                // Test mode: direct authorize + deriveKey (no pending request)
                                var result = logos.callModule("keycard", "authorize", [pinField.text])

                                try {
                                    var parsed = JSON.parse(result)

                                    if (parsed.authorized) {
                                        var keyResult = logos.callModule("keycard", "deriveKey", [authWindow.domain])
                                        var keyParsed = JSON.parse(keyResult)

                                        if (keyParsed.key) {
                                            authWindow.authorizationComplete(true, keyParsed.key)
                                            authWindow.close()
                                        } else {
                                            errorText.text = keyParsed.error || "Failed to derive key"
                                        }
                                    } else {
                                        errorText.text = parsed.error || "Wrong PIN"

                                        if (parsed.remainingAttempts !== undefined) {
                                            authWindow.remainingAttempts = parsed.remainingAttempts

                                            if (authWindow.remainingAttempts === 0) {
                                                errorText.text = "Card blocked"
                                                authorizeBtn.enabled = false
                                                pinField.enabled = false
                                            }
                                        }

                                        pinField.clear()
                                        pinField.forceActiveFocus()
                                    }
                                } catch (e) {
                                    errorText.text = "Error: " + e.toString()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Status Row Component (auto-detected, no button)
    component StatusRow: Rectangle {
        id: statusRow
        Layout.fillWidth: true
        Layout.preferredHeight: 100
        color: "#1a1a1a"
        border.color: "#555555"
        border.width: 1
        radius: 5

        property string title: ""
        property string statusText: ""
        property bool statusGood: false
        property string resultText: ""

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10

            // Title and Status
            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                Text {
                    text: statusRow.title
                    font.pixelSize: 16
                    font.bold: true
                    color: "#ffffff"
                    Layout.preferredWidth: 200
                }

                Text {
                    id: statusTextDisplay
                    text: statusRow.statusText
                    font.pixelSize: 14
                    color: statusRow.statusGood ? "#00ff00" : "#ff4444"
                    Layout.fillWidth: true
                }

                Button {
                    text: "Copy"
                    Layout.preferredWidth: 50
                    Layout.preferredHeight: 24
                    visible: statusRow.statusGood
                    onClicked: {
                        // Copy status text to clipboard
                        var tempEdit = Qt.createQmlObject('import QtQuick 2.15; TextEdit { visible: false }', statusRow)
                        tempEdit.text = statusRow.statusText
                        tempEdit.selectAll()
                        tempEdit.copy()
                        tempEdit.destroy()
                        this.text = "✓"
                        statusTextCopyTimer.restart()
                    }

                    Timer {
                        id: statusTextCopyTimer
                        interval: 1000
                        onTriggered: {
                            parent.text = "Copy"
                        }
                    }

                    background: Rectangle {
                        color: parent.down ? "#4a7ba7" : "#5a8fc7"
                        border.color: "#6a9fd7"
                        border.width: 1
                        radius: 3
                    }

                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.pixelSize: 10
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Text {
                    text: "AUTO"
                    font.pixelSize: 11
                    color: "#888888"
                    Layout.preferredWidth: 60
                    horizontalAlignment: Text.AlignRight
                }
            }

            // Result Display
            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    color: "#0a0a0a"
                    border.color: "#555555"
                    border.width: 1
                    radius: 3

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 5
                        clip: true

                        TextEdit {
                            id: statusResultDisplay
                            text: statusRow.resultText
                            font.pixelSize: 11
                            font.family: "monospace"
                            color: statusRow.statusGood ? "#00ff00" : "#ff4444"
                            wrapMode: TextEdit.Wrap
                            readOnly: true
                            selectByMouse: true
                        }
                    }
                }

                Button {
                    text: "Copy"
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 30
                    enabled: statusRow.resultText.length > 0
                    onClicked: {
                        statusResultDisplay.selectAll()
                        statusResultDisplay.copy()
                        statusResultDisplay.deselect()
                        this.text = "✓ Copied"
                        statusCopyTimer.restart()
                    }

                    Timer {
                        id: statusCopyTimer
                        interval: 1000
                        onTriggered: {
                            parent.text = "Copy"
                        }
                    }

                    background: Rectangle {
                        color: parent.enabled ? (parent.down ? "#4a7ba7" : "#5a8fc7") : "#3a3a3a"
                        border.color: parent.enabled ? "#6a9fd7" : "#555555"
                        border.width: 1
                        radius: 3
                    }

                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "#ffffff" : "#666666"
                        font.pixelSize: 11
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    // Action Row Component
    component ActionRow: Rectangle {
        id: row
        Layout.fillWidth: true
        Layout.preferredHeight: showPinInput || showDomainInput ? 140 : 100
        color: "#1a1a1a"
        border.color: "#555555"
        border.width: 1
        radius: 5

        property string title: ""
        property string prereqText: ""
        property bool prereqMet: false
        property bool alwaysEnabled: false
        property bool showPinInput: false
        property bool showDomainInput: false
        property string inputPlaceholder: ""
        property string inputLabel: ""
        property string defaultInputValue: ""
        property alias inputValue: inputField.text
        property var executeFunc: function() { return '{"error":"Not implemented"}' }

        Component.onCompleted: {
            if (defaultInputValue.length > 0) {
                inputField.text = defaultInputValue
            }
        }

        function clearInput() {
            inputField.text = ""
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10

            // Title and Prerequisites
            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                Text {
                    text: row.title
                    font.pixelSize: 16
                    font.bold: true
                    color: "#ffffff"
                    Layout.preferredWidth: 200
                }

                Text {
                    text: row.prereqText
                    font.pixelSize: 13
                    color: row.prereqMet || row.alwaysEnabled ? "#00ff00" : "#ff4444"
                    Layout.fillWidth: true
                }

                Button {
                    text: "Execute"
                    enabled: row.prereqMet || row.alwaysEnabled
                    Layout.preferredWidth: 100
                    onClicked: {
                        var result = row.executeFunc()
                        resultDisplay.text = result
                        try {
                            var obj = JSON.parse(result)
                            if (obj.error) {
                                resultDisplay.color = "#ff4444"
                            } else {
                                resultDisplay.color = "#00ff00"
                            }
                        } catch (e) {
                            resultDisplay.color = "#ffaa00"
                        }
                    }

                    background: Rectangle {
                        color: parent.enabled ? (parent.down ? "#555555" : "#3a3a3a") : "#2a2a2a"
                        border.color: parent.enabled ? "#666666" : "#444444"
                        border.width: 1
                        radius: 3
                    }

                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "#ffffff" : "#666666"
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // Input Field (if needed)
            RowLayout {
                visible: row.showPinInput || row.showDomainInput
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: row.inputLabel.length > 0 ? row.inputLabel : (row.showPinInput ? "PIN:" : "Domain:")
                    color: "#aaaaaa"
                    font.pixelSize: 13
                }

                TextField {
                    id: inputField
                    placeholderText: row.showPinInput ? "Enter PIN" : row.inputPlaceholder
                    echoMode: row.showPinInput ? TextInput.Password : TextInput.Normal
                    Layout.fillWidth: true
                    color: "#ffffff"
                    background: Rectangle {
                        color: "#0a0a0a"
                        border.color: "#555555"
                        border.width: 1
                        radius: 3
                    }
                }
            }

            // Result Display with Copy Button
            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    color: "#0a0a0a"
                    border.color: "#555555"
                    border.width: 1
                    radius: 3

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 5
                        clip: true

                        TextEdit {
                            id: resultDisplay
                            text: "No result yet"
                            font.pixelSize: 11
                            font.family: "monospace"
                            color: "#888888"
                            wrapMode: TextEdit.Wrap
                            readOnly: true
                            selectByMouse: true
                        }
                    }
                }

                Button {
                    text: "Copy"
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 30
                    enabled: resultDisplay.text.length > 0 && resultDisplay.text !== "No result yet"
                    onClicked: {
                        resultDisplay.selectAll()
                        resultDisplay.copy()
                        resultDisplay.deselect()
                        // Show brief feedback
                        this.text = "✓ Copied"
                        copyFeedbackTimer.restart()
                    }

                    Timer {
                        id: copyFeedbackTimer
                        interval: 1000
                        onTriggered: {
                            parent.text = "Copy"
                        }
                    }

                    background: Rectangle {
                        color: parent.enabled ? (parent.down ? "#4a7ba7" : "#5a8fc7") : "#3a3a3a"
                        border.color: parent.enabled ? "#6a9fd7" : "#555555"
                        border.width: 1
                        radius: 3
                    }

                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "#ffffff" : "#666666"
                        font.pixelSize: 11
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
