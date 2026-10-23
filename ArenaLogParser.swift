import Foundation

public enum ArenaLogEvent: Equatable, Sendable {
    case offered([String])
    case selected(name: String, gameId: String?)
    case draftStarted
}

/// Defensive best-effort parser: game log formats change across Hearthstone patches.
/// Only produces an offer when three distinct slots are explicitly represented.
public struct ArenaLogParser {
    public init() {}

    public func parse(_ line: String) -> ArenaLogEvent? {
        if line.contains("Client chooses:") {
            let rest = line.components(separatedBy: "Client chooses:").dropFirst().joined(separator: "Client chooses:")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let r = rest.range(of: #"^(.+?)\s*\(([A-Za-z0-9_]+)\)"#, options: .regularExpression) {
                let part = String(rest[r]); let p = part.lastIndex(of: "(")!
                return .selected(name: String(part[..<p]).trimmingCharacters(in: .whitespaces),
                                 gameId: String(part[part.index(after: p)..<part.index(before: part.endIndex)]))
            }
            if !rest.isEmpty { return .selected(name: rest, gameId: nil) }
        }
        if line.contains("SetDraftMode - DRAFTING") { return .draftStarted }

        // Some patches emit one explicit bracketed triple, others log names and IDs.
        // Do not interpret arbitrary comma-containing lines as offers.
        let markers = ["Draft choices:", "Offered cards:", "DraftManager.OnChoices -", "Draft options:"]
        guard let marker = markers.first(where: { line.localizedCaseInsensitiveContains($0) }) else { return nil }
        guard let range = line.range(of: marker, options: .caseInsensitive) else { return nil }
        let tail = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let separator = tail.contains(" | ") ? " | " : ", "
        let options = tail.components(separatedBy: separator).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"^[\[\(]|[\]\)]$"#, with: "", options: .regularExpression)
        }
        if options.count == 3 && options.allSatisfy({ $0.count >= 3 }) { return .offered(options) }
        return nil
    }
}
