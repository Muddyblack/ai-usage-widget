import QtQuick
import Quickshell.Io

// The `runner` ui/CommandBackend.qml starts commands through: one Quickshell
// Process per call, destroyed once it has exited and both streams are read
// (those arrive in either order).
QtObject {
    id: root

    property string workingDirectory: ""

    property Component job: Component {
        Process {
            id: proc

            property var callback: null
            property string out: ""
            property string err: ""
            property int outDone: 0
            property int code: -1

            function finish() {
                if (proc.outDone < 2 || proc.code < 0)
                    return;
                var cb = proc.callback;
                proc.callback = null;
                if (typeof cb === "function")
                    cb(proc.out, proc.err, proc.code);
                proc.destroy();
            }

            stdout: StdioCollector {
                onStreamFinished: {
                    proc.out = this.text;
                    proc.outDone += 1;
                    proc.finish();
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    proc.err = this.text;
                    proc.outDone += 1;
                    proc.finish();
                }
            }
            onExited: function (exitCode) {
                proc.code = exitCode;
                proc.finish();
            }
        }
    }

    function run(argv, callback) {
        var proc = root.job.createObject(root, {
            callback: callback
        });
        var options = {
            command: argv
        };
        if (root.workingDirectory !== "")
            options.workingDirectory = root.workingDirectory;
        proc.exec(options);
    }
}
