import Foundation

public struct DraftPick: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var card: ArenaCard
    public var score: Double
    public var selectedAt: Date
    public init(card: ArenaCard, score: Double) {
        self.id = UUID(); self.card = card; self.score = score; self.selectedAt = Date()
    }
}

public struct ScoreFactor: Sendable {
    public let key: String
    public let description: String
    public let points: Double
}

public struct ScoreDetail: Sendable {
    public let total: Double
    public let base: Double
    public let label: String
    public let reasons: [String]
    public let hasExternalRating: Bool
    public let explanation: String
    public let factors: [ScoreFactor]
    public let hasDeckReason: Bool
    public let caution: String?
}

public struct ExternalRatings: Sendable {
    public var byId: [String: Double] = [:]
    public var byClassAndName: [String: Double] = [:]
    public var byName: [String: Double] = [:]

    public init() {}

    public func score(card: ArenaCard, playerClass: String) -> Double? {
        if let value = byId[card.id.uppercased()] { return value }
        if let value = card.dbfId.flatMap({ byId[String($0)] }) { return value }
        let name = CatalogIndex.normalize(card.name)
        let cls = playerClass.uppercased()
        return byClassAndName["\(cls)|\(name)"] ?? byName[name]
    }

    public static func parseCSV(_ data: Data) throws -> ExternalRatings {
        guard let text = String(data: data, encoding: .utf8) else { throw CSVError.encoding }
        let rows = csvRows(text).filter { !$0.isEmpty && !$0.allSatisfy { $0.isEmpty } }
        guard let header = rows.first else { throw CSVError.header }
        let columns = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let scoreCol = columns.firstIndex(where: { ["score", "rating", "value"].contains($0) }) else { throw CSVError.header }
        let nameCol = columns.firstIndex(of: "name") ?? columns.firstIndex(of: "card")
        let idCol = columns.firstIndex(of: "id") ?? columns.firstIndex(of: "cardid")
        let clsCol = columns.firstIndex(of: "class") ?? columns.firstIndex(of: "cardclass")
        guard nameCol != nil || idCol != nil else { throw CSVError.header }
        var result = ExternalRatings()
        for row in rows.dropFirst() {
            guard scoreCol < row.count, let score = Double(row[scoreCol].trimmingCharacters(in: .whitespaces)), score.isFinite, (0...100).contains(score) else { continue }
            if let idCol, idCol < row.count, !row[idCol].isEmpty { result.byId[row[idCol].uppercased()] = score }
            if let nameCol, nameCol < row.count, !row[nameCol].isEmpty {
                let name = CatalogIndex.normalize(row[nameCol])
                if let clsCol, clsCol < row.count, !row[clsCol].isEmpty {
                    result.byClassAndName["\(row[clsCol].uppercased())|\(name)"] = score
                } else { result.byName[name] = score }
            }
        }
        return result
    }

    public enum CSVError: LocalizedError {
        case encoding, header
        public var errorDescription: String? {
            switch self {
            case .encoding: return "This CSV is not UTF-8."
            case .header: return "CSV needs name,score columns (optional class or id)."
            }
        }
    }

    private static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if ch == "," && !quoted { row.append(field); field = "" }
            else if (ch == "\n" || ch == "\r") && !quoted {
                row.append(field); rows.append(row); row = []; field = ""
            } else { field.append(ch) }
            i += 1
        }
        if !row.isEmpty || !field.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

