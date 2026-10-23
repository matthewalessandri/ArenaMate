import AppKit
import SwiftUI

@main
struct ArenaMateApplication: App {
    @StateObject private var store = DraftStore()

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
            CommandGroup(replacing: .newItem) {
                Button("New Arena Draft") { store.newDraft() }.keyboardShortcut("n")
                Button("Undo Last Pick") { store.undoPick() }.keyboardShortcut("z")
            }
        }
    }
}
