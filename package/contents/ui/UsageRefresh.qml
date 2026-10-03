import QtQuick
import "../code/Shell.js" as Shell

// Keep one backend alive per widget. Requests received while it runs collapse
// into one follow-up, whose command is built from the latest UI settings.
Item {
    id: root

    required property var buildCommand
    property string timeoutExecutable: "timeout"
    property real timeoutSeconds: 60
    readonly property bool running: activeSource !== ""
    property bool pending: false
    property string activeSource: ""
    property string activeCommand: ""
    property int generation: 0

    signal finished(var data)

    function refresh() {
        if (running) {
            pending = true;
            return;
        }
        var command = buildCommand();
        if (!command)
            return;

        activeCommand = command;
        generation += 1;
        // The deadline belongs to the process, so even a blocked UI cannot
        // keep a backend alive indefinitely. KILL stops the whole process
        // group, including helpers that ignore TERM. Keep an outer shell:
        // deleting the DataSource must not kill the timeout supervisor itself.
        activeSource = Shell.quote(timeoutExecutable) + " --signal=KILL " + Math.max(0.01, timeoutSeconds) + "s /bin/sh -c " + Shell.quote(command) + "; exit $? #gen=" + generation;
        source.connectSource(activeSource);
    }

    CommandSource {
        id: source

        onNewData: function (command, data) {
            if (command !== root.activeSource)
                return;
            try {
                // A tab or credential change supersedes this answer. A timer
                // or repeated refresh of the same data does not.
                if (root.activeCommand === root.buildCommand())
                    root.finished(data);
            } finally {
                var again = root.pending;
                root.pending = false;
                root.activeSource = "";
                root.activeCommand = "";
                if (again)
                    root.refresh();
            }
        }
    }
}
