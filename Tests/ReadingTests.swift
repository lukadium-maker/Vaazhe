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

    func testApprovedStoryCoversAreMappedByStableIDWithFallbackForOtherStories() throws {
        let (stories, _) = try load()
        let expected = [
            "elfy-reading-01": "story_elfy-reading-01_cover",
            "elfy-reading-02": "story_elfy-reading-02_cover",
            "elfy-reading-03": "story_elfy-reading-03_cover",
            "elfy-reading-04": "story_elfy-reading-04_cover",
            "elfy-reading-05": "story_elfy-reading-05_cover",
            "elfy-reading-06": "story_elfy-reading-06_cover",
            "elfy-reading-07": "story_elfy-reading-07_cover",
            "elfy-reading-08": "story_elfy-reading-08_cover",
            "elfy-reading-09": "story_elfy-reading-09_cover",
            "elfy-reading-10": "story_elfy-reading-10_cover",
            "elfy-reading-11": "story_elfy-reading-11_cover",
            "elfy-reading-12": "story_elfy-reading-12_cover",
            "elfy-reading-13": "story_elfy-reading-13_cover",
            "elfy-reading-14": "story_elfy-reading-14_cover",
            "elfy-reading-15": "story_elfy-reading-15_cover",
            "elfy-reading-16": "story_elfy-reading-16_cover",
            "elfy-reading-17": "story_elfy-reading-17_cover",
            "elfy-reading-18": "story_elfy-reading-18_cover",
            "elfy-reading-19": "story_elfy-reading-19_cover",
            "elfy-reading-20": "story_elfy-reading-20_cover",
            "elfy-reading-21": "story_elfy-reading-21_cover",
            "elfy-reading-22": "story_elfy-reading-22_cover",
            "elfy-reading-23": "story_elfy-reading-23_cover",
            "elfy-reading-24": "story_elfy-reading-24_cover",
            "elfy-reading-25": "story_elfy-reading-25_cover",
            "elfy-reading-26": "story_elfy-reading-26_cover",
            "elfy-reading-27": "story_elfy-reading-27_cover",
            "elfy-reading-28": "story_elfy-reading-28_cover",
            "elfy-reading-29": "story_elfy-reading-29_cover",
            "elfy-reading-30": "story_elfy-reading-30_cover"
        ]
        XCTAssertTrue(Set(expected.keys).isSubset(of: Set(stories.map(\.id))))
        for story in stories.reversed() {
            XCTAssertEqual(ReadingCover.assetName(for: story.id), expected[story.id])
        }
        XCTAssertNil(ReadingCover.assetName(for: "future-story"))
    }

    func testBundledStoriesValidateWithVocabularyOffline() throws {
        let (stories, cards) = try load()
        let cardIDs = Set(cards.map(\.id))
        XCTAssertEqual(stories.count, 30)
        XCTAssertEqual(Set(stories.map(\.id)).count, 30)
        XCTAssertEqual(stories.flatMap(\.questions).count, 90)
        let targetIDs = Set(stories.flatMap(\.targetWordIds))
        XCTAssertEqual(targetIDs.count, 164)
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

    func testNewStoriesLinkEveryTarget() throws {
        let (stories, _) = try load()
        let added = Array(stories.suffix(10))
        for story in added {
            XCTAssertEqual(Set(ReadingVocabulary.matches(in: story).map(\.id)), Set(story.targetWordIds))
        }
    }

    func testAllStoriesBundlePersianTranslations() throws {
        let (stories, _) = try load()
        let translated = stories.filter { $0.textFa?.isEmpty == false }
        XCTAssertEqual(translated.count, 30)
        XCTAssertEqual(Set(translated.map(\.level)), Set(ReadingLevel.allCases))
        XCTAssertTrue(translated.allSatisfy { $0.textFa?.contains("ي") == false })
    }

    @MainActor func testReadingResetClearsCompletionAndAllowsFreshDailyPick() throws {
        let (stories, _) = try load()
        let original = stories[0]
        let replacement = stories[1]
        let ids = Set(stories.map(\.id))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reading.store")
        do {
            let container = try ReadingStore.makeContainer(at: url)
            let context = container.mainContext
            _ = try ReadingStore.dailyStoryID(at: now, calendar: calendar, availableIDs: ids,
                                             in: context) { _ in original.id }
            try ReadingStore.complete(original, score: 3, at: now, in: context)
            XCTAssertEqual(try ReadingStore.records(in: context)[original.id]?.completed, true)
            try ReadingStore.reset(in: context)
        }
        let container = try ReadingStore.makeContainer(at: url)
        let context = container.mainContext
        XCTAssertTrue(try ReadingStore.records(in: context).isEmpty)
        XCTAssertEqual(try ReadingStore.dailyStoryID(at: now, calendar: calendar, availableIDs: ids,
                                                    in: context) { _ in replacement.id }, replacement.id)
    }

    func testStoryCardActionsForUnreadInProgressAndCompletedStories() {
        XCTAssertEqual(ReadingCardAction(record: nil, hasReadingPosition: false), .start)
        XCTAssertEqual(ReadingCardAction(record: nil, hasReadingPosition: true), .resume)
        let read = ReadingRecord(read: true, bestScore: 0, recentScore: nil, attempts: 0, lastCompletion: nil)
        XCTAssertEqual(ReadingCardAction(record: read, hasReadingPosition: false), .resume)
        let completed = ReadingRecord(read: true, bestScore: 0, recentScore: 0, attempts: 1, lastCompletion: now)
        XCTAssertEqual(ReadingCardAction(record: completed, hasReadingPosition: true), .reread)
    }

    func testLevelAndReadFilters() throws {
        let (stories, _) = try load()
        for (filter, count) in [(ReadingFilter.all, 30), (.a1, 6), (.a2, 20), (.b1, 4), (.read, 0)] {
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

    func testFirstVocabularyLessonPreparesLearnerForTheEarlyTrain() throws {
        let (stories, cards) = try load()
        let planner = StudyPlanner(cards: cards, progress: [:], goal: 10, at: now, calendar: calendar)
        let firstStory = try XCTUnwrap(ReadingRecommendationEngine.recommend(
            stories: stories, statuses: planner.status, progress: [:], recalls: [], records: [:], at: now,
            calendar: calendar
        ))
        let story = try XCTUnwrap(stories.first { $0.id == firstStory.storyID })
        XCTAssertEqual(story.titleEn, "The Early Train")
        XCTAssertEqual(planner.newCards.count, 10)
        XCTAssertTrue(Set(story.targetWordIds).isSubset(of: Set(planner.newCards.map(\.id))))
        XCTAssertEqual(Set(planner.newCards.map(\.word)).subtracting(story.targetWords), ["train", "morning", "late"])
    }

    func testSecondVocabularyLessonPreparesLearnerForATripWithAProblem() throws {
        let (stories, cards) = try load()
        let first = StudyPlanner(cards: cards, progress: [:], goal: 10, at: now, calendar: calendar)
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        var progress = Dictionary(uniqueKeysWithValues: first.newCards.map {
            ($0.id, StudyPlanner.Progress(introduced: now, due: nextDay))
        })
        let second = StudyPlanner(cards: cards, progress: progress, goal: 10, at: nextDay, calendar: calendar)
        XCTAssertEqual(second.newCards.count, 10)
        for card in second.newCards {
            progress[card.id] = .init(introduced: nextDay, due: nextDay)
        }
        let story = try XCTUnwrap(stories.first { $0.titleEn == "A Trip with a Problem" })
        XCTAssertTrue(Set(story.targetWordIds).isSubset(of: Set(progress.keys)))
        let completed = ReadingRecord(read: true, bestScore: 3, recentScore: 3, attempts: 1, lastCompletion: now)
        let recommendation = ReadingRecommendationEngine.recommend(
            stories: stories, statuses: second.status, progress: progress, recalls: [],
            records: ["elfy-reading-01": completed], at: nextDay, calendar: calendar,
            previousStoryID: "elfy-reading-01"
        )
        XCTAssertEqual(recommendation?.storyID, story.id)
    }

    func testFifthVocabularyLessonPreparesLearnerForASmallBookshop() throws {
        let (stories, cards) = try load()
        let story = try XCTUnwrap(stories.first { $0.titleEn == "A Small Bookshop" })
        let targets = Set(story.targetWordIds)
        var progress: [String: StudyPlanner.Progress] = [:]
        for day in 0..<5 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: day, to: now))
            let planner = StudyPlanner(cards: cards, progress: progress, goal: 10, at: date, calendar: calendar)
            XCTAssertEqual(planner.newCards.count, 10)
            let ids = Set(planner.newCards.map(\.id))
            if day < 4 {
                XCTAssertTrue(targets.isDisjoint(with: ids))
            } else {
                XCTAssertTrue(targets.isSubset(of: ids))
            }
            for card in try XCTUnwrap(planner.dailyPlan).cards {
                let old = progress[card.id]
                let next = Schedule(days: old?.days ?? 0, streak: old?.streak ?? 0, due: old?.due ?? date)
                    .rated(.good, at: date, calendar: calendar)
                progress[card.id] = .init(introduced: old?.introduced ?? date, due: next.due,
                                          days: next.days, streak: next.streak)
            }
        }
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
        XCTAssertEqual(records.count, 30)
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
