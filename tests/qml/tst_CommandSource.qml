import QtQuick
import QtTest
import "../../package/contents/ui" as Widget

TestCase {
    id: testCase
    name: "CommandSource"

    Widget.CommandSource {
        id: commands
    }

    Component {
        id: commandFactory
        Widget.CommandSource {}
    }

    SignalSpy {
        id: replies
        target: commands
        signalName: "newData"
    }

    function init() {
        replies.clear();
    }

    function cleanup() {
        var pending = Object.keys(commands._jobs);
        for (var i = 0; i < pending.length; i++)
            commands.disconnectSource(pending[i]);
    }

    function test_repeatedCommandsReleaseSources() {
        // Generation tags and embedded history payloads make real commands
        // distinct on every poll. No completed DataSource should survive.
        for (var i = 0; i < 100; i++) {
            var command = "printf reply #generation=" + i;
            replies.clear();
            commands.connectSource(command);
            var request = commands._jobs[command];
            tryCompare(replies, "count", 1, 3000);
            compare(replies.signalArguments[0][0], command);
            compare(replies.signalArguments[0][1].stdout, "reply");
            compare(replies.signalArguments[0][1]["exit code"], 0);
            compare(Object.keys(commands._jobs).length, 0);
            tryVerify(function () {
                return !Qt.isQtObject(request);
            }, 3000);
        }
    }

    function test_duplicateConnectionAndCancellation() {
        var command = "sleep 0.1; printf cancelled";
        commands.connectSource(command);
        var request = commands._jobs[command];
        commands.connectSource(command);
        compare(commands._jobs[command], request);
        compare(Object.keys(commands._jobs).length, 1);
        ignoreWarning(/QProcess: Destroyed while process .* is still running./);
        commands.disconnectSource(command);
        commands.disconnectSource(command);
        compare(Object.keys(commands._jobs).length, 0);
        tryVerify(function () {
            return !Qt.isQtObject(request);
        }, 3000);
        wait(200);
        compare(replies.count, 0);
    }

    function test_concurrentCommandsAndFailure() {
        commands.connectSource("printf first; exit 7");
        commands.connectSource("printf second");
        tryCompare(replies, "count", 2, 3000);
        var results = {};
        for (var i = 0; i < replies.count; i++) {
            var result = replies.signalArguments[i][1];
            results[result.stdout] = result["exit code"];
        }
        compare(results.first, 7);
        compare(results.second, 0);
        compare(Object.keys(commands._jobs).length, 0);
    }

    function test_ownerDestructionReleasesPendingSources() {
        var owner = commandFactory.createObject(testCase);
        var command = "sleep 0.1; printf pending";
        owner.connectSource(command);
        var request = owner._jobs[command];
        verify(Qt.isQtObject(request));
        ignoreWarning(/QProcess: Destroyed while process .* is still running./);
        owner.destroy();
        tryVerify(function () {
            return !Qt.isQtObject(request);
        }, 3000);
    }

    function test_completionCanStartNextCommand() {
        function next(command, data) {
            if (data.stdout === "start")
                commands.connectSource("printf finish");
        }
        commands.newData.connect(next);
        try {
            commands.connectSource("printf start");
            tryCompare(replies, "count", 2, 3000);
            compare(replies.signalArguments[1][1].stdout, "finish");
            compare(Object.keys(commands._jobs).length, 0);
        } finally {
            commands.newData.disconnect(next);
        }
    }
}
