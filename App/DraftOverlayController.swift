import AppKit
import SwiftUI
import UniformTypeIdentifiers

// ArenaMate now has just one window: the compact, floating drafting UI.
// This adapter configures the SwiftUI WindowGroup's NSWindow without a second panel.
struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        // Higher window level and cross-application Space membership are needed
        // for a regular AppKit window to appear in native fullscreen Spaces.
        // Some games use exclusive fullscreen rendering that still blocks overlays.
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .fullScreenAuxiliary]
        window.level = .screenSaver
        window.isMovableByWindowBackground = true
        window.title = "ArenaMate"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.17, green: 0.105, blue: 0.066, alpha: 1)
        window.minSize = NSSize(width: 650, height: 195)
    }
}

// Legacy API retained to avoid breaking existing source references; there is no
// second floating NSPanel. Toggling the old overlay state is no longer needed.
@MainActor
final class DraftOverlayController {
    init(store: DraftStore) {}
    func show() {}
    func hide() {}
}

struct OverlayView: View {
    @ObservedObject var store: DraftStore
    @State private var showSettings = false
    @State private var showDraftHistory = false
    @State private var ratingsPicker = false
    @State private var confirmReset = false

    // Hearthstone-inspired tavern palette; deliberately compact rather than decorative.
    private let wood = Color(red: 0.17, green: 0.105, blue: 0.066)
    private let woodInset = Color(red: 0.24, green: 0.145, blue: 0.083)
    private let brass = Color(red: 0.87, green: 0.65, blue: 0.28)
    private let parchment = Color(red: 0.93, green: 0.82, blue: 0.61)
    private let ink = Color(red: 0.22, green: 0.14, blue: 0.09)

    private var hasOffer: Bool { store.choices.allSatisfy { $0.matched != nil } }
    // The UI is distraction-free when capture is running. Show a recovery
    // surface only when access is missing or the live scanner has failed.
    private var needsAttention: Bool {
        !store.screenPermissionGranted || store.scanFailureNeedsAttention
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("ARENAMATE")
                    .font(.system(size: 14, weight: .heavy, design: .serif))
                    .tracking(1.1).foregroundStyle(parchment)
                Spacer()
                Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                    .help("More settings")
                    .popover(isPresented: $showSettings) { settingsPopover }
                    .popover(isPresented: $showDraftHistory) { historyPopover }
            }
            .buttonStyle(.borderless)
            .padding(.top, 3)

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Button { if hasOffer { store.recordPick(i) } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Spacer(minLength: 2)
                            if store.recommendedIndex == i, hasOffer {
                                Image(systemName: "star.fill").foregroundStyle(brass)
                            }
                            if let score = store.score(at: i), store.showScores {
                                Text("\(Int(score.total.rounded()))")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(store.recommendedIndex == i ? ink : parchment)
                                    .monospacedDigit()
                            }
                        }
                        .frame(height: 22)
                        Text(store.choices[i].matched?.name ?? "Waiting for card…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(store.recommendedIndex == i && hasOffer ? ink : parchment.opacity(store.choices[i].matched == nil ? 0.6 : 1))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(store.recommendedIndex == i && hasOffer ? ink : parchment)
                    .background(store.recommendedIndex == i && hasOffer ? parchment : woodInset,
                                in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(store.recommendedIndex == i && hasOffer ? brass : brass.opacity(0.34), lineWidth: store.recommendedIndex == i && hasOffer ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasOffer)
                    .help(hasOffer ? "Click to record choice \(i + 1)" : "Waiting for three cards")
                }
            }

            if let explanation = store.recommendationExplanation {
                HStack(alignment: .center, spacing: 10) {
                    Image("InnkeeperPortrait")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(brass, lineWidth: 2))
                        .accessibilityLabel("The Innkeeper")
                    Text(explanation)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(parchment)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(woodInset, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(brass.opacity(0.40), lineWidth: 1))
            }

