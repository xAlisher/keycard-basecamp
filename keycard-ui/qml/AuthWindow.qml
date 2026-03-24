import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Window {
    id: authWindow
    title: "Keycard Authorization"
    width: 450
    height: 320
    minimumWidth: 450
    minimumHeight: 320
    maximumWidth: 450
    maximumHeight: 320

    modality: Qt.ApplicationModal
    flags: Qt.Dialog | Qt.WindowStaysOnTopHint

    // Properties
    property string domain: ""
    property string requestingModule: ""
    property int remainingAttempts: 3

    // Signals
    signal authorizationComplete(bool success, string key)
    signal cancelled()

    // Auto-center on screen
    Component.onCompleted: {
        x = (Screen.width - width) / 2
        y = (Screen.height - height) / 2
    }

    // Background
    Rectangle {
        anchors.fill: parent
        color: "#2b2b2b"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 30
            spacing: 20

            // Header
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Keycard Authorization"
                    font.pixelSize: 24
                    font.bold: true
                    color: "#ffffff"
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 2
                    color: "#444444"
                }

                Text {
                    text: requestingModule ?
                          "Module \"" + requestingModule + "\" requests access" :
                          "Authorization required"
                    font.pixelSize: 14
                    color: "#aaaaaa"
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Domain: " + domain
                    font.pixelSize: 13
                    color: "#888888"
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // PIN Input Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "Enter PIN:"
                    font.pixelSize: 14
                    color: "#ffffff"
                }

                TextField {
                    id: pinField
                    Layout.fillWidth: true
                    placeholderText: "6-digit PIN"
                    echoMode: TextInput.Password
                    font.pixelSize: 16
                    maximumLength: 10

                    background: Rectangle {
                        color: "#1a1a1a"
                        border.color: pinField.activeFocus ? "#4a9eff" : "#444444"
                        border.width: 2
                        radius: 4
                    }

                    color: "#ffffff"

                    Keys.onReturnPressed: authorizeButton.clicked()
                    Keys.onEnterPressed: authorizeButton.clicked()

                    Component.onCompleted: {
                        forceActiveFocus()
                    }
                }

                // Error message
                Text {
                    id: errorText
                    Layout.fillWidth: true
                    text: ""
                    font.pixelSize: 13
                    color: "#ff4444"
                    wrapMode: Text.WordWrap
                    visible: text !== ""

                    SequentialAnimation on opacity {
                        running: errorText.visible
                        NumberAnimation { to: 1.0; duration: 0 }
                        PauseAnimation { duration: 100 }
                        NumberAnimation { to: 0.7; duration: 500 }
                        NumberAnimation { to: 1.0; duration: 500 }
                    }
                }

                // Remaining attempts
                Text {
                    id: attemptsText
                    Layout.fillWidth: true
                    text: remainingAttempts > 0 ?
                          "Remaining attempts: " + remainingAttempts :
                          ""
                    font.pixelSize: 12
                    color: remainingAttempts <= 2 ? "#ff8844" : "#aaaaaa"
                    visible: remainingAttempts > 0 && remainingAttempts <= 5
                }
            }

            // Spacer
            Item {
                Layout.fillHeight: true
            }

            // Buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                Button {
                    id: cancelButton
                    text: "Cancel"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40

                    background: Rectangle {
                        color: cancelButton.pressed ? "#3a3a3a" :
                               cancelButton.hovered ? "#444444" : "#2a2a2a"
                        border.color: "#555555"
                        border.width: 1
                        radius: 4
                    }

                    contentItem: Text {
                        text: cancelButton.text
                        font.pixelSize: 14
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
                    id: authorizeButton
                    text: "Authorize"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    enabled: pinField.text.length > 0

                    background: Rectangle {
                        color: !authorizeButton.enabled ? "#1a1a1a" :
                               authorizeButton.pressed ? "#3a7acc" :
                               authorizeButton.hovered ? "#5a9eff" : "#4a9eff"
                        border.color: !authorizeButton.enabled ? "#333333" : "#6ab0ff"
                        border.width: 1
                        radius: 4
                    }

                    contentItem: Text {
                        text: authorizeButton.text
                        font.pixelSize: 14
                        font.bold: true
                        color: authorizeButton.enabled ? "#ffffff" : "#555555"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        authorize()
                    }
                }
            }
        }
    }

    // Authorization logic
    function authorize() {
        errorText.text = ""

        // Call keycard module to authorize
        var result = logos.callModule("keycard", "authorize", [pinField.text])

        try {
            var parsed = JSON.parse(result)

            if (parsed.authorized) {
                // Success - derive key immediately
                var keyResult = logos.callModule("keycard", "deriveKey", [authWindow.domain])
                var keyParsed = JSON.parse(keyResult)

                if (keyParsed.key) {
                    // Authorization and derivation successful
                    authWindow.authorizationComplete(true, keyParsed.key)
                    authWindow.close()
                } else if (keyParsed.error) {
                    errorText.text = "Key derivation failed: " + keyParsed.error
                } else {
                    errorText.text = "Failed to derive key"
                }
            } else {
                // Authorization failed
                if (parsed.error) {
                    errorText.text = parsed.error
                } else {
                    errorText.text = "Wrong PIN"
                }

                // Update remaining attempts if available
                if (parsed.remainingAttempts !== undefined) {
                    remainingAttempts = parsed.remainingAttempts

                    if (remainingAttempts === 0) {
                        errorText.text = "Card blocked - too many wrong attempts"
                        authorizeButton.enabled = false
                        pinField.enabled = false
                    }
                }

                // Clear PIN field for retry
                pinField.clear()
                pinField.forceActiveFocus()
            }
        } catch (e) {
            errorText.text = "Error: " + e.toString()
        }
    }

    // Clear sensitive data when closing
    onClosing: {
        pinField.clear()
        errorText.text = ""
    }
}
