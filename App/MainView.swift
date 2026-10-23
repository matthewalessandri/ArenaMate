import SwiftUI
import UniformTypeIdentifiers

private enum Theme {
    static let backdrop = Color(red: 0.055, green: 0.065, blue: 0.093)
    static let panel = Color(red: 0.105, green: 0.119, blue: 0.160)
    static let raised = Color(red: 0.145, green: 0.160, blue: 0.211)
    static let accent = Color(red: 0.38, green: 0.70, blue: 1.0)
    static let gold = Color(red: 0.99, green: 0.78, blue: 0.38)
    static let muted = Color(red: 0.59, green: 0.64, blue: 0.72)
}

struct MainView: View {
    @ObservedObject var store: DraftStore
    @State private var importingRatings = false
    @State private var importingScreenshot = false
    @State private var wantsReset = false
    private let classes = ["DEATHKNIGHT", "DEMONHUNTER", "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"]

    var body: some View {
        HStack(spacing: 0) {
            controls
                .frame(width: 257)
                .background(Theme.panel)
            Divider().overlay(.white.opacity(0.07))
            VStack(alignment: .leading, spacing: 20) {
                heading
                cardPanel
                footer
                history
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.backdrop)
        .fileImporter(isPresented: $importingRatings, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            if case .success(let url) = result { store.importRatings(at: url) }
        }
        .fileImporter(isPresented: $importingScreenshot, allowedContentTypes: [.png, .jpeg, .tiff]) { result in
            if case .success(let url) = result { store.testScreenshot(url) }
        }
        .confirmationDialog("Start a new draft?", isPresented: $wantsReset) {
            Button("Clear current deck", role: .destructive) { store.newDraft() }
        } message: { Text("This clears your saved picks.") }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.title2).foregroundStyle(Theme.gold)
                    Text("ARENAMATE").font(.headline.weight(.heavy)).tracking(1.7)
                }.padding(.bottom, 7)

