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

    // Auto-start detection on load
    Component.onCompleted: {
        // Initialize reader detection
        var result = logos.callModule("keycard", "discoverReader", [])
        try {
            var obj = JSON.parse(result)
            root.readerFound = obj.found === true
        } catch (e) {}
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
                                    return "✓ Paired (slot " + root.pairingSlot + ")"
                                }
                                if (root.currentState === "CARD_PRESENT" ||
                                    root.currentState === "AUTHORIZED" ||
                                    root.currentState === "SESSION_ACTIVE") return "Ready to pair"
                                if (root.currentState === "CARD_NOT_PRESENT") return "✗ Card not present"
                                if (root.currentState === "READER_NOT_FOUND") return "✗ Reader not found"
                                return "Ready to pair"
                            }
                            font.pixelSize: 13
                            color: root.cardPaired ? "#00ff00" :
                                   ((root.currentState === "CARD_PRESENT" ||
                                     root.currentState === "AUTHORIZED" ||
                                     root.currentState === "SESSION_ACTIVE") ? "#00ff00" : "#ff4444")
                            Layout.fillWidth: true
                        }

                        Button {
                            text: root.cardPaired ? "Unpair" : "Pair"
                            enabled: root.cardPaired || (root.currentState === "CARD_PRESENT" ||
                                                          root.currentState === "AUTHORIZED" ||
                                                          root.currentState === "SESSION_ACTIVE")
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
