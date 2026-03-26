import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

FocusScope {
    id: root
    focus: true

    signal approved()
    signal declined()

    property string moduleName: "Notes module"
    property string domain: "notes_private"
    property string path: "m/43'/60'/1581'/1437890605'/512438859'"
    property string pinValue: ""
    property int maxPinLength: 6

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

            // Main content (centered)
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
                            text: root.moduleName + " requesting access"
                            color: DesignTokens.foreground
                            font.pixelSize: 24
                            font.weight: Font.Bold
                            font.family: DesignTokens.fontPrimary
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 345
                            text: "Approve will allow the module to derive an encryption key only for approved path"
                            color: DesignTokens.foregroundSecondary
                            font.pixelSize: DesignTokens.fontSizeSmall
                            font.weight: Font.Medium
                            font.family: DesignTokens.fontPrimary
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    // Info box
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 345
                        Layout.preferredHeight: infoLayout.implicitHeight + 32
                        color: "#2a2a2a"
                        radius: DesignTokens.radiusM

                        ColumnLayout {
                            id: infoLayout
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 16

                            // Domain
                            ColumnLayout {
                                spacing: 4

                                Text {
                                    text: "domain"
                                    color: DesignTokens.mutedForeground
                                    font.pixelSize: DesignTokens.fontSizeSmall
                                    font.family: DesignTokens.fontPrimary
                                }

                                Text {
                                    text: root.domain
                                    color: DesignTokens.foreground
                                    font.pixelSize: DesignTokens.fontSizeBase
                                    font.family: DesignTokens.fontPrimary
                                }
                            }

                            // Path
                            ColumnLayout {
                                spacing: 4

                                Text {
                                    text: "path"
                                    color: DesignTokens.mutedForeground
                                    font.pixelSize: DesignTokens.fontSizeSmall
                                    font.family: DesignTokens.fontPrimary
                                }

                                Text {
                                    Layout.preferredWidth: 313
                                    text: root.path
                                    color: DesignTokens.foreground
                                    font.pixelSize: DesignTokens.fontSizeBase
                                    font.family: DesignTokens.fontPrimary
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
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

                    // Buttons
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        // Approve button
                        Rectangle {
                            width: 85
                            height: 32
                            color: approveArea.containsMouse ? "#e64a19" : DesignTokens.primary
                            radius: 16
                            opacity: root.pinValue.length === root.maxPinLength ? 1.0 : 0.5

                            Text {
                                anchors.centerIn: parent
                                text: "Approve"
                                color: DesignTokens.foreground
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                font.family: DesignTokens.fontPrimary
                            }

                            MouseArea {
                                id: approveArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.pinValue.length === root.maxPinLength
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    console.log("Approve clicked, PIN:", root.pinValue)
                                    root.approved()
                                }
                            }
                        }

                        // Decline button
                        Rectangle {
                            width: 85
                            height: 32
                            color: declineArea.containsMouse ? "#3a3a3a" : "transparent"
                            border.color: DesignTokens.border
                            border.width: 1
                            radius: 16

                            Text {
                                anchors.centerIn: parent
                                text: "Decline"
                                color: DesignTokens.foreground
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                font.family: DesignTokens.fontPrimary
                            }

                            MouseArea {
                                id: declineArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    console.log("Decline clicked")
                                    root.declined()
                                }
                            }
                        }
                    }
                }
            }

            // Activity Log (bottom)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 167
                color: DesignTokens.background

                // Top border only
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: DesignTokens.border
                }

                ListView {
                    id: activityLog
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 4
                    clip: true
                    model: ListModel {
                        ListElement { timestamp: "[09:11:47]"; message: "Notes module requesting access to domain: notes_private"; level: "warning" }
                        ListElement { timestamp: "[09:12:03]"; message: "looking for smart card reader..."; level: "info" }
                        ListElement { timestamp: "[09:08:11]"; message: "card reader detected"; level: "success" }
                        ListElement { timestamp: "[09:12:03]"; message: "looking for Keycard..."; level: "info" }
                        ListElement { timestamp: "[09:08:11]"; message: "Keycard detected"; level: "success" }
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
    }
}
