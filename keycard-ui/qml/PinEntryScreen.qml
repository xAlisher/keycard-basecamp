import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

FocusScope {
    id: root
    focus: true

    signal unlocked()

    property string pinValue: ""
    property int maxPinLength: 6
    property int attemptsRemaining: 3

    // Timer to ensure focus after component is fully loaded
    Timer {
        id: focusTimer
        interval: 100
        running: true
        repeat: false
        onTriggered: {
            root.forceActiveFocus()
            hiddenInput.forceActiveFocus()
        }
    }

    // Invisible text input to capture keyboard
    TextInput {
        id: hiddenInput
        visible: false
        focus: true

        onTextChanged: {
            // Handle numeric input
            var text = hiddenInput.text
            if (text.length > 0) {
                var lastChar = text.charAt(text.length - 1)
                if (lastChar >= '0' && lastChar <= '9') {
                    if (root.pinValue.length < root.maxPinLength) {
                        root.pinValue += lastChar
                        if (root.pinValue.length === root.maxPinLength) {
                            verifyPin()
                        }
                    }
                }
                hiddenInput.text = ""  // Clear for next input
            }
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Backspace) {
                if (root.pinValue.length > 0) {
                    root.pinValue = root.pinValue.slice(0, -1)
                }
                event.accepted = true
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: DesignTokens.background

        MouseArea {
            anchors.fill: parent
            onClicked: hiddenInput.forceActiveFocus()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

        // PIN Input Section (centered)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: DesignTokens.spacing3xl

                // Header
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: DesignTokens.spacingS

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Enter Keycard PIN to unlock"
                        color: DesignTokens.foreground
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        font.family: DesignTokens.fontPrimary
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 345
                        text: "Never enter PIN in modules you don't trust"
                        color: DesignTokens.foregroundSecondary
                        font.pixelSize: DesignTokens.fontSizeSmall
                        font.weight: Font.Medium
                        font.family: DesignTokens.fontPrimary
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }

                // PIN Digit Display
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: DesignTokens.spacingM

                    Repeater {
                        model: root.maxPinLength

                        Rectangle {
                            width: DesignTokens.pinDigitSize
                            height: DesignTokens.pinDigitSize
                            color: "transparent"
                            border.color: {
                                if (index === root.pinValue.length) return DesignTokens.primary  // Active
                                return DesignTokens.border  // Empty or filled
                            }
                            border.width: index === root.pinValue.length ? 2 : 1
                            radius: DesignTokens.radiusM

                            // Filled dot
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: DesignTokens.foreground
                                visible: index < root.pinValue.length
                            }

                            // Active cursor
                            Rectangle {
                                anchors.centerIn: parent
                                width: 2
                                height: 20
                                color: DesignTokens.primary
                                visible: index === root.pinValue.length

                                SequentialAnimation on opacity {
                                    running: parent.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 0; duration: 530 }
                                    NumberAnimation { from: 0; to: 1; duration: 530 }
                                }
                            }
                        }
                    }
                }

                // Error message (wrong PIN)
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: attemptsRemaining < 3 ? `Wrong PIN - ${attemptsRemaining} attempts remaining` : ""
                    color: DesignTokens.error
                    font.pixelSize: DesignTokens.fontSizeSmall
                    font.family: DesignTokens.fontPrimary
                    visible: text !== ""
                }
            }
        }

        // Activity Log (bottom)
        ActivityLog {
            id: activityLog
            Layout.fillWidth: true
            Layout.preferredHeight: 167

            Component.onCompleted: {
                // Mock data for now - will be replaced with real backend events
                addEntry("[09:12:03]", "looking for smart card reader...", "info")
                addEntry("[09:08:11]", "card reader detected", "success")
                addEntry("[09:12:03]", "looking for Keycard...", "info")
                addEntry("[09:08:11]", "Keycard detected", "success")
                addEntry("[09:11:47]", "waiting for PIN", "warning")
            }
        }
        }
    }

    function verifyPin() {
        console.log("Verifying PIN:", pinValue)

        // TODO: Call backend authorize(pin)
        // Mock: accept PIN "123456"
        if (pinValue === "123456") {
            unlocked()
        } else {
            attemptsRemaining--
            pinValue = ""
        }
    }
}
