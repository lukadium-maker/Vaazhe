import XCTest
import SwiftData
@testable import Vaazhe

final class VaazheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let card = Card(id: "personal-test", word: "arrive", partOfSpeech: "verb", level: "",
                            meaningFa: "رسیدن", exampleEn: "", exampleFa: "", topic: "")

    func testSchedulingTransitions() {
        let calendar = Calendar(identifier: .gregorian)
        let new = Schedule(due: now)
        let hard = new.rated(.hard, at: now, calendar: calendar)
        let good = new.rated(.good, at: now, calendar: calendar)
        XCTAssertGreaterThan(good.due, hard.due)
        XCTAssertEqual(good.rated(.good, at: now, calendar: calendar).days, 4)
        let again = good.rated(.again, at: now, calendar: calendar)
        XCTAssertEqual(again.streak, 0)
        XCTAssertEqual(again.due.timeIntervalSince(now), 600)
    }

    func testForgottenCardReturnsAfterOtherCards() {
        var second = card
        second.id = "second"
        var third = card
        third.id = "third"
        var queue = StudyQueue(cards: [card, second, third])
        queue.advance(.again)
        XCTAssertEqual(queue.cards.map(\.id), ["second", "third", card.id])
        queue.advance(.good)
        queue.advance(.good)
        queue.advance(.good)
        XCTAssertEqual(queue.count, 4)
        XCTAssertEqual(queue.practiced.count, 3)
        XCTAssertTrue(queue.needsPractice.isEmpty)
    }

    func testDailyPlannerOrdersDueCardsAndPrioritizesPersonalNewCards() throws {
        func cardWithID(_ id: String) -> Card {
            var copy = card
            copy.id = id
            return copy
        }

        let calendar = Calendar(identifier: .gregorian)
        let cards = ["bundled-new", "due-later", "personal-new", "due-earlier", "seen-today"].map(cardWithID)
        let yesterday = now.addingTimeInterval(-86_400)
        let progress: [String: StudyPlanner.Progress] = [
            "due-later": .init(introduced: yesterday, due: now),
            "due-earlier": .init(introduced: yesterday, due: yesterday),
            "seen-today": .init(introduced: now, due: now.addingTimeInterval(3_600))
        ]
        let planner = StudyPlanner(cards: cards, progress: progress, goal: 2, at: now, calendar: calendar)
        let plan = try XCTUnwrap(planner.dailyPlan)
        XCTAssertEqual(plan.cards.map(\.id), ["due-earlier", "due-later", "personal-new"])
        XCTAssertEqual(plan.newIDs, ["personal-new"])
        XCTAssertEqual(planner.introducedCount, 3)

        let zeroGoal = StudyPlanner(cards: cards, progress: progress, goal: 0, at: now, calendar: calendar)
        XCTAssertEqual(zeroGoal.dailyPlan?.cards.map(\.id), ["due-earlier", "due-later"])
        XCTAssertNil(StudyPlanner(cards: [card], progress: [:], goal: 0, at: now, calendar: calendar).dailyPlan)
    }

    func testSessionOnlyAdvancesAfterSuccessfulSaveAndRejectsStaleAttempts() throws {
        enum TestError: Error { case writeFailed }
        var session = StudySession(plan: StudyPlan(cards: [card], newIDs: [card.id]))
        let attempt = session.attemptID
        session.submit(.good, for: attempt) { _, _, _ in XCTFail("Unrevealed card was recorded") }

        session.reveal()
        XCTAssertThrowsError(try session.submit(.good, for: attempt) { _, _, _ in throw TestError.writeFailed })
        XCTAssertEqual(session.currentCard?.id, card.id)
        XCTAssertEqual(session.attemptID, attempt)
        XCTAssertTrue(session.isRevealed)

        session.submit(.good, for: attempt) { savedCard, _, savedAttempt in
            XCTAssertEqual(savedCard.id, card.id)
            XCTAssertEqual(savedAttempt, attempt)
        }
        session.submit(.good, for: attempt) { _, _, _ in XCTFail("Stale attempt was recorded") }
        XCTAssertNil(session.currentCard)
        XCTAssertFalse(session.isRevealed)
        XCTAssertEqual(session.newCardsPracticed, 1)
        XCTAssertEqual(session.queue.count, 1)
    }

    @MainActor func testProgressAndCustomCardSurviveReopeningAndDeduplicate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema([PersonalCard.self, ReviewState.self, ReviewEvent.self])
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"))
        let attempt = UUID()
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            context.insert(PersonalCard(card))
            try ReviewStore.record(card, rating: .good, attemptID: attempt, date: now, in: context)
            try ReviewStore.record(card, rating: .again, attemptID: attempt, date: now, in: context)
        }
        let reopenedContainer = try ModelContainer(for: schema, configurations: [config])
        defer { withExtendedLifetime(reopenedContainer) {} }
        let reopened = reopenedContainer.mainContext
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<ReviewEvent>()), 1)
        XCTAssertEqual(try reopened.fetch(FetchDescriptor<ReviewState>()).first?.streak, 1)
        XCTAssertEqual(try reopened.fetch(FetchDescriptor<PersonalCard>()).first?.card.word, card.word)
    }
}

