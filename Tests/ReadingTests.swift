import Foundation
import SwiftData
import XCTest
@testable import Elphy

final class ReadingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private var contentBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    private func load() throws -> (stories: [ReadingStory], cards: [Card]) {
        let cards = try Card.load(from: contentBundle)
        return (try ReadingContent.load(cards: cards, from: contentBundle), cards)
    }

    func testBundledStoriesValidateWithVocabularyOffline() throws {
        let (stories, cards) = try load()
        let cardIDs = Set(cards.map(\.id))
        XCTAssertEqual(stories.count, 20)
        XCTAssertEqual(Set(stories.map(\.id)).count, 20)
        XCTAssertEqual(stories.flatMap(\.questions).count, 60)
        let targetIDs = Set(stories.flatMap(\.targetWordIds))
        XCTAssertEqual(targetIDs.count, 104)
        XCTAssertTrue(targetIDs.isSubset(of: cardIDs))
        for story in stories {
            XCTAssertEqual(story.questions.count, 3)
            XCTAssertGreaterThan(story.readingMinutes, 0)
            for question in story.questions {
                XCTAssertEqual(question.optionsEn.count, 4)
                XCTAssertTrue(question.optionsEn.indices.contains(question.correctIndex))
                XCTAssertFalse(question.explanationFa.isEmpty)
            }
        }
    }

    func testLevelAndReadFilters() throws {
        let (stories, _) = try load()
        for (filter, count) in [(ReadingFilter.all, 20), (.a1, 6), (.a2, 10), (.b1, 4), (.read, 0)] {
            XCTAssertEqual(stories.filter { filter.includes($0, record: nil) }.count, count)
        }
        let read = ReadingRecord(read: true, bestScore: 0, recentScore: nil, attempts: 0, lastCompletion: nil)
        let story = try XCTUnwrap(stories.first)
        XCTAssertTrue(ReadingFilter.read.includes(story, record: read))
        XCTAssertFalse(read.completed)
    }

    func testRejectsBrokenReferencesQuestionsAndTargetOccurrences() throws {
        let (_, cards) = try load()
        let url = try XCTUnwrap(contentBundle.url(forResource: "elfy-reading-stories-20", withExtension: "json"))
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let original = try XCTUnwrap(source["stories"] as? [[String: Any]])
        for (field, replacement) in [
            ("targetWordIds", ["unknown"]),
            ("textEn", "No target appears here."),
            ("questions", [["id": "q1", "promptEn": "Which?", "optionsEn": ["A", "B", "C", "D"],
                            "correctIndex": 4, "explanationFa": "توضیح"]])
        ] as [(String, Any)] {
            var document = source
            var stories = original
            stories[0][field] = replacement
            document["stories"] = stories
            let corrupted = try JSONSerialization.data(withJSONObject: document)
            XCTAssertThrowsError(try ReadingContent.decode(corrupted, cards: cards), field)
        }
    }

    func testEnglishTokenRangesKeepPunctuationAndPersianContentIntact() throws {
        let (stories, _) = try load()
        let train = try XCTUnwrap(stories.first)
        let matches = ReadingVocabulary.matches(in: train)
        XCTAssertTrue(matches.contains { train.textEn[$0.range] == "leaves" && $0.id == "en-leave-verb" })
        XCTAssertTrue(matches.contains { train.textEn[$0.range] == "arrives" && $0.id == "en-arrive-verb" })
        XCTAssertTrue(ReadingVocabulary.forms(for: "bring").contains("brought"))
        let text = "پاسخ: “arrived,” Hamed’s quick snack in traffic."
        XCTAssertEqual(ReadingVocabulary.tokens(in: text).map { String(text[$0]) },
                       ["arrived", "Hamed’s", "quick", "snack", "in", "traffic"])
        XCTAssertEqual(train.titleFa, "قطار صبح زود")
        let cafe = try XCTUnwrap(stories.first { $0.id == "elfy-reading-07" })
        XCTAssertFalse(ReadingVocabulary.matches(in: cafe).contains { $0.id == "en-taste-verb" })
    }

    func testNewLearnerGetsBeginnerStoryAndRecentCompletionRotatesFallback() throws {
        let (stories, _) = try load()
        let first = try XCTUnwrap(ReadingRecommendationEngine.recommend(
            stories: stories, statuses: [:], progress: [:], recalls: [], records: [:], at: now
        ))
        XCTAssertEqual(first.storyID, "elfy-reading-01")
        XCTAssertTrue(first.matchingVocabularyIDs.isEmpty)
        let completed = ReadingRecord(read: true, bestScore: 3, recentScore: 3, attempts: 1, lastCompletion: now)
        let next = try XCTUnwrap(ReadingRecommendationEngine.recommend(
            stories: stories, statuses: [:], progress: [:], recalls: [], records: [first.storyID: completed], at: now
        ))
        XCTAssertEqual(next.storyID, "elfy-reading-02")
    }

    func testRecommendationsRespondToDifferentLearnersAndDifficultWords() throws {
        let (stories, cards) = try load()
        let travel = ["en-airport-noun", "en-airline-noun"]
        let professional = ["en-opportunity-noun", "en-consider-verb"]
        func recommend(_ ids: [String], misses: [Recall] = [],
                       records: [String: ReadingRecord] = [:]) throws -> ReadingRecommendationEngine.Recommendation {
            let yesterday = now.addingTimeInterval(-86_400)
            let progress = Dictionary(uniqueKeysWithValues: ids.map {
                ($0, StudyPlanner.Progress(introduced: yesterday, due: now))
            })
            let planner = StudyPlanner(cards: cards, progress: progress, goal: 5,
                                       at: now, calendar: calendar, recalls: misses)
            return try XCTUnwrap(ReadingRecommendationEngine.recommend(
                stories: stories, statuses: planner.status, progress: progress,
                recalls: misses, records: records, at: now
            ))
        }
        let airport = try recommend(travel)
        let email = try recommend(professional)
        XCTAssertEqual(airport.storyID, "elfy-reading-06")
        XCTAssertEqual(Set(airport.matchingVocabularyIDs), Set(travel))
        XCTAssertEqual(email.storyID, "elfy-reading-15")
        XCTAssertEqual(Set(email.matchingVocabularyIDs), Set(professional))
        let misses = [-600.0, 0.0].map {
            Recall(cardID: travel[0], date: now.addingTimeInterval($0), rating: .again)
        }
        XCTAssertGreaterThan(try recommend(travel, misses: misses).score, airport.score)
        let completed = ReadingRecord(read: true, bestScore: 3, recentScore: 3, attempts: 1, lastCompletion: now)
        let alternative = try recommend(travel + professional, misses: misses, records: [airport.storyID: completed])
        XCTAssertEqual(alternative.storyID, email.storyID)
    }

    func testQuizAcceptsOneAnswerPerQuestionAndStartsRetryWithZeroScore() throws {
        let story = try XCTUnwrap(load().stories.first)
        var quiz = ReadingQuiz(questions: story.questions)
        quiz.advance()
        quiz.select(-1)
        XCTAssertEqual(quiz.index, 0)
        XCTAssertNil(quiz.selection)
        for question in story.questions {
            quiz.select(question.correctIndex)
            quiz.select((question.correctIndex + 1) % 4)
            XCTAssertEqual(quiz.selection, question.correctIndex)
            XCTAssertEqual(quiz.isFinalAnswer, quiz.index == 2)
            quiz.advance()
        }
        XCTAssertEqual(quiz.score, 3)
        XCTAssertNil(quiz.current)
        quiz = ReadingQuiz(questions: story.questions)
        XCTAssertEqual(quiz.score, 0)
        XCTAssertEqual(quiz.index, 0)
        XCTAssertNil(quiz.selection)
    }

    @MainActor func testDailyStorySurvivesOtherReadingVocabularyChangesAndRelaunch() throws {
        let (stories, _) = try load()
        let first = stories[0]
        let ids = Set(stories.map(\.id))
        var calendar = calendar
        calendar.timeZone = .gmt
        let start = calendar.startOfDay(for: now).addingTimeInterval(60)
        let later = start.addingTimeInterval(600)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reading.store")

        do {
            let container = try ReadingStore.makeContainer(at: url)
            let context = container.mainContext
            let selected = try ReadingStore.dailyStoryID(at: start, calendar: calendar, availableIDs: ids,
                                                         in: context) { _ in first.id }
            XCTAssertEqual(selected, first.id)
            try ReadingStore.markRead(first.id, at: later, in: context)
            XCTAssertEqual(try ReadingStore.records(in: context)[first.id]?.completed, false)
            for story in stories[1...5] {
                try ReadingStore.complete(story, score: 2, at: later, in: context)
            }
            XCTAssertEqual(try ReadingStore.dailyStoryID(at: later, calendar: calendar, availableIDs: ids,
                                                        in: context) { _ in
                XCTFail("Reranked today's story after other reading or a new vocabulary match")
                return stories[6].id
            }, first.id)

            // Both the Today shortcut and the library finish via ReadingStore.complete.
            try ReadingStore.complete(first, score: 0, at: later, in: context)
            let completed = try XCTUnwrap(ReadingStore.records(in: context)[first.id])
            XCTAssertTrue(completed.completed)
            XCTAssertEqual(completed.recentScore, 0)
            XCTAssertTrue(ReadingFilter.all.includes(first, record: completed))
            XCTAssertTrue(ReadingFilter.read.includes(first, record: completed))
            XCTAssertEqual(try ReadingStore.dailyStoryID(at: later, calendar: calendar, availableIDs: ids,
                                                        in: context) { _ in
                XCTFail("Completion replaced today's story")
                return nil
            }, first.id)
        }
        let reopened = try ReadingStore.makeContainer(at: url)
        let context = reopened.mainContext
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: later, calendar: calendar, availableIDs: ids,
                                                    in: context) { _ in
            XCTFail("Reopening the store should reuse today's pick")
            return nil
        }, first.id)
        XCTAssertEqual(try ReadingStore.records(in: context)[first.id]?.recentScore, 0)

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: later))
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: tomorrow, calendar: calendar, availableIDs: ids,
                                                    in: context) { previous in
            XCTAssertEqual(previous, first.id)
            return stories[6].id
        }, stories[6].id)
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: later, calendar: calendar, availableIDs: ids,
                                                    in: context) { _ in nil }, first.id)

        let afterAbsence = try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: later))
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: afterAbsence, calendar: calendar, availableIDs: ids,
                                                    in: context) { previous in
            XCTAssertNil(previous)
            return stories[7].id
        }, stories[7].id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyReadingPick>()), 3)
    }

    func testDailyRankingAvoidsYesterdayAndCanRerecommendCompletedStories() throws {
        let (stories, _) = try load()
        let first = stories[0]
        let second = stories[1]
        let records = Dictionary(uniqueKeysWithValues: stories.enumerated().map { index, story in
            let completion = now.addingTimeInterval(Double(index - 30) * 86_400)
            return (story.id, ReadingRecord(read: true, bestScore: 3, recentScore: 3,
                                            attempts: 1, lastCompletion: completion))
        })
        XCTAssertEqual(records.count, 20)
        func pick(previous: String? = nil) -> String? {
            ReadingRecommendationEngine.recommend(stories: stories, statuses: [:], progress: [:], recalls: [],
                                                  records: records, at: now, calendar: calendar,
                                                  previousStoryID: previous)?.storyID
        }
        XCTAssertEqual(pick(), first.id)
        XCTAssertEqual(pick(previous: first.id), second.id)
        XCTAssertEqual(pick(previous: first.id), second.id)
    }

    @MainActor func testLocalDayAcrossDaylightSavingTimezoneAndMissingStory() throws {
        var eastern = calendar
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let dates = ISO8601DateFormatter()
        func time(_ value: String) throws -> Date { try XCTUnwrap(dates.date(from: value)) }
        let springStart = try time("2026-03-08T05:10:00Z")
        let springMidnight = try time("2026-03-09T04:00:00Z")
        XCTAssertLessThan(springMidnight.timeIntervalSince(springStart), 86_400)
        XCTAssertEqual(ReadingDay(at: springStart, calendar: eastern),
                       ReadingDay(at: springMidnight.addingTimeInterval(-1), calendar: eastern))
        XCTAssertNotEqual(ReadingDay(at: springStart, calendar: eastern),
                          ReadingDay(at: springMidnight, calendar: eastern))
        let fallStart = try time("2026-11-01T04:10:00Z")
        let fallEnd = try time("2026-11-02T04:50:00Z")
        XCTAssertGreaterThan(fallEnd.timeIntervalSince(fallStart), 86_400)
        XCTAssertEqual(ReadingDay(at: fallStart, calendar: eastern), ReadingDay(at: fallEnd, calendar: eastern))

        let schema = Schema([DailyReadingPick.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        var utc = calendar
        utc.timeZone = .gmt
        let instant = try time("2026-03-09T01:00:00Z")
        let ids: Set<String> = ["first", "second", "replacement"]
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: instant, calendar: eastern, availableIDs: ids,
                                                    in: context) { _ in "first" }, "first")
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: instant, calendar: utc, availableIDs: ids,
                                                    in: context) { previous in
            XCTAssertEqual(previous, "first")
            return "second"
        }, "second")
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: instant, calendar: eastern, availableIDs: ids,
                                                    in: context) { _ in nil }, "first")
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: instant, calendar: eastern, availableIDs: ["replacement"],
                                                    in: context) { _ in "replacement" }, "replacement")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyReadingPick>()), 2)
    }

    @MainActor func testAddingDailyPicksPreservesExistingReadingHistory() throws {
        let story = try XCTUnwrap(load().stories.first)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reading.store")
        do {
            let oldSchema = Schema([ReadingProgress.self])
            let configuration = ModelConfiguration("ReadingProgress", schema: oldSchema, url: url)
            let oldContainer = try ModelContainer(for: oldSchema, configurations: [configuration])
            try ReadingStore.complete(story, score: 2, at: now, in: oldContainer.mainContext)
        }
        let upgraded = try ReadingStore.makeContainer(at: url)
        let context = upgraded.mainContext
        XCTAssertEqual(try ReadingStore.records(in: context)[story.id]?.bestScore, 2)
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: now, calendar: calendar, availableIDs: [story.id],
                                                    in: context) { _ in story.id }, story.id)
        XCTAssertEqual(try ReadingStore.records(in: context)[story.id]?.attempts, 1)
    }

    @MainActor func testReadingProgressSurvivesReopenWithoutChangingFlashcardReviews() throws {
        let (stories, cards) = try load()
        let story = try XCTUnwrap(stories.first)
        let card = try XCTUnwrap(cards.first { $0.id == story.targetWordIds.first })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let readingURL = directory.appendingPathComponent("ReadingProgress.store")
        let vocabulary = try ModelContainer(for: PersonalCard.self, ReviewState.self, ReviewEvent.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let vocabularyContext = vocabulary.mainContext
        try ReviewStore.record(card, rating: .good, attemptID: UUID(), date: now, in: vocabularyContext,
                               calendar: calendar)
        let originalDue = try XCTUnwrap(vocabularyContext.fetch(FetchDescriptor<ReviewState>()).first).due
        let latest = now.addingTimeInterval(300)
        do {
            let reading = try ReadingStore.makeContainer(at: readingURL)
            let context = reading.mainContext
            try ReadingStore.markRead(story.id, at: now, in: context)
            let readOnly = try XCTUnwrap(ReadingStore.records(in: context)[story.id])
            XCTAssertTrue(readOnly.read)
            XCTAssertFalse(readOnly.completed)
            XCTAssertNil(readOnly.recentScore)
            try ReadingStore.complete(story, score: 3, at: now, in: context)
            try ReadingStore.complete(story, score: 1, at: latest, in: context)
            try ReadingStore.markRead(story.id, at: latest, in: context)
        }
        let reopened = try ReadingStore.makeContainer(at: readingURL)
        let records = try ReadingStore.records(in: reopened.mainContext)
        let record = try XCTUnwrap(records[story.id])
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.bestScore, 3)
        XCTAssertEqual(record.recentScore, 1)
        XCTAssertEqual(record.attempts, 2)
        XCTAssertEqual(record.lastCompletion, latest)

        let states = try vocabularyContext.fetch(FetchDescriptor<ReviewState>())
        let state = try XCTUnwrap(states.first)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(state.introduced, now)
        XCTAssertEqual(state.due, originalDue)
        XCTAssertEqual(state.days, 2)
        XCTAssertEqual(state.streak, 1)
        XCTAssertEqual(try vocabularyContext.fetchCount(FetchDescriptor<ReviewEvent>()), 1)
        let planner = StudyPlanner(cards: cards, progress: [card.id: state.progress], goal: 5,
                                   at: now, calendar: calendar)
        XCTAssertEqual(planner.introducedToday, 1)
        XCTAssertEqual(planner.newCards.count, 4)
    }
}
