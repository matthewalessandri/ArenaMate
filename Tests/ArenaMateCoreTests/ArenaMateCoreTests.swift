import XCTest
@testable import ArenaMateCore

final class ArenaMateCoreTests: XCTestCase {
    func testMatchesOCRAndCardIds() {
        let card = ArenaCard(id: "EX1_116", dbfId: 559, name: "Leeroy Jenkins", cost: 5, type: "MINION", cardClass: "NEUTRAL")
        let index = CatalogIndex(cards: [card])
        XCTAssertEqual(index.find("LEEROY JENKlNS")?.card.name, "Leeroy Jenkins")
        XCTAssertEqual(index.find("EX1_116")?.card.name, "Leeroy Jenkins")
        XCTAssertEqual(index.find("559")?.card.name, "Leeroy Jenkins")
        XCTAssertNil(index.find("no match"))
    }
    func testCSVWithQuotedNameAndClass() throws {
        let csv = "name,class,score\n\"Leeroy, Jenkins\",MAGE,85\nFrostbolt,MAGE,88\n"
        let parsed = try ExternalRatings.parseCSV(Data(csv.utf8))
        let card = ArenaCard(id: "1", name: "Frostbolt")
        XCTAssertEqual(parsed.score(card: card, playerClass: "MAGE"), 88)
        XCTAssertNil(parsed.score(card: card, playerClass: "ROGUE"))
    }
    func testNoInventedTiers() {
        let card = ArenaCard(id: "X", name: "Mana Wyrm", cost: 1, type: "MINION", cardClass: "MAGE", attack: 1, health: 3)
        let result = DraftScorer.score(card, picks: [], ratings: ExternalRatings(), playerClass: "MAGE")
        XCTAssertEqual(result.label, "Estimate")
        XCTAssertFalse(result.hasExternalRating)
    }
    func testLogChooseAndOffers() {
        let p = ArenaLogParser()
        XCTAssertEqual(p.parse("D 00:20:11 Client chooses: Mutating Lifeform (GDB_321)"), .selected(name: "Mutating Lifeform", gameId: "GDB_321"))
        XCTAssertEqual(p.parse("D 00:00:00 Offered cards: Frostbolt | Fireball | Flamestrike"), .offered(["Frostbolt", "Fireball", "Flamestrike"]))
        XCTAssertNil(p.parse("D something irrelevant"))
    }
    func testTribalMissingEnablerPenalty() {
        let card = ArenaCard(id: "B", name: "Dragon Rider", cost: 3, type: "MINION", cardClass: "MAGE", text: "Battlecry: If you're holding a Dragon, gain +2/+2.", attack: 3, health: 3)
        let score = DraftScorer.score(card, picks: [], ratings: ExternalRatings(), playerClass: "MAGE")
        XCTAssertTrue(score.reasons.contains("No dragon support drafted"))
    }
}

final class OfferRecognitionTests: XCTestCase {
    private var catalog: CatalogIndex {
        CatalogIndex(cards: [
            ArenaCard(id: "A", name: "Husk, Eternal Reaper", cardClass: "DEATHKNIGHT"),
            ArenaCard(id: "B", name: "Helya", cardClass: "DEATHKNIGHT"),
            ArenaCard(id: "C", name: "Maw and Paw", cardClass: "DEATHKNIGHT"),
            ArenaCard(id: "D", name: "Fireball", cardClass: "MAGE"),
            ArenaCard(id: "E", name: "Storm Giant", cardClass: "NEUTRAL"),
            ArenaCard(id: "F", name: "Netherspite Historian", cardClass: "NEUTRAL"),
            ArenaCard(id: "G", name: "Sandmaw", cardClass: "NEUTRAL"),
            ArenaCard(id: "H", name: "Gold Panner", cardClass: "NEUTRAL")
        ])
    }

