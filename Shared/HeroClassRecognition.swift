import Foundation

/// Conservative hero-class inference from the Hearthstone draft screen.
/// Vision coordinates are normalized with y=0 at bottom of the image.
public enum HeroClassRecognition {
    public static let classKeys = ["DEATHKNIGHT", "DEMONHUNTER", "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"]
    public static func detect(lines: [RecognizedLine], offeredNames: [String]?, catalog: CatalogIndex) -> String? {
        // Hero class text appears immediately beneath the portrait on the lower-left
        // of the draft screen. Reject labels in the deck list, card text and elsewhere.
        for line in lines where line.x < 0.38 && line.y < 0.30 && line.confidence >= 0.65 {
            let text = CatalogIndex.normalize(line.text).uppercased().replacingOccurrences(of: " ", with: "")
            if classKeys.contains(text) { return text }
        }
        // A unique class-only offered card can establish the class as well,
        // but neutral and multiclass cards cannot.
        guard let offeredNames else { return nil }
        let unique = Set(offeredNames.compactMap { name -> String? in
            guard let card = catalog.find(name, playerClass: "ALL", allowFuzzy: false)?.card,
                  let cls = card.cardClass?.uppercased(), classKeys.contains(cls),
                  (card.classes ?? []).isEmpty else { return nil }
            return cls
        })
        return unique.count == 1 ? unique.first : nil
    }
}
