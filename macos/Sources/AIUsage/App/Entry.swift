import AppKit

/// The entry point.
///
/// `@main` on a type rather than top-level code in a `main.swift`: top-level
/// code is *not* main-actor isolated, so every line of it that touched the app
/// delegate or the diagnostic modes was a call into an actor from outside it.
/// A `@MainActor static func main()` is the same program, on the actor the
/// whole app lives on.
@main
enum AIUsageMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        // NSApplication.delegate is weak, so this has to outlive the call
        // below — which it does: run() only returns when the app quits.
        let delegate = AppDelegate(mode: LaunchMode(arguments: CommandLine.arguments))
        application.delegate = delegate
        // .accessory is LSUIElement's runtime half: a menu bar item, no Dock
        // tile, no app menu. The Info.plist carries the same thing for a
        // launch from Finder. The diagnostic modes keep it too — they drive
        // the real status item, and a status item needs a real app.
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
