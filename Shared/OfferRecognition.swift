import Foundation

/// Positions are normalized to [0, 1] relative to the captured Hearthstone window,
/// with y=0 at the bottom (Vision coordinate convention).
public struct RecognizedLine: Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var confidence: Double
    public init(text: String, x: Double, y: Double, confidence: Double = 1) {
        self.text = text; self.x = x; self.y = y; self.confidence = confidence
    }
}

public struct OfferRecognitionResult: Sendable {
    public var names: [String]?
    public var matched: [String]
    public var message: String
}

public enum OfferRecognition {
    private struct Item {
        let line: RecognizedLine
        let match: MatchResult
    }

    /// Arena draft card names occupy three fixed *board* slots, not arbitrary
    /// card-name rows. The right-hand deck list and hovered previews must never
    /// be eligible to fill missing draft slots.
    ///
    /// The slot bounds are deliberately conservative: if any card is unreadable,
    /// return no recommendation rather than mapping a fourth card to the wrong pick.
    private static let slotRanges: [ClosedRange<Double>] = [
        0.075...0.315, 0.325...0.555, 0.565...0.795
    ]
    private static let slotCenters: [Double] = [0.195, 0.440, 0.680]
    private static let titleBand: ClosedRange<Double> = 0.43...0.82

    /// The board can occupy a narrower row when the deck sidebar is visible.
    /// Require three evenly spaced title boxes. Only legendary-group screens
    /// may recover a damaged title using unique rules text beneath that card.
    private static func alignedOffer(lines: [RecognizedLine], catalog: CatalogIndex,
                                     allowRulesRecovery: Bool) -> OfferRecognitionResult? {
        let titles = lines.filter { titleBand.contains($0.y) && $0.x > 0.075 && $0.x < 0.795 }
            .sorted { $0.y > $1.y }
        for anchor in titles {
            guard catalog.matchOCR(anchor.text) != nil else { continue }
            let row = titles.filter { abs($0.y - anchor.y) < 0.025 }.sorted { $0.x < $1.x }
            var groups: [[RecognizedLine]] = []
            for line in row {
                if let last = groups.last, abs(last[0].x - line.x) < 0.025 {
                    groups[groups.count - 1].append(line)
                } else { groups.append([line]) }
            }
            guard groups.count == 3 else { continue }
            let xs = groups.map { $0[0].x }
            let leftGap = xs[1] - xs[0], rightGap = xs[2] - xs[1]
            guard leftGap >= 0.12, leftGap <= 0.28,
                  rightGap >= 0.12, rightGap <= 0.28,
                  abs(leftGap - rightGap) < 0.045 else { continue }
            var names: [String] = []
            for group in groups {
                let matches = group.compactMap { catalog.matchOCR($0.text) }
                if let match = matches.max(by: { $0.confidence < $1.confidence }) {
                    names.append(match.card.name)
                    continue
                }
                guard allowRulesRecovery else { break }
                let title = group[0]
                let body = lines.filter {
                    abs($0.x - title.x) < min(leftGap, rightGap) * 0.3 &&
                    $0.y < title.y - 0.03 && $0.y > title.y - 0.16
                }.map { CatalogIndex.normalize($0.text) }.filter { $0.count >= 18 }
                guard let card = catalog.matchRulesEvidence(body) else { break }
                names.append(card.name)
            }
            if names.count == 3, Set(names).count == 3 {
                return OfferRecognitionResult(names: names, matched: names,
                    message: "Recognized aligned draft titles: " + names.joined(separator: " | "))
            }
        }
        return nil
    }

    public static func findOffer(lines: [RecognizedLine], catalog: CatalogIndex, playerClass: String) -> OfferRecognitionResult {
        let isLegendaryGroup = lines.contains {
            CatalogIndex.normalize($0.text).contains("choose a legendary group")
        }
        if let aligned = alignedOffer(lines: lines, catalog: catalog, allowRulesRecovery: isLegendaryGroup) {
            return aligned
        }
        var slots: [[Item]] = [[], [], []]
        for line in lines {
            guard titleBand.contains(line.y),
                  let slot = slotRanges.firstIndex(where: { $0.contains(line.x) }),
                  let match = catalog.matchOCR(line.text, playerClass: playerClass),
                  match.confidence >= 0.79 else { continue }
            slots[slot].append(Item(line: line, match: match))
        }
        let found = slots.flatMap { $0.map { $0.match.card.name } }
        guard slots.allSatisfy({ !$0.isEmpty }) else {
            let missing = slots.indices.filter { slots[$0].isEmpty }.map { String($0 + 1) }.joined(separator: ", ")
            return OfferRecognitionResult(names: nil, matched: found,
                message: "Draft slot(s) \(missing) unreadable; no recommendation. Ignoring other screen text.")
        }

        // Vision may supply several alternative OCR readings at the same location.
        // Choose the best *aligned* combination of one name per physical draft slot.
        var best: (score: Double, names: [String])?
        for a in slots[0].prefix(12) {
            for b in slots[1].prefix(12) {
                for c in slots[2].prefix(12) {
                    let candidates = [a, b, c]
                    let ys = candidates.map { $0.line.y }
                    let spread = (ys.max() ?? 0) - (ys.min() ?? 0)
                    guard spread <= 0.12 else { continue }
                    let names = candidates.map { $0.match.card.name }
                    // Repeated name observations in two slots are usually UI
                    // duplicates, not three real draft choices.
                    guard Set(names).count == 3 else { continue }
                    let quality = candidates.enumerated().reduce(0.0) { total, entry in
                        let (i, item) = entry
                        return total + 2 * item.match.confidence + item.line.confidence
                            - 2.5 * abs(item.line.x - slotCenters[i])
                    }
                    let score = quality - 8 * spread + 4 * ys.reduce(0, +)
                    if best == nil || score > best!.score {
                        best = (score, names)
                    }
                }
            }
        }
        guard let best else {
            return OfferRecognitionResult(names: nil, matched: found,
                message: "Card names found, but not aligned to the three draft positions; no recommendation.")
        }
        return OfferRecognitionResult(names: best.names, matched: found,
            message: "Recognized all 3 draft slots: " + best.names.joined(separator: " | "))
    }
}
