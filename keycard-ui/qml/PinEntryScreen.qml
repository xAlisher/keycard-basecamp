import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

FocusScope {
    id: root
    focus: true

    property string pinValue: ""
    property int maxPinLength: 6
    property int attemptsRemaining: 3
    property alias activityLog: activityLog
    property bool cardPresent: false
    property bool readerPresent: false
    property bool initialLoadComplete: false
    property bool verifyingPin: false

    // Current pending request (null = no requests, object = show request)
    property var currentRequest: null
    property var pendingQueue: []
    property bool pendingChecked: false

    // Auto-advance timer for multiple requests
    Timer {
        id: nextRequestTimer
        interval: 3000
        running: false
        repeat: false
        onTriggered: showNextRequest()
    }

    // Monitor card/reader state and pending requests
    Timer {
        id: stateMonitor
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            checkState()
            checkPendingRequests()
        }
    }

    function checkPendingRequests() {
        var result = logos.callModule("keycard", "getPendingAuths", [])
        try {
            var response = JSON.parse(result)

            // Process activity log
            if (response._activity && Array.isArray(response._activity)) {
                for (var i = 0; i < response._activity.length; i++) {
                    var entry = response._activity[i]
                    activityLog.addEntry(entry.timestamp, entry.message, entry.level)
                }
            }

            if (response.pending && Array.isArray(response.pending)) {
                pendingChecked = true
                pendingQueue = response.pending
                // If no current request and there are pending ones, show first
                if (!currentRequest && pendingQueue.length > 0) {
                    currentRequest = pendingQueue[0]
                    pinValue = ""
                    hiddenInput.forceActiveFocus()
                }
                // If current request was handled, clear it
                if (currentRequest) {
                    var stillPending = false
                    for (var j = 0; j < pendingQueue.length; j++) {
                        if (pendingQueue[j].authId === currentRequest.authId) {
                            stillPending = true
                            break
                        }
                    }
                    if (!stillPending) {
                        currentRequest = null
                        pinValue = ""
                        // Show next if available
                        if (pendingQueue.length > 0) {
                            nextRequestTimer.start()
                        }
                    }
                }
            } else if (response.count !== undefined && response.count === 0) {
                pendingChecked = true
                currentRequest = null
                pendingQueue = []
                pinValue = ""
            }
        } catch (e) {
            console.error("Failed to check pending requests:", e)
        }
    }

    function showNextRequest() {
        if (pendingQueue.length > 0) {
            currentRequest = pendingQueue[0]
            pinValue = ""
            hiddenInput.forceActiveFocus()
        }
    }

    function checkState() {
        var result = logos.callModule("keycard", "getState", [])
        try {
            var response = JSON.parse(result)
            var state = response.state

            var wasCardPresent = cardPresent
            var wasReaderPresent = readerPresent

            readerPresent = (state !== "READER_NOT_FOUND" && state !== "NO_PCSC")
            cardPresent = (state === "CARD_PRESENT" || state === "READY" || state === "SESSION_ACTIVE" || state === "AUTHORIZED")

            var timestamp = Qt.formatTime(new Date(), "[HH:mm:ss]")

            if (wasReaderPresent && !readerPresent) {
                activityLog.addEntry(timestamp, "Smart card reader not found", "error")
                activityLog.addEntry(timestamp, "Looking for smart card reader...", "info")
            } else if (!wasReaderPresent && readerPresent) {
                activityLog.addEntry(timestamp, "Smart card reader detected", "success")
                if (!cardPresent) {
                    activityLog.addEntry(timestamp, "Looking for Keycard...", "info")
                }
            }

            if (wasCardPresent && !cardPresent && readerPresent) {
                activityLog.addEntry(timestamp, "Keycard not found", "error")
                activityLog.addEntry(timestamp, "Looking for Keycard...", "info")
            } else if (!wasCardPresent && cardPresent && readerPresent && initialLoadComplete) {
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

    // Invisible text input to capture keyboard (for PIN entry)
    TextInput {
        id: hiddenInput
        visible: false
        focus: true
        enabled: cardPresent && readerPresent && currentRequest !== null

        onTextChanged: {
            var text = hiddenInput.text
            if (text.length > 0) {
                var lastChar = text.charAt(text.length - 1)
                if (lastChar >= '0' && lastChar <= '9') {
                    if (root.pinValue.length < root.maxPinLength) {
                        root.pinValue += lastChar
                    }
                }
                hiddenInput.text = ""
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

            // Main Content Area (centered)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // State 1: No pending requests
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: DesignTokens.spacingM
                    visible: currentRequest === null

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: pendingChecked ? "No pending requests" : "Looking for pending requests..."
                        color: DesignTokens.foregroundSecondary
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        font.family: DesignTokens.fontPrimary
                    }
                }

                // State 2: Pending request with PIN input
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: DesignTokens.spacing3xl
                    visible: currentRequest !== null

                    // Header
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: DesignTokens.spacingS

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: currentRequest ? currentRequest.caller + " requesting access" : ""
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

                    // Info box (matching old AuthorizationScreen)
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

                            ColumnLayout {
                                spacing: 4

                                Text {
                                    text: "domain"
                                    color: DesignTokens.mutedForeground
                                    font.pixelSize: DesignTokens.fontSizeSmall
                                    font.family: DesignTokens.fontPrimary
                                }

                                Text {
                                    text: currentRequest ? currentRequest.domain : ""
                                    color: DesignTokens.foreground
                                    font.pixelSize: DesignTokens.fontSizeBody
                                    font.family: DesignTokens.fontPrimary
                                }
                            }

                            ColumnLayout {
                                spacing: 4

                                Text {
                                    text: "module"
                                    color: DesignTokens.mutedForeground
                                    font.pixelSize: DesignTokens.fontSizeSmall
                                    font.family: DesignTokens.fontPrimary
                                }

                                Text {
                                    text: currentRequest ? currentRequest.caller : ""
                                    color: DesignTokens.foreground
                                    font.pixelSize: DesignTokens.fontSizeBody
                                    font.family: DesignTokens.fontPrimary
                                }
                            }
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
                                        return DesignTokens.primary
                                    }
                                    return DesignTokens.border
                                }
                                border.width: {
                                    if ((root.cardPresent && root.readerPresent) && index === root.pinValue.length) {
                                        return 2
                                    }
                                    return 1
                                }
                                radius: DesignTokens.radiusM

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: DesignTokens.foreground
                                    visible: index < root.pinValue.length
                                }

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

                    // Buttons (pill style, matching old AuthorizationScreen)
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        Rectangle {
                            width: root.verifyingPin ? 100 : 85
                            height: 32
                            color: root.verifyingPin ? DesignTokens.secondary : (approveArea.containsMouse ? "#e64a19" : DesignTokens.primary)
                            radius: 16
                            opacity: (root.pinValue.length === root.maxPinLength || root.verifyingPin) ? 1.0 : 0.5

                            Text {
                                anchors.centerIn: parent
                                text: root.verifyingPin ? "Approving..." : "Approve"
                                color: DesignTokens.foreground
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                font.family: DesignTokens.fontPrimary
                            }

                            MouseArea {
                                id: approveArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.pinValue.length === root.maxPinLength && !root.verifyingPin
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: approveRequest()
                            }
                        }

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
                                enabled: !root.verifyingPin
                                cursorShape: Qt.PointingHandCursor
                                onClicked: declineRequest()
                            }
                        }
                    }
                }
            }

            // Activity Log (always visible at bottom)
            ActivityLog {
                id: activityLog
                Layout.fillWidth: true
                Layout.preferredHeight: 167
            }
        }
    }

    Component.onCompleted: {
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

            checkPendingRequests()
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

    function approveRequest() {
        if (!currentRequest) return

        verifyingPin = true

        var timestamp = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(timestamp, "Authorizing request from " + currentRequest.caller + "...", "info")

        var result = logos.callModule("keycard", "authorizeRequest", [currentRequest.authId, pinValue])
        processActivity(result)

        verifyingPin = false

        try {
            var response = JSON.parse(result)
            if (response.status === "complete") {
                // Success — clear current request, return to empty state
                currentRequest = null
                pinValue = ""
            } else {
                // PIN failed or error
                attemptsRemaining = response.remainingAttempts || 0
                pinValue = ""
                hiddenInput.forceActiveFocus()
            }
        } catch (e) {
            console.error("Failed to authorize request:", e)
            pinValue = ""
        }
    }

    function declineRequest() {
        if (!currentRequest) return

        var result = logos.callModule("keycard", "rejectRequest", [currentRequest.authId])
        processActivity(result)

        currentRequest = null
        pinValue = ""
    }
}
