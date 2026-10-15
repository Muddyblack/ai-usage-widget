pragma Singleton
import QtQuick

// Shared application colours, independent of Qt's inherited item palettes.
// Updating an inherited palette under a live layout can crash Qt 6.11 in
// QQuickPaletteProvider::updateChildrenPalettes. Ordinary property bindings
// also reach detached menus and tooltips without palette propagation.
QtObject {
    property color window: "#10141c"
}
