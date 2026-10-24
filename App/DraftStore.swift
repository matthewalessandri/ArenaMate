import AppKit
import CoreGraphics
import Foundation
import SwiftUI

struct OfferedCard: Identifiable {
    let id: Int
    var rawName = ""
    var matched: ArenaCard?
    var confidence = 0.0
}

@MainActor
final class DraftStore: ObservableObject {
    @Published var picks: [DraftPick] = []
    @Published var choices = (0..<3).map { OfferedCard(id: $0) }
    @Published var playerClass: String = "MAGE"
    @Published var classSource = "Last used"
    @Published var status = "Loading card catalog…"
    @Published var logStatus = "Log watcher off"
    @Published var logSetupStatus = ""
    @Published var scanStatus = "Screen scanner off"
    @Published var scanDetails = ""
    @Published var isScanning = false
    @Published var scanFailureNeedsAttention = false
    @Published var screenPermissionGranted = CGPreflightScreenCaptureAccess()
    @Published var isWatchingLogs = false
    @Published var overlayVisible = false
    @Published var cardCount = 0
    @Published var ratingsCount = 0
    @Published var ratingSource = "Built-in estimates"
    @Published var showScores = true
    @Published var autoRecordLogPicks = true
    @Published var previewImage: NSImage?
    @Published var sourceLabel = "Manual entry"

    private var catalog = CatalogIndex(cards: [])
    private var importedRatings = ExternalRatings()
    private var scannerTask: Task<Void, Never>?
    private var logTask: Task<Void, Never>?
    private var overlay: DraftOverlayController?
    private var lastDetected = ""
    private var stableFrames = 0
    private let parser = ArenaLogParser()

