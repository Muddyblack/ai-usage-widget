import QtQuick
import QtQuick.Window
import "../../ui"
import "../../ui/studio"
import "../../ui/theme" as Appearance
import "../../ui/js/Tone.js" as Tone

// Run with QT_QPA_PLATFORM=offscreen qml tests/behavior/ThemeSwitchHarness.qml.
// Exercise the production settings layout and detached popup while switching
// appearance repeatedly. No processes, network requests or settings writes.
Window {
    id: view
    width: 1000
    height: 800
    visible: true

    QtObject {
        id: runner
        function run(argv, callback) {
        }
    }
    CommandBackend {
        id: backend
        runner: runner
        toolsDir: ""
        translateDir: ""
        assetsDir: Qt.resolvedUrl("../../assets").toString().replace(/^file:\/\//, "")
        configPath: ""
    }
    AppState {
        id: state
        backend: backend
        settingsSection: "appearance"
    }
    SettingsPage {
        anchors.fill: parent
        shell: state
    }
    PanelPill {
        id: pill
        y: 740
    }
    StudioSelect {
        id: select
        x: 800
        y: 740
        options: [["one", "One"], ["two", "Two"]]
        value: "one"
    }

    function check(condition, message) {
        if (!condition) {
            console.error(message);
            Qt.exit(1);
        }
    }

    Timer {
        property int step: 0
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            // Cover both system appearances in auto, plus explicit overrides.
            var modes = ["light", "auto", "dark", "auto"];
            var mode = modes[step % modes.length];
            state.systemLight = Math.floor(step / modes.length) % 2 === 0;
            state.setSetting2("appearance", mode);
            var light = mode === "light" || (mode === "auto" && state.systemLight);
            view.check(state.light === light, "Incorrect appearance mode");
            view.check(Tone.isLight(Appearance.Palette) === light, "Theme state did not update");
            view.check(pill.light === light, "Panel did not update");
            // Also exercise a control in the detached dropdown's content tree.
            var menuLight = select.popup.background.color.hslLightness > 0.5;
            view.check(menuLight === light, "Detached popup did not update");
            if (step % 8 === 0)
                select.popup.open();
            else if (step % 8 === 7)
                select.popup.close();
            if (++step === 80) {
                console.log("Theme switching passed (80 transitions)");
                Qt.quit();
            }
        }
    }
}