            if needsAttention {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(brass)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.screenPermissionGranted
                             ? (store.hearthstoneIsRunning ? "Hearthstone window unavailable" : "Hearthstone not running")
                             : "Screen access needed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(parchment)
                        Text(store.screenPermissionGranted
                             ? (store.hearthstoneIsRunning
                                ? "Make sure Hearthstone is visible, then retry the connection."
                                : "Please launch Hearthstone, then click Retry.")
                             : "Allow screen recording to identify Arena cards automatically.")
                            .font(.system(size: 10))
                            .foregroundStyle(parchment.opacity(0.82))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    if store.screenPermissionGranted {
                        Button("Retry") { store.startScreenScan() }
                    } else {
                        Button("Allow access") { store.requestScreenPermission() }
                        Button("Recheck") {
                            if store.checkScreenPermission() { store.startScreenScan() }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(woodInset, in: RoundedRectangle(cornerRadius: 9))
            }

        }
        .padding(13)
        .frame(minWidth: 650)
        .background(wood)
        .preferredColorScheme(.dark)
        .background(FloatingWindowConfigurator().frame(width: 0, height: 0))
        .fileImporter(isPresented: $ratingsPicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            if case .success(let url) = result { store.importRatings(at: url) }
        }
        .confirmationDialog("Clear this draft?", isPresented: $confirmReset) {
            Button("Start new draft", role: .destructive) { store.newDraft() }
        }
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Draft settings").font(.headline)
            HStack {
                Text("Class: " + store.playerClass.replacingOccurrences(of: "DEATHKNIGHT", with: "DEATH KNIGHT")
                    .replacingOccurrences(of: "DEMONHUNTER", with: "DEMON HUNTER").capitalized)
                Spacer()
                Text(store.classSource).foregroundStyle(.secondary).font(.caption2)
            }
            Text("Class is detected from the game when reliable. Use the override only if recognition fails.")
                .font(.caption2).foregroundStyle(.secondary)
            Picker("Class override", selection: Binding(get: { store.playerClass }, set: { store.selectClass($0) })) {
                ForEach(HeroClassRecognition.classKeys, id: \.self) { key in
                    Text(key.replacingOccurrences(of: "DEATHKNIGHT", with: "DEATH KNIGHT")
                        .replacingOccurrences(of: "DEMONHUNTER", with: "DEMON HUNTER").capitalized).tag(key)
                }
            }
            Button("Show drafted cards") { showSettings = false; showDraftHistory = true }
            Toggle("Show numeric scores", isOn: $store.showScores)
            Toggle("Auto-record log picks", isOn: $store.autoRecordLogPicks)
            Divider()
            HStack {
                Button("Refresh card data") { Task { await store.refreshCards() } }
                Text("\(store.cardCount) cards").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button("Import ratings CSV") { ratingsPicker = true }
                Text("\(store.ratingsCount) ratings").font(.caption2).foregroundStyle(.secondary)
            }
            Button("Enable Arena logging") { store.enableArenaLogs() }
            Button("Copy OCR report") { store.copyScanDiagnostics() }
            Button("New draft") { confirmReset = true }
            if !store.logStatus.isEmpty { Text(store.logStatus).font(.caption2).foregroundStyle(.secondary) }
            if !store.status.isEmpty { Text(store.status).font(.caption2).foregroundStyle(.secondary) }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .padding(15).frame(width: 280, alignment: .leading)
    }

    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Drafted cards (\(store.picks.count)/30)").font(.headline)
                Spacer()
                Button("Undo") { store.undoPick() }.disabled(store.picks.isEmpty)
                    .buttonStyle(.bordered).controlSize(.small)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(store.picks.enumerated()), id: \.offset) { index, pick in
                        Text("\(index + 1). \(pick.card.name)").font(.caption)
                    }
                    if store.picks.isEmpty { Text("No cards drafted yet.").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 280)
        }.padding(14).frame(width: 260)
    }
}
