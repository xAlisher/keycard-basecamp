import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    color: DesignTokens.background

    signal lockRequested()

    // Mock data
    property var pendingRequests: [
        { name: "LEZ_wallet", domain: "wallet_key" },
        { name: "Storage", domain: "storage_encryption" },
        { name: "Messaging", domain: "message_encryption" }
    ]

    property var connectedModules: [
        { name: "notes", domains: "north-wing.local" }
    ]

    property string cardHash: "0a2b3c5fh4g4e5d"
    property string version: "0.1"

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: DesignTokens.background

            // Bottom border only
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: DesignTokens.border
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 16

                // Left: Title + Version
                RowLayout {
                    spacing: 4

                    Text {
                        text: "Keycard for Basecamp"
                        color: DesignTokens.foreground
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        font.family: DesignTokens.fontPrimary
                    }

                    Text {
                        text: root.version
                        color: "#707070"
                        font.pixelSize: 11
                        font.weight: Font.Normal
                        font.family: DesignTokens.fontPrimary
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 2
                    }
                }

                Item { Layout.fillWidth: true }

                // Right: Card hash + Lock + Settings
                RowLayout {
                    spacing: 16

                    // Hash (group 1)
                    Text {
                        text: root.cardHash
                        color: DesignTokens.mutedForeground
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        font.family: DesignTokens.fontPrimary
                    }

                    // Lock + Ctrl+L (group 2)
                    RowLayout {
                        spacing: 4

                        Rectangle {
                            width: 20
                            height: 20
                            color: "transparent"

                            Image {
                                id: lockIcon
                                anchors.fill: parent
                                source: "icons/lock.svg"
                                sourceSize: Qt.size(20, 20)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    console.log("Lock icon clicked!")
                                    lockSession()
                                }
                            }
                        }

                        Rectangle {
                            width: ctrlLText.implicitWidth
                            height: ctrlLText.implicitHeight
                            color: "transparent"

                            Text {
                                id: ctrlLText
                                text: "Ctrl+L"
                                color: DesignTokens.foreground
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                font.family: DesignTokens.fontPrimary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    console.log("Ctrl+L clicked!")
                                    lockSession()
                                }
                            }
                        }
                    }

                    // Settings (group 3)
                    Image {
                        id: settingsIcon
                        width: 20
                        height: 20
                        source: "icons/bolt.svg"
                        sourceSize: Qt.size(20, 20)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: console.log("Settings clicked")
                        }
                    }
                }
            }
        }

        // Body: Two columns
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 24
            Layout.margins: 24

            // Left column: Pending Requests
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 24

                Text {
                    text: "Pending requests"
                    color: DesignTokens.foreground
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    font.family: DesignTokens.fontPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Repeater {
                        model: root.pendingRequests

                        // Request card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            color: "#2a2a2a"  // background-secondary
                            radius: 8

                            // Yellow marker (left border) with clip
                            Item {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 8
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 16
                                    color: DesignTokens.warning
                                    radius: 8
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 10
                                spacing: 8

                                // Module info
                                ColumnLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 4

                                    Text {
                                        text: modelData.name
                                        color: DesignTokens.foreground
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    Text {
                                        text: "domain: " + modelData.domain
                                        color: DesignTokens.foregroundSecondary
                                        font.pixelSize: 12
                                        font.family: DesignTokens.fontPrimary
                                    }
                                }

                                Item { Layout.fillWidth: true }  // Spacer to push buttons right

                                // Approve button
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 85
                                    height: 32
                                    color: approveArea.containsMouse ? "#e64a19" : DesignTokens.primary
                                    radius: 16  // Pill shape

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
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: console.log("Approve:", modelData.name)
                                    }
                                }

                                // Decline button
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 85
                                    height: 32
                                    color: declineArea.containsMouse ? "#3a3a3a" : "transparent"
                                    border.color: DesignTokens.border
                                    border.width: 1
                                    radius: 16  // Pill shape

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
                                        onClicked: console.log("Decline:", modelData.name)
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Right column: Connected Modules
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 24

                Text {
                    text: "Connected modules"
                    color: DesignTokens.foreground
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    font.family: DesignTokens.fontPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Repeater {
                        model: root.connectedModules

                        // Connected module card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            color: "#2a2a2a"  // background-secondary
                            radius: 8

                            // Green marker (left border) with clip
                            Item {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 8
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 16
                                    color: DesignTokens.success
                                    radius: 8
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 10
                                spacing: 8

                                // Module info
                                ColumnLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 4

                                    Text {
                                        text: modelData.name
                                        color: DesignTokens.foreground
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    Text {
                                        text: "domains: " + modelData.domains
                                        color: DesignTokens.foregroundSecondary
                                        font.pixelSize: 12
                                        font.family: DesignTokens.fontPrimary
                                    }
                                }

                                Item { Layout.fillWidth: true }  // Spacer to push button right

                                // Disconnect button
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 105
                                    height: 32
                                    color: disconnectArea.containsMouse ? "#3a3a3a" : "transparent"
                                    border.color: DesignTokens.border
                                    border.width: 1
                                    radius: 16  // Pill shape

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Disconnect"
                                        color: DesignTokens.foreground
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    MouseArea {
                                        id: disconnectArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: console.log("Disconnect:", modelData.name)
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
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
                addEntry("[14:23:45]", "notes requested access to notes.private", "warning")
                addEntry("[14:23:50]", "authorized notes.private (Key: ff21fc...)", "success")
                addEntry("[14:25:12]", "wallet requested access to wallet.ethereum", "warning")
                addEntry("[14:25:15]", "user denied request", "error")
            }
        }
    }

    function lockSession() {
        console.log("Locking session...")
        lockRequested()
    }
}
