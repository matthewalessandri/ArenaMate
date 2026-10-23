import Foundation

public struct ArenaCard: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let dbfId: Int?
    public let name: String
    public let cost: Int?
    public let type: String?
    public let cardClass: String?
    public let classes: [String]?
    public let rarity: String?
    public let mechanics: [String]?
    public let text: String?
    public let attack: Int?
    public let health: Int?
    public let race: String?
    public let collectible: Bool?
    public let spellSchool: String?

    public init(id: String, dbfId: Int? = nil, name: String, cost: Int? = nil,
                type: String? = nil, cardClass: String? = nil, classes: [String]? = nil,
                rarity: String? = nil, mechanics: [String]? = nil, text: String? = nil,
                attack: Int? = nil, health: Int? = nil, race: String? = nil,
                collectible: Bool? = nil, spellSchool: String? = nil) {
        self.id = id; self.dbfId = dbfId; self.name = name; self.cost = cost
        self.type = type; self.cardClass = cardClass; self.classes = classes
        self.rarity = rarity; self.mechanics = mechanics; self.text = text
        self.attack = attack; self.health = health; self.race = race
        self.collectible = collectible; self.spellSchool = spellSchool
    }

    public var plainText: String {
        (text ?? "").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "[x]", with: "", options: .literal)
    }
}

public struct MatchResult: Sendable {
    public var card: ArenaCard
    public var confidence: Double
}

public struct CatalogIndex: Sendable {
    public private(set) var cards: [ArenaCard]
    private let byName: [String: [ArenaCard]]
    private let byId: [String: ArenaCard]
    private let byDbf: [Int: ArenaCard]
    private let byOCRPrefix: [String: [ArenaCard]]

    public init(cards: [ArenaCard]) {
        self.cards = cards
        var names: [String: [ArenaCard]] = [:]
        var ids: [String: ArenaCard] = [:]
        var dbfs: [Int: ArenaCard] = [:]
        var prefixes: [String: [ArenaCard]] = [:]
        for card in cards {
            let normalized = Self.normalize(card.name)
            names[normalized, default: []].append(card)
            if normalized.count >= 3 { prefixes[String(normalized.prefix(2)), default: []].append(card) }
            ids[card.id.uppercased()] = card
            if let id = card.dbfId { dbfs[id] = card }
        }
        byName = names; byId = ids; byDbf = dbfs; byOCRPrefix = prefixes
    }

    public func byGameId(_ id: String) -> ArenaCard? {
        if let c = byId[id.uppercased()] { return c }
        if let n = Int(id), let c = byDbf[n] { return c }
        return nil
    }

    public func find(_ query: String, playerClass: String? = nil, allowFuzzy: Bool = true) -> MatchResult? {
        let q = Self.normalize(query)
        if let direct = byGameId(query) { return MatchResult(card: direct, confidence: 1) }
        guard q.count >= 3 else { return nil }
        if let matches = byName[q], let exact = choose(matches, playerClass: playerClass) {
            return MatchResult(card: exact, confidence: 1)
        }
        guard allowFuzzy else { return nil }
        var best: ArenaCard?
        var bestScore = 0.0
        for card in cards {
            let n = Self.normalize(card.name)
            if abs(n.count - q.count) > 3 { continue }
            if let cls = playerClass?.uppercased(), cls != "ALL", !isUsable(card, by: cls) { continue }
            let confidence = 1 - Double(Self.editDistance(q, n)) / Double(max(1, max(q.count, n.count)))
            if confidence > bestScore { best = card; bestScore = confidence }
        }
        if let best, bestScore >= 0.78 { return MatchResult(card: best, confidence: bestScore) }
        return nil
    }

    /// OCR calls run frequently; avoid scanning tens of thousands of card names
    /// for every word of recognized text. Bias to the same two first letters.
    public func matchOCR(_ query: String, playerClass: String? = nil) -> MatchResult? {
        if let exact = find(query, playerClass: playerClass, allowFuzzy: false) { return exact }
        let q = Self.normalize(query)
        guard q.count >= 4, q.count <= 42 else { return nil }
        let pool = byOCRPrefix[String(q.prefix(2))] ?? []
        let cls = playerClass?.uppercased() ?? "ALL"
        var best: ArenaCard?
        var score = 0.0
        for card in pool {
            let n = Self.normalize(card.name)
            guard abs(n.count - q.count) <= 4 else { continue }
            guard cls == "ALL" || isUsable(card, by: cls) else { continue }
            let similarity = 1 - Double(Self.editDistance(q, n)) / Double(max(q.count, n.count))
            if similarity > score { best = card; score = similarity }
        }
        if let best, score >= 0.79 { return MatchResult(card: best, confidence: score) }
        return nil
    }

    private func choose(_ cards: [ArenaCard], playerClass: String?) -> ArenaCard? {
        let cls = playerClass?.uppercased() ?? "ALL"
        return cards.first(where: { isUsable($0, by: cls) }) ?? cards.first
    }

    private func isUsable(_ card: ArenaCard, by cls: String) -> Bool {
        if cls == "ALL" { return true }
        return card.cardClass?.uppercased() == "NEUTRAL" || card.cardClass?.uppercased() == cls || (card.classes ?? []).contains(cls)
    }

    public static func normalize(_ text: String) -> String {
        let lower = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(lower.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for (i, aChar) in a.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, bChar) in b.enumerated() {
                next[j + 1] = min(next[j] + 1, previous[j + 1] + 1,
                                  previous[j] + (aChar == bChar ? 0 : 1))
            }
            previous = next
        }
        return previous[b.count]
    }
}
