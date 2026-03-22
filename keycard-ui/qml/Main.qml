import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    width: 900
    height: 700
    color: "#2b2b2b"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        Text {
            text: "Keycard Debug UI - Phase 2"
            font.pixelSize: 28
            color: "#ffffff"
            Layout.alignment: Qt.AlignHCenter
        }

        // Action buttons
        GridLayout {
            columns: 2
            columnSpacing: 10
            rowSpacing: 10
            Layout.alignment: Qt.AlignHCenter

            Button {
                text: "1. Discover Reader"
                Layout.preferredWidth: 200
                onClicked: {
                    var result = logos.callModule("keycard", "discoverReader", [])
                    console.log("discoverReader:", result)
                    resultText.text = result
                }
            }

            Button {
                text: "2. Discover Card"
                Layout.preferredWidth: 200
                onClicked: {
                    var result = logos.callModule("keycard", "discoverCard", [])
                    console.log("discoverCard:", result)
                    resultText.text = result
                }
            }

            Button {
                text: "3. Authorize (PIN)"
                Layout.preferredWidth: 200
                onClicked: {
                    var pin = pinInput.text
                    if (pin.length === 0) {
                        resultText.text = '{"error":"Enter PIN first"}'
                        return
                    }
                    var result = logos.callModule("keycard", "authorize", [pin])
                    console.log("authorize:", result)
                    resultText.text = result
                    pinInput.text = ""  // Clear PIN after use
                }
            }

            Button {
                text: "4. Derive Key"
                Layout.preferredWidth: 200
                onClicked: {
                    var domain = domainInput.text || "test-domain"
                    var result = logos.callModule("keycard", "deriveKey", [domain])
                    console.log("deriveKey:", result)
                    resultText.text = result
                }
            }

            Button {
                text: "5. Get State"
                Layout.preferredWidth: 200
                onClicked: {
                    var result = logos.callModule("keycard", "getState", [])
                    console.log("getState:", result)
                    resultText.text = result
                }
            }

            Button {
                text: "6. Close Session"
                Layout.preferredWidth: 200
                onClicked: {
                    var result = logos.callModule("keycard", "closeSession", [])
                    console.log("closeSession:", result)
                    resultText.text = result
                }
            }
        }

        // Input fields
        RowLayout {
            spacing: 10
            Layout.alignment: Qt.AlignHCenter

            Text {
                text: "PIN:"
                color: "#ffffff"
                font.pixelSize: 14
            }

            TextField {
                id: pinInput
                placeholderText: "Enter PIN"
                echoMode: TextInput.Password
                Layout.preferredWidth: 150
                color: "#ffffff"
                background: Rectangle {
                    color: "#1a1a1a"
                    border.color: "#555555"
                    border.width: 1
                    radius: 3
                }
            }

            Text {
                text: "Domain:"
                color: "#ffffff"
                font.pixelSize: 14
            }

            TextField {
                id: domainInput
                placeholderText: "test-domain"
                Layout.preferredWidth: 150
                color: "#ffffff"
                background: Rectangle {
                    color: "#1a1a1a"
                    border.color: "#555555"
                    border.width: 1
                    radius: 3
                }
            }
        }

        // Result display
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 10
            color: "#1a1a1a"
            border.color: "#555555"
            border.width: 1
            radius: 5

            ScrollView {
                anchors.fill: parent
                anchors.margins: 10

                TextEdit {
                    id: resultText
                    text: "Click a button to test Keycard operations\n\nFlow:\n1. Discover Reader\n2. Insert card → Discover Card\n3. Enter PIN → Authorize\n4. Derive Key (optional domain)\n5. Close Session when done"
                    font.pixelSize: 13
                    font.family: "monospace"
                    color: "#00ff00"
                    wrapMode: TextEdit.Wrap
                    readOnly: true
                    selectByMouse: true
                    selectByKeyboard: true
                }
            }
        }
    }
}
