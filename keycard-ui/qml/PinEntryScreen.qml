import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

FocusScope {
    id: root
    focus: true

    property alias activityLog: activityLog
    property bool readerDetected: false

    function checkReader() {
        var result = logos.callModule("keycard", "checkReaderPresent", [])
        try {
            var r = JSON.parse(result)
            var was = root.readerDetected
            root.readerDetected = r.found || false
            if (was !== root.readerDetected) {
                var ts = Qt.formatTime(new Date(), "[HH:mm:ss]")
                if (root.readerDetected)
                    activityLog.addEntry(ts, "Smart card reader detected", "success")
                else
                    activityLog.addEntry(ts, "Smart card reader not detected", "error")
            }
        } catch (e) {}
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.checkReader()
    }

    Component.onCompleted: root.checkReader()

    Rectangle {
        anchors.fill: parent
        color: DesignTokens.background

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        width: 10; height: 10; radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.readerDetected ? "#4caf50" : "#f44336"
                    }

                    Text {
                        text: root.readerDetected ? "Smart card reader detected" : "Smart card reader not detected"
                        color: root.readerDetected ? "#4caf50" : "#f44336"
                        font.pixelSize: 16
                        font.family: DesignTokens.fontPrimary
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
