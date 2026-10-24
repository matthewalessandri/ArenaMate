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
    func testRecentArenaResultsAreClassSpecificAndSampleAware() throws {
        let json = #"""
        {
          "data": {
            "MAGE": [
              {"card_id":"HIGH","drawn_win_rate":60,"num_games":5000},
              {"card_id":"LOW","drawn_win_rate":45,"num_games":5000},
              {"card_id":"TINY","drawn_win_rate":99,"num_games":1}
            ],
            "ALL": [
              {"card_id":"NEUTRAL","drawn_win_rate":52,"num_games":1000}
            ]
          }
        }
        """#
        let ratings = try ExternalRatings.parseHSReplay(Data(json.utf8), minimumRows: 4)
        let high = ArenaCard(id: "HIGH", name: "High")
        let low = ArenaCard(id: "LOW", name: "Low")
        let tiny = ArenaCard(id: "TINY", name: "Tiny")
        XCTAssertGreaterThan(try XCTUnwrap(ratings.score(card: high, playerClass: "MAGE")),
                             try XCTUnwrap(ratings.score(card: low, playerClass: "MAGE")))
        XCTAssertLessThan(try XCTUnwrap(ratings.score(card: tiny, playerClass: "MAGE")),
                          try XCTUnwrap(ratings.score(card: high, playerClass: "MAGE")))
        XCTAssertNotNil(ratings.score(card: ArenaCard(id: "NEUTRAL", name: "Neutral"), playerClass: "ROGUE"))
        XCTAssertNil(ratings.score(card: high, playerClass: "ROGUE"))
        XCTAssertEqual(ratings.evidence(card: high, playerClass: "MAGE")?.sampleSize, 5000)
    }
    func testPerformanceRatingsNormalizeMultiwordClassesAndCoreReprints() throws {
        let json = #"{"data":{"DEATH_KNIGHT":[{"card_id":"CS2_029","drawn_win_rate":55,"num_games":1000}]}}"#
        let ratings = try ExternalRatings.parseHSReplay(Data(json.utf8), minimumRows: 1)
        let core = ArenaCard(id: "CORE_CS2_029", name: "Fireball")
        XCTAssertNotNil(ratings.score(card: core, playerClass: "DEATHKNIGHT"))
    }
    func testRecentArenaResultsRejectIncompleteOrMalformedResponses() {
        XCTAssertThrowsError(try ExternalRatings.parseHSReplay(Data(#"{"data":{"MAGE":[]}}"#.utf8), minimumRows: 1))
        XCTAssertThrowsError(try ExternalRatings.parseHSReplay(Data("not json".utf8), minimumRows: 1))
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

final class DraftTitleRegressionTests: XCTestCase {
    // Card metadata reproduced from HearthSim's card definitions. Buckets and
    // tokens are real catalog entries, but aren't offered Arena card titles.
    private var catalog: CatalogIndex {
        CatalogIndex(cards: [
            ArenaCard(id: "PVPDR_BucketList_Mechs", name: "Mechs", type: "SPELL", collectible: false),
            ArenaCard(id: "PRO_001at", name: "Murloc", type: "MINION", collectible: false),
            ArenaCard(id: "TRLA_Paladin_01", name: "Magnetic", type: "SPELL", collectible: false),
            ArenaCard(id: "TTN_852e", name: "Noble Minibot", type: "ENCHANTMENT", collectible: false),
            ArenaCard(id: "YOG_525", name: "Muscle-o-Tron", type: "MINION", collectible: true),
            ArenaCard(id: "VAC_531", name: "Bayfin Bodybuilder", type: "MINION", collectible: true),
            ArenaCard(id: "TTN_852", name: "Noble Minibot", type: "MINION", collectible: true)
        ])
    }
    func testTribesAndKeywordsDoNotReplaceCardTitles() {
        let lines = [
            RecognizedLine(text: "Muscle-o-Tron", x: 0.19, y: 0.65),
            RecognizedLine(text: "Bayfin Bodybuilder", x: 0.44, y: 0.65),
            RecognizedLine(text: "Noble Minibot", x: 0.69, y: 0.65),
            RecognizedLine(text: "Mechs", x: 0.19, y: 0.46),
            RecognizedLine(text: "Murloc", x: 0.44, y: 0.46),
            RecognizedLine(text: "Magnetic", x: 0.69, y: 0.56)
        ]
        let offer = OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "ALL")
        XCTAssertEqual(offer.names, ["Muscle-o-Tron", "Bayfin Bodybuilder", "Noble Minibot"])
        XCTAssertFalse(offer.matched.contains("Mechs"))
        XCTAssertFalse(offer.matched.contains("Murloc"))
        XCTAssertFalse(offer.matched.contains("Magnetic"))
    }
    func testNormalOfferCompressedByDeckSidebarKeepsLeftMiddleRight() {
        let lines = [
            RecognizedLine(text: "Muscle-o-Tron", x: 0.247, y: 0.610),
            RecognizedLine(text: "Bayfin Bodybuilder", x: 0.408, y: 0.611),
            RecognizedLine(text: "Noble Minibot", x: 0.558, y: 0.609),
            RecognizedLine(text: "Murloc", x: 0.408, y: 0.46)
        ]
        XCTAssertEqual(OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "ALL").names,
            ["Muscle-o-Tron", "Bayfin Bodybuilder", "Noble Minibot"])
    }
    func testMissingTitleIsNotFilledWithKeyword() {
        let lines = [
            RecognizedLine(text: "Muscle-o-Tron", x: 0.19, y: 0.65),
            RecognizedLine(text: "Bayfin Bodybuilder", x: 0.44, y: 0.65),
            RecognizedLine(text: "Magnetic", x: 0.69, y: 0.56)
        ]
        XCTAssertNil(OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "ALL").names)
    }
    func testRealCardPreferredOverSameNamedEnchantment() {
        XCTAssertEqual(catalog.matchOCR("Noble Minibot")?.card.id, "TTN_852")
        XCTAssertEqual(catalog.find("Noble Minibot")?.card.id, "TTN_852")
        XCTAssertNil(catalog.matchOCR("Mechs"))
        XCTAssertNil(catalog.matchOCR("Murloc"))
        XCTAssertNil(catalog.matchOCR("Magnetic"))
        // Manual ID lookup still supports noncollectible entries.
        XCTAssertEqual(catalog.byGameId("PRO_001at")?.name, "Murloc")
    }
}

final class RecommendationExplanationTests: XCTestCase {
    private func pick(_ card: ArenaCard) -> DraftPick { DraftPick(card: card, score: 50) }
    private var midgame: [DraftPick] {
        (0..<5).map { pick(ArenaCard(id: "M\($0)", name: "Minion \($0)", cost: 4, type: "MINION")) }
    }
    private func score(_ card: ArenaCard, picks: [DraftPick] = [], ratings: ExternalRatings = ExternalRatings()) -> ScoreDetail {
        DraftScorer.score(card, picks: picks, ratings: ratings, playerClass: "MAGE")
    }
    func testMissingBoardClearExplainsAndChangesScore() {
        let clear = ArenaCard(id: "C", name: "Flamestrike", cost: 7, type: "SPELL", text: "Deal 5 damage to all enemy minions.")
        let needed = score(clear, picks: midgame)
        let covered = score(clear, picks: midgame + [pick(clear)])
        XCTAssertTrue(needed.explanation.contains("don't have a board clear"))
        XCTAssertTrue(needed.reasons.contains("First board clear"))
        XCTAssertGreaterThan(needed.total, covered.total)
        XCTAssertFalse(covered.explanation.contains("don't have a board clear"))
    }
    func testBuffAndSingleTargetRemovalDoNotClaimBoardClear() {
        for text in ["Give all enemy minions +1 Attack.", "Deal 5 damage to an enemy minion.", "Destroy an enemy minion."] {
            let result = score(ArenaCard(id: "S", name: "Spell", cost: 3, type: "SPELL", text: text), picks: midgame)
            XCTAssertFalse(result.explanation.contains("board clear"))
            XCTAssertFalse(result.reasons.contains("First board clear"))
        }
    }
    func testCurveNeedTracksActualDraft() {
        let early = ArenaCard(id: "E", name: "Early Minion", cost: 2, type: "MINION", attack: 2, health: 3)
        XCTAssertTrue(score(early, picks: midgame).explanation.contains("short on early minions"))
        let filled = (0..<6).map { _ in pick(early) }
        XCTAssertFalse(score(early, picks: filled).explanation.contains("short on early minions"))
    }
    func testTribalPayoffNamesAnActualPartnerAndWarnsWithoutOne() {
        let partner = ArenaCard(id: "D", name: "Azure Drake", cost: 5, type: "MINION", race: "DRAGON")
        let payoff = ArenaCard(id: "P", name: "Dragon Rider", cost: 4, type: "MINION", text: "Battlecry: If you're holding a Dragon, gain +2/+2.")
        let supported = score(payoff, picks: [pick(partner)])
        XCTAssertTrue(supported.explanation.contains("Azure Drake"))
        let unsupported = score(payoff)
        XCTAssertFalse(unsupported.explanation.contains("Azure Drake"))
        XCTAssertTrue(unsupported.explanation.contains("haven't drafted any Dragon support"))
        XCTAssertGreaterThan(supported.total, unsupported.total)
        XCTAssertTrue(score(partner, picks: [pick(payoff)]).explanation.contains("Dragon Rider"))
    }
    func testMagneticOnlyNamesADraftedMech() {
        let card = ArenaCard(id: "N", name: "Noble Minibot", cost: 2, type: "MINION", mechanics: ["MAGNETIC"], race: "MECH")
        let partner = ArenaCard(id: "M", name: "Muscle-o-Tron", cost: 3, type: "MINION", race: "MECH")
        XCTAssertTrue(score(card, picks: [pick(partner)]).explanation.contains("Mechs you've already drafted, including Muscle-o-Tron"))
        XCTAssertFalse(score(card).explanation.contains("magnetize"))
    }
    func testOpponentSpellTriggerDoesNotClaimSynergyWithOwnSpells() {
        let spell = ArenaCard(id: "S", name: "Spell", type: "SPELL")
        let picks = Array(repeating: pick(spell), count: 5)
        let opponentPayoff = ArenaCard(id: "O", name: "Watcher", cost: 4, type: "MINION", text: "Whenever your opponent casts a spell, gain +1 Attack.")
        XCTAssertFalse(score(opponentPayoff, picks: picks).reasons.contains("Fits existing spells"))
        XCTAssertFalse(score(opponentPayoff, picks: picks).explanation.contains("help trigger"))
        let ownPayoff = ArenaCard(id: "P", name: "Spellcaster", cost: 4, type: "MINION", text: "Whenever you cast a spell, gain +1 Attack.")
        XCTAssertTrue(score(ownPayoff, picks: picks).explanation.contains("drafted 5 spells"))
    }
    func testSpellDamageRequiresDamageSpellsRatherThanAnySpells() {
        let minion = ArenaCard(id: "S", name: "Spell Support", cost: 4, type: "MINION", text: "Spell Damage +1")
        let draw = ArenaCard(id: "DRAW", name: "Arcane Intellect", type: "SPELL", text: "Draw 2 cards.")
        XCTAssertFalse(score(minion, picks: Array(repeating: pick(draw), count: 5)).reasons.contains("Spell-damage support"))
        let damage = ArenaCard(id: "F", name: "Frostbolt", type: "SPELL", text: "Deal 3 damage to a character.")
        XCTAssertTrue(score(minion, picks: [pick(damage), pick(damage)]).explanation.contains("Frostbolt"))
    }
    func testCurrentCatalogRacesAndLegacyMechanicalRaceEnableMechSynergy() throws {
        let data = Data(#"{"id":"M","name":"Muscle-o-Tron","type":"MINION","races":["MECHANICAL"]}"#.utf8)
        let partner = try JSONDecoder().decode(ArenaCard.self, from: data)
        let magnetic = ArenaCard(id: "N", name: "Noble Minibot", cost: 2, type: "MINION", mechanics: ["MAGNETIC"], races: ["MECHANICAL"])
        XCTAssertTrue(score(magnetic, picks: [pick(partner)]).explanation.contains("Muscle-o-Tron"))
        XCTAssertEqual(partner.tribes, ["MECH"])
        XCTAssertEqual(ArenaCard(id: "L", name: "Legacy Mech", race: "MECHANICAL").tribes, ["MECH"])
        let dual = ArenaCard(id: "D", name: "Dual tribe", races: ["DRAGON", "BEAST"])
        XCTAssertEqual(dual.tribes, ["DRAGON", "BEAST"])
    }
    func testFallbackDoesNotTeachKeywordsOrInventDeckNeed() {
        for mechanic in ["RUSH", "TAUNT", "LIFESTEAL", "DIVINE_SHIELD", "CHARGE"] {
            let card = ArenaCard(id: "R", name: "Strong Minion", cost: 4, type: "MINION", mechanics: [mechanic])
            let explanation = score(card).explanation
            XCTAssertTrue(explanation.contains("Strong Minion"))
            XCTAssertFalse(explanation.contains("standalone"))
            XCTAssertFalse(explanation.lowercased().contains(mechanic.lowercased()))
        }
        let plain = ArenaCard(id: "V", name: "Plain Minion", cost: 4, type: "MINION")
        var ratings = ExternalRatings(); ratings.byId["V"] = 90
        let rated = score(plain, ratings: ratings)
        XCTAssertTrue(rated.explanation.contains("imported ratings"))
        XCTAssertFalse(rated.explanation.contains("estimated standalone"))
        XCTAssertTrue(score(plain).explanation.contains("Plain Minion"))
    }
}

final class SidebarTitleRegressionTests: XCTestCase {
    private let names = ["Deputization Aura", "Carry-On Grub", "Cult Neophyte", "Hand of Infinity"]
    private var catalog: CatalogIndex {
        CatalogIndex(cards: names.enumerated().map { ArenaCard(id: String($0.offset), name: $0.element, collectible: true) })
    }
    private var lines: [RecognizedLine] {
        [RecognizedLine(text: names[0], x: 0.247, y: 0.610),
         RecognizedLine(text: names[1], x: 0.408, y: 0.611),
         RecognizedLine(text: names[2], x: 0.558, y: 0.609),
         RecognizedLine(text: names[3], x: 0.767, y: 0.610)]
    }
    func testFourthSidebarTitleCannotReplaceCultNeophyte() {
        XCTAssertEqual(OfferRecognition.findOffer(lines: lines, catalog: catalog, playerClass: "ALL").names,
                       Array(names.prefix(3)))
    }
    func testWeakAlternativeDoesNotBeatStrongCultNeophyteReading() {
        var observations = Array(lines.prefix(3))
        observations[2].text = "Cult Neophyle"
        observations[2].confidence = 0.98
        observations.append(RecognizedLine(text: "Hand of Infinity", x: 0.558, y: 0.609, confidence: 0.2))
        XCTAssertEqual(OfferRecognition.findOffer(lines: observations, catalog: catalog, playerClass: "ALL").names,
                       Array(names.prefix(3)))
    }
    func testEvenlySpacedMiddleRightAndSidebarCannotShiftIntoThreeSlots() {
        let shifted = [RecognizedLine(text: names[1], x: 0.408, y: 0.61),
                       RecognizedLine(text: names[2], x: 0.558, y: 0.61),
                       RecognizedLine(text: names[3], x: 0.708, y: 0.61)]
        XCTAssertNil(OfferRecognition.findOffer(lines: shifted, catalog: catalog, playerClass: "ALL").names)
    }
    func testSidebarTitleIsExcludedEvenWhenEvenlySpacedWithTwoBoardTitles() {
        let outsideBoard = [RecognizedLine(text: names[0], x: 0.27, y: 0.61),
                            RecognizedLine(text: names[1], x: 0.51, y: 0.61),
                            RecognizedLine(text: names[3], x: 0.75, y: 0.61)]
        XCTAssertNil(OfferRecognition.findOffer(lines: outsideBoard, catalog: catalog, playerClass: "ALL").names)
    }
    func testSidebarCannotReplaceUnreadableThirdTitle() {
        var missing = lines
        missing.remove(at: 2)
        XCTAssertNil(OfferRecognition.findOffer(lines: missing, catalog: catalog, playerClass: "ALL").names)
    }
    func testSidebarCannotReplaceUnreadableMiddleTitle() {
        var missing = lines
        missing.remove(at: 1)
        XCTAssertNil(OfferRecognition.findOffer(lines: missing, catalog: catalog, playerClass: "ALL").names)
    }
}

final class ExplicitRationaleTests: XCTestCase {
    private let hammer = ArenaCard(id: "H", name: "Hammer of Wrath", cost: 4, type: "SPELL", text: "Deal 3 damage. Draw a card.")
    private let cult = ArenaCard(id: "C", name: "Cult Neophyte", cost: 2, type: "MINION", attack: 3, health: 2)
    private let body = ArenaCard(id: "B", name: "Plain Minion", cost: 4, type: "MINION", attack: 4, health: 5)
    private func score(_ card: ArenaCard, picks: [DraftPick] = []) -> ScoreDetail {
        DraftScorer.score(card, picks: picks, ratings: ExternalRatings(), playerClass: "PALADIN")
    }
    private func explain(_ offers: [ArenaCard], picks: [DraftPick] = [], ratings: ExternalRatings = ExternalRatings()) -> String? {
        DraftScorer.recommendation(offers: offers, picks: picks, ratings: ratings, playerClass: "PALADIN")
    }
    func testHammerComparedWithActualRunnerUpForDamageAndDraw() throws {
        let text = try XCTUnwrap(explain([body, hammer, cult]))
        XCTAssertTrue(text.contains("Hammer of Wrath over Cult Neophyte"))
        XCTAssertTrue(text.contains("damage"))
        XCTAssertTrue(text.contains("card draw"))
        XCTAssertFalse(text.contains("standalone"))
        XCTAssertFalse(text.contains("highest estimated"))
    }
    func testDrawContextUsesActualDraftAndDoesNotMissDrawFour() {
        let picks = Array(repeating: DraftPick(card: body, score: 48), count: 5)
        XCTAssertTrue(score(hammer, picks: picks).explanation.contains("None of your 5 drafted cards"))
        let drawFour = ArenaCard(id: "D", name: "Big Draw", type: "SPELL", text: "Draw 4 cards.")
        let covered = picks + [DraftPick(card: drawFour, score: 50)]
        XCTAssertFalse(score(hammer, picks: covered).explanation.contains("provide card draw yet"))
    }
    func testRecoveryContextDoesNotInventCurrentHealthAndRecognizesGrantedLifesteal() {
        let lifesteal = ArenaCard(id: "L", name: "Recovery Minion", cost: 4, type: "MINION", mechanics: ["LIFESTEAL"], attack: 4, health: 5)
        let picks = Array(repeating: DraftPick(card: body, score: 48), count: 5)
        let text = score(lifesteal, picks: picks).explanation
        XCTAssertTrue(text.contains("haven't drafted a recovery card"))
        XCTAssertFalse(text.contains("low health"))
        XCTAssertFalse(text.contains("when this deals damage"))
        let aura = ArenaCard(id: "A", name: "Deputization Aura", type: "SPELL", text: "Your left-most minion has +2 Attack and Lifesteal.")
        XCTAssertFalse(score(lifesteal, picks: picks + [DraftPick(card: aura, score: 50)]).explanation.contains("haven't drafted a recovery card"))
    }
    func testNamedSynergyTakesPriorityOverIndividualCardComparison() throws {
        let mech = ArenaCard(id: "M", name: "Muscle-o-Tron", cost: 3, type: "MINION", races: ["MECHANICAL"])
        let magnetic = ArenaCard(id: "N", name: "Noble Minibot", cost: 2, type: "MINION", mechanics: ["MAGNETIC"], attack: 10, health: 10)
        let text = try XCTUnwrap(explain([magnetic, body, cult], picks: [DraftPick(card: mech, score: 50)]))
        XCTAssertTrue(text.contains("Muscle-o-Tron"))
        XCTAssertFalse(text.contains("standalone"))
    }
    func testImportedRatingsAreComparedAsRatingsAndMixedSourcesNotConflated() throws {
        var ratings = ExternalRatings(); ratings.byId["H"] = 90; ratings.byId["C"] = 80
        let text = try XCTUnwrap(explain([hammer, cult, body], ratings: ratings))
        XCTAssertTrue(text.contains("Hammer of Wrath at 90"))
        XCTAssertTrue(text.contains("Cult Neophyte at 80/100"))
        ratings.byId.removeValue(forKey: "C")
        let mixed = try XCTUnwrap(explain([hammer, cult, body], ratings: ratings))
        XCTAssertTrue(mixed.contains("imported ratings give Hammer of Wrath 90/100"))
        XCTAssertFalse(mixed.contains("Cult Neophyte at"))
    }
    func testTiesAndMissingMetadataAreExplicit() throws {
        let same = ArenaCard(id: "S", name: "Same Stats", cost: 4, type: "MINION", attack: 4, health: 5)
        let weak = ArenaCard(id: "W", name: "Weak Body", cost: 4, type: "MINION", attack: 1, health: 1)
        XCTAssertTrue(try XCTUnwrap(explain([body, same, weak])).contains("tied in my estimate"))
        XCTAssertNil(explain([hammer, cult]))
        XCTAssertTrue(score(ArenaCard(id: "?", name: "Unknown")).explanation.contains("current scoring rules"))
    }
    func testContributionsPreserveExistingNumericScores() {
        XCTAssertEqual(score(hammer).total, 72)
        XCTAssertEqual(score(cult).base, 51)
        XCTAssertEqual(score(cult).total, 54)
        XCTAssertEqual(score(body).total, 48)
        let rush = ArenaCard(id: "R", name: "Rush", cost: 4, type: "MINION", mechanics: ["RUSH"], attack: 4, health: 5)
        XCTAssertEqual(score(rush).total, 57)
        let both = ArenaCard(id: "D", name: "Discover and Draw", cost: 4, type: "SPELL", text: "Discover a spell. Draw a card.")
        XCTAssertEqual(score(both).total, 67)
        XCTAssertEqual(score(both).factors.first(where: { $0.key == "draw" })?.points, 4)
        XCTAssertEqual(score(both).factors.first(where: { $0.key == "discover" })?.points, 11)
    }
    func testComparativeExplanationRetainsMissingSupportCaution() throws {
        let payoff = ArenaCard(id: "P", name: "Unsupported Dragon", cost: 4, type: "MINION", text: "If you're holding a Dragon, gain +2/+2.", attack: 10, health: 10)
        let text = try XCTUnwrap(explain([payoff, body, cult]))
        XCTAssertTrue(text.contains("haven't drafted any Dragon support"))
    }
}

final class SummonPayoffTests: XCTestCase {
    private let shanty = ArenaCard(id: "VAC_558", name: "Sea Shanty", cost: 10, type: "SPELL",
        text: "Summon three 5/5 Pirates. Costs (1) less for each spell you've cast on characters this game.")
    private func score(_ card: ArenaCard, support: [ArenaCard] = []) -> ScoreDetail {
        DraftScorer.score(card, picks: support.map { DraftPick(card: $0, score: 50) }, ratings: ExternalRatings(), playerClass: "PALADIN")
    }
    func testSeaShantyEvaluatesBodiesAndWarnsAboutUnsupportedCost() {
        let result = score(shanty)
        XCTAssertTrue(result.factors.contains { $0.key == "summon" && $0.description == "three 5/5 bodies" && $0.points > 0 })
        XCTAssertGreaterThan(result.base, 52)
        XCTAssertTrue(result.explanation.contains("board refill"))
        XCTAssertTrue(result.explanation.contains("10 mana"))
        XCTAssertTrue(result.explanation.contains("still need character-targeted spells"))
        XCTAssertFalse(result.explanation.contains("isn't covered"))
        XCTAssertFalse(result.explanation.contains("standalone"))
    }
    func testDiscountSupportNamesActualTargetedSpellsWithoutAssumingCasts() {
        let hammer = ArenaCard(id: "H", name: "Hammer of Wrath", cost: 4, type: "SPELL", text: "Deal 3 damage. Draw a card.")
        let blessing = ArenaCard(id: "B", name: "Blessing of Kings", cost: 4, type: "SPELL", text: "Give a minion +4/+4.")
        let result = score(shanty, support: [hammer, blessing])
        XCTAssertTrue(result.explanation.contains("drafted 2 character-targeted spells"))
        XCTAssertTrue(result.explanation.contains("Hammer of Wrath and Blessing of Kings"))
        XCTAssertTrue(result.explanation.contains("help reduce its 10-mana starting cost"))
        XCTAssertFalse(result.explanation.contains("costs 8"))
        XCTAssertGreaterThan(result.total, score(shanty).total)
    }
    func testAurasDrawGlobalAndRandomSpellsAreNotDiscountEnablers() {
        let nonTargets = [
            ArenaCard(id: "A", name: "Deputization Aura", type: "SPELL", text: "Your left-most minion has +2 Attack and Lifesteal."),
            ArenaCard(id: "D", name: "Draw", type: "SPELL", text: "Draw 2 cards."),
            ArenaCard(id: "G", name: "Global", type: "SPELL", text: "Deal 3 damage to all enemy minions."),
            ArenaCard(id: "R", name: "Random", type: "SPELL", text: "Deal 3 damage to a random enemy minion.")
        ]
        XCTAssertTrue(score(shanty, support: nonTargets).explanation.contains("still need character-targeted spells"))
        XCTAssertFalse(score(shanty, support: nonTargets).reasons.contains("Character-targeted spell discount support"))
    }
    func testGeneralSummonParserHandlesWordsDigitsAndHTML() {
        for text in ["Summon two 3/3 Wolves.", "<b>Summon</b> 2 3/3 Wolves.", "Summon two\n3/3 Wolves."] {
            let card = ArenaCard(id: "S", name: "Pack", cost: 4, type: "SPELL", text: text)
            let result = score(card)
            XCTAssertTrue(result.factors.contains { $0.key == "summon" && $0.description == "two 3/3 bodies" })
            XCTAssertTrue(result.explanation.contains("board refill"))
        }
    }
    func testEnemyAndTriggeredSummonsAreNotTreatedAsImmediateFriendlyBoardRefills() {
        for text in ["Summon three 5/5 Pirates for your opponent.",
                     "If you control a Pirate, summon three 5/5 Pirates.",
                     "Give a minion Deathrattle: Summon three 5/5 Pirates.",
                     "At the end of your turn, summon three 5/5 Pirates."] {
            let result = score(ArenaCard(id: "S", name: "Conditional", cost: 4, type: "SPELL", text: text))
            XCTAssertFalse(result.factors.contains { $0.key == "summon" })
            XCTAssertFalse(result.explanation.contains("board refill"))
        }
    }
    func testUnknownEffectsAreAttributedToScoringLimitsNotMissingCardData() {
        let card = ArenaCard(id: "U", name: "Unsupported Effect", cost: 4, type: "SPELL", text: "Do a genuinely new effect.")
        XCTAssertTrue(score(card).explanation.contains("current scoring rules"))
        XCTAssertFalse(score(card).explanation.contains("card information available"))
    }
}