public enum DraftScorer {
    public static func score(_ card: ArenaCard, picks: [DraftPick], ratings: ExternalRatings,
                             playerClass: String) -> ScoreDetail {
        let imported = ratings.score(card: card, playerClass: playerClass)
        let estimate = heuristic(card)
        let base = imported ?? estimate.total
        var diff = 0.0, reasons: [String] = []
        var insights: [(priority: Double, text: String)] = []
        var cautions: [(priority: Double, text: String)] = []
        let cost = card.cost ?? 0
        let minions = picks.map(\.card).filter { $0.type == "MINION" }
        let early = picks.filter { ($0.card.cost ?? 0) <= 2 && $0.card.type == "MINION" }.count
        let expensive = picks.filter { ($0.card.cost ?? 0) >= 6 }.count
        let effectiveTarget = max(4, Int(Double(max(1, picks.count)) * 0.26))
        if card.type == "MINION" && (1...2).contains(cost) && early < effectiveTarget {
            diff += 3; reasons.append("Helps early-game curve")
            insights.append((3, picks.isEmpty
                ? "I'd start with this early play to help build a smooth curve."
                : "You're short on early minions. This gives you another play before turn three."))
        }
        if cost >= 6 && expensive >= max(2, picks.count / 7) {
            diff -= 4; reasons.append("Already heavy at 6+ mana")
            cautions.append((4, "Your deck is already heavy at six mana and up, so watch your curve."))
        }
        let text = card.plainText.lowercased()
        let allTexts = picks.map { $0.card.plainText.lowercased() }
        let spellCount = picks.filter { $0.card.type == "SPELL" }.count
        let damageSpells = picks.filter {
            $0.card.type == "SPELL" && $0.card.plainText.lowercased().contains("deal") &&
                $0.card.plainText.lowercased().contains("damage")
        }
        if text.contains("spell damage"), damageSpells.count >= 2, let partner = damageSpells.first {
            diff += 2; reasons.append("Spell-damage support")
            insights.append((4, "Spell Damage helps the damage spells you've drafted, including \(partner.card.name)."))
        }
        if text.contains("spell") && (text.contains("whenever you cast") || text.contains("after you cast")) {
            if spellCount >= 5 {
                diff += 3; reasons.append("Fits existing spells")
                insights.append((3, "You've already drafted \(spellCount) spells to help trigger this card's spell payoff."))
            }
            else if spellCount < 2 {
                diff -= 3; reasons.append("Few spells for payoff")
                cautions.append((3, "You'll want more spells to get consistent value from its payoff."))
            }
        }
        let cardTribes = card.tribes
        for tribe in cardTribes.sorted() {
            let matched = minions.filter { $0.tribes.contains(tribe) }.count
            if matched >= 3 { diff += 2; reasons.append("\(tribe.capitalized) density") }
        }
        // A card that demands a tribe can be a liability with no enablers.
        let tribes = ["dragon", "beast", "mech", "elemental", "demon", "murloc", "pirate", "undead"]
        for tribe in tribes {
            if supportsTribe(text, tribe: tribe) {
                let enablers = minions.filter { $0.tribes.contains(tribe.uppercased()) }
                if let partner = enablers.first {
                    diff += 3; reasons.append("Supported \(tribe) payoff")
                    insights.append((5, "This has \(tribe.capitalized) support already in your deck, including \(partner.name), to help its payoff work."))
                } else {
                    diff -= 6; reasons.append("No \(tribe) support drafted")
                    cautions.append((6, "You haven't drafted any \(tribe.capitalized) support yet, so its payoff still needs help."))
                }
            }
            if cardTribes.contains(tribe.uppercased()),
               let partner = picks.first(where: { supportsTribe($0.card.plainText.lowercased(), tribe: tribe) }) {
                diff += 3; reasons.append("Enables drafted \(tribe) payoff")
                insights.append((5, "This gives \(partner.card.name) another \(tribe.capitalized) to work with."))
            }
        }
        if text.contains("battlecry") && allTexts.filter({ $0.contains("battlecry") }).count >= 5 && text.contains("your battlecries") {
            diff += 2; reasons.append("Battlecry deck synergy")
            insights.append((3, "You've already drafted several Battlecry minions, so this has Battlecries to support."))
        }
        let mechanics = Set((card.mechanics ?? []).map { $0.uppercased() })
        if mechanics.contains("MAGNETIC") || text.contains("magnetic"),
           let partner = minions.first(where: { $0.tribes.contains("MECH") }) {
            diff += 3; reasons.append("Magnetic target drafted")
            insights.append((5, "This fits the Mechs you've already drafted, including \(partner.name)."))
        }
        if isBoardClear(card) {
            let clears = picks.filter { isBoardClear($0.card) }.count
            if picks.count >= 4 && clears == 0 {
                diff += 4; reasons.append("First board clear")
                insights.append((6, "You don't have a board clear yet, and this fills that gap."))
            }
        }
        if picks.count >= 5 {
            if text.contains("draw a card") && !text.contains("your opponent draws") {
                let drawCount = allTexts.filter { $0.contains("draw") }.count
                if drawCount == 0 {
                    let extra = text.contains("deal") && text.contains("damage") ? " alongside damage" : ""
                    insights.append((2.5, "None of your \(picks.count) drafted cards provide card draw yet. \(card.name) adds draw\(extra)."))
                }
            }
            if estimate.factors.contains(where: { $0.key == "LIFESTEAL" && $0.points > 0 }), !picks.contains(where: {
                ($0.card.mechanics ?? []).contains("LIFESTEAL") || $0.card.plainText.lowercased().contains("lifesteal") || ($0.card.plainText.lowercased().contains("restore") && $0.card.plainText.lowercased().contains("health"))
            }) {
                insights.append((2, "You haven't drafted a recovery card yet; \(card.name) adds one."))
            }
        }
        let bounded = max(-9, min(9, diff))
        let total = max(0, min(100, base + bounded))
        if reasons.isEmpty { reasons.append(imported == nil ? "Estimated from card stats and text" : "Imported base rating") }
        return ScoreDetail(total: total, base: base,
                           label: imported == nil ? "Estimate" : "Imported tier rating",
                           reasons: reasons, hasExternalRating: imported != nil,
                           explanation: explanation(card, imported: imported, factors: estimate.factors, insights: insights, cautions: cautions),
                           factors: imported == nil ? estimate.factors : [], hasDeckReason: !insights.isEmpty,
                           caution: cautions.max(by: { $0.priority < $1.priority })?.text)
    }

