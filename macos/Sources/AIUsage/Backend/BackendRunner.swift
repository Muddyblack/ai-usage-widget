import Foundation

/// Runs the shared Python backend and hands back its JSON.
///
/// macOS ships no Python a user can rely on — `/usr/bin/python3` is a stub
/// that asks to install the Xcode command line tools — so the release build
/// carries its own frozen copy in `Contents/Resources/backend/`. The backend
/// is standard-library-only, which is what makes freezing it a 15 MB detail
/// rather than a project. Development runs the checkout's own scripts
/// instead; `AI_USAGE_BACKEND` points at either.
enum Backend {
    enum Failure: Error, LocalizedError {
        case notFound
        case failed(status: Int32, stderr: String)
        case badJSON(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "the usage backend is missing from this build"
            case let .failed(status, stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "usage backend exited \(status)" : trimmed
            case let .badJSON(message):
                return "usage backend returned unreadable data: \(message)"
            }
        }
    }

    /// The frozen binary, the checkout's launcher, or nil.
    ///
    /// Resolved once: it cannot change while the app runs, and every poll
    /// would otherwise stat the same handful of paths again.
    static let executable: URL? = {
        if let override = ProcessInfo.processInfo.environment["AI_USAGE_BACKEND"] {
            let url = URL(fileURLWithPath: override)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        for candidate in searchPaths where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        return nil
    }()

    /// True when the backend found is the checkout's bash launcher rather than
    /// the frozen binary — it takes `history` through a separate script.
    static var isCheckoutLauncher: Bool {
        executable?.lastPathComponent == "get-ai-usage"
    }

    private static var searchPaths: [URL] {
        var paths: [URL] = []
        let resources = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/backend", isDirectory: true)
        paths.append(resources.appendingPathComponent("ai-usage-backend"))

        // `swift run` from a checkout: walk up from the executable looking for
        // the repository layout, so the app runs against the working tree.
        var dir = Bundle.main.bundleURL.resolvingSymlinksInPath()
        for _ in 0..<6 {
            paths.append(dir.appendingPathComponent("package/contents/tools/sh/get-ai-usage"))
            dir = dir.deletingLastPathComponent()
        }
        return paths
    }

    /// One envelope for every enabled provider.
    static func snapshot() throws -> Envelope {
        let data = try run(arguments: ["--all"])
        do {
            return try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw Failure.badJSON(error.localizedDescription)
        }
    }

    /// Recent local agent sessions for the optional Sessions view.
    /// `get-ai-usage --sessions --query <text>` prints a redacted envelope
    /// (titles and folder names only — never paths or transcripts), and the
    /// frozen binary passes these flags straight through to `aiusage.__main__`.
    static func sessions(
        _ query: String = "", limit: Int? = nil, offset: Int? = nil
    ) throws -> LocalSessions {
        var arguments = ["--sessions", "--query", query]
        if let limit {
            arguments += ["--limit", String(limit)]
        }
        if let offset {
            arguments += ["--offset", String(offset)]
        }
        let data = try run(arguments: arguments)
        do {
            return try JSONDecoder().decode(LocalSessions.self, from: data)
        } catch {
            throw Failure.badJSON(error.localizedDescription)
        }
    }

    /// Resume one listed session (by its `openKey`) in the user's terminal.
    /// `--open-session` prints `{ok,message}` and exits 1 on a failure that is
    /// still meant to be shown, not thrown — so this bypasses `run()`'s
    /// nonzero-exit guard and decodes stdout either way.
    static func openSession(_ key: String) throws -> OpenSessionResult {
        guard let tool = executable else { throw Failure.notFound }

        let process = Process()
        process.executableURL = tool
        process.arguments = ["--open-session", key]
        process.environment = ProcessInfo.processInfo.environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let data = try collect(process, out: out, err: err, ignoreStatus: true)
        do {
            return try JSONDecoder().decode(OpenSessionResult.self, from: data)
        } catch {
            throw Failure.badJSON(error.localizedDescription)
        }
    }

    /// One `history-io` command.
    ///
    /// The payload — the samples just taken — goes in through
    /// WIDGET_HISTORY_JSON rather than on stdin, because that is the one way
    /// both backends accept it: the frozen binary reads either, but the
    /// checkout's bash launcher only reads the variable. It is a handful of
    /// new points per poll, never a whole series, so it is nowhere near an
    /// environment block's limit.
    @discardableResult
    static func history(_ command: String, payload: String = "") throws -> Data {
        let environment: [String: String] = payload.isEmpty ? [:] : ["WIDGET_HISTORY_JSON": payload]
        if isCheckoutLauncher, let url = executable {
            // tools/sh/history-io, beside the get-ai-usage that was found.
            let script = url.deletingLastPathComponent().appendingPathComponent("history-io")
            return try run(tool: script, arguments: [command], environment: environment)
        }
        return try run(arguments: ["history", command], environment: environment)
    }

    private static func run(
        tool overrideTool: URL? = nil, arguments: [String], environment: [String: String] = [:]
    ) throws -> Data {
        guard let tool = overrideTool ?? executable else { throw Failure.notFound }

        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        // The backend reads the shared settings file and the user's own
        // credential stores; it needs the login environment, not a trimmed one.
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        // Nothing here reads stdin, and a child that inherits the app's would
        // block forever if one ever did.
        process.standardInput = FileHandle.nullDevice

        try process.run()
        return try collect(process, out: out, err: err)
    }

    private static func collect(
        _ process: Process, out: Pipe, err: Pipe, ignoreStatus: Bool = false
    ) throws -> Data {
        // Both pipes are drained while the child runs. Waiting first and
        // reading after deadlocks as soon as a provider list outgrows the
        // 64 KB pipe buffer, which `--all` does.
        var stdout = Data()
        var stderr = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "org.muddyblack.aiusage.backend-io", attributes: .concurrent)
        group.enter()
        queue.async {
            stdout = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        queue.async {
            stderr = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()

        guard ignoreStatus || process.terminationStatus == 0 else {
            throw Failure.failed(
                status: process.terminationStatus,
                stderr: String(data: stderr, encoding: .utf8) ?? ""
            )
        }
        return stdout
    }
}

/// `--open-session`'s answer: safe to show as-is, names binaries and
/// terminals only — never a path or transcript.
struct OpenSessionResult: Decodable {
    var ok: Bool
    var message: String
}