                VStack(alignment: .leading, spacing: 9) {
                    sidebarTitle("HERO CLASS")
                    Picker("", selection: Binding(get: { store.playerClass }, set: { store.selectClass($0) })) {
                        ForEach(classes, id: \.self) { cls in
                            Text(cls.replacingOccurrences(of: "DEMONHUNTER", with: "DEMON HUNTER")
                                .replacingOccurrences(of: "DEATHKNIGHT", with: "DEATH KNIGHT").capitalized).tag(cls)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 12) {
                    sidebarTitle("LIVE DETECTION")
                    actionRow("Screen OCR", icon: "viewfinder", enabled: store.isScanning) {
                        if store.isScanning { store.stopScreenScan() } else { store.startScreenScan() }
                    }
                    Text(store.scanStatus).font(.caption2).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Circle().fill(store.screenPermissionGranted ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(store.screenPermissionGranted ? "Screen access authorized" : "Screen access not authorized")
                            .font(.caption2).foregroundStyle(Theme.muted)
                    }
                    if !store.screenPermissionGranted {
                        Button("Request screen access…") { store.requestScreenPermission() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    Button("Recheck permission") { _ = store.checkScreenPermission() }
                        .buttonStyle(.bordered).controlSize(.small)
                    if !store.scanDetails.isEmpty {
                        Text(store.scanDetails).font(.caption2).foregroundStyle(Theme.muted.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Test screenshot…") { importingScreenshot = true }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("Copy OCR report") { store.copyScanDiagnostics() }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("Save screenshot + OCR report…") { store.saveScanDiagnostics() }
                        .buttonStyle(.bordered).controlSize(.small)
                    Text("The report is local. Only Hearthstone's window is captured; no screen data is uploaded.")
                        .font(.caption2).foregroundStyle(Theme.muted)
                    Divider().overlay(.white.opacity(0.08))
                    actionRow("Hearthstone logs", icon: "doc.text.magnifyingglass", enabled: store.isWatchingLogs) {
                        if store.isWatchingLogs { store.stopLogWatcher() } else { store.startLogWatcher() }
                    }
                    Text(store.logStatus).font(.caption2).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Enable Arena logging (optional)…") { store.enableArenaLogs() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent)
                    if !store.logSetupStatus.isEmpty {
                        Text(store.logSetupStatus).font(.caption2).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Logs are optional; screen recognition works independently.")
                        .font(.caption2).foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 12) {
                    sidebarTitle("DRAFT OVERLAY")
                    actionRow("Floating overlay", icon: "rectangle.on.rectangle", enabled: store.overlayVisible) {
                        store.showOverlay()
                    }
                    Text("Keep Hearthstone in Windowed or Borderless mode.")
                        .font(.caption2).foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 12) {
                    sidebarTitle("CARD DATA")
                    HStack {
                        Text("Catalog").foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(store.cardCount)").monospacedDigit()
                    }.font(.caption)
                    Button("Refresh cards") { Task { await store.refreshCards() } }
                        .buttonStyle(.bordered).controlSize(.small)
                    HStack {
                        Text("Imported ratings").foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(store.ratingsCount)").monospacedDigit()
                    }.font(.caption)
                    Button("Import tier ratings CSV…") { importingRatings = true }
                        .buttonStyle(.bordered).controlSize(.small)
                    Text("Without imported ratings, scores are estimates—not HearthArena ratings.")
                        .font(.caption2).foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 11) {
                    sidebarTitle("PREFERENCES")
                    Toggle("Auto-record log picks", isOn: Binding(
                        get: { store.autoRecordLogPicks },
                        set: { store.autoRecordLogPicks = $0; UserDefaults.standard.set($0, forKey: "arena.autopicks") }
                    )).font(.caption)
                    Toggle("Show numeric scores", isOn: Binding(
                        get: { store.showScores },
                        set: { store.showScores = $0; UserDefaults.standard.set($0, forKey: "arena.showscores") }
                    )).font(.caption)
                }

                Text("Unofficial fan-made companion · No game input or memory access")
                    .font(.caption2).foregroundStyle(Theme.muted).padding(.top, 12)
            }.padding(20)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Arena draft").font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("Choose stronger cards. Build a more balanced deck.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("\(store.picks.count) / 30")
                    .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.gold)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(Theme.gold).frame(width: geo.size.width * CGFloat(store.picks.count) / 30)
                }
            }.frame(height: 6)
        }
    }

    private var cardPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CURRENT CHOICES").font(.caption.weight(.heavy)).tracking(1.4)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(store.sourceLabel).font(.caption).foregroundStyle(Theme.muted)
                Button("Demo offer") { store.loadDemoOffer() }
                    .buttonStyle(.borderless).font(.caption)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    cardColumn(index)
                }
            }
            if let best = store.recommendedIndex {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.gold).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RECOMMENDATION: CARD \(best + 1)")
                            .font(.caption.bold()).foregroundStyle(Theme.gold)
                        Text(store.choices[best].matched?.name ?? "")
                            .font(.headline)
                        if let detail = store.score(at: best) {
                            Text(detail.reasons.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    Button("Pick \(best + 1)") { store.recordPick(best) }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                }.padding(13)
                    .background(Theme.gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.23)))
            } else {
                Label("Open an Arena draft, or enter three card names to get a recommendation.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Theme.muted).padding(.vertical, 8)
            }
        }
    }

    private func cardColumn(_ index: Int) -> some View {
        let choice = store.choices[index]
        let detail = store.score(at: index)
        let isBest = store.recommendedIndex == index
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("0\(index + 1)").font(.title3.monospacedDigit().bold())
                    .foregroundStyle(isBest ? Theme.gold : Theme.muted)
                Spacer()
                if isBest {
                    Label("BEST", systemImage: "star.fill")
                        .font(.caption2.bold()).foregroundStyle(Theme.gold)
                }
            }
            TextField("Card name", text: Binding(
                get: { store.choices[index].rawName },
                set: { store.inputName(at: index, value: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.subheadline)
            Text(choice.matched?.name ?? "Waiting for card…")
                .font(.system(.headline, design: .rounded)).lineLimit(2)
                .frame(height: 45, alignment: .topLeading)
            if let card = choice.matched {
                HStack(spacing: 6) {
                    statTag("\(card.cost ?? 0) MANA")
                    statTag((card.type ?? "CARD").capitalized)
                }
                if let detail {
                    HStack(alignment: .firstTextBaseline) {
                        if store.showScores {
                            Text("\(Int(detail.total.rounded()))")
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundStyle(isBest ? Theme.gold : .white)
                        } else {
                            Text(isBest ? "TOP PICK" : "—")
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        Text(detail.label).font(.caption2).foregroundStyle(Theme.muted)
                    }.padding(.top, 8)
                    Text(detail.reasons.joined(separator: ", "))
                        .font(.caption).foregroundStyle(Theme.muted)
                        .lineLimit(3).frame(height: 48, alignment: .topLeading)
                }
            } else {
                Text("Enter the exact name, or enable scanning")
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer(minLength: 65)
            }
            Button("Select this card") { store.recordPick(index) }
                .buttonStyle(.borderedProminent)
                .tint(isBest ? Theme.accent : Theme.raised)
                .frame(maxWidth: .infinity)
                .disabled(choice.matched == nil || store.picks.count >= 30)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 276, alignment: .topLeading)
        .background(isBest ? Theme.panel.opacity(0.98) : Theme.panel, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15)
            .stroke(isBest ? Theme.gold.opacity(0.75) : .white.opacity(0.09), lineWidth: isBest ? 1.4 : 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle().fill(store.isScanning || store.isWatchingLogs ? .green : Theme.muted)
                    .frame(width: 7, height: 7)
                Text(store.status).font(.caption).foregroundStyle(Theme.muted)
                    .lineLimit(2)
                Spacer()
            }
            Text("OCR and log support are best-effort; always verify the three card names before picking. Imported ratings are not bundled.")
                .font(.caption2).foregroundStyle(Theme.muted)
        }
    }

    private var history: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("DRAFTED DECK").font(.caption.bold()).tracking(1.2).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Undo") { store.undoPick() }.disabled(store.picks.isEmpty)
                    Button("New draft") { wantsReset = true }
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(store.picks.enumerated()), id: \.element.id) { item in
                            let (index, pick) = item
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", index + 1))
                                    .foregroundStyle(Theme.muted).frame(width: 22)
                                Text(pick.card.name).lineLimit(1)
                                Spacer()
                                Text("\(pick.card.cost ?? 0)").foregroundStyle(Theme.muted)
                                Text("\(Int(pick.score.rounded()))")
                                    .monospacedDigit().foregroundStyle(Theme.gold)
                            }.font(.caption).padding(.vertical, 6)
                            Divider().opacity(0.2)
                        }
                        if store.picks.isEmpty {
                            Text("Your picks appear here automatically when confirmed in Arena.log, or when selected above.")
                                .font(.caption).foregroundStyle(Theme.muted)
                                .padding(14)
                        }
                    }
                }
            }
            .padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, minHeight: 230)

            VStack(alignment: .leading, spacing: 13) {
                Text("DECK STATS").font(.caption.bold()).tracking(1.2).foregroundStyle(Theme.muted)
                HStack {
                    Text("Average draft score").font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(store.averageScore.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.headline.monospacedDigit())
                }
                Text("Mana curve").font(.caption.bold())
                HStack(alignment: .bottom, spacing: 11) {
                    ForEach(store.manaBuckets, id: \.0) { item in
                        let (label, count) = item
                        VStack(spacing: 4) {
                            Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.accent.opacity(0.88))
                                .frame(height: CGFloat(max(5, count * 13)))
                            Text(label).font(.caption2).foregroundStyle(Theme.muted)
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 112, alignment: .bottom)
            }
            .padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .frame(width: 280, height: 230)
        }
    }

    private func statTag(_ text: String) -> some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 4)
            .background(Theme.raised, in: Capsule()).foregroundStyle(Theme.muted)
    }

    private func sidebarTitle(_ label: String) -> some View {
        Text(label).font(.caption2.bold()).tracking(1.5).foregroundStyle(Theme.muted)
    }

    private func actionRow(_ label: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 18)
                Text(label).font(.subheadline.weight(.medium))
                Spacer()
                Circle().fill(enabled ? Color.green : Color.gray.opacity(0.6))
                    .frame(width: 9, height: 9)
            }
            .padding(.horizontal, 11).padding(.vertical, 10)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}
