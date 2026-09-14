import Foundation

/// How this process was started.
///
/// `--selftest` and `--screenshot <dir>` are the same two switches
/// `windows/app.py` carries, for the same reason: the UI of a widget nobody can
/// run on their own desktop needs some way to be looked at, and a build that
/// compiles is not the same as a build that draws. Both run the real app —
/// real status item, real popover, real settings window — and exit.
///
/// Point `AI_USAGE_BACKEND` at a script that prints a fixture envelope and they
/// render real contract data without a credential and without the network.
enum LaunchMode {
    case normal
    case selftest
    /// Photograph every window into this directory, then quit.
    case screenshot(directory: String)

    init(arguments: [String]) {
        if let index = arguments.firstIndex(of: "--screenshot"), index + 1 < arguments.count {
            self = .screenshot(directory: arguments[index + 1])
        } else if arguments.contains("--selftest") {
            self = .selftest
        } else {
            self = .normal
        }
    }

    var isDiagnostic: Bool {
        if case .normal = self { return false }
        return true
    }

    var screenshotDirectory: String? {
        if case .screenshot(let directory) = self { return directory }
        return nil
    }
}
