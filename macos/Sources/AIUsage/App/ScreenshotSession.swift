import AppKit

/// Photographs the running app, window by window.
///
/// The first version of this rendered the SwiftUI views offscreen with
/// `ImageRenderer`, which was wrong in a way that only a picture shows:
/// `ImageRenderer` cannot rasterise an AppKit-backed control, so every `Menu`,
/// segmented `Picker` and `TabView` came out as a yellow "prohibited" box — the
/// provider picker, the overflow menu and the entire settings window. It also
/// never showed the popover's material, arrow or shadow, because those belong
/// to the window server and not to the view.
///
/// So this drives the real app instead: open the real popover under the real
/// status item, let it settle, and ask `screencapture` for that window. What
/// comes out is what a user sees. Where the window server refuses — a runner
/// with no screen recording permission returns nothing — it falls back to the
/// window drawing itself into a bitmap, which still has the real controls in it
/// and is worth more than a black rectangle.
@MainActor
final class ScreenshotSession {
    /// How long to let the run loop settle between steps.
    ///
    /// Generous on purpose. The first version used 0.7s and produced three
    /// byte-identical popover shots out of four: the window server had not
    /// composited the new appearance — or the newly opened popover — by the
    /// time `screencapture` asked for it, so it handed back the previous
    /// frame. A screenshot that silently repeats itself is worse than none.
    private let settle: TimeInterval = 1.4

    private let directory: URL?
    private let model: AppModel
    private let statusItem: StatusItemController
    private let settingsWindow: SettingsWindowController
    private var failures: [String] = []
    private var appearance: Appearance = .light
    /// Digest of every shot written, so two that came out identical are named
    /// in the log rather than left for someone to notice in an artifact.
    private var digests: [String: String] = [:]

    /// `directory` nil is --selftest: everything is opened and inspected, and
    /// nothing is written.
    init(
        directory: String?, model: AppModel, statusItem: StatusItemController,
        settingsWindow: SettingsWindowController
    ) {
        self.directory = directory.map { URL(fileURLWithPath: $0) }
        self.model = model
        self.statusItem = statusItem
        self.settingsWindow = settingsWindow
    }

    func run(onFinish: @escaping (Int32) -> Void) {
        var steps: [() -> Void] = []

        // One snapshot before anything opens, so the popover has rows in it
        // rather than "Reading usage…".
        steps.append { self.loadData() }

        // The menu bar, once, and before any appearance is forced.
        //
        // There is no light and dark version of this shot to take: the system
        // menu bar does not follow an application's appearance. NSApp.appearance
        // styles this app's own windows; the menu bar's is the system's, from
        // System Settings, and an app cannot change it for itself. Taking two
        // produced the same picture twice, which the duplicate check caught.
        //
        // It also has to be taken with the appearance left alone, because the
        // item's own title is drawn in .labelColor against the *menu bar's*
        // appearance — forcing darkAqua on the app would tint it for a menu bar
        // that is still light.
        steps.append { NSApp.appearance = nil }
        // One shot per icon style: this is the choice that cannot be judged
        // from a description.
        for icon in MenuBarIcon.allCases {
            steps.append {
                self.model.changeSettings { $0.menuBarIcon = icon }
                self.refreshStatusItem()
            }
            steps.append { self.captureMenuBar("menubar-\(icon.rawValue)") }
        }
        steps.append {
            self.model.changeSettings { $0.menuBarIcon = .monochrome }
            self.refreshStatusItem()
        }

        for scheme in [Appearance.light, Appearance.dark] {
            steps.append {
                self.appearance = scheme
                NSApp.appearance = scheme.nsAppearance
                // The popover is closed and reopened for each appearance: a
                // hosting view already on screen does not always pick up an
                // application-level appearance change, and a stale one is
                // exactly the failure this sequence is recovering from.
                self.statusItem.close()
            }
            steps.append {
                self.statusItem.open()
                self.prepare(self.statusItem.popoverWindow)
            }
            if scheme == .dark {
                steps.append { self.capture(self.statusItem.popoverWindow, "popover-dark") }
                steps.append { self.captureScreen("screen-dark") }
            }
            steps.append {
                self.model.showingChart = true
                self.model.showingStats = true
            }
            steps.append { self.capture(self.statusItem.popoverWindow, "popover-expanded-\(scheme.name)") }
            steps.append {
                self.model.showingChart = false
                self.model.showingStats = false
                self.statusItem.close()
            }
            if scheme == .dark {
                steps.append {
                    self.settingsWindow.show(model: self.model)
                    self.prepare(self.settingsWindow.window)
                }
                steps.append { self.capture(self.settingsWindow.window, "settings-dark") }
                steps.append { self.settingsWindow.close() }
            }
        }

        schedule(steps) {
            for failure in self.failures {
                FileHandle.standardError.write(Data("\(failure)\n".utf8))
            }
            if self.failures.isEmpty {
                print(self.directory.map { "wrote screenshots to \($0.path)" } ?? "selftest ok")
            }
            onFinish(self.failures.isEmpty ? 0 : 1)
        }
    }

