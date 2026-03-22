import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 1000
    height: 800
    color: "#2b2b2b"

    property string currentState: "READER_NOT_FOUND"

    // Poll state every 500ms for live updates
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            var result = logos.callModule("keycard", "getState", [])
            try {
                var obj = JSON.parse(result)
                if (obj.state) {
                    root.currentState = obj.state
                }
            } catch (e) {}
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

            // Action Rows
            ActionRow {
                title: "1. Discover Reader"
                alwaysEnabled: true
                prereqText: "No prerequisites"
                prereqMet: true
                onExecute: function() {
                    return logos.callModule("keycard", "discoverReader", [])
                }
            }

            ActionRow {
                title: "2. Discover Card"
                prereqText: root.currentState !== "READER_NOT_FOUND" ? "✓ Reader found" : "✗ Reader not found"
                prereqMet: root.currentState !== "READER_NOT_FOUND"
                onExecute: function() {
                    return logos.callModule("keycard", "discoverCard", [])
                }
            }

            ActionRow {
                id: authorizeRow
                title: "3. Authorize"
                prereqText: root.currentState === "CARD_PRESENT" ? "✓ Card present" : "✗ Card not present"
                prereqMet: root.currentState === "CARD_PRESENT"
                showPinInput: true
                onExecute: function() {
                    var pin = authorizeRow.inputValue
                    if (pin.length === 0) {
                        return '{"error":"PIN required"}'
                    }
                    var result = logos.callModule("keycard", "authorize", [pin])
                    authorizeRow.clearInput()
                    return result
                }
            }

            ActionRow {
                id: deriveKeyRow
                title: "4. Derive Key"
                prereqText: (root.currentState === "AUTHORIZED" || root.currentState === "SESSION_ACTIVE")
                    ? "✓ Authorized" : "✗ Not authorized"
                prereqMet: root.currentState === "AUTHORIZED" || root.currentState === "SESSION_ACTIVE"
                showDomainInput: true
                inputPlaceholder: "logos-notes-encryption"
                onExecute: function() {
                    var domain = deriveKeyRow.inputValue || "logos-notes-encryption"
                    return logos.callModule("keycard", "deriveKey", [domain])
                }
            }

            ActionRow {
                title: "5. Get State"
                alwaysEnabled: true
                prereqText: "No prerequisites"
                prereqMet: true
                onExecute: function() {
                    return logos.callModule("keycard", "getState", [])
                }
            }

            ActionRow {
                title: "6. Get Last Error"
                alwaysEnabled: true
                prereqText: "No prerequisites"
                prereqMet: true
                onExecute: function() {
                    return logos.callModule("keycard", "getLastError", [])
                }
            }

            ActionRow {
                title: "7. Close Session"
                prereqText: root.currentState === "SESSION_ACTIVE" ? "✓ Session active" : "✗ No active session"
                prereqMet: root.currentState === "SESSION_ACTIVE"
                onExecute: function() {
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

    // Action Row Component
    component ActionRow: Rectangle {
        id: row
        Layout.fillWidth: true
        Layout.preferredHeight: showPinInput || showDomainInput ? 140 : 100
        color: "#1a1a1a"
        border.color: prereqMet || alwaysEnabled ? "#00aa00" : "#aa0000"
        border.width: 1
        radius: 5

        property string title: ""
        property string prereqText: ""
        property bool prereqMet: false
        property bool alwaysEnabled: false
        property bool showPinInput: false
        property bool showDomainInput: false
        property string inputPlaceholder: ""
        property alias inputValue: inputField.text

        signal execute()

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
                        var result = row.execute()
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
                }
            }

            // Input Field (if needed)
            RowLayout {
                visible: row.showPinInput || row.showDomainInput
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: row.showPinInput ? "PIN:" : "Domain:"
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

            // Result Display
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
        }
    }
}
