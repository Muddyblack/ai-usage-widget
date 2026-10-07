// Quickshell entry point.
//
// The shell itself lives in hosts/quickshell/AiUsageShell.qml; this file exists
// only to put the config root at the repository root. Quickshell sandboxes the
// QML engine to the directory holding the file it was pointed at, and anything
// outside resolves to qrc:/qs-blackhole. With the root here, the host can import
// the shared UI under ui/ and the provider JS under ui/js/;
// rooted at hosts/quickshell/ those imports escape the sandbox and the whole
// configuration fails to load.
//
// Run with `qs -p <repo>` (or `-p <repo>/shell.qml`) — never the file in
// hosts/quickshell/, which would reinstate the broken root.
import "hosts/quickshell"

AiUsageShell {}
