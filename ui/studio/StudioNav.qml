import QtQuick
import "Theme.js" as Theme

// The studios' tab list: icon and label per entry. Vertical as a sidebar when
// there is room; otherwise the same entries wrap across as many rows as the
// width needs, so none of them is ever hidden off the edge.
Item {
    id: nav

    // [{ id, label, icon }] — icon is an SVG path on a 24 x 24 grid.
    property var entries: []
    property string currentId: ""
    property bool horizontal: false
    property color accent: Theme.brand
    signal selected(string id)

    implicitWidth: horizontal ? 300 : 156
    implicitHeight: horizontal ? strip.height : column.implicitHeight

    Column {
        id: column
        visible: !nav.horizontal
        width: parent.width
        spacing: 3
        Repeater {
            model: nav.horizontal ? [] : nav.entries
            StudioNavEntry {
                owner: nav
            }
        }
    }

    Flow {
        id: strip
        visible: nav.horizontal
        width: nav.width
        spacing: 4
        Repeater {
            model: nav.horizontal ? nav.entries : []
            StudioNavEntry {
                owner: nav
            }
        }
    }
}
