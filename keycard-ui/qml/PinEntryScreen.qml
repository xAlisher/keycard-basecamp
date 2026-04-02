import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

FocusScope {
    id: root
    focus: true

    property alias activityLog: activityLog
    property bool readerDetected: false
    property bool cardDetected: false
    property bool paired: false
    property int pairingSlot: -1
    property string pairingStatus: ""
    property var currentRequest: null
    onCurrentRequestChanged: {
        if (currentRequest !== null && paired)
            hiddenInput.forceActiveFocus()
    }
    property bool pendingChecked: false
    property string pinValue: ""
    property int maxPinLength: 6
    property bool verifyingPin: false
    property int attemptsRemaining: 3
    property bool cardBlocked: false

    function checkHardware() {
        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")

        var readerResult = logos.callModule("keycard", "checkReaderPresent", [])
        try {
            var r = JSON.parse(readerResult)
            var wasReader = root.readerDetected
            root.readerDetected = r.found || false
            if (wasReader !== root.readerDetected) {
                if (root.readerDetected)
                    activityLog.addEntry(ts, "Smart card reader detected", "success")
                else
                    activityLog.addEntry(ts, "Smart card reader not detected", "error")
            }
        } catch (e) {}

        if (root.readerDetected) {
            var cardResult = logos.callModule("keycard", "checkCardPresent", [])
            try {
                var c = JSON.parse(cardResult)
                var wasCard = root.cardDetected
                root.cardDetected = c.found || false
                if (wasCard !== root.cardDetected) {
                    if (root.cardDetected) {
                        activityLog.addEntry(ts, "Keycard detected", "success")
                        checkPairing()
                    } else {
                        activityLog.addEntry(ts, "Keycard not detected", "error")
                        root.paired = false
                        root.pairingSlot = -1
                        root.pairingStatus = ""
                        root.currentRequest = null
                        root.pendingChecked = false
                    }
                }
            } catch (e) {}
        } else {
            if (root.cardDetected) {
                root.cardDetected = false
                root.paired = false
                root.pairingSlot = -1
                root.pairingStatus = ""
                root.currentRequest = null
                root.pendingChecked = false
                activityLog.addEntry(ts, "Keycard not detected", "error")
            }
        }

        if (root.paired && !root.currentRequest) {
            checkPendingRequests()
        }
    }

    function checkPairing() {
        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(ts, "Checking pairing...", "info")

        logos.callModule("keycard", "discoverReader", [])
        logos.callModule("keycard", "discoverCard", [])

        var result = logos.callModule("keycard", "checkPairing", [])
        ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        try {
            var r = JSON.parse(result)
            if (r.paired) {
                root.paired = true
                root.pairingSlot = r.pairingIndex || -1
                root.pairingStatus = "paired"
                activityLog.addEntry(ts, "Keycard already paired. Slot " + root.pairingSlot, "success")
                checkCardStatus()
            } else {
                activityLog.addEntry(ts, "Keycard not paired. Pairing...", "info")
                var pairResult = logos.callModule("keycard", "pairCard", ["KeycardDefaultPairing"])
                try {
                    var pr = JSON.parse(pairResult)
                    if (pr.paired) {
                        root.paired = true
                        root.pairingSlot = pr.pairingIndex || -1
                        root.pairingStatus = "paired"
                        activityLog.addEntry(ts, "Keycard paired successfully. Slot " + root.pairingSlot, "success")
                        checkCardStatus()
                    } else {
                        root.paired = false
                        var error = pr.error || ""
                        if (error.toLowerCase().indexOf("slot") >= 0 || error.toLowerCase().indexOf("free") >= 0) {
                            root.pairingStatus = "no_slots"
                            activityLog.addEntry(ts, "Pairing failed — no free slots", "error")
                        } else {
                            root.pairingStatus = "failed"
                            activityLog.addEntry(ts, "Pairing failed: " + error, "error")
                        }
                    }
                } catch (e) {
                    root.pairingStatus = "failed"
                    activityLog.addEntry(ts, "Pairing failed", "error")
                }
            }
        } catch (e) {}
    }

    function checkCardStatus() {
        var result = logos.callModule("keycard", "getCardStatus", [])
        try {
            var r = JSON.parse(result)
            var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
            root.cardBlocked = r.blocked || false
            if (r.pinAttempts >= 0)
                root.attemptsRemaining = r.pinAttempts
            if (root.cardBlocked) {
                activityLog.addEntry(ts, "WARNING: Card PIN is BLOCKED (0 attempts left)", "error")
                activityLog.addEntry(ts, "Use PUK to unblock (Ctrl+U)", "warning")
            } else if (r.pinAttempts >= 0 && r.pinAttempts < 3) {
                activityLog.addEntry(ts, "PIN attempts remaining: " + r.pinAttempts, "warning")
            }
        } catch (e) {}
    }

    function unblockCard() {
        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(ts, "Attempting to unblock PIN with default PUK...", "info")
        var result = logos.callModule("keycard", "unblockPIN", ["000000000000", "000000"])
        try {
            var r = JSON.parse(result)
            if (r._activity) {
                for (var i = 0; i < r._activity.length; i++)
                    activityLog.addEntry(r._activity[i].timestamp, r._activity[i].message, r._activity[i].level)
            }
            if (r.success) {
                root.cardBlocked = false
                root.attemptsRemaining = 3
                ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
                activityLog.addEntry(ts, "PIN reset to 000000", "success")
            }
        } catch (e) {
            activityLog.addEntry(ts, "Unblock failed: " + e, "error")
        }
    }

    function checkPendingRequests() {
        var result = logos.callModule("keycard", "getPendingAuths", [])
        try {
            var response = JSON.parse(result)
            var wasPendingChecked = root.pendingChecked
            root.pendingChecked = true
            var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
            if (response.pending && response.pending.length > 0 && !root.currentRequest) {
                root.currentRequest = response.pending[0]
                activityLog.addEntry(ts, "New request from " + root.currentRequest.caller + " for domain " + root.currentRequest.domain, "warning")
            } else if (!wasPendingChecked && (!response.pending || response.pending.length === 0)) {
                activityLog.addEntry(ts, "No pending requests", "success")
            }
        } catch (e) {}
    }

    function approveRequest() {
        if (!currentRequest) return
        verifyingPin = true
        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(ts, "Authorizing request from " + currentRequest.caller + "...", "info")

        hwTimer.stop()
        var result = logos.callModule("keycard", "authorizeRequest", [currentRequest.authId, pinValue])
        hwTimer.start()
        verifyingPin = false

        try {
            var response = JSON.parse(result)
            if (response._activity) {
                for (var i = 0; i < response._activity.length; i++) {
                    var entry = response._activity[i]
                    activityLog.addEntry(entry.timestamp, entry.message, entry.level)
                }
            }
            if (response.status === "complete") {
                currentRequest = null
                pinValue = ""
                pendingChecked = false
            } else {
                attemptsRemaining = response.remainingAttempts || 0
                pinValue = ""
                hiddenInput.forceActiveFocus()
            }
        } catch (e) { pinValue = "" }
    }

    function declineRequest() {
        if (!currentRequest) return
        logos.callModule("keycard", "rejectRequest", [currentRequest.authId])
        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(ts, "Request declined", "warning")
        currentRequest = null
        pinValue = ""
        pendingChecked = false
    }

    // Hidden PIN input
    TextInput {
        id: hiddenInput
        visible: false
        focus: true
        enabled: (root.currentRequest !== null && root.paired && !root.cardBlocked) || root.cardBlocked

        onTextChanged: {
            var text = hiddenInput.text
            if (text.length > 0) {
                var lastChar = text.charAt(text.length - 1)
                if (lastChar >= '0' && lastChar <= '9') {
                    if (root.pinValue.length < root.maxPinLength)
                        root.pinValue += lastChar
                }
                hiddenInput.text = ""
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                root.unblockCard()
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.pinValue.length === root.maxPinLength && root.paired && !root.verifyingPin && !root.cardBlocked)
                    root.approveRequest()
                event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
                if (root.pinValue.length > 0)
                    root.pinValue = root.pinValue.slice(0, -1)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                if (root.currentRequest)
                    root.declineRequest()
                event.accepted = true
            }
        }
    }

    Timer {
        id: hwTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.checkHardware()
    }

    Component.onCompleted: Qt.callLater(root.checkHardware)

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

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: root.currentRequest === null
                    text: root.cardBlocked ? "Card PIN BLOCKED — press Ctrl+U to unblock" : (root.pendingChecked ? "No pending requests" : "Looking for pending requests...")
                    color: DesignTokens.foregroundSecondary
                    font.pixelSize: 24
                    font.weight: Font.Medium
                    font.family: DesignTokens.fontPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

                // Request (when pending)
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: DesignTokens.spacing3xl
                    visible: root.currentRequest !== null

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: DesignTokens.spacingS

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.currentRequest ? root.currentRequest.caller + " requesting access" : ""
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
                            font.family: DesignTokens.fontPrimary
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 345
                        Layout.preferredHeight: reqCol.implicitHeight + 32
                        color: "#2a2a2a"
                        radius: DesignTokens.radiusM

                        Column {
                            id: reqCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Column {
                                spacing: 4
                                Text { text: "domain"; color: DesignTokens.mutedForeground; font.pixelSize: DesignTokens.fontSizeSmall; font.family: DesignTokens.fontPrimary }
                                Text { text: root.currentRequest ? root.currentRequest.domain : ""; color: DesignTokens.foreground; font.pixelSize: DesignTokens.fontSizeBody; font.family: DesignTokens.fontPrimary }
                            }
                            Column {
                                spacing: 4
                                Text { text: "module"; color: DesignTokens.mutedForeground; font.pixelSize: DesignTokens.fontSizeSmall; font.family: DesignTokens.fontPrimary }
                                Text { text: root.currentRequest ? root.currentRequest.caller : ""; color: DesignTokens.foreground; font.pixelSize: DesignTokens.fontSizeBody; font.family: DesignTokens.fontPrimary }
                            }
                        }
                    }

                    // PIN dots
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: DesignTokens.spacingM
                        opacity: root.paired ? 1.0 : 0.3

                        Repeater {
                            model: root.maxPinLength
                            Rectangle {
                                width: DesignTokens.pinDigitSize
                                height: DesignTokens.pinDigitSize
                                color: "transparent"
                                border.color: (root.paired && index === root.pinValue.length) ? DesignTokens.primary : DesignTokens.border
                                border.width: (root.paired && index === root.pinValue.length) ? 2 : 1
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
                                    visible: root.paired && index === root.pinValue.length

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
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        Rectangle {
                            width: 85
                            height: 32
                            radius: 16
                            color: approveArea.containsMouse ? "#e64a19" : DesignTokens.primary
                            opacity: (root.pinValue.length === root.maxPinLength && root.paired) ? 1.0 : 0.5

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
                                enabled: root.pinValue.length === root.maxPinLength && root.paired && !root.verifyingPin
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.approveRequest()
                            }
                        }

                        Rectangle {
                            width: 85
                            height: 32
                            radius: 16
                            color: declineArea.containsMouse ? "#3a3a3a" : "transparent"
                            border.color: DesignTokens.border
                            border.width: 1

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
                                onClicked: root.declineRequest()
                            }
                        }
                    }
                }
            }

            ActivityLog {
                id: activityLog
                Layout.fillWidth: true
                Layout.preferredHeight: 167
            }
        }
    }
}
