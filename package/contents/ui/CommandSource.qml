pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

// DataSource stores each command in a QQmlPropertyMap. Clearing a result does
// not remove its key, so track URLs and request generations grow that map for
// the lifetime of the widget. Give each command its own disposable source.
//
// Commands are identified by their exact text. Callers may still append a
// unique suffix ("... # <generation>") to tell a stale reply from the current
// one, or to run the same command again while an earlier run is in flight: an
// identical string that is already running is ignored on purpose.
Item {
    id: root
    property var connectedSources: []
    property var _jobs: Object.create(null)
    signal newData(string source, var data)

    function connectSource(source) {
        if (_jobs[source])
            return;
        const job = command.createObject(root) as Plasma5Support.DataSource;
        _jobs[source] = job;
        connectedSources = connectedSources.concat([source]);
        job.connectSource(source);
    }

    function disconnectSource(source) {
        const job = _jobs[source];
        if (!job)
            return;
        delete _jobs[source];
        connectedSources = connectedSources.filter(value => value !== source);
        job.disconnectSource(source);
        job.destroy();
    }

    function cancelSource(source) {
        const job = _jobs[source];
        if (job && typeof job.cancelSource === "function")
            job.cancelSource(source);
        disconnectSource(source);
    }

    Component.onDestruction: {
        for (const source of connectedSources.slice())
            disconnectSource(source);
    }

    Component {
        id: command
        Plasma5Support.DataSource {
            id: job
            engine: "executable"
            connectedSources: []
            onNewData: function (source, data) {
                if (root._jobs[source] !== job)
                    return;
                // Release before notifying: a callback may start another job,
                // including a new invocation of this same command.
                root.disconnectSource(source);
                root.newData(source, data);
            }
        }
    }
}
