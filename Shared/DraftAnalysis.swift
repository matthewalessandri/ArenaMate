import Foundation

public enum CardRole: String, Codable, CaseIterable, Sendable {
    case removal
    case boardClear
    case draw
    case generation
    case recovery
    case reach
    case earlyBoard
    case lateThreat
}

public struct DeckProfile: Sendable {
    public let cardCount: Int
    public let roleCounts: [CardRole: Int]
    public let curve: [Int: Int]

    public init(cards: [ArenaCard]) {
        cardCount = cards.count
        var roles: [CardRole: Int] = [:]
        var costs: [Int: Int] = [:]
        for card in cards {
            costs[min(7, max(0, card.cost ?? 0)), default: 0] += 1
            for role in DraftAnalysis.roles(of: card) { roles[role, default: 0] += 1 }
        }
        roleCounts = roles
        curve = costs
    }

    public func count(_ role: CardRole) -> Int { roleCounts[role, default: 0] }
}

public enum DraftAnalysis {
    public static func roles(of card: ArenaCard) -> Set<CardRole> {
        let text = normalized(card.plainText)
        let mechanics = Set((card.mechanics ?? []).map { $0.uppercased() })
        var roles: Set<CardRole> = []
        let cost = card.cost ?? 0

        if card.type == "MINION" && (1...2).contains(cost) { roles.insert(.earlyBoard) }
        if cost >= 7 && (card.type == "MINION" || text.contains("summon ")) { roles.insert(.lateThreat) }
        if mechanics.contains("LIFESTEAL") || text.contains("lifesteal") ||
            (text.contains("restore ") && text.contains(" health")) || text.contains("gain armor") {
            roles.insert(.recovery)
        }
        if text.range(of: #"\bdraw (?:a|[1-9]|one|two|three|four) cards?\b"#,
                      options: .regularExpression) != nil && !text.contains("opponent draws") {
            roles.insert(.draw)
        }
        if text.contains("discover ") || text.range(of: #"\badd (?:a|[1-9]|one|two|three) .+ to your hand\b"#,
                                                     options: .regularExpression) != nil {
            roles.insert(.generation)
        }
        if isBoardClearText(text) { roles.insert(.boardClear); roles.insert(.removal) }
        if isSingleTargetRemovalText(text) { roles.insert(.removal) }
        if isReachText(text) { roles.insert(.reach) }
        return roles
    }

    public static func isBoardClear(_ card: ArenaCard) -> Bool {
        roles(of: card).contains(.boardClear)
    }

    private static func normalized(_ source: String) -> String {
        source.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func isBoardClearText(_ text: String) -> Bool {
        text.contains("destroy all minions") || text.contains("destroy all enemy minions") ||
            ((text.contains("deal") && text.contains("damage")) &&
             (text.contains("to all enemy minions") || text.contains("to all minions") ||
              text.contains("to all enemies")))
    }

    private static func isSingleTargetRemovalText(_ text: String) -> Bool {
        guard !text.contains("random") else { return false }
        return text.range(of: #"\b(?:destroy|silence|transform|return) (?:a|an) (?:enemy )?minion\b"#,
                          options: .regularExpression) != nil ||
            text.range(of: #"\bdeal \$?[1-9][0-9]* damage(?:\.| to (?:a|an) (?:enemy )?(?:minion|character))"#,
                       options: .regularExpression) != nil
    }

    private static func isReachText(_ text: String) -> Bool {
        guard text.contains("deal"), text.contains("damage"), !text.contains("your hero") else { return false }
        return text.contains("damage to the enemy hero") || text.contains("damage to an enemy") ||
            text.range(of: #"\bdeal \$?[1-9][0-9]* damage\.$"#, options: .regularExpression) != nil
    }
}