    fileprivate enum Appearance {
        case light, dark
        var name: String { self == .light ? "light" : "dark" }
        var nsAppearance: NSAppearance? {
            NSAppearance(named: self == .light ? .aqua : .darkAqua)
        }
    }

    private func schedule(_ steps: [() -> Void], done: @escaping () -> Void) {
        // Start each delay after the previous step completes. A blocking
        // backend or screencapture must not consume later settling intervals.
        func next(_ index: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                guard index < steps.count else {
                    done()
                    return
                }
                steps[index]()
                next(index + 1)
            }
        }
        next(0)
    }

    private func prepare(_ window: NSWindow?) {
        // Set appearance before the scheduled settling interval, not just
        // before blocking the main thread to ask the compositor for a frame.
        window?.appearance = appearance.nsAppearance
        window?.contentView?.needsDisplay = true
        window?.displayIfNeeded()
    }

    /// The backend, read on this thread rather than through the model's worker:
    /// there is nobody to wait for the answer here.
    private func loadData() {
        model.history.loadSynchronously()
        do {
            let envelope = try Backend.snapshot()
            model.applyForDiagnostics(envelope)
            if envelope.providers.isEmpty {
                failures.append("the backend answered with no providers")
            }
        } catch {
            failures.append("backend: \(error.localizedDescription)")
        }
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        statusItem.update(
            provider: model.selected,
            style: model.settings.menuBarStyle,
            slots: model.settings.menuBarSlots,
            coloured: model.settings.colouredPercentages,
            icon: model.settings.menuBarIcon)
    }

    // ── Capture ──────────────────────────────────────────────────────────

    private func capture(_ window: NSWindow?, _ name: String) {
        guard let window else {
            failures.append("\(name): the window never appeared")
            return
        }
        guard let directory else { return }  // --selftest: opening it was the test

        let url = directory.appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var how = "screencapture"
        if !screencapture(window, to: url) {
            guard drawIntoBitmap(window, to: url) else {
                failures.append("\(name): could not be captured")
                return
            }
            how = "the window's own drawing (screencapture gave nothing)"
        }
        guard flattenWindowPNG(at: url) else {
            failures.append("\(name): could not give the window PNG an opaque background")
            return
        }
        record(name: name, url: url, how: how + ", opaque \(appearance.name) background")
    }

    /// Window captures may retain the popover material's transparency. Give
    /// exports a theme-matched backdrop so light text/background contrast does
    /// not depend on the page displaying the PNG. Screen captures stay intact.
    private func flattenWindowPNG(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let source = NSBitmapImageRep(data: data)?.cgImage,
              let context = CGContext(
                data: nil, width: source.width, height: source.height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return false }
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        appearance.nsAppearance?.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(rect)
        }
        context.draw(source, in: rect)
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return false }
        do {
            try png.write(to: url, options: Data.WritingOptions.atomic)
            return true
        } catch {
            return false
        }
    }

    /// Names each shot, its size and how it was taken — and says so when two
    /// come out identical, which is what a capture racing the compositor looks
    /// like from the outside.
    private func record(name: String, url: URL, how: String) {
        let data = (try? Data(contentsOf: url)) ?? Data()
        let digest = "\(data.count):\(data.hashValue)"
        if let twin = digests.first(where: { $0.value == digest })?.key {
            // Deliberately does not guess why. The first time this fired it was
            // a capture racing the compositor; the second time it was two shots
            // that could never have differed. Both are worth failing on.
            failures.append("\(name): byte-for-byte identical to \(twin) — one of them is not what it claims")
        }
        digests[name] = digest
        print("  \(name).png  \(data.count) bytes, via \(how)")
    }

    /// The menu bar, cropped to the right-hand end where the item lives.
    private func captureMenuBar(_ name: String) {
        guard let screen = NSScreen.main else {
            failures.append("\(name): no screen to photograph")
            return
        }
        // The menu bar is what the screen has that its visible area does not.
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        // Wide enough to show the item among its neighbours and the clock,
        // which is the context that says whether it reads at a glance.
        let width = min(CGFloat(460), screen.frame.width)
        let right = itemFrame.map { min($0.maxX + 12, screen.frame.maxX) } ?? screen.frame.maxX
        let rect = NSRect(
            x: max(screen.frame.minX, right - width), y: 0, width: width, height: barHeight)
        captureRegion(rect, name)
    }

    private var itemFrame: NSRect? { statusItem.itemFrame }

    /// The whole main display — the item, the popover and the distance between
    /// them, which no window shot can show.
    private func captureScreen(_ name: String) {
        guard let screen = NSScreen.main else {
            failures.append("\(name): no screen to photograph")
            return
        }
        captureRegion(NSRect(origin: .zero, size: screen.frame.size), name)
    }

    /// `screencapture -R` takes a rectangle whose origin is the *top* left of
    /// the main display, unlike every NSScreen coordinate, so callers here pass
    /// one already in those terms.
    private func captureRegion(_ rect: NSRect, _ name: String) {
        guard let directory else { return }
        let url = directory.appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let arguments = [
            "-x", "-R\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))",
            url.path,
        ]
        guard run(screencaptureWith: arguments), fileLooksLikeAnImage(url) else {
            failures.append("\(name): the screen could not be photographed")
            return
        }
        record(
            name: name, url: url,
            how: "screencapture -R \(Int(rect.origin.x)),\(Int(rect.origin.y))"
                + " \(Int(rect.width))×\(Int(rect.height))")
    }

    /// What the compositor has on screen for this window — material, arrow,
    /// shadow and all. `-o` drops the drop shadow, which otherwise pads every
    /// shot with a wide transparent margin.
    private func screencapture(_ window: NSWindow, to url: URL) -> Bool {
        run(screencaptureWith: ["-x", "-o", "-l\(window.windowNumber)", url.path])
            && fileLooksLikeAnImage(url)
    }

    private func run(screencaptureWith arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }

    /// `screencapture` exits 0 having written nothing when the window server
    /// declines, so the file has to be looked at rather than the status code.
    private func fileLooksLikeAnImage(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return ((attributes?[.size] as? Int) ?? 0) > 1024
    }

    /// The window drawing itself, with no window server involved. Loses the
    /// material behind the popover and its arrow; keeps every real control.
    private func drawIntoBitmap(_ window: NSWindow, to url: URL) -> Bool {
        guard let view = window.contentView else { return false }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let representation = view.bitmapImageRepForCachingDisplay(in: bounds)
        else { return false }

        view.cacheDisplay(in: bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
