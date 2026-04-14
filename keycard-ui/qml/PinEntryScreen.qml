import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

FocusScope {
    id: root
    focus: true

    property alias activityLog: activityLog
    property var coreReachable: null  // null = unknown, true/false after first poll
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
    onPairedChanged: {
        if (paired && currentRequest !== null)
            hiddenInput.forceActiveFocus()
    }
    property bool pendingChecked: false
    property string pinValue: ""
    property int maxPinLength: 6
    property bool verifyingPin: false
    property int attemptsRemaining: 3
    property bool checkHardwareBusy: false
    property bool checkPairingBusy: false
    property string pairingPassword: "KeycardDefaultPairing"
    property string pairingError: ""
    property bool pairingBusy: false

    // logos.callModule wraps the C++ QString return in an extra JSON layer — parse twice
    function callModuleParse(raw) {
        try {
            var tmp = JSON.parse(raw)
            return (typeof tmp === 'string') ? JSON.parse(tmp) : tmp
        } catch (e) { return null }
    }

    function checkHardware() {
        if (root.checkHardwareBusy) return  // callModule blocks ~20s; guard prevents re-entrant stack buildup
        root.checkHardwareBusy = true

        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")

        var readerResult = logos.callModule("keycard", "checkReaderPresent", [])
        var r = callModuleParse(readerResult)

        var coreWasReachable = root.coreReachable
        var coreNowReachable = r !== null && !r.error
        root.coreReachable = coreNowReachable
        if (coreWasReachable !== coreNowReachable) {
            if (coreNowReachable) {
                activityLog.addEntry(ts, "Keycard module connected", "success")
            } else {
                activityLog.addEntry(ts, "Keycard module not reachable", "error")
                root.readerDetected = false
                root.cardDetected = false
                root.paired = false
                root.pairingSlot = -1
                root.pairingStatus = ""
                root.currentRequest = null
                root.pendingChecked = false
            }
        }
        if (!coreNowReachable) { root.checkHardwareBusy = false; return }

        var wasReader = root.readerDetected
        root.readerDetected = r.found || false
        if (wasReader !== root.readerDetected) {
            if (root.readerDetected)
                activityLog.addEntry(ts, "Smart card reader detected", "success")
            else
                activityLog.addEntry(ts, "Smart card reader not detected", "error")
        }

        if (root.readerDetected) {
            var cardResult = logos.callModule("keycard", "checkCardPresent", [])
            try {
                var c = callModuleParse(cardResult)
                var wasCard = root.cardDetected
                root.cardDetected = c.found || false
                if (wasCard !== root.cardDetected) {
                    if (root.cardDetected) {
                        activityLog.addEntry(ts, "Keycard detected", "success")
                        Qt.callLater(root.checkPairing)
                    } else {
                        activityLog.addEntry(ts, "Keycard not detected", "error")
                        root.paired = false
                        root.pairingSlot = -1
                        root.pairingStatus = ""
                        root.currentRequest = null
                        root.pendingChecked = false
                        root.checkPairingBusy = false
                        root.pairingPassword = ""
                        root.pairingError = ""
                        root.pairingBusy = false
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
                root.checkPairingBusy = false
                root.pairingPassword = ""
                root.pairingError = ""
                root.pairingBusy = false
                activityLog.addEntry(ts, "Keycard not detected", "error")
            }
        }

        if (root.cardDetected && !root.currentRequest) {
            checkPendingRequests()
        }
        root.checkHardwareBusy = false
    }

    function checkPairing() {
        if (root.checkPairingBusy) return
        root.checkPairingBusy = true

        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(ts, "Checking pairing...", "info")

        logos.callModule("keycard", "discoverReader", [])
        logos.callModule("keycard", "discoverCard", [])

        var result = logos.callModule("keycard", "checkPairing", [])
        ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        try {
            var r = callModuleParse(result)
            if (r.paired) {
                root.paired = true
                root.pairingSlot = r.pairingIndex || -1
                root.pairingStatus = "paired"
                activityLog.addEntry(ts, "Keycard already paired. Slot " + root.pairingSlot, "success")
            } else {
                root.paired = false
                root.pairingStatus = "not_paired"
                activityLog.addEntry(ts, "Keycard not paired", "warning")
            }
        } catch (e) {}
        root.checkPairingBusy = false
    }

    function doPairCard() {
        if (root.pairingBusy) return
        if (root.pairingPassword.length < 5 || root.pairingPassword.length > 25) {
            root.pairingError = "Password must be 5-25 characters"
            return
        }
        root.pairingBusy = true
        root.pairingError = ""
        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(ts, "Pairing card...", "info")
        var result = logos.callModule("keycard", "pairCard", [root.pairingPassword])
        ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        try {
            var r = callModuleParse(result)
            if (r && r.paired === true) {
                root.paired = true
                root.pairingSlot = r.pairingIndex || -1
                root.pairingStatus = "paired"
                root.pairingPassword = ""
                root.pairingError = ""
                activityLog.addEntry(ts, "Keycard paired. Slot " + root.pairingSlot, "success")
            } else {
                root.pairingError = (r && r.error) ? r.error : "Pairing failed"
                activityLog.addEntry(ts, "Pairing failed: " + root.pairingError, "error")
            }
        } catch (e) {
            root.pairingError = "Pairing failed"
            activityLog.addEntry(ts, "Pairing failed", "error")
        }
        root.pairingBusy = false
    }

    function checkPendingRequests() {
        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        var wasPendingChecked = root.pendingChecked
        root.pendingChecked = true

        // Check auth requests
        var authResult = logos.callModule("keycard", "getPendingAuths", [])
        try {
            var authResponse = callModuleParse(authResult)
            if (authResponse && authResponse.pending && authResponse.pending.length > 0 && !root.currentRequest) {
                root.currentRequest = authResponse.pending[0]
                activityLog.addEntry(ts, "New auth request from " + root.currentRequest.caller, "warning")
                return
            }
        } catch (e) {}

        // Check sign requests
        var signResult = logos.callModule("keycard", "getPendingSignRequests", [])
        try {
            var signResponse = callModuleParse(signResult)
            if (signResponse && signResponse.pending && signResponse.pending.length > 0 && !root.currentRequest) {
                root.currentRequest = signResponse.pending[0]
                activityLog.addEntry(ts, "New sign request from " + root.currentRequest.caller, "warning")
                return
            }
        } catch (e) {}

        if (!wasPendingChecked) {
            activityLog.addEntry(ts, "No pending requests", "success")
        }
    }

    function approveRequest() {
        if (!currentRequest) return
        verifyingPin = true
        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        var isSign = !!currentRequest.signId

        if (isSign) {
            activityLog.addEntry(ts, "Signing for " + currentRequest.caller + "...", "info")
        } else {
            activityLog.addEntry(ts, "Authorizing request from " + currentRequest.caller + "...", "info")
        }

        hwTimer.stop()
        var result = isSign
            ? logos.callModule("keycard", "approveSign", [currentRequest.signId, pinValue])
            : logos.callModule("keycard", "authorizeRequest", [currentRequest.authId, pinValue])
        hwTimer.start()
        verifyingPin = false

        try {
            var response = callModuleParse(result)
            if (response._activity) {
                for (var i = 0; i < response._activity.length; i++) {
                    var entry = response._activity[i]
                    activityLog.addEntry(entry.timestamp, entry.message, entry.level)
                }
            }
            var ts2 = Qt.formatTime(new Date(), "[HH:mm:ss]")
            if (response.status === "complete") {
                var caller = currentRequest.caller
                currentRequest = null
                pinValue = ""
                pendingChecked = false
                if (isSign) {
                    activityLog.addEntry(ts2, "Signed — return to " + caller, "success")
                }
            } else {
                var remaining = response.remainingAttempts
                if (remaining >= 0) {
                    if (remaining === 0) {
                        activityLog.addEntry(ts2, "Keycard blocked — no PIN attempts remaining", "error")
                    } else {
                        activityLog.addEntry(ts2, "Wrong PIN — " + remaining + " attempt" + (remaining !== 1 ? "s" : "") + " remaining", "error")
                        activityLog.addEntry(ts2, "Try again", "warning")
                    }
                } else {
                    var err = response.error || (isSign ? "Signing failed" : "Authorization failed")
                    activityLog.addEntry(ts2, err, "error")
                    activityLog.addEntry(ts2, "Try again", "warning")
                }
                pinValue = ""
                hiddenInput.forceActiveFocus()
            }
        } catch (e) { pinValue = "" }
    }

    function declineRequest() {
        if (!currentRequest) return
        var isSign = !!currentRequest.signId
        if (isSign) {
            logos.callModule("keycard", "declineSign", [currentRequest.signId])
        } else {
            logos.callModule("keycard", "rejectRequest", [currentRequest.authId])
        }
        var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
        activityLog.addEntry(ts, "Request declined", "warning")
        currentRequest = null
        pinValue = ""
        pendingChecked = false
        pairingPassword = ""
        pairingError = ""
    }

    // Hidden PIN input
    TextInput {
        id: hiddenInput
        visible: false
        focus: true
        enabled: root.currentRequest !== null && root.paired

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
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.pinValue.length === root.maxPinLength && root.paired && !root.verifyingPin)
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

    Component.onCompleted: {
        // DEBUG: activityLog.addEntry(Qt.formatTime(new Date(), "[HH:mm:ss]"), "PinEntryScreen loaded", "info")
        Qt.callLater(root.checkHardware)
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

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: root.currentRequest === null
                    text: root.pairingStatus === "not_paired"
                          ? "Pair your Keycard to continue"
                          : (root.pendingChecked ? "No pending requests" : "Looking for pending requests...")
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
                            text: {
                                if (!root.currentRequest) return ""
                                return root.currentRequest.signId
                                    ? root.currentRequest.caller + " requesting signature"
                                    : root.currentRequest.caller + " requesting access"
                            }
                            color: DesignTokens.foreground
                            font.pixelSize: 24
                            font.weight: Font.Bold
                            font.family: DesignTokens.fontPrimary
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 345
                            text: root.currentRequest && root.currentRequest.signId
                                  ? "Sign will produce a Schnorr signature with your Keycard key"
                                  : "Approve will allow the module to derive an encryption key only for approved path"
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

                            // Auth fields
                            Column {
                                visible: root.currentRequest && !root.currentRequest.signId
                                spacing: 4
                                Text { text: "domain"; color: DesignTokens.mutedForeground; font.pixelSize: DesignTokens.fontSizeSmall; font.family: DesignTokens.fontPrimary }
                                Text { text: root.currentRequest ? root.currentRequest.domain : ""; color: DesignTokens.foreground; font.pixelSize: DesignTokens.fontSizeBody; font.family: DesignTokens.fontPrimary }
                            }

                            // Sign fields
                            Column {
                                visible: root.currentRequest && !!root.currentRequest.signId
                                spacing: 4
                                Text { text: "payload"; color: DesignTokens.mutedForeground; font.pixelSize: DesignTokens.fontSizeSmall; font.family: DesignTokens.fontPrimary }
                                Text {
                                    text: root.currentRequest && root.currentRequest.payloadHash
                                          ? root.currentRequest.payloadHash.substring(0, 32) + "..."
                                          : ""
                                    color: DesignTokens.foreground
                                    font.pixelSize: DesignTokens.fontSizeBody
                                    font.family: "monospace"
                                }
                            }
                            Column {
                                visible: root.currentRequest && !!root.currentRequest.signId
                                spacing: 4
                                Text { text: "scheme"; color: DesignTokens.mutedForeground; font.pixelSize: DesignTokens.fontSizeSmall; font.family: DesignTokens.fontPrimary }
                                Text { text: root.currentRequest ? (root.currentRequest.scheme || "") : ""; color: DesignTokens.foreground; font.pixelSize: DesignTokens.fontSizeBody; font.family: DesignTokens.fontPrimary }
                            }

                            Column {
                                spacing: 4
                                Text { text: "module"; color: DesignTokens.mutedForeground; font.pixelSize: DesignTokens.fontSizeSmall; font.family: DesignTokens.fontPrimary }
                                Text { text: root.currentRequest ? root.currentRequest.caller : ""; color: DesignTokens.foreground; font.pixelSize: DesignTokens.fontSizeBody; font.family: DesignTokens.fontPrimary }
                            }
                        }
                    }

                    // Pairing form (when not paired)
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: DesignTokens.spacingM
                        visible: !root.paired

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Pair your Keycard to approve"
                            color: DesignTokens.foregroundSecondary
                            font.pixelSize: DesignTokens.fontSizeSmall
                            font.family: DesignTokens.fontPrimary
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 345
                            height: 44
                            color: "#2a2a2a"
                            radius: DesignTokens.radiusM
                            border.color: pairingInput.activeFocus ? DesignTokens.primary : DesignTokens.border
                            border.width: 1

                            TextInput {
                                id: pairingInput
                                anchors.fill: parent
                                anchors.margins: 12
                                verticalAlignment: TextInput.AlignVCenter
                                color: DesignTokens.foreground
                                font.pixelSize: DesignTokens.fontSizeBody
                                font.family: DesignTokens.fontPrimary
                                echoMode: TextInput.Normal
                                text: root.pairingPassword
                                onTextChanged: root.pairingPassword = text
                                Keys.onReturnPressed: root.doPairCard()
                            }
                            Text {
                                anchors.fill: parent
                                anchors.margins: 12
                                verticalAlignment: Text.AlignVCenter
                                text: "Pairing password"
                                color: DesignTokens.mutedForeground
                                font.pixelSize: DesignTokens.fontSizeBody
                                font.family: DesignTokens.fontPrimary
                                visible: pairingInput.text.length === 0
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: root.pairingError !== ""
                            text: root.pairingError
                            color: "#ff4444"
                            font.pixelSize: DesignTokens.fontSizeSmall
                            font.family: DesignTokens.fontPrimary
                        }

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 12

                            Rectangle {
                                width: 120
                                height: 32
                                radius: 16
                                color: pairArea.containsMouse ? "#e64a19" : DesignTokens.primary
                                opacity: (root.pairingPassword.length >= 5 && !root.pairingBusy) ? 1.0 : 0.5

                                Text {
                                    anchors.centerIn: parent
                                    text: root.pairingBusy ? "Pairing..." : "Pair Keycard"
                                    color: DesignTokens.foreground
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    font.family: DesignTokens.fontPrimary
                                }

                                MouseArea {
                                    id: pairArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: root.pairingPassword.length >= 5 && !root.pairingBusy
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.doPairCard()
                                }
                            }

                            Rectangle {
                                width: 85
                                height: 32
                                radius: 16
                                color: pairDeclineArea.containsMouse ? "#3a3a3a" : "transparent"
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
                                    id: pairDeclineArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.declineRequest()
                                }
                            }
                        }
                    }

                    // PIN dots (when paired)
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: DesignTokens.spacingM
                        visible: root.paired

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

                    // Buttons (when paired)
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12
                        visible: root.paired

                        Rectangle {
                            width: 85
                            height: 32
                            radius: 16
                            color: approveArea.containsMouse ? "#e64a19" : DesignTokens.primary
                            opacity: (root.pinValue.length === root.maxPinLength && root.paired) ? 1.0 : 0.5

                            // Static label
                            Text {
                                anchors.centerIn: parent
                                visible: !root.verifyingPin
                                text: root.currentRequest && root.currentRequest.signId ? "Sign" : "Approve"
                                color: DesignTokens.foreground
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                font.family: DesignTokens.fontPrimary
                            }

                            // Animated dots
                            Row {
                                anchors.centerIn: parent
                                visible: root.verifyingPin
                                spacing: 6

                                Repeater {
                                    model: 3
                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: DesignTokens.foreground

                                        SequentialAnimation on opacity {
                                            running: root.verifyingPin
                                            loops: Animation.Infinite
                                            PauseAnimation { duration: index * 200 }
                                            NumberAnimation { from: 0.2; to: 1; duration: 300 }
                                            NumberAnimation { from: 1; to: 0.2; duration: 300 }
                                            PauseAnimation { duration: (2 - index) * 200 }
                                        }
                                    }
                                }
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
