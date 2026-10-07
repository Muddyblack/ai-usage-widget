pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

// The `runner` ui/CommandBackend.qml starts commands through, on Plasma: one
// disposable executable DataSource per call. A DataSource keeps every command
// it has seen in a map for its whole life, so each job gets its own and drops
// it once answered. The command text carries a job number, so two identical
// commands in flight are still two jobs.
Item {
    id: root

    property int jobCount: 0

    // One argument, safe for /bin/sh: single-quoted, with any single quote
    // closed, escaped and reopened.
    function quote(arg) {
        return "'" + String(arg).replace(/'/g, "'\\''") + "'";
    }

    function run(argv, callback) {
        root.jobCount += 1;
        var command = argv.map(root.quote).join(" ") + " # job " + root.jobCount;
        const job = jobComponent.createObject(root, {
            callback: callback
        }) as Plasma5Support.DataSource;
        job.connectSource(command);
    }

    Component {
        id: jobComponent

        Plasma5Support.DataSource {
            id: job

            property var callback: null

            engine: "executable"
            connectedSources: []
            onNewData: function (source, data) {
                job.disconnectSource(source);
                var cb = job.callback;
                job.callback = null;
                if (typeof cb === "function")
                    cb(data["stdout"] || "", data["stderr"] || "", data["exit code"] || 0);
                job.destroy();
            }
        }
    }
}
