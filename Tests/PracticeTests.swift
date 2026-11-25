import Foundation
import SwiftData
import XCTest
@testable import Elphy

final class PracticeTests: XCTestCase {
    private struct Random: RandomNumberGenerator {
        var state: UInt64 = 18
        mutating func next() -> UInt64 {
            state = 2862933555777941757 &* state &+ 3037000493
            return state
        }
    }

    private let date = Date(timeIntervalSince1970: 1_810_000_000)

    private func catalog() throws -> [Card] {
        #if SWIFT_PACKAGE
        try Card.load(from: .module)
        #else
        try Card.load()
        #endif
    }

    private func engine(_ cards: [Card], seen: [Card], difficult: Set<String> = [],
                        history: [PracticeResult] = []) -> PracticeEngine {
        let progress = Dictionary(uniqueKeysWithValues: seen.map {
            ($0.id, StudyPlanner.Progress(introduced: date, due: date))
        })
        return PracticeEngine(cards: cards, progress: progress, difficult: difficult, history: history,
                              date: date, calendar: Calendar(identifier: .gregorian))
    }

    func testFiveEncounteredWordsCanPlayEveryGameAndUnseenTargetsAreExcluded() throws {
        let cards = try catalog()
        let seen = Array(cards.prefix(5))
        var random = Random()
        for game in PracticeGame.allCases {
            let empty = engine(cards, seen: []).round(for: game, mode: .standard, difficulty: .easy, using: &random)
            XCTAssertTrue(empty.isEmpty)
            let round = engine(cards, seen: seen).round(for: game, mode: .standard, difficulty: .easy, using: &random)
            XCTAssertEqual(Set(round.map(\.card.id)), Set(seen.map(\.id)))
        }
    }

    func testMatchingRejectsHomographsAndAlternativeTranslationCollisions() throws {
        let card = try XCTUnwrap(catalog().first)
        var homograph = card
        homograph.id = "homograph"
        homograph.meaningFa = "بازگشت"
        var sharedMeaning = card
        sharedMeaning.id = "shared"
        sharedMeaning.word = "return"
        sharedMeaning.meaningFa = "باز آمدن"
        sharedMeaning.alternativeMeaningsFa = ["بازگشت؛ " + card.meaningFa]
        var random = Random()
        let cards = [card, homograph, sharedMeaning]
        let round = engine(cards, seen: cards).round(for: .matching, mode: .quick, difficulty: .easy, using: &random)
        let words = round.map { $0.card.word.lowercased() }
        XCTAssertEqual(Set(words).count, words.count)
        XCTAssertFalse(Set(round.map(\.card.id)).isSuperset(of: [card.id, sharedMeaning.id]))
        XCTAssertLessThan(round.count, cards.count)
    }

    func testMatchingKeepsMistakenPairAvailableAndReportsAccuracy() throws {
        let cards = Array(try catalog().prefix(5))
        var random = Random()
        let questions = engine(cards, seen: cards).round(for: .matching, mode: .quick,
                                                       difficulty: .easy, using: &random)
        var round = PracticeMatchingRound(questions: questions, using: &random)
        XCTAssertNil(round.answer(0))
        round.select(0)
        XCTAssertEqual(round.answer(1), false)
        XCTAssertTrue(round.matched.isEmpty)
        XCTAssertEqual(round.answer(0), true)
        XCTAssertNil(round.completedAnswers)
        for index in 1..<questions.count {
            round.select(index)
            XCTAssertEqual(round.answer(index), true)
        }
        let answers = try XCTUnwrap(round.completedAnswers)
        let result = PracticeResult(id: UUID(), game: .matching, date: date, seconds: 10, answers: answers)
        XCTAssertEqual(result.correct, 5)
        XCTAssertEqual(result.mistakes, 1)
        XCTAssertEqual(result.accuracy, 83)
        let replay = PracticeMatchingRound(questions: questions, using: &random)
        XCTAssertTrue(replay.matched.isEmpty)
        XCTAssertNil(replay.completedAnswers)
    }