    private var storeDir: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArenaMate", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    init() {
        if let data = try? Data(contentsOf: storeDir.appendingPathComponent("draft.json")),
           let saved = try? JSONDecoder().decode([DraftPick].self, from: data) { picks = saved }
        playerClass = UserDefaults.standard.string(forKey: "arena.class") ?? "MAGE"
        showScores = UserDefaults.standard.object(forKey: "arena.showscores") as? Bool ?? true
        autoRecordLogPicks = UserDefaults.standard.object(forKey: "arena.autopicks") as? Bool ?? true
        if let bytes = try? Data(contentsOf: storeDir.appendingPathComponent("arena-performance.json")),
           let loaded = try? JSONDecoder().decode(ExternalRatings.self, from: bytes) {
            importedRatings = loaded; updateRatingCount()
            ratingSource = "Recent Arena results"
        } else if let bytes = try? Data(contentsOf: storeDir.appendingPathComponent("ratings.csv")),
           let loaded = try? ExternalRatings.parseCSV(bytes) {
            importedRatings = loaded; updateRatingCount()
            ratingSource = "Imported ratings"
        }
        if let bytes = try? Data(contentsOf: storeDir.appendingPathComponent("cards.json")),
           let loaded = try? JSONDecoder().decode([ArenaCard].self, from: bytes) {
            installCards(loaded); status = "Using cached catalog; press Refresh for updated cards"
        }
    }

    private func updateRatingCount() {
        ratingsCount = importedRatings.byId.count + importedRatings.byName.count +
            importedRatings.byClassAndName.count + importedRatings.performanceByClassAndId.count
    }

    private func installCards(_ cards: [ArenaCard]) {
        // Keep one record per game ID. An Arena offered card can also be a noncollectible.
        catalog = CatalogIndex(cards: cards)
        cardCount = cards.count
        rematchChoices()
    }

    func refreshCards() async {
        status = "Downloading current Hearthstone cards…"
        do {
            let url = URL(string: "https://api.hearthstonejson.com/v1/latest/enUS/cards.json")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 50
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DownloadError.http }
            let decoded = try JSONDecoder().decode([ArenaCard].self, from: data)
            guard decoded.count > 500 else { throw DownloadError.empty }
            try data.write(to: storeDir.appendingPathComponent("cards.json"), options: .atomic)
            installCards(decoded)
            status = "Loaded \(cardCount) cards · Ready to scan"
        } catch {
            status = "Catalog update failed: \(error.localizedDescription)" + (cardCount > 0 ? " · Cached cards still available" : "")
        }
    }

    func refreshPerformanceRatings(force: Bool = false) async {
        let cacheURL = storeDir.appendingPathComponent("arena-performance.json")
        if !force, ratingsCount > 0,
           let modified = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) < 12 * 60 * 60 { return }
        do {
            let url = URL(string: "https://hsreplay.net/api/v1/arena/card_stats/free/?format=json")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 40
            request.setValue("ArenaMate/4.6 (+https://github.com/matthewalessandri/ArenaMate)",
                             forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DownloadError.http }
            let parsed = try ExternalRatings.parseHSReplay(data)
            let encoded = try JSONEncoder().encode(parsed)
            try encoded.write(to: cacheURL, options: .atomic)
            importedRatings = parsed
            updateRatingCount()
            ratingSource = "Recent Arena results"
            status = "Updated \(ratingsCount) class-specific Arena ratings"
        } catch {
            status = ratingsCount > 0
                ? "Arena ratings update failed; cached ratings remain active"
                : "Arena ratings unavailable; using built-in deck analysis"
        }
    }

    enum DownloadError: LocalizedError {
        case http, empty
        var errorDescription: String? {
            switch self { case .http: return "Card server returned an error"; case .empty: return "Card server returned an incomplete catalog" }
        }
    }

    func selectClass(_ value: String) {
        playerClass = value
        classSource = "Manual override"
        UserDefaults.standard.set(value, forKey: "arena.class")
        rematchChoices()
    }

    private func setDetectedClass(_ value: String) {
        guard HeroClassRecognition.classKeys.contains(value) else { return }
        if playerClass != value {
            playerClass = value
            UserDefaults.standard.set(value, forKey: "arena.class")
            rematchChoices()
        }
        classSource = "Auto-detected"
    }

    func importRatings(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try ExternalRatings.parseCSV(data)
            importedRatings = parsed
            updateRatingCount()
            ratingSource = "Imported ratings"
            try data.write(to: storeDir.appendingPathComponent("ratings.csv"), options: .atomic)
            status = "Imported \(ratingsCount) card ratings from CSV"
        } catch { status = "Could not import CSV: \(error.localizedDescription)" }
    }

    func inputName(at index: Int, value: String) {
        guard choices.indices.contains(index) else { return }
        choices[index].rawName = value
        let match = catalog.find(value, playerClass: playerClass)
        choices[index].matched = match?.card
        choices[index].confidence = match?.confidence ?? 0
        sourceLabel = "Manually edited"
    }

    func updateOffer(_ names: [String], source: String) {
        guard names.count == 3, picks.count < 30 else { return }
        let matching = names.map { catalog.find($0, playerClass: playerClass) }
        guard matching.allSatisfy({ $0 != nil }) else {
            status = "Detected text, but some cards could not be matched. Try manual correction."
            return
        }
        if names == choices.map(\.rawName) { return }
        choices = (0..<3).map { index in
            OfferedCard(id: index, rawName: matching[index]!.card.name,
                        matched: matching[index]!.card, confidence: matching[index]!.confidence)
        }
        sourceLabel = source
        status = "Detected three Arena cards (\(source))"
    }

    private func rematchChoices() {
        for i in choices.indices {
            let match = catalog.find(choices[i].rawName, playerClass: playerClass)
            choices[i].matched = match?.card
            choices[i].confidence = match?.confidence ?? 0
        }
    }

    func score(at index: Int) -> ScoreDetail? {
        guard choices.indices.contains(index), let card = choices[index].matched else { return nil }
        return DraftScorer.score(card, picks: picks, ratings: importedRatings, playerClass: playerClass)
    }

    var recommendedIndex: Int? {
        let scored = choices.indices.compactMap { index -> (Int, Double)? in
            guard let score = score(at: index) else { return nil }
            return (index, score.total)
        }
        guard scored.count == 3 else { return nil }
        return scored.max { $0.1 < $1.1 }?.0
    }

    /// Explain the same deck needs and synergies used by the scorer.
    var recommendationExplanation: String? {
        let offers = choices.compactMap(\.matched)
        return DraftScorer.recommendation(offers: offers, picks: picks,
                                          ratings: importedRatings, playerClass: playerClass)
    }

    func recordPick(_ index: Int, auto: Bool = false) {
        guard picks.count < 30, let score = score(at: index), let card = choices[index].matched else { return }
        picks.append(DraftPick(card: card, score: score.total))
        persistDraft()
        choices = (0..<3).map { OfferedCard(id: $0) }
        lastDetected = ""; stableFrames = 0
        status = "\(auto ? "Auto-recorded" : "Recorded") \(card.name) · Pick \(picks.count)/30"
    }

    func undoPick() {
        guard !picks.isEmpty else { return }
        let last = picks.removeLast()
        persistDraft()
        status = "Undid \(last.card.name)"
    }

    func newDraft() {
        picks = []
        choices = (0..<3).map { OfferedCard(id: $0) }
        lastDetected = ""; stableFrames = 0
        persistDraft(); status = "New draft ready"
    }

    private func persistDraft() {
        if let data = try? JSONEncoder().encode(picks) {
            try? data.write(to: storeDir.appendingPathComponent("draft.json"), options: .atomic)
        }
    }

    var averageScore: Double? {
        guard !picks.isEmpty else { return nil }
        return picks.map(\.score).reduce(0, +) / Double(picks.count)
    }

    var manaBuckets: [(String, Int)] {
        let costs = picks.map { $0.card.cost ?? 0 }
        return [("0–1", costs.filter { $0 <= 1 }.count),
                ("2", costs.filter { $0 == 2 }.count),
                ("3", costs.filter { $0 == 3 }.count),
                ("4", costs.filter { $0 == 4 }.count),
                ("5", costs.filter { $0 == 5 }.count),
                ("6+", costs.filter { $0 >= 6 }.count)]
    }

    /// This is read-only: unlike CGRequestScreenCaptureAccess it never opens a
    /// macOS permission dialog. Check before *every* ScreenCaptureKit call.
    @discardableResult
    func checkScreenPermission() -> Bool {
        screenPermissionGranted = CGPreflightScreenCaptureAccess()
        if !screenPermissionGranted {
            scanFailureNeedsAttention = true
            scanStatus = "Screen recording permission isn't active for this app build. Live scanning is paused."
            scanDetails = "Use Request screen access below, grant access, quit ArenaMate, and reopen it."
        }
        return screenPermissionGranted
    }

    /// The only code path allowed to request macOS screen-recording permission.
    /// This is exclusively connected to a deliberate button press (never a timer).
    func requestScreenPermission() {
        // A stale scanning flag must never make the permission button inert.
        if isScanning { stopScreenScan() }
        if CGPreflightScreenCaptureAccess() {
            screenPermissionGranted = true
            scanFailureNeedsAttention = false
            scanStatus = "Screen access is granted. Restarting scanner…"
            scanDetails = ""
            startScreenScan()
            return
        }

        // The macOS consent dialog may only be shown once for a given app
        // identity. Subsequent calls can return false without displaying UI.
        // Always open the authoritative settings pane as a fallback.
        let granted = CGRequestScreenCaptureAccess()
        screenPermissionGranted = granted || CGPreflightScreenCaptureAccess()
        if screenPermissionGranted {
            scanStatus = "Permission granted. Quit and reopen ArenaMate if scanning does not start."
            scanDetails = ""
            startScreenScan()
        } else {
            scanFailureNeedsAttention = true
            scanStatus = "Enable ArenaMate in System Settings → Screen & System Audio Recording."
            scanDetails = "Then fully quit and reopen ArenaMate. Don't rebuild the app between granting access and testing."
            openScreenRecordingSettings()
        }
    }

    private func openScreenRecordingSettings() {
        // System Settings URL is supported on recent macOS releases; fall back
        // to opening System Settings when macOS ignores the deep link.
        let deepLink = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        if !NSWorkspace.shared.open(deepLink) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
                configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }


    /// Process discovery is independent of ScreenCaptureKit window discovery.
    /// A running game in exclusive fullscreen can be invisible to SCShareableContent.
    var hearthstoneIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            let name = (app.localizedName ?? "").lowercased()
            let binary = app.executableURL?.lastPathComponent.lowercased() ?? ""
            return name == "hearthstone" || binary == "hearthstone"
        }
    }

    func startScreenScan() {
        guard !isScanning else { return }
        guard cardCount > 0 else { status = "Update the card database first"; return }
        // Never enter ScreenCaptureKit while the current binary is unauthorized.
        // Otherwise SCShareableContent can trigger a new alert every two seconds.
        guard checkScreenPermission() else { return }
        isScanning = true
        scanFailureNeedsAttention = false
        scanStatus = "Scanning Hearthstone window…"
        scanDetails = ""
        scannerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                // Permission can change while the app is open. Stop without
                // invoking ScreenCaptureKit again if that happens.
                guard self.checkScreenPermission() else {
                    self.isScanning = false
                    self.scanFailureNeedsAttention = true
                    self.scannerTask = nil
                    break
                }
                do {
                    let capture = try await GameScreenOCR.scan(catalog: self.catalog, playerClass: self.playerClass)
                    guard !Task.isCancelled else { break }
                    self.scanFailureNeedsAttention = false
                    if let detected = capture.detectedClass { self.setDetectedClass(detected) }
                    self.scanStatus = capture.message
                    self.scanDetails = "\(capture.windowName) · \(capture.recognizedLines.count) OCR lines"
                    if let names = capture.names {
                        if names.joined(separator: "|") == self.lastDetected { self.stableFrames += 1 }
                        else { self.lastDetected = names.joined(separator: "|"); self.stableFrames = 1 }
                        // Present a complete verified offer immediately. Subsequent frames
                        // simply refresh it if the actual choice set changes.
                        self.updateOffer(names, source: "On-screen OCR")
                    } else {
                        self.stableFrames = 0; self.lastDetected = ""
                        // Hover previews and draft animations can obscure a title.
                        // Keep the last complete offer until another complete trio
                        // replaces it. Recording a pick or resetting the draft
                        // still clears the choices explicitly.
                    }
                } catch {
                    // Pause on the first failure. Retrying SCShareableContent
                    // automatically risks repeatedly showing the system alert.
                    self.scanStatus = "Screen capture failed: \(error.localizedDescription)"
                    self.scanDetails = "Keep Hearthstone open in Windowed or Borderless mode. ArenaMate is retrying automatically."
                    // A missing window (e.g. during a Space transition) is
                    // recoverable and does not imply missing screen permission.
                    // Do not repeatedly retry permission or generic capture errors.
                    if let scanError = error as? GameScreenOCR.ScanError,
                       case .windowNotFound = scanError {
                        self.scanFailureNeedsAttention = true
                        try? await Task.sleep(for: .seconds(2))
                        continue
                    }
                    self.scanFailureNeedsAttention = true
                    self.isScanning = false
                    self.scannerTask = nil
                    break
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func testScreenshot(_ url: URL) {
        stopScreenScan() // Prevent next live frame from overwriting the screenshot test.
        do {
            let result = try GameScreenOCR.scanScreenshot(at: url, catalog: catalog, playerClass: playerClass)
            if let detected = result.detectedClass { setDetectedClass(detected) }
            scanStatus = result.message
            scanDetails = result.windowName
            if let names = result.names { updateOffer(names, source: "Screenshot test") }
        } catch { scanStatus = "Screenshot test failed: \(error.localizedDescription)" }
    }

    func saveScanDiagnostics() {
        do {
            let folder = try GameScreenOCR.saveDiagnostic()
            NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent("recognition.txt")])
            status = "Saved screen diagnostics and opened the folder in Finder"
        } catch { status = "Can't save diagnostic: \(error.localizedDescription)" }
    }

    func copyScanDiagnostics() {
        guard let text = GameScreenOCR.diagnosticText() else {
            status = "No screen capture yet. Enable OCR or test a screenshot first."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Copied the card OCR report. Paste it into ChatGPT to troubleshoot."
    }

    func stopScreenScan() {
        scannerTask?.cancel(); scannerTask = nil
        isScanning = false; scanStatus = "Screen scanner off"
    }

    func startLogWatcher() {
        guard !isWatchingLogs else { return }
        isWatchingLogs = true
        logStatus = "Looking for Arena.log…"
        logTask = Task { [weak self] in
            let monitor = ArenaLogWatcher()
            while let self, !Task.isCancelled {
                let result = monitor.poll()
                if let path = result.path { self.logStatus = "Watching " + path.lastPathComponent }
                else { self.logStatus = "No Arena.log yet — try enabling logs and restarting Hearthstone" }
                for line in result.lines {
                    guard let event = self.parser.parse(line) else { continue }
                    switch event {
                    case .offered(let options):
                        self.updateOffer(options, source: "Arena.log")
                    case .selected(let name, let cardID):
                        if self.autoRecordLogPicks {
                            let index = self.choices.firstIndex {
                                guard let card = $0.matched else { return false }
                                return card.name.caseInsensitiveCompare(name) == .orderedSame || (cardID != nil && card.id.caseInsensitiveCompare(cardID!) == .orderedSame)
                            }
                            if let index { self.recordPick(index, auto: true) }
                        }
                    case .draftStarted:
                        self.logStatus = "Draft session detected"
                    }
                }
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    func stopLogWatcher() {
        logTask?.cancel(); logTask = nil; isWatchingLogs = false
        logStatus = "Log watcher off"
    }

    func enableArenaLogs() {
        do {
            try ArenaLogWatcher.configureArenaLog()
            logSetupStatus = "log.config updated. Quit and restart Hearthstone to activate logging."
            status = logSetupStatus
        } catch {
            logSetupStatus = "Can't update log.config: \(error.localizedDescription)"
            status = logSetupStatus
        }
    }

    func showOverlay() {
        if overlayVisible { overlay?.hide(); overlay = nil; overlayVisible = false }
        else { overlay = DraftOverlayController(store: self); overlay?.show(); overlayVisible = true }
    }

    func loadDemoOffer() {
        let demo: [ArenaCard] = [
            ArenaCard(id: "CS2_024", name: "Frostbolt", cost: 2, type: "SPELL", cardClass: "MAGE", text: "Deal 3 damage to a character and Freeze it."),
            ArenaCard(id: "CS2_029", name: "Fireball", cost: 4, type: "SPELL", cardClass: "MAGE", text: "Deal 6 damage."),
            ArenaCard(id: "CS2_028", name: "Blizzard", cost: 6, type: "SPELL", cardClass: "MAGE", text: "Deal 2 damage to all enemy minions and Freeze them.")
        ]
        choices = demo.enumerated().map { index, card in
            OfferedCard(id: index, rawName: card.name,
                        matched: catalog.find(card.id)?.card ?? card, confidence: 1)
        }
        sourceLabel = "Demo cards · Not a live draft"
        status = "Demo loaded — these may not be in the current Arena rotation"
    }
}