    func testOffCenterLegendaryGroupInScreenshot() {
        // Reproduces user's Hearthstone screenshot where cards occupy only the
        // left ~70% of the game window, not three equally-sized screen thirds.
        let lines = [
            RecognizedLine(text: "Choose a Legendary Group for your deck:", x: 0.46, y: 0.91),
            RecognizedLine(text: "Husk, Eternal Reaper", x: 0.17, y: 0.64),
            RecognizedLine(text: "Helya", x: 0.40, y: 0.64),
            RecognizedLine(text: "Maw and Paw", x: 0.64, y: 0.63)
        ]
        let result = OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "DEATHKNIGHT")
        XCTAssertEqual(result.names, ["Husk, Eternal Reaper", "Helya", "Maw and Paw"])
    }

    func testMissingThirdCardDoesNotGuess() {
        let lines = [RecognizedLine(text: "Helya", x: 0.4, y: 0.62),
                     RecognizedLine(text: "Maw and Paw", x: 0.64, y: 0.62)]
        let result = OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "DEATHKNIGHT")
        XCTAssertNil(result.names)
        XCTAssertEqual(result.matched.count, 2)
    }

    func testDifferentVerticalRowsDoNotGetMixed() {
        let lines = [RecognizedLine(text: "Husk, Eternal Reaper", x: 0.17, y: 0.64),
                     RecognizedLine(text: "Helya", x: 0.40, y: 0.42),
                     RecognizedLine(text: "Maw and Paw", x: 0.64, y: 0.64)]
        let result = OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "DEATHKNIGHT")
        XCTAssertNil(result.names)
    }

    func testOCRAlternateSpelling() {
        let lines = [RecognizedLine(text: "Husk Eternal Reaper", x: 0.17, y: 0.64),
                     RecognizedLine(text: "Helya", x: 0.40, y: 0.64),
                     RecognizedLine(text: "Maw and Paw", x: 0.64, y: 0.64)]
        let result = OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "DEATHKNIGHT")
        XCTAssertEqual(result.names?.first, "Husk, Eternal Reaper")
    }
    func testRegressionPreviewCannotReplaceMiddleOrRightDraftCard() {
        // User's screenshot: Storm Giant, Netherspite Historian, Sandmaw.
        // A hovered fourth card, Gold Panner, is visible in the right panel.
        let lines = [
            RecognizedLine(text: "Storm Giant", x: 0.190, y: 0.66),
            RecognizedLine(text: "Netherspite Historian", x: 0.445, y: 0.66),
            RecognizedLine(text: "Sandmaw", x: 0.690, y: 0.66),
            RecognizedLine(text: "Gold Panner", x: 0.91, y: 0.66)
        ]
        XCTAssertEqual(OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "DEATHKNIGHT").names,
                       ["Storm Giant", "Netherspite Historian", "Sandmaw"])
    }

    func testNeverFillMissingDraftSlotFromDeckOrPreview() {
        let lines = [
            RecognizedLine(text: "Storm Giant", x: 0.19, y: 0.66),
            RecognizedLine(text: "Sandmaw", x: 0.69, y: 0.66),
            RecognizedLine(text: "Gold Panner", x: 0.91, y: 0.66),
            RecognizedLine(text: "Helya", x: 0.44, y: 0.20)
        ]
        XCTAssertNil(OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "DEATHKNIGHT").names)
    }

    func testOffRowNamesDoNotFillDraftSlots() {
        let lines = [
            RecognizedLine(text: "Storm Giant", x: 0.19, y: 0.66),
            RecognizedLine(text: "Netherspite Historian", x: 0.44, y: 0.32),
            RecognizedLine(text: "Sandmaw", x: 0.69, y: 0.66)
        ]
        XCTAssertNil(OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "DEATHKNIGHT").names)
    }

    func testModerateTitleHeightDifferencesAcrossSlots() {
        let lines = [RecognizedLine(text: "Storm Giant", x: 0.19, y: 0.65),
                     RecognizedLine(text: "Netherspite Historian", x: 0.44, y: 0.59),
                     RecognizedLine(text: "Sandmaw", x: 0.69, y: 0.66)]
        XCTAssertEqual(OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "ALL").names,
                       ["Storm Giant", "Netherspite Historian", "Sandmaw"])
    }

    func testDraftNamesLowerOnScreenStillDetect() {
        let lines = [RecognizedLine(text: "Storm Giant", x: 0.19, y: 0.49),
                     RecognizedLine(text: "Netherspite Historian", x: 0.44, y: 0.49),
                     RecognizedLine(text: "Sandmaw", x: 0.69, y: 0.49),
                     RecognizedLine(text: "Gold Panner", x: 0.91, y: 0.49)]
        XCTAssertEqual(OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "ALL").names,
                       ["Storm Giant", "Netherspite Historian", "Sandmaw"])
    }

}