final class PronunciationSelectionTests: XCTestCase {
    private struct Voice {
        let id: String
        let language: String
        let quality: Int
    }

    func testVoiceSelectionPrefersHighestQualityWithinExactAccent() {
        let voices = [
            Voice(id: "UK basic", language: "en-GB", quality: 1),
            Voice(id: "US premium", language: "en-US", quality: 3),
            Voice(id: "UK enhanced", language: "en-gb", quality: 2)
        ]
        XCTAssertEqual(
            EnglishAccent.british.bestVoice(in: voices, language: \.language, quality: \.quality)?.id,
            "UK enhanced"
        )
        XCTAssertEqual(
            EnglishAccent.american.bestVoice(in: voices, language: \.language, quality: \.quality)?.id,
            "US premium"
        )
    }

    func testUnavailableAccentDoesNotSubstituteAnotherEnglishVoice() {
        let voices = [
            Voice(id: "US basic", language: "en-US", quality: 1),
            Voice(id: "AU enhanced", language: "en-AU", quality: 2)
        ]
        XCTAssertNil(EnglishAccent.british.bestVoice(in: voices, language: \.language, quality: \.quality))
        XCTAssertEqual(
            EnglishAccent.american.bestVoice(in: voices, language: \.language, quality: \.quality)?.id,
            "US basic"
        )
    }

    func testExistingAccentPreferenceAndLegacyOffValue() {
        XCTAssertEqual(EnglishAccent.preferred("en-GB"), .british)
        XCTAssertEqual(EnglishAccent.preferred("en-US"), .american)
        XCTAssertEqual(EnglishAccent.preferred("off"), .american)
    }
}

final class QuizTests: XCTestCase {
    private struct SeededRandom: RandomNumberGenerator {
        var state: UInt64 = 42

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return state
        }
    }

    private func card(_ word: String, _ meaning: String, alternatives: [String] = []) -> Card {
        Card(id: word, word: word, partOfSpeech: "verb", level: "A1", meaningFa: meaning,
             alternativeMeaningsFa: alternatives, exampleEn: "", exampleFa: "", topic: "")
    }

    func testQuestionsHaveFourDistinctChoicesAndExcludeOverlappingMeanings() throws {
        var random = SeededRandom()
        let cards = [
            card("remember", "به یاد آوردن", alternatives: ["یادآوری کردن"]),
            card("recall", "يادآوری كردن"),
            card("wait", "منتظر ماندن"),
            card("leave", "رفتن"),
            card("bring", "آوردن")
        ]
        let questions = QuizSession.makeQuestions(practicedCards: cards, distractorPool: cards, limit: 5, using: &random)
        XCTAssertEqual(questions.count, 5)
        XCTAssertTrue(questions.allSatisfy { Set($0.choices).count == 4 && $0.choices.contains($0.card.meaningFa) })
        let remember = try XCTUnwrap(questions.first { $0.card.word == "remember" })
        XCTAssertFalse(remember.choices.contains("يادآوری كردن"))
        XCTAssertTrue(QuizSession.makeQuestions(practicedCards: cards, distractorPool: Array(cards.prefix(3)), limit: 10, using: &random).isEmpty)
    }

    func testOnlyPracticedCardsBecomeQuestions() {
        var random = SeededRandom()
        let practiced = [card("wait", "منتظر ماندن")]
        let deck = practiced + [card("leave", "رفتن"), card("bring", "آوردن"), card("sit", "نشستن")]
        let questions = QuizSession.makeQuestions(
            practicedCards: practiced, distractorPool: deck, limit: 10, using: &random
        )
        XCTAssertEqual(questions.map(\.id), ["wait"])
        XCTAssertEqual(questions.first.map { Set($0.choices) }, Set(deck.map(\.meaningFa)))
        XCTAssertTrue(QuizSession.makeQuestions(
            practicedCards: [], distractorPool: deck, limit: 10, using: &random
        ).isEmpty)
    }

    func testQuizGradesOnlyFirstValidChoiceAndCompletes() {
        let first = QuizQuestion(card: card("leave", "رفتن"), choices: ["رفتن", "ماندن", "نشستن", "ایستادن"])
        let second = QuizQuestion(card: card("wait", "منتظر ماندن"), choices: ["آوردن", "منتظر ماندن", "دیدن", "رفتن"])
        var quiz = QuizSession(questions: [first, second])
        quiz.next()
        quiz.answer("نامعتبر")
        XCTAssertEqual(quiz.index, 0)
        XCTAssertNil(quiz.selected)

        quiz.answer("ماندن")
        quiz.answer("رفتن")
        XCTAssertEqual(quiz.correctCount, 0)
        XCTAssertEqual(quiz.selected, "ماندن")
        quiz.next()
        XCTAssertEqual(quiz.currentQuestion?.id, second.id)
        quiz.answer(second.card.meaningFa)
        quiz.next()
        XCTAssertNil(quiz.currentQuestion)
        XCTAssertEqual(quiz.correctCount, 1)
    }
}