    private static func supportsTribe(_ text: String, tribe: String) -> Bool {
        text.contains("if you're holding a \(tribe)") || text.contains("if you control a \(tribe)") ||
        text.contains("your \(tribe)s") || text.contains("whenever you summon a \(tribe)") ||
        text.contains("after you summon a \(tribe)")
    }

    /// Require an actual damaging/destroying effect, not a buff mentioning
    /// "all minions", a single-target removal, or damage to heroes only.
    private static func isBoardClear(_ card: ArenaCard) -> Bool {
        let text = card.plainText.lowercased()
        return text.contains("destroy all minions") || text.contains("destroy all enemy minions") ||
            ((text.contains("deal") && text.contains("damage")) &&
             (text.contains("to all enemy minions") || text.contains("to all minions") || text.contains("to all enemies")))
    }

    private static func explanation(_ card: ArenaCard, imported: Double?, factors: [ScoreFactor],
                                    insights: [(priority: Double, text: String)],
                                    cautions: [(priority: Double, text: String)]) -> String {
        let lead: String
        if let insight = insights.max(by: { $0.priority < $1.priority }) {
            lead = insight.text
        } else if let imported {
            lead = "Your imported ratings give \(card.name) \(ratingText(imported))/100."
        } else {
            let strengths = strongestFactors(factors)
            if strengths.isEmpty {
                lead = "I can't identify a specific advantage for \(card.name) from the card information available."
            } else {
                let cost = card.cost.map { " At \($0) mana," } ?? ""
                lead = "\(card.name):\(cost) I'm weighing \(joined(strengths)) most heavily."
            }
        }
        if let caution = cautions.max(by: { $0.priority < $1.priority }) {
            return lead + " " + caution.text
        }
        return lead
    }

    /// Explain the chosen card against the next-best option using the same
    /// score contributions that determine the recommendation.
    public static func recommendation(offers: [ArenaCard], picks: [DraftPick], ratings: ExternalRatings,
                                      playerClass: String) -> String? {
        guard offers.count == 3 else { return nil }
        let details = offers.map { score($0, picks: picks, ratings: ratings, playerClass: playerClass) }
        guard let winner = details.indices.max(by: { details[$0].total < details[$1].total }),
              let runner = details.indices.filter({ $0 != winner }).max(by: { details[$0].total < details[$1].total }) else { return nil }
        let chosen = details[winner], other = details[runner]
        if abs(chosen.total - other.total) < 0.5 {
            return "\(offers[winner].name) and \(offers[runner].name) are tied in my estimate. " + chosen.explanation
        }
        // Preserve concrete deck needs, named combos and caveats ahead of
        // individual-card comparisons.
        if chosen.hasDeckReason { return chosen.explanation }
        if chosen.hasExternalRating && other.hasExternalRating {
            return "Your imported ratings put \(offers[winner].name) at \(ratingText(chosen.base)) and \(offers[runner].name) at \(ratingText(other.base))/100." + cautionSuffix(chosen)
        }
        if !chosen.hasExternalRating && !other.hasExternalRating {
            let theirs = Dictionary(grouping: other.factors, by: \.key).mapValues { $0.reduce(0) { $0 + $1.points } }
            let advantages = chosen.factors.map {
                ScoreFactor(key: $0.key, description: $0.description, points: $0.points - (theirs[$0.key] ?? 0))
            }
            let strengths = strongestFactors(advantages)
            if !strengths.isEmpty {
                return "I'd take \(offers[winner].name) over \(offers[runner].name) for \(joined(strengths))." + cautionSuffix(chosen)
            }
        }
        return chosen.explanation
    }

