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
    property bool pendingChecked: false

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
                    text: root.pendingChecked ? "No pending requests" : "Looking for pending requests..."
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
