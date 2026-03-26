import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    color: DesignTokens.background

    signal unlocked()

    property string pinValue: ""
    property int maxPinLength: 6
    property int attemptsRemaining: 3

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
                        font.pixelSize: DesignTokens.fontSizeTitle
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
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: DesignTokens.activityLogHeight
            color: DesignTokens.background
            border.color: DesignTokens.border
            border.width: 1

            ListView {
                id: activityLog
                anchors.fill: parent
                anchors.margins: 18
                spacing: 4
                clip: true
                model: ListModel {
                    ListElement { timestamp: "[09:12:03]"; message: "looking for smart card reader..."; level: "info" }
                    ListElement { timestamp: "[09:08:11]"; message: "card reader detected"; level: "success" }
                    ListElement { timestamp: "[09:12:03]"; message: "looking for Keycard..."; level: "info" }
                    ListElement { timestamp: "[09:08:11]"; message: "Keycard detected"; level: "success" }
                    ListElement { timestamp: "[09:11:47]"; message: "waiting for PIN"; level: "warning" }
                    ListElement { timestamp: "[09:11:47]"; message: "wrong PIN - 2 attempts left"; level: "error" }
                    ListElement { timestamp: "[09:11:47]"; message: "waiting for PIN"; level: "warning" }
                }

                delegate: Text {
                    width: activityLog.width
                    text: timestamp + " " + message
                    color: {
                        if (level === "success") return DesignTokens.success
                        if (level === "warning") return DesignTokens.warning
                        if (level === "error") return DesignTokens.error
                        return DesignTokens.info
                    }
                    font.pixelSize: DesignTokens.fontSizeSmall
                    font.family: "monospace"
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // PIN Input handling
    Keys.onPressed: (event) => {
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            if (pinValue.length < maxPinLength) {
                pinValue += String.fromCharCode(event.key)
                if (pinValue.length === maxPinLength) {
                    verifyPin()
                }
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
            if (pinValue.length > 0) {
                pinValue = pinValue.slice(0, -1)
            }
            event.accepted = true
        }
    }

    focus: true

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