    func testCuratedQuestionsValidateInflectionsCapitalsAndSentenceEdits() throws {
        let cards = try catalog()
        var random = Random()
        let questions = cards.compactMap { PracticeCloze.question(for: $0, using: &random) }
        XCTAssertGreaterThanOrEqual(questions.count, 125)
        for question in questions {
            XCTAssertEqual(question.blank.replacingOccurrences(of: "_____", with: question.answer), question.card.exampleEn)
            XCTAssertEqual(Set(question.options.map { $0.lowercased() }).count, 4)
            XCTAssertEqual(question.options.filter { $0 == question.answer }.count, 1)
        }
        XCTAssertEqual(questions.first { $0.card.word == "arrive" }?.answer, "arrived")
        XCTAssertEqual(questions.first { $0.card.word == "choose" }?.answer, "Choose")
        XCTAssertEqual(questions.first { $0.card.word == "save" }?.answer, "saving")
        XCTAssertEqual(questions.first { $0.card.word == "include" }?.answer, "includes")
        XCTAssertEqual(questions.first { $0.card.word == "attend" }?.blank, "I’ll _____ the meeting online tomorrow.")
        var altered = try XCTUnwrap(cards.first)
        altered.exampleEn = "We arrived after dinner."
        XCTAssertNil(PracticeCloze.question(for: altered, using: &random))
        altered.word = "art"
        altered.exampleEn = "They started late."
        XCTAssertNil(PracticeCloze.blank(for: altered))
    }

    func testExpandedCatalogFeedsEveryPracticeGameAndMeaningQuiz() throws {
        let cards = try catalog()
        XCTAssertEqual(cards.count, 300)
        let new = Array(cards.suffix(150))
        var random = Random()
        let curated = new.compactMap { PracticeCloze.question(for: $0, using: &random) }
        XCTAssertEqual(curated.count, 88)
        let ids = Set(new.map(\.id))
        for game in PracticeGame.allCases {
            let round = engine(cards, seen: new).round(for: game, mode: .standard,
                                                      difficulty: .easy, using: &random)
            XCTAssertEqual(round.count, game == .matching ? 5 : 10)
            XCTAssertTrue(round.allSatisfy { ids.contains($0.card.id) })
            if game == .sentence {
                XCTAssertTrue(round.allSatisfy { Set($0.options).count == 4 && $0.options.contains($0.answer) })
            }
        }
        let questions = QuizSession.makeQuestions(practicedCards: new, distractorPool: cards,
                                                  limit: 150, using: &random)
        XCTAssertEqual(questions.count, 150)
        for question in questions {
            XCTAssertTrue(ids.contains(question.card.id))
            XCTAssertEqual(question.choices.filter { $0 == question.card.meaningFa }.count, 1)
            XCTAssertEqual(Set(question.choices.map(Card.normalizedMeaning)).count, 4)
        }
    }

    func testRepeatedLettersHintsUndoAndIndependentEvidence() {
        var random = Random()
        var tiles = PracticeTiles(answer: "letter", difficulty: .hard, using: &random)
        XCTAssertEqual(Set(tiles.tiles.map(\.id)).count, 8)
        XCTAssertEqual(tiles.tiles.filter { $0.letter == "t" }.count, 2)
        let wrong = tiles.tiles.first { $0.letter != "l" }!
        tiles.tap(wrong.id)
        XCTAssertTrue(tiles.reveal(first: true))
        XCTAssertEqual(tiles.value, "l")
        XCTAssertTrue(tiles.reveal(first: false))
        XCTAssertEqual(tiles.value, "le")
        tiles.remove(at: 1)
        XCTAssertEqual(tiles.value, "l")
        for letter in "etter" {
            let tile = tiles.tiles.first { $0.letter == letter && !tiles.placed.contains($0.id) }!
            tiles.tap(tile.id)
        }
        XCTAssertEqual(tiles.value, "letter")
        XCTAssertTrue(tiles.full)
        XCTAssertTrue(PracticeAnswer(cardID: "a", correct: true, attempts: 1, hints: 0).independent)
        XCTAssertFalse(PracticeAnswer(cardID: "a", correct: true, attempts: 1, hints: 2).independent)
        XCTAssertFalse(PracticeAnswer(cardID: "a", correct: true, attempts: 2, hints: 0).firstAttempt)
    }

