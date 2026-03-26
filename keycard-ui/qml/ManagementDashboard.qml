import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    color: DesignTokens.background

    // Mock data (replace with actual backend calls)
    property var pendingRequests: [
        { name: "LEZ_wallet", domain: "wallet_key" },
        { name: "Storage", domain: "storage_encryption" },
        { name: "Messaging", domain: "message_encryption" }
    ]

    property var connectedModules: [
        { name: "notes", domains: "north-wing.local", lastAccess: "2m ago" }
    ]

    property string cardHash: "0a2b3c5fh4g4e5d"
    property string version: "0.1"

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: DesignTokens.headerHeight
            color: DesignTokens.background
            border.color: DesignTokens.border
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: DesignTokens.spacingXl
                anchors.rightMargin: DesignTokens.spacingXl
                spacing: DesignTokens.spacingL

                // Left side: Title + Version
                RowLayout {
                    spacing: DesignTokens.spacingS

                    Text {
                        text: "Keycard for Basecamp"
                        color: DesignTokens.foreground
                        font.pixelSize: DesignTokens.fontSizeTitle
                        font.weight: Font.Bold
                        font.family: DesignTokens.fontPrimary
                    }

                    Text {
                        text: root.version
                        color: DesignTokens.mutedForeground
                        font.pixelSize: DesignTokens.fontSizeBody
                        font.weight: Font.Medium
                        font.family: DesignTokens.fontPrimary
                    }
                }

                Item { Layout.fillWidth: true }  // Spacer

                // Right side: Card hash + Lock + Settings
                RowLayout {
                    spacing: DesignTokens.spacingL

                    Text {
                        text: root.cardHash
                        color: DesignTokens.mutedForeground
                        font.pixelSize: DesignTokens.fontSizeBody
                        font.weight: Font.Medium
                        font.family: DesignTokens.fontPrimary
                    }

                    // Lock button
                    RowLayout {
                        spacing: DesignTokens.spacingS

                        Text {
                            text: "🔒"  // Lock icon (TODO: use Lucide icon)
                            color: DesignTokens.foreground
                            font.pixelSize: DesignTokens.fontSizeBody
                        }

                        Text {
                            text: "Ctrl+L"
                            color: DesignTokens.foreground
                            font.pixelSize: DesignTokens.fontSizeBody
                            font.weight: Font.Medium
                            font.family: DesignTokens.fontPrimary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: lockSession()
                        }
                    }

                    // Settings icon
                    Text {
                        text: "⚙️"  // Settings icon (TODO: use Lucide icon)
                        color: DesignTokens.foreground
                        font.pixelSize: DesignTokens.fontSizeTitle

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: console.log("Settings clicked (not implemented)")
                        }
                    }
                }
            }
        }

        // Body: Two columns
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: DesignTokens.spacingXl

            Layout.margins: DesignTokens.spacingXl

            // Left column: Pending Requests
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: DesignTokens.spacingXl

                Text {
                    text: "Pending requests"
                    color: DesignTokens.foreground
                    font.pixelSize: DesignTokens.fontSizeBody
                    font.weight: Font.Medium
                    font.family: DesignTokens.fontPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: DesignTokens.spacingL

                    Repeater {
                        model: root.pendingRequests

                        // Pending request card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 72
                            color: DesignTokens.secondary
                            radius: DesignTokens.radiusM

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: DesignTokens.spacingL
                                spacing: DesignTokens.spacingL

                                // Yellow indicator bar
                                Rectangle {
                                    width: 4
                                    Layout.fillHeight: true
                                    color: DesignTokens.warning
                                    radius: 2
                                }

                                // Module info
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: modelData.name
                                        color: DesignTokens.foreground
                                        font.pixelSize: DesignTokens.fontSizeBody
                                        font.weight: Font.Medium
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    Text {
                                        text: "domain: " + modelData.domain
                                        color: DesignTokens.foregroundSecondary
                                        font.pixelSize: DesignTokens.fontSizeSmall
                                        font.family: DesignTokens.fontPrimary
                                    }
                                }

                                // Approve button
                                Button {
                                    text: "Approve"
                                    Layout.preferredWidth: 90
                                    Layout.preferredHeight: DesignTokens.buttonHeight

                                    background: Rectangle {
                                        color: parent.hovered ? DesignTokens.primaryHover : DesignTokens.primary
                                        radius: DesignTokens.radiusS
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        color: DesignTokens.foreground
                                        font.pixelSize: DesignTokens.fontSizeBody
                                        font.weight: Font.Medium
                                        font.family: DesignTokens.fontPrimary
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: console.log("Approve:", modelData.name)
                                }

                                // Decline button
                                Button {
                                    text: "Decline"
                                    Layout.preferredWidth: 90
                                    Layout.preferredHeight: DesignTokens.buttonHeight

                                    background: Rectangle {
                                        color: parent.hovered ? DesignTokens.secondaryHover : DesignTokens.secondary
                                        border.color: DesignTokens.border
                                        border.width: 1
                                        radius: DesignTokens.radiusS
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        color: DesignTokens.foreground
                                        font.pixelSize: DesignTokens.fontSizeBody
                                        font.weight: Font.Medium
                                        font.family: DesignTokens.fontPrimary
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: console.log("Decline:", modelData.name)
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }  // Spacer
                }
            }

            // Right column: Connected Modules
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: DesignTokens.spacingXl

                Text {
                    text: "Connected modules"
                    color: DesignTokens.foreground
                    font.pixelSize: DesignTokens.fontSizeBody
                    font.weight: Font.Medium
                    font.family: DesignTokens.fontPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: DesignTokens.spacingL

                    Repeater {
                        model: root.connectedModules

                        // Connected module card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 72
                            color: DesignTokens.secondary
                            radius: DesignTokens.radiusM

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: DesignTokens.spacingL
                                spacing: DesignTokens.spacingL

                                // Green indicator bar
                                Rectangle {
                                    width: 4
                                    Layout.fillHeight: true
                                    color: DesignTokens.success
                                    radius: 2
                                }

                                // Module info
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: modelData.name
                                        color: DesignTokens.foreground
                                        font.pixelSize: DesignTokens.fontSizeBody
                                        font.weight: Font.Medium
                                        font.family: DesignTokens.fontPrimary
                                    }

                                    Text {
                                        text: "domains: " + modelData.domains
                                        color: DesignTokens.foregroundSecondary
                                        font.pixelSize: DesignTokens.fontSizeSmall
                                        font.family: DesignTokens.fontPrimary
                                    }
                                }

                                // Disconnect button
                                Button {
                                    text: "Disconnect"
                                    Layout.preferredWidth: 110
                                    Layout.preferredHeight: DesignTokens.buttonHeight

                                    background: Rectangle {
                                        color: parent.hovered ? DesignTokens.secondaryHover : DesignTokens.secondary
                                        border.color: DesignTokens.border
                                        border.width: 1
                                        radius: DesignTokens.radiusS
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        color: DesignTokens.foreground
                                        font.pixelSize: DesignTokens.fontSizeBody
                                        font.weight: Font.Medium
                                        font.family: DesignTokens.fontPrimary
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: console.log("Disconnect:", modelData.name)
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }  // Spacer
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
                    ListElement { timestamp: "[14:23:45]"; message: "notes requested access to notes.private"; level: "warning" }
                    ListElement { timestamp: "[14:23:50]"; message: "authorized notes.private (Key: ff21fc...)"; level: "success" }
                    ListElement { timestamp: "[14:25:12]"; message: "wallet requested access to wallet.ethereum"; level: "warning" }
                    ListElement { timestamp: "[14:25:15]"; message: "user denied request"; level: "error" }
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

    function lockSession() {
        console.log("Locking session...")
        // TODO: Call backend lockSession()
    }
}
