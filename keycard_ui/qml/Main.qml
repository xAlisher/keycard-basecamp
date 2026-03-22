import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    width: 800
    height: 600
    color: "#2b2b2b"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 20

        Text {
            text: "Keycard Debug UI"
            font.pixelSize: 32
            color: "#ffffff"
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Phase 1: Scaffolding loaded successfully"
            font.pixelSize: 16
            color: "#888888"
            Layout.alignment: Qt.AlignHCenter
        }

        Button {
            text: "Test getState()"
            Layout.alignment: Qt.AlignHCenter
            onClicked: {
                var result = logos.callModule("keycard", "getState", [])
                console.log("getState result:", result)
                resultText.text = result
            }
        }

        Text {
            id: resultText
            text: "Click button to test"
            font.pixelSize: 14
            color: "#00ff00"
            Layout.alignment: Qt.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.preferredWidth: 600
        }
    }
}
