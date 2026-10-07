import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QC

// One API-key row: masked field with a reveal toggle. Writes into
// shell.settings.keys[settingKey] on edit and triggers a refresh.
RowLayout {
    id: keyRow

    property var shell
    property string label: ""
    property string placeholder: ""
    property string settingKey: ""
    property bool secret: true

    Layout.fillWidth: true
    spacing: 6

    property bool revealed: false
    readonly property string stored: (shell.settings.keys[settingKey] || "")

    Text {
        text: keyRow.label
        font.pixelSize: 11
        color: "#f8fafc"
        Layout.preferredWidth: 90
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: 5
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: field.activeFocus ? Qt.rgba(0.31, 0.62, 0.87, 0.6) : Qt.rgba(1, 1, 1, 0.12)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 4
            spacing: 4

            QC.TextField {
                id: field
                Layout.fillWidth: true
                text: keyRow.stored
                font.pixelSize: 10
                color: "#f8fafc"
                placeholderText: keyRow.placeholder
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.3)
                echoMode: !keyRow.secret || keyRow.revealed ? TextInput.Normal : TextInput.Password
                verticalAlignment: TextInput.AlignVCenter
                background: null
                selectByMouse: true
                onTextEdited: {
                    // Store trimmed: a pasted key often carries a trailing
                    // space or newline. The field itself is left alone — this
                    // fires while typing, and rewriting the text would move the
                    // cursor mid-edit.
                    keyRow.shell.setSetting("keys", keyRow.settingKey, String(text).trim());
                    refreshDebounce.restart();
                }
                onEditingFinished: {
                    // Once typing has settled, rewrite the visible text too, so
                    // what is shown matches what was stored — the same guarantee
                    // KeyRow.qml (the Plasma frontend) gives on blur.
                    var val = String(text).trim();
                    if (val !== text)
                        text = val;
                }
            }

            Text {
                visible: keyRow.secret
                text: keyRow.revealed ? "🙈" : "👁"
                font.pixelSize: 12
                opacity: revealMouse.containsMouse ? 1.0 : 0.5
                Layout.alignment: Qt.AlignVCenter
                MouseArea {
                    id: revealMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: keyRow.revealed = !keyRow.revealed
                }
            }
        }
    }

    // Debounce so we don't spawn a backend refresh on every keystroke.
    Timer {
        id: refreshDebounce
        interval: 1200
        onTriggered: keyRow.shell.refresh()
    }
}
