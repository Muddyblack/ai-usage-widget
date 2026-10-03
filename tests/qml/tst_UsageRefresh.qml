import QtQuick
import QtTest
import "../../package/contents/ui" as Widget
import "../../package/contents/code/Shell.js" as Shell

TestCase {
    id: testCase
    name: "UsageRefresh"

    property string nextCommand: ""

    Widget.UsageRefresh {
        id: refresh
        buildCommand: () => testCase.nextCommand
    }

    Widget.CommandSource {
        id: probe
    }

    Component {
        id: refreshFactory
        Widget.UsageRefresh {}
    }

    SignalSpy {
        id: replies
        target: refresh
        signalName: "finished"
    }

    SignalSpy {
        id: probeReplies
        target: probe
        signalName: "newData"
    }

    function init() {
        failOnWarning(/.*(TypeError|ReferenceError|Unable to assign).*/);
        nextCommand = "";
        refresh.timeoutExecutable = "timeout";
        refresh.timeoutSeconds = 2;
        refresh.generation = 0;
        replies.clear();
        probeReplies.clear();
    }

    function cleanup() {
        nextCommand = "";
        tryCompare(refresh, "running", false, 4000);
        compare(refresh.pending, false);
    }

    function test_refreshBurstRunsOneFollowUp() {
        nextCommand = "sleep 0.15; printf same";
        refresh.refresh();
        for (var i = 0; i < 50; i++)
            refresh.refresh();
        compare(refresh.generation, 1);
        verify(refresh.running);
        verify(refresh.pending);
        tryCompare(replies, "count", 2, 4000);
        compare(refresh.generation, 2);
        compare(replies.signalArguments[0][0].stdout, "same");
        compare(replies.signalArguments[1][0].stdout, "same");
        compare(refresh.running, false);
    }

    function test_followUpUsesLatestCommandAndDropsOldAnswer() {
        nextCommand = "sleep 0.15; printf old";
        refresh.refresh();
        nextCommand = "printf intermediate";
        refresh.refresh();
        nextCommand = "printf latest";
        refresh.refresh();
        compare(refresh.generation, 1);
        tryCompare(refresh, "running", false, 4000);
        compare(refresh.generation, 2);
        compare(replies.count, 1);
        compare(replies.signalArguments[0][0].stdout, "latest");
    }

    function test_disabledOrBackedOffRefreshDoesNotLaunchFollowUp() {
        nextCommand = "sleep 0.15; printf old";
        refresh.refresh();
        refresh.refresh();
        nextCommand = "";
        tryCompare(refresh, "running", false, 4000);
        compare(refresh.generation, 1);
        compare(replies.count, 0);
    }

    function test_completionCanRequestAnotherRefresh() {
        function again(data) {
            if (data.stdout === "first") {
                nextCommand = "printf second";
                refresh.refresh();
            }
        }
        refresh.finished.connect(again);
        try {
            nextCommand = "printf first";
            refresh.refresh();
            tryCompare(replies, "count", 2, 4000);
            compare(refresh.generation, 2);
            compare(replies.signalArguments[1][0].stdout, "second");
        } finally {
            refresh.finished.disconnect(again);
        }
    }

    function test_replyBackoffSuppressesPendingRefresh() {
        function backoff() {
            nextCommand = "";
        }
        refresh.finished.connect(backoff);
        try {
            nextCommand = "sleep 0.15; printf rate-limited";
            refresh.refresh();
            refresh.refresh();
            tryCompare(refresh, "running", false, 4000);
            compare(replies.count, 1);
            compare(refresh.generation, 1);
        } finally {
            refresh.finished.disconnect(backoff);
        }
    }

    function test_failureReleasesRunner() {
        nextCommand = "printf failed; exit 7";
        refresh.refresh();
        tryCompare(replies, "count", 1, 4000);
        compare(replies.signalArguments[0][0]["exit code"], 7);
        compare(refresh.running, false);
        nextCommand = "printf recovered";
        refresh.refresh();
        tryCompare(replies, "count", 2, 4000);
        compare(replies.signalArguments[1][0].stdout, "recovered");
    }

    function test_commandQuotingPreservesLiteralValues() {
        var value = "spaces ' quotes $dollar `backticks`\nnext line";
        nextCommand = "VALUE=" + Shell.quote(value) + " sh -c 'printf %s \"$VALUE\"'";
        refresh.refresh();
        tryCompare(replies, "count", 1, 4000);
        compare(replies.signalArguments[0][0].stdout, value);
    }

    function test_missingTimeoutDoesNotRunAnUnboundedBackend() {
        refresh.timeoutExecutable = "/does-not-exist/timeout";
        nextCommand = "printf must-not-run";
        refresh.refresh();
        tryCompare(replies, "count", 1, 4000);
        compare(replies.signalArguments[0][0]["exit code"], 127);
        compare(replies.signalArguments[0][0].stdout, "");
        compare(refresh.running, false);
    }

    function test_timeoutKillsHelpersAndAllowsRecovery() {
        refresh.timeoutSeconds = 0.2;
        // Both the child shell and its sleep ignore TERM. The deadline must
        // stop the process group, not just abandon its output in the UI.
        nextCommand = "sh -c 'trap \"\" TERM; sleep 30' & child=$!; printf %s \"$child\"; wait";
        refresh.refresh();
        tryCompare(replies, "count", 1, 4000);
        var result = replies.signalArguments[0][0];
        verify(result["exit code"] !== 0 || result["exit status"] !== 0);
        var child = Number(result.stdout);
        verify(child > 0);
        probe.connectSource("ps -o stat= -p " + child);
        tryCompare(probeReplies, "count", 1, 4000);
        var state = probeReplies.signalArguments[0][1].stdout.trim();
        // A killed orphan can briefly remain a zombie until init reaps it.
        verify(state === "" || state[0] === "Z", "helper still running: " + state);
        compare(refresh.running, false);

        refresh.timeoutSeconds = 2;
        nextCommand = "printf recovered";
        refresh.refresh();
        tryCompare(replies, "count", 2, 4000);
        compare(replies.signalArguments[1][0].stdout, "recovered");
    }

    function test_deadlineSurvivesWidgetRemoval() {
        probe.connectSource("mktemp -d /tmp/ai-usage-refresh.XXXXXX");
        tryCompare(probeReplies, "count", 1, 4000);
        var directory = probeReplies.signalArguments[0][1].stdout.trim();
        verify(directory.indexOf("/tmp/") === 0);
        var pidFile = Shell.quote(directory + "/pid");
        var owner = refreshFactory.createObject(testCase, {
            buildCommand: function () {
                return "printf %s $$ > " + pidFile + "; sleep 30";
            },
            timeoutSeconds: 0.5
        });
        verify(owner !== null);
        try {
            owner.refresh();
            probeReplies.clear();
            probe.connectSource("timeout 2s /bin/sh -c " + Shell.quote("while [ ! -s " + pidFile + " ]; do sleep 0.01; done; cat " + pidFile));
            tryCompare(probeReplies, "count", 1, 4000);
            var child = Number(probeReplies.signalArguments[0][1].stdout);
            verify(child > 0);
            ignoreWarning(/QProcess: Destroyed while process .* is still running./);
            owner.destroy();
            owner = null;
            wait(700);
            probeReplies.clear();
            probe.connectSource("ps -o stat= -p " + child);
            tryCompare(probeReplies, "count", 1, 4000);
            var state = probeReplies.signalArguments[0][1].stdout.trim();
            verify(state === "" || state[0] === "Z", "backend outlived its deadline: " + state);
        } finally {
            if (owner)
                owner.destroy();
            probeReplies.clear();
            probe.connectSource("rm -f " + pidFile + "; rmdir " + Shell.quote(directory));
            tryCompare(probeReplies, "count", 1, 4000);
        }
    }
}