final class HeroClassRecognitionTests: XCTestCase {
    let catalog = CatalogIndex(cards: [
        ArenaCard(id: "A", name: "Frostbolt", cardClass: "MAGE"),
        ArenaCard(id: "B", name: "Sandmaw", cardClass: "NEUTRAL"),
        ArenaCard(id: "C", name: "Gold Panner", cardClass: "NEUTRAL")
    ])
    func testExplicitHeroLabel() {
        let lines = [RecognizedLine(text: "Death Knight", x: 0.25, y: 0.1)]
        XCTAssertEqual(HeroClassRecognition.detect(lines: lines, offeredNames: nil, catalog: catalog), "DEATHKNIGHT")
    }
    func testRightHandClassLabelIgnored() {
        let lines = [RecognizedLine(text: "Mage", x: 0.95, y: 0.1)]
        XCTAssertNil(HeroClassRecognition.detect(lines: lines, offeredNames: nil, catalog: catalog))
    }
    func testClassFromExclusiveCard() {
        XCTAssertEqual(HeroClassRecognition.detect(lines: [], offeredNames: ["Frostbolt", "Sandmaw", "Gold Panner"], catalog: catalog), "MAGE")
    }
    func testNeutralOnlyDoesNotInventClass() {
        XCTAssertNil(HeroClassRecognition.detect(lines: [], offeredNames: ["Sandmaw", "Gold Panner"], catalog: catalog))
    }

}

final class LegendaryCaptureRegressionTests: XCTestCase {
    private let cards = [
        ArenaCard(id: "A", name: "Amitut, Keeper of Amitus"),
        ArenaCard(id: "P", name: "Prison of Yogg-Saron"),
        ArenaCard(id: "T", name: "Tyr", text: "Battlecry: Resurrect a 2, 3, and 4-Attack minion from your class."),
        ArenaCard(id: "EX1_334", dbfId: 8, name: "Mind Control")
    ]
    private var lines: [RecognizedLine] {
        [
            RecognizedLine(text: "Choose a Legendary Group for your deck:", x: 0.404, y: 0.838),
            RecognizedLine(text: "Amitut, Keeper of Amitus", x: 0.247, y: 0.610),
            RecognizedLine(text: "Prison of Yogg-Saron", x: 0.408, y: 0.611),
            RecognizedLine(text: "ТуВ", x: 0.558, y: 0.609, confidence: 0.5),
            RecognizedLine(text: "Battlecry: Resurrect a", x: 0.562, y: 0.550),
            RecognizedLine(text: "2, 3, and 4-Attack minion", x: 0.562, y: 0.534),
            RecognizedLine(text: "from your class.", x: 0.562, y: 0.515),
            RecognizedLine(text: "8", x: 0.302, y: 0.487)
        ]
    }
    func testReportedNarrowLegendaryLayoutAndUnreadableTyr() {
        let result = OfferRecognition.findOffer(lines: lines, catalog: CatalogIndex(cards: cards), playerClass: "ALL")
        XCTAssertEqual(result.names, ["Amitut, Keeper of Amitus", "Prison of Yogg-Saron", "Tyr"])
        XCTAssertFalse(result.matched.contains("Mind Control"))
    }
    func testNumericOCRDoesNotMatchDatabaseID() {
        let catalog = CatalogIndex(cards: cards)
        XCTAssertEqual(catalog.find("8")?.card.name, "Mind Control")
        XCTAssertNil(catalog.matchOCR("8"))
    }
    func testUnreadableTitleWithoutRulesEvidenceDoesNotGuess() {
        let result = OfferRecognition.findOffer(lines: Array(lines.prefix(4)), catalog: CatalogIndex(cards: cards), playerClass: "ALL")
        XCTAssertNil(result.names)
    }
    func testAmbiguousRulesTextDoesNotGuess() {
        let duplicate = ArenaCard(id: "D", name: "Another resurrection card", text: cards[2].text)
        let result = OfferRecognition.findOffer(lines: lines, catalog: CatalogIndex(cards: cards + [duplicate]), playerClass: "ALL")
        XCTAssertNil(result.names)
    }
    func testRulesTextFromSidebarDoesNotFillMissingCard() {
        var shifted = lines
        for i in 4...6 { shifted[i].x = 0.91 }
        XCTAssertNil(OfferRecognition.findOffer(lines: shifted, catalog: CatalogIndex(cards: cards), playerClass: "ALL").names)
    }
}
