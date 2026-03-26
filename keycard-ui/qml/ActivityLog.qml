import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    color: DesignTokens.background

    // Public API
    property alias model: logList.model

    function addEntry(timestamp, message, level) {
        logList.model.append({
            timestamp: timestamp,
            message: message,
            level: level
        })

        // Auto-scroll to bottom
        logList.positionViewAtEnd()

        // Keep only last 100 entries (prevent memory bloat)
        if (logList.model.count > 100) {
            logList.model.remove(0)
        }
    }

    function clear() {
        logList.model.clear()
    }

    function copyAllToClipboard() {
        var text = ""
        for (var i = 0; i < logList.model.count; i++) {
            var item = logList.model.get(i)
            text += item.timestamp + " " + item.message + "\n"
        }

        // Use hidden TextEdit to copy to clipboard
        clipboardHelper.text = text
        clipboardHelper.selectAll()
        clipboardHelper.copy()

        // Visual feedback
        copyButton.opacity = 0.3
        feedbackTimer.restart()
    }

    // Hidden TextEdit for clipboard operations
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    // Top border only
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: DesignTokens.border
    }

    // Copy button (top-right corner)
    Rectangle {
        id: copyButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 8
        width: 20
        height: 20
        color: "transparent"
        opacity: copyArea.containsMouse ? 0.8 : 0.5

        Behavior on opacity { NumberAnimation { duration: 150 } }

        // Copy icon (two overlapping rectangles)
        Rectangle {
            x: 3
            y: 5
            width: 10
            height: 10
            color: "transparent"
            border.color: DesignTokens.mutedForeground
            border.width: 1
            radius: 2
        }

        Rectangle {
            x: 6
            y: 2
            width: 10
            height: 10
            color: DesignTokens.background
            border.color: DesignTokens.mutedForeground
            border.width: 1
            radius: 2
        }

        MouseArea {
            id: copyArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.copyAllToClipboard()
        }

        ToolTip {
            visible: copyArea.containsMouse
            text: "Copy all logs"
            delay: 500
        }
    }

    Timer {
        id: feedbackTimer
        interval: 200
        onTriggered: copyButton.opacity = copyArea.containsMouse ? 0.8 : 0.5
    }

    ListView {
        id: logList
        anchors.fill: parent
        anchors.margins: 18
        spacing: 4
        clip: true

        model: ListModel {}

        delegate: TextEdit {
            width: logList.width
            text: timestamp + " " + message
            color: {
                if (level === "success") return DesignTokens.success
                if (level === "warning") return DesignTokens.warning
                if (level === "error") return DesignTokens.error
                return DesignTokens.info
            }
            font.pixelSize: DesignTokens.fontSizeSmall
            font.family: "monospace"
            wrapMode: TextEdit.WordWrap
            readOnly: true
            selectByMouse: true
            selectByKeyboard: true
        }
    }
}