    private static func cautionSuffix(_ detail: ScoreDetail) -> String {
        detail.caution.map { " " + $0 } ?? ""
    }

    private static func ratingText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func joined(_ descriptions: [String]) -> String {
        descriptions.prefix(2).joined(separator: " and ")
    }

    private static func strongestFactors(_ factors: [ScoreFactor]) -> [String] {
        factors.filter { $0.points > 0 && !["type", "random", "expensive"].contains($0.key) }
            .sorted { $0.points == $1.points ? $0.key < $1.key : $0.points > $1.points }
            .prefix(2).map(\.description)
    }

    /// Record contributions while calculating the estimate, so explanations
    /// cannot drift from the actual weights. This preserves existing scores.
    private static func heuristic(_ card: ArenaCard) -> (total: Double, factors: [ScoreFactor]) {
        let cost = Double(max(0, card.cost ?? 0))
        let text = card.plainText.lowercased()
        let mechanics = Set((card.mechanics ?? []).map { $0.uppercased() })
        var factors: [ScoreFactor] = []
        func add(_ key: String, _ description: String, _ points: Double) {
            if let i = factors.firstIndex(where: { $0.key == key }) {
                let old = factors[i]
                factors[i] = ScoreFactor(key: key, description: old.description, points: old.points + points)
            } else { factors.append(ScoreFactor(key: key, description: description, points: points)) }
        }
        if card.type == "MINION" {
            let stats = Double((card.attack ?? 0) + (card.health ?? 0))
            let expected = cost * 2 + 1
            let description = card.attack.flatMap { attack in card.health.map { "a \(attack)/\($0) body at \(Int(cost)) mana" } } ?? "the estimated stat budget"
            add("stats", description, max(-15, min(14, (stats - expected) * 3)))
            if cost == 2 || cost == 3 { add("cost", "early-game cost", 3) }
            for (mechanic, label, points) in [("RUSH", "immediate board impact", 9.0),
                                              ("DIVINE_SHIELD", "Divine Shield", 8),
                                              ("LIFESTEAL", "recovery potential", 4),
                                              ("TAUNT", "defensive coverage", 3),
                                              ("WINDFURY", "attack pressure", 2),
                                              ("STEALTH", "Stealth", 2), ("CHARGE", "immediate attack pressure", 8)] {
                if mechanics.contains(mechanic) { add(mechanic, label, points) }
            }
        } else if card.type == "SPELL" {
            add("type", "spell flexibility", 4)
            if text.contains("deal") && text.contains("damage") { add("damage", "damage", 10) }
            if text.contains("all enemy minions") || text.contains("all enemies") { add("area", "a board-wide effect", 10) }
            if text.contains("draw") || text.contains("discover") { add(text.contains("discover") ? "discover" : "draw", text.contains("discover") ? "Discover options" : "card draw", 6) }
            if text.contains("destroy a minion") || text.contains("destroy an enemy minion") { add("removal", "single-target removal", 10) }
        } else if card.type == "WEAPON" { add("type", "weapon access", 5) }
        if text.contains("discover") { add("discover", "Discover options", 5) }
        if text.contains("draw a card") { add("draw", "card draw", 4) }
        if text.contains("deal") && text.contains("damage") && card.type == "MINION" { add("damage", "a damage effect", 5) }
        if text.contains("random") { add("random", "random outcomes", -2) }
        if card.type == "MINION" && cost >= 8 { add("expensive", "high mana commitment", -3) }
        return (max(5, min(95, 48 + factors.reduce(0) { $0 + $1.points })), factors)
    }
}
