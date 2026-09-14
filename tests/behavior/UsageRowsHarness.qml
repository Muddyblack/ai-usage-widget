import QtQuick
import "../../hyprland"

Item {
    property string envelopeJson: "{}"
    width: 420
    height: 600

    UsageRows {
        objectName: "rows"
        width: parent.width
        provider: (JSON.parse(envelopeJson).providers || [])[0] || null
    }
}
