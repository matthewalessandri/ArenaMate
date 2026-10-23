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

    public static func findOffer(lines: [RecognizedLine], catalog: CatalogIndex, playerClass: String) -> OfferRecognitionResult {
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
                    let score = quality - 8 * spread
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
