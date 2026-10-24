import AppKit
import Combine
import SwiftUI
import Sparkle

@main
struct ArenaMateApplication: App {
    @NSApplicationDelegateAdaptor(ArenaMateAppDelegate.self) private var appDelegate

    var body: some Scene {
        // The visible UI is a single non-activating NSPanel, owned by the
        // delegate. Keep a scene for SwiftUI's application command integration.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {}
                ArenaMateCommands(store: appDelegate.store, updates: appDelegate.updates)
            }
    }
}

private struct ArenaMateCommands: Commands {
    @ObservedObject var store: DraftStore
    @ObservedObject var updates: AppUpdates

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
            Toggle("Automatically Check for Updates", isOn: Binding(
                get: { updates.automaticallyChecksForUpdates },
                set: { updates.setAutomaticChecks($0) }
            ))
            .disabled(!updates.isConfigured)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Arena Draft") { store.newDraft() }.keyboardShortcut("n")
            Button("Undo Last Pick") { store.undoPick() }.keyboardShortcut("z")
        }
    }
}

private struct PanelContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 250
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private final class DraftFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ArenaMateAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = DraftStore()
    let updates = AppUpdates(startingUpdater: !ProcessInfo.processInfo.arguments.contains("--smoke-test"))
    private var panel: NSPanel?
    private var spaceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = DraftFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 670, height: 250),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "ArenaMate"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = .screenSaver
        panel.delegate = self
        let root = OverlayView(store: store)
            .environmentObject(updates)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: PanelContentHeight.self, value: geometry.size.height)
            })
            .onPreferenceChange(PanelContentHeight.self) { [weak panel] height in
                Task { @MainActor in
                    guard let panel, let content = panel.contentView, height.isFinite, height > 0 else { return }
                    guard content.bounds.width >= 650 else { return }
                    let chrome = panel.frame.height - panel.contentRect(forFrameRect: panel.frame).height
                    let target = max(panel.minSize.height, ceil(height) + chrome)
                    guard abs(panel.frame.height - target) > 1 else { return }
                    var frame = panel.frame
                    frame.origin.y += frame.height - target
                    frame.size.height = target
                    panel.setFrame(frame, display: true)
                }
            }
            .task { [store] in
                guard !ProcessInfo.processInfo.arguments.contains("--smoke-test") else { return }
                if store.cardCount == 0 { await store.refreshCards() }
                await store.refreshPerformanceRatings()
                if !store.isScanning && store.cardCount > 0 { store.startScreenScan() }
            }
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(x: 0, y: 0, width: 670, height: 250)
        panel.contentView = hostingView
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let panel = self?.panel, panel.isVisible, !panel.isMiniaturized else { return }
                // Restore z-order after entering a fullscreen Space without
                // activating ArenaMate or pulling focus away from Hearthstone.
                panel.orderFrontRegardless()
            }
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--smoke-test"), arguments.indices.contains(index + 1) {
            let report = URL(fileURLWithPath: arguments[index + 1])
            Task { await runStartupCheck(report: report) }
        }
    }

    private func runStartupCheck(report: URL) async {
        // Run the actual AppKit/SwiftUI lifecycle without capture permissions,
        // card downloads or updater dialogs on the macOS CI runner.
        guard let panel else { NSApp.terminate(nil); return }
        var previousHeight = panel.frame.height
        var stableSamples = 0
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if abs(panel.frame.height - previousHeight) < 1 { stableSamples += 1 }
            else { stableSamples = 0 }
            previousHeight = panel.frame.height
            if stableSamples >= 5 { break }
        }
        let checks = [
            "visible": panel.isVisible,
            "singleVisibleWindow": NSApp.windows.filter { $0.isVisible }.count == 1,
            "nonActivatingPanel": panel.styleMask.contains(.nonactivatingPanel),
            "staysVisibleWhenInactive": !panel.hidesOnDeactivate,
            "fullscreenAuxiliary": panel.collectionBehavior.contains(.fullScreenAuxiliary),
            "allSpaces": panel.collectionBehavior.contains(.canJoinAllSpaces),
            "stableLayout": stableSamples >= 5 && panel.frame.height >= 195 && panel.frame.height < 800,
            "captureNotStarted": !store.isScanning
        ]
        if checks["stableLayout"] != true {
            NSLog("Overlay layout failed to settle: frame=%@ content=%@ samples=%ld", NSStringFromRect(panel.frame), NSStringFromRect(panel.contentView?.bounds ?? .zero), stableSamples)
        }
        panel.performClose(nil)
        let closed = !panel.isVisible
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        var result = checks
        result["closeAndReopen"] = closed && panel.isVisible
        do {
            try JSONSerialization.data(withJSONObject: result, options: .sortedKeys).write(to: report)
        } catch { NSLog("Overlay startup report could not be written: %@", error.localizedDescription) }
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel?.isMiniaturized == true { panel?.deminiaturize(nil) }
        panel?.makeKeyAndOrderFront(nil)
        if !store.isScanning && store.cardCount > 0 { store.startScreenScan() }
        return false
    }

    func windowWillClose(_ notification: Notification) { store.stopScreenScan() }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopScreenScan()
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }
}

/// Keep a single updater alive for the app's lifetime. Local builds without the
/// release public key do not start Sparkle or show configuration-error dialogs.
@MainActor
final class AppUpdates: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    let isConfigured: Bool
    private let controller: SPUStandardUpdaterController?

    init(startingUpdater: Bool = true) {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = Data(base64Encoded: key)?.count == 32
        guard isConfigured && startingUpdater else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true,
            updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}