    func testWeakSelectionAndRoundVariety() throws {
        let cards = Array(try catalog().prefix(18))
        let weak = cards[0].id
        var random = Random()
        let first = engine(cards, seen: cards, difficult: [weak])
            .round(for: .matching, mode: .weak, difficulty: .medium, using: &random)
        XCTAssertEqual(first.first?.card.id, weak)
        let history = [PracticeResult(id: UUID(), game: .matching, date: date, seconds: 10,
                                      answers: first.map { PracticeAnswer(cardID: $0.card.id, correct: true, attempts: 1, hints: 0) })]
        let second = engine(cards, seen: cards, history: history)
            .round(for: .matching, mode: .quick, difficulty: .medium, using: &random)
        XCTAssertTrue(Set(first.map(\.card.id)).isDisjoint(with: second.map(\.card.id)))
    }

    @MainActor func testResultsPersistWithoutWritingReviewStateAndAreIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Practice.store")
        let result = PracticeResult(id: UUID(), game: .builder, date: date, seconds: 15, answers: [
            PracticeAnswer(cardID: "one", correct: true, attempts: 1, hints: 0),
            PracticeAnswer(cardID: "two", correct: true, attempts: 2, hints: 1)
        ])
        do {
            let container = try PracticeStore.makeContainer(at: url)
            try PracticeStore.save(result, in: container.mainContext)
            try PracticeStore.save(result, in: container.mainContext)
        }
        let reopened = try PracticeStore.makeContainer(at: url)
        let stats = PracticeStatistics(results: try PracticeStore.results(in: reopened.mainContext))
        XCTAssertEqual(stats.results.count, 1)
        XCTAssertEqual(stats.questions, 2)
        XCTAssertEqual(stats.firstAttemptAccuracy, 50)
        XCTAssertEqual(stats.mostMissed, ["two"])
        XCTAssertEqual(stats.best?.id, result.id)
    }

    #if DEBUG
    @MainActor func testSimulationCopiesAndResetsPracticeWithoutChangingRealStoreOrReviewSchedule() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let real = try PracticeStore.makeContainer(at: directory.appending(path: "RealPractice.store"))
        let vocabulary = try ModelContainer(for: PersonalCard.self, ReviewState.self, ReviewEvent.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let reading = try ReadingStore.makeContainer(at: directory.appending(path: "Reading.store"))
        let calendar = Calendar(identifier: .gregorian)
        let first = PracticeResult(id: UUID(), game: .matching, date: date, seconds: 11, answers: [])
        try PracticeStore.save(first, in: real.mainContext)
        let simulation = try DeveloperSimulation.start(at: date, calendar: calendar, in: directory,
                                                         copying: (vocabulary.mainContext, reading.mainContext),
                                                         practice: real.mainContext)
        let context = simulation.container.mainContext
        let result = PracticeResult(id: UUID(), game: .builder, date: simulation.date, seconds: 29, answers: [])
        try PracticeStore.save(result, in: context)
        XCTAssertEqual(try PracticeStore.results(in: context).map(\.id), [result.id, first.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewEvent>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewState>()), 0)
        try simulation.resetDay()
        XCTAssertEqual(try PracticeStore.results(in: context).map(\.id), [first.id])
        try simulation.resetProgress()
        XCTAssertTrue(try PracticeStore.results(in: context).isEmpty)
        XCTAssertEqual(try PracticeStore.results(in: real.mainContext).map(\.id), [first.id])
    }

    @MainActor func testExistingSimulationStoreResumesWithPlaygroundSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let session = DeveloperSimulation.Session(id: UUID(), started: date, date: date, calendar: calendar)
        let profile = directory.appending(path: session.id.uuidString)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: directory.appending(path: "ActiveSession.json"))
        let card = try XCTUnwrap(catalog().first)
        do {
            let schema = Schema([PersonalCard.self, ReviewState.self, ReviewEvent.self,
                                 ReadingProgress.self, DailyReadingPick.self, SimulationCheckpoint.self,
                                 SimulationReadingCompletion.self])
            let configuration = ModelConfiguration("Simulation", schema: schema,
                                                   url: profile.appending(path: "Learning.store"), cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [configuration])
            try ReviewStore.record(card, rating: .good, attemptID: UUID(), date: date,
                                   in: old.mainContext, calendar: calendar)
        }
        let simulation = try XCTUnwrap(DeveloperSimulation.resume(in: directory))
        let context = simulation.container.mainContext
        XCTAssertEqual(simulation.id, session.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewState>()), 1)
        XCTAssertTrue(try PracticeStore.results(in: context).isEmpty)
    }
    #endif
}
