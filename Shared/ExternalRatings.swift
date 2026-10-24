import Foundation

public struct RatingEvidence: Codable, Sendable {
    public let value: Double
    public let rawWinRate: Double?
    public let sampleSize: Int?
    public let percentile: Double?
    public let source: String
    public let importedAt: Date?

    public init(value: Double, rawWinRate: Double? = nil, sampleSize: Int? = nil,
                percentile: Double? = nil, source: String, importedAt: Date? = nil) {
        self.value = value
        self.rawWinRate = rawWinRate
        self.sampleSize = sampleSize
        self.percentile = percentile
        self.source = source
        self.importedAt = importedAt
    }
}

public struct ExternalRatings: Codable, Sendable {
    public var byId: [String: Double] = [:]
    public var byClassAndName: [String: Double] = [:]
    public var byName: [String: Double] = [:]
    public var performanceByClassAndId: [String: RatingEvidence] = [:]

    public init() {}

    public func score(card: ArenaCard, playerClass: String) -> Double? {
        evidence(card: card, playerClass: playerClass)?.value
    }

    public func evidence(card: ArenaCard, playerClass: String) -> RatingEvidence? {
        let gameID = card.id.uppercased()
        var ids = [gameID]
        if gameID.hasPrefix("CORE_") { ids.append(String(gameID.dropFirst(5))) }
        if let dbfId = card.dbfId { ids.append(String(dbfId)) }
        let cls = Self.normalizedClass(playerClass)
        for id in ids {
            if let value = performanceByClassAndId["\(cls)|\(id)"] ?? performanceByClassAndId["ALL|\(id)"] {
                return value
            }
        }
        if let value = byId[card.id.uppercased()] ?? card.dbfId.flatMap({ byId[String($0)] }) {
            return RatingEvidence(value: value, source: "Imported ratings")
        }
        let name = CatalogIndex.normalize(card.name)
        if let value = byClassAndName["\(cls)|\(name)"] ?? byName[name] {
            return RatingEvidence(value: value, source: "Imported ratings")
        }
        return nil
    }

    private struct HSReplayEnvelope: Decodable { let data: [String: [HSReplayRow]] }
    private struct HSReplayRow: Decodable {
        let cardID: String
        let drawnWinRate: Double
        let numGames: Int
        enum CodingKeys: String, CodingKey {
            case cardID = "card_id"
            case drawnWinRate = "drawn_win_rate"
            case numGames = "num_games"
        }
    }

    public static func parseHSReplay(_ data: Data, importedAt: Date = Date(),
                                     minimumRows: Int = 500) throws -> ExternalRatings {
        let payload: HSReplayEnvelope
        do { payload = try JSONDecoder().decode(HSReplayEnvelope.self, from: data) }
        catch { throw PerformanceDataError.invalid }
        var result = ExternalRatings()
        var accepted = 0
        for (rawClass, rawRows) in payload.data {
            let rows = rawRows.filter { row in
                !row.cardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                row.drawnWinRate.isFinite && (0...100).contains(row.drawnWinRate) && row.numGames > 0
            }
            guard !rows.isEmpty else { continue }
            let totalGames = rows.reduce(0.0) { $0 + Double($1.numGames) }
            let weightedTotal = rows.reduce(0.0) { $0 + $1.drawnWinRate * Double($1.numGames) }
            let mean = weightedTotal / totalGames
            var ranked: [RankedRow] = []
            ranked.reserveCapacity(rows.count)
            for row in rows {
                let reliability = Double(row.numGames) / Double(row.numGames + 400)
                let stabilized = mean + (row.drawnWinRate - mean) * reliability
                ranked.append(RankedRow(row: row, stabilizedRate: stabilized))
            }
            ranked.sort {
                $0.stabilizedRate == $1.stabilizedRate
                    ? $0.row.cardID < $1.row.cardID
                    : $0.stabilizedRate < $1.stabilizedRate
            }
            for (rank, item) in ranked.enumerated() {
                let percentile = (Double(rank) + 0.5) / Double(ranked.count)
                let key = normalizedClass(rawClass) + "|" + item.row.cardID
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).uppercased()
                result.performanceByClassAndId[key] = RatingEvidence(
                    value: 25 + 65 * percentile, rawWinRate: item.row.drawnWinRate,
                    sampleSize: item.row.numGames, percentile: percentile,
                    source: "Recent Arena results", importedAt: importedAt)
                accepted += 1
            }
        }
        guard accepted >= minimumRows else { throw PerformanceDataError.incomplete(accepted) }
        return result
    }

    private struct RankedRow {
        let row: HSReplayRow
        let stabilizedRate: Double
    }

    private static func normalizedClass(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    public enum PerformanceDataError: LocalizedError {
        case invalid, incomplete(Int)
        public var errorDescription: String? {
            switch self {
            case .invalid: return "Arena statistics were not in the expected format"
            case .incomplete(let count): return "Arena statistics were incomplete (\(count) ratings)"
            }
        }
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
            guard scoreCol < row.count,
                  let score = Double(row[scoreCol].trimmingCharacters(in: .whitespaces)),
                  score.isFinite, (0...100).contains(score) else { continue }
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
