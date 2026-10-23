import AppKit
import Combine
import SwiftUI
import Sparkle

@main
struct ArenaMateApplication: App {
    @StateObject private var store = DraftStore()
    @StateObject private var updates = AppUpdates()

    var body: some Scene {
        WindowGroup("ArenaMate") {
            OverlayView(store: store)
                .task {
                    if store.cardCount == 0 { await store.refreshCards() }
                    if !store.isScanning && store.cardCount > 0 { store.startScreenScan() }
                }
        }
        .defaultSize(width: 670, height: 250)
        .windowResizability(.contentSize)
        .commands {
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
}

/// Keep a single updater alive for the app's lifetime. Local builds without the
/// release public key do not start Sparkle or show configuration-error dialogs.
@MainActor
final class AppUpdates: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    let isConfigured: Bool
    private let controller: SPUStandardUpdaterController?

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = Data(base64Encoded: key)?.count == 32
        guard isConfigured else {
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
