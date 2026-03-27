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
    property alias activityLog: activityLog
    property bool cardPresent: false
    property bool readerPresent: false
    property bool initialLoadComplete: false
    property bool verifyingPin: false

    // Monitor card/reader state
    Timer {
        id: stateMonitor
        interval: 1000
        running: true
        repeat: true
        onTriggered: checkState()
    }

    function checkState() {
        var result = logos.callModule("keycard", "getState", [])
        try {
            var response = JSON.parse(result)
            var state = response.state

            var wasCardPresent = cardPresent
            var wasReaderPresent = readerPresent

            // Update state
            readerPresent = (state !== "READER_NOT_FOUND" && state !== "NO_PCSC")
            cardPresent = (state === "CARD_PRESENT" || state === "READY" || state === "SESSION_ACTIVE")

            // Detect disconnects and reconnects
            var timestamp = Qt.formatTime(new Date(), "[HH:mm:ss]")

            if (wasReaderPresent && !readerPresent) {
                activityLog.addEntry(timestamp, "Smart card reader not found", "error")
                activityLog.addEntry(timestamp, "Looking for smart card reader...", "info")
            } else if (!wasReaderPresent && readerPresent) {
                activityLog.addEntry(timestamp, "Smart card reader detected", "success")
                // If no card present, start looking for keycard
                if (!cardPresent) {
                    activityLog.addEntry(timestamp, "Looking for Keycard...", "info")
                }
            }

            if (wasCardPresent && !cardPresent && readerPresent) {
                activityLog.addEntry(timestamp, "Keycard not found", "error")
                activityLog.addEntry(timestamp, "Looking for Keycard...", "info")
            } else if (!wasCardPresent && cardPresent && readerPresent && initialLoadComplete) {
                // Card reconnected (skip during initial load) - get UID and show PIN prompt
                var cardResult = logos.callModule("keycard", "discoverCard", [])
                processActivity(cardResult)
            }
        } catch (e) {
            console.error("Failed to check state:", e)
        }
    }

    // Timer to ensure focus after component is fully loaded
    Timer {
        id: focusTimer
        interval: 200
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
        enabled: cardPresent && readerPresent

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
                    opacity: root.verifyingPin ? 0.5 : 1.0

                    Repeater {
                        model: root.maxPinLength

                        Rectangle {
                            width: DesignTokens.pinDigitSize
                            height: DesignTokens.pinDigitSize
                            color: "transparent"
                            border.color: {
                                if ((root.cardPresent && root.readerPresent) && index === root.pinValue.length) {
                                    return DesignTokens.primary  // Active focus
                                }
                                return DesignTokens.border  // Empty or filled
                            }
                            border.width: {
                                if ((root.cardPresent && root.readerPresent) && index === root.pinValue.length) {
                                    return 2  // Active focus
                                }
                                return 1  // Normal
                            }
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
                                visible: (root.cardPresent && root.readerPresent) && index === root.pinValue.length

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

            }
        }

        // Activity Log (bottom)
        ActivityLog {
            id: activityLog
            Layout.fillWidth: true
            Layout.preferredHeight: 167
        }
        }
    }

    Component.onCompleted: {
        // Discover reader and card AFTER UI loads (non-blocking)
        Qt.callLater(function() {
            var readerResult = logos.callModule("keycard", "discoverReader", [])
            processActivity(readerResult)

            try {
                var readerResponse = JSON.parse(readerResult)
                readerPresent = readerResponse.found || false
            } catch (e) {}

            var cardResult = logos.callModule("keycard", "discoverCard", [])
            processActivity(cardResult)

            try {
                var cardResponse = JSON.parse(cardResult)
                cardPresent = cardResponse.found || false
            } catch (e) {}

            // Mark initial load as complete
            initialLoadComplete = true
        })
    }

    function processActivity(responseJson) {
        try {
            var response = JSON.parse(responseJson)
            if (response._activity && Array.isArray(response._activity)) {
                for (var i = 0; i < response._activity.length; i++) {
                    var entry = response._activity[i]
                    activityLog.addEntry(entry.timestamp, entry.message, entry.level)
                }
            }
        } catch (e) {
            console.error("Failed to process activity:", e)
        }
    }

    function verifyPin() {
        console.log("Verifying PIN:", pinValue)

        verifyingPin = true

        // Show verifying message
        var timestamp = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(timestamp, "Verifying PIN...", "info")

        // Call backend authorize
        var result = logos.callModule("keycard", "authorize", [pinValue])
        processActivity(result)

        verifyingPin = false

        try {
            var response = JSON.parse(result)
            if (response.authorized) {
                unlocked()
            } else {
                attemptsRemaining = response.remainingAttempts || 0
                pinValue = ""
            }
        } catch (e) {
            console.error("Failed to parse authorize response:", e)
        }
    }
}
