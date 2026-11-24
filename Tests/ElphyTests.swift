import XCTest
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
@testable import Elphy

final class ElphyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let card = Card(id: "personal-test", word: "arrive", partOfSpeech: "verb", level: "",
                            meaningFa: "رسیدن", exampleEn: "", exampleFa: "", topic: "")

    #if canImport(UIKit)
    @MainActor func testAllMascotPosesLoadFromTheAppBundle() throws {
        let poses = ElphyMascotView.Mood.allCases
        XCTAssertEqual(poses.count, 8)
        for pose in poses {
            let image = try XCTUnwrap(UIImage(named: pose.assetName, in: .main, compatibleWith: nil), pose.assetName)
            let pixels = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(max(pixels.width, pixels.height), 420)
        }
    }
    #endif

    func testSchedulingTransitions() {
        let calendar = Calendar(identifier: .gregorian)
        let new = Schedule(due: now)
        let hard = new.rated(.hard, at: now, calendar: calendar)
        let good = new.rated(.good, at: now, calendar: calendar)
        XCTAssertGreaterThan(good.due, hard.due)
        XCTAssertEqual(good.rated(.good, at: good.due, calendar: calendar).days, 4)
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

    func testShortLearningStepAndExpandingIntervals() {
        let calendar = Calendar(identifier: .gregorian)
        let old = Schedule(days: 80, streak: 4, due: now)
        let missed = old.rated(.again, at: now, calendar: calendar)
        let early = now.addingTimeInterval(60)
        XCTAssertEqual(missed.rated(.good, at: early, calendar: calendar), missed)
        XCTAssertEqual(missed.rated(.easy, at: early, calendar: calendar), missed)
        XCTAssertEqual(missed.rated(.good, at: missed.due, calendar: calendar).days, 2)
        XCTAssertEqual(missed.rated(.easy, at: missed.due, calendar: calendar).days, 4)
        XCTAssertEqual(old.rated(.good, at: now, calendar: calendar).days, 90)
        XCTAssertEqual(old.rated(.hard, at: now, calendar: calendar).days, 80)
    }

    func testDailyGoalCelebrationRequiresNewLearningAtTheSameGoalOnTheSameDay() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func progress(_ count: Int, _ target: Int, goal: Int = 5, day: Date? = nil) -> DailyLearningProgress {
            DailyLearningProgress(day: day ?? start, count: count, target: target, configuredGoal: goal)
        }
        XCTAssertTrue(progress(5, 5).reachedGoal(since: progress(4, 5)))
        XCTAssertFalse(progress(5, 5).reachedGoal(since: progress(5, 5)))
        XCTAssertFalse(progress(4, 4, goal: 4).reachedGoal(since: progress(4, 5)))
        XCTAssertFalse(progress(5, 5, goal: 5).reachedGoal(since: progress(4, 5, goal: 10)))
        XCTAssertFalse(progress(5, 5, day: start.addingTimeInterval(86_400)).reachedGoal(since: progress(4, 5)))
        XCTAssertFalse(progress(0, 0).reachedGoal(since: progress(0, 0)))
    }

    func testTodayPresentationForNewPartialCompletedAndReviewReadyLearners() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let day = calendar.startOfDay(for: now)
        let tomorrow = day.addingTimeInterval(86_400)
        let cards = (0..<12).map { index in
            var item = card
            item.id = "word-\(index)"
            return item
        }
        func planner(_ learned: Int, dueFirst: Bool = false, goal: Int = 10) -> StudyPlanner {
            let progress = Dictionary(uniqueKeysWithValues: cards.prefix(learned).enumerated().map { index, card in
                (card.id, StudyPlanner.Progress(introduced: day, due: dueFirst && index == 0 ? now : tomorrow))
            })
            return StudyPlanner(cards: cards, progress: progress, goal: goal, at: now, calendar: calendar)
        }
        func fraction(_ planner: StudyPlanner, goal: Int = 10) -> Double {
            DailyLearningProgress(day: day, count: planner.introducedToday, target: planner.effectiveGoal,
                                  configuredGoal: goal).fraction
        }
        let first = planner(0)
        XCTAssertEqual(TodayLearningState(planner: first), .next(.learn))
        XCTAssertEqual(fraction(first), 0)
        XCTAssertTrue(first.dueCards.isEmpty)
        let partial = planner(5)
        XCTAssertEqual(TodayLearningState(planner: partial), .next(.continueStudy))
        XCTAssertEqual(fraction(partial), 0.5)
        XCTAssertEqual(partial.newCards.count, 5)
        XCTAssertEqual(fraction(planner(5, goal: 20), goal: 20), 5.0 / 12)
        let complete = planner(10)
        XCTAssertEqual(TodayLearningState(planner: complete), .goalComplete(action: .practice))
        XCTAssertEqual(fraction(complete), 1)
        XCTAssertNil(complete.dailyPlan)
        XCTAssertEqual(complete.completionPlan()?.mode, .practice)
        XCTAssertEqual(complete.completionPlan()?.cards.map(\.id), cards.prefix(10).map(\.id))
        XCTAssertTrue(complete.completionPlan()?.newIDs.isEmpty == true)
        let ready = planner(10, dueFirst: true)
        XCTAssertEqual(TodayLearningState(planner: ready), .goalComplete(action: .scheduled))
        XCTAssertEqual(ready.dailyPlan?.cards.map(\.id), [cards[0].id])
        XCTAssertEqual(ready.completionPlan()?.cards.map(\.id), [cards[0].id])
        XCTAssertTrue(ready.completionPlan()?.newIDs.isEmpty == true)
        XCTAssertNil(first.completionPlan())
    }

    func testMorePracticeAfterFirstGoalIncludesOtherPracticedWordsAlongsideOneDifficultWord() throws {
        let calendar = Calendar(identifier: .gregorian)
        let cards = (0..<6).map { index in
            var copy = card
            copy.id = "practice-\(index)"
            return copy
        }
        let practiced = Array(cards.prefix(5))
        let difficult = practiced[2]
        let progress = Dictionary(uniqueKeysWithValues: practiced.map {
            ($0.id, StudyPlanner.Progress(introduced: now, due: now.addingTimeInterval(600)))
        })
        let recalls = [
            Recall(cardID: difficult.id, date: now.addingTimeInterval(-30), rating: .again),
            Recall(cardID: difficult.id, date: now, rating: .again)
        ]
        let planner = StudyPlanner(cards: cards, progress: progress, goal: 5, at: now,
                                   calendar: calendar, recalls: recalls)
        XCTAssertEqual(TodayLearningState(planner: planner), .goalComplete(action: .practice))
        XCTAssertEqual(planner.difficultPlan.cards.map(\.id), [difficult.id])
        let ordered = try XCTUnwrap(planner.completionPlan())
        XCTAssertEqual(ordered.cards.first?.id, difficult.id)
        let practice = try XCTUnwrap(planner.completionPlan(shufflePractice: true))
        XCTAssertEqual(practice.mode, .practice)
        XCTAssertEqual(practice.cards.count, practiced.count)
        XCTAssertEqual(Set(practice.cards.map(\.id)), Set(practiced.map(\.id)))
        XCTAssertTrue(practice.newIDs.isEmpty)
    }

    func testFirstLaunchAndChangingGoal() {
        let calendar = Calendar(identifier: .gregorian)
        let cards = (0..<13).map { index in
            var item = card
            item.id = "word-\(index)"
            return item
        }
        let first = StudyPlanner(cards: cards, progress: [:], goal: DailyGoal.defaultValue,
                                 at: now, calendar: calendar)
        XCTAssertEqual(first.nextAction, .learn)
        XCTAssertEqual(first.newCards.count, 10)
        XCTAssertEqual(first.remainingNew, 13)
        XCTAssertEqual(first.status[cards[0].id]?.stage, .new)
        XCTAssertEqual(DailyGoal.choices(including: 17), [0, 5, 10, 17, 20, 30])

        let state = [cards[0].id: StudyPlanner.Progress(introduced: now, due: now.addingTimeInterval(600))]
        let changed = StudyPlanner(cards: cards, progress: state, goal: 5, at: now, calendar: calendar)
        XCTAssertEqual(changed.newCards.count, 4)
        XCTAssertEqual(changed.nextAction, .continueStudy)
        XCTAssertEqual(changed.introducedToday, 1)
        XCTAssertEqual(changed.scheduledLaterToday, 1)
        XCTAssertTrue(changed.dueCards.isEmpty)
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        let nextDay = StudyPlanner(cards: cards, progress: state, goal: 5, at: tomorrow, calendar: calendar)
        XCTAssertEqual(nextDay.introducedToday, 0)
        XCTAssertEqual(nextDay.newCards.count, 5)
        XCTAssertEqual(nextDay.dueCards.map(\.id), [cards[0].id])
        XCTAssertEqual(nextDay.nextAction, .mixed)
    }

    func testCompletedDailyWorkOffersPracticeAndKeepsFutureReviewsSeparate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let future = calendar.date(byAdding: .day, value: 2, to: now)!
        let state = [card.id: StudyPlanner.Progress(introduced: now, due: future, days: 2, streak: 1)]
        let complete = StudyPlanner(cards: [card], progress: state, goal: 10, at: now, calendar: calendar)
        XCTAssertEqual(complete.effectiveGoal, 1)
        XCTAssertEqual(complete.remainingNew, 0)
        XCTAssertEqual(complete.nextAction, .practice)
        XCTAssertNil(complete.dailyPlan)
        XCTAssertEqual(complete.nextDue, future)
        XCTAssertEqual(complete.scheduledLaterToday, 0)
        let plan = try XCTUnwrap(complete.optionalPlan(for: complete.practicedCards))
        var session = StudySession(plan: plan)
        session.reveal()
        session.submit(.again, for: session.attemptID) { _, _, _ in
            XCTFail("Optional practice tried to reschedule the word")
        }
        XCTAssertNil(session.currentCard)
        XCTAssertEqual(session.queue.needsPractice, [card.id])
        XCTAssertEqual(session.newCardsPracticed, 0)

        let due = StudyPlanner(cards: [card], progress: state, goal: 0, at: future, calendar: calendar)
        XCTAssertEqual(due.nextAction, .review)
        XCTAssertEqual(due.dailyPlan?.cards.map(\.id), [card.id])
    }

    func testEmptyDeckAndReviewOnlyHaveUsefulPaths() {
        let calendar = Calendar(identifier: .gregorian)
        let empty = StudyPlanner(cards: [], progress: [:], goal: 10, at: now, calendar: calendar)
        XCTAssertEqual(empty.nextAction, .browse)
        XCTAssertNil(empty.optionalPlan(for: [card]))
        let noNew = StudyPlanner(cards: [card], progress: [:], goal: 0, at: now, calendar: calendar)
        XCTAssertEqual(noNew.nextAction, .setGoal)
        XCTAssertNil(noNew.dailyPlan)
        XCTAssertNil(noNew.optionalPlan(for: [card]))
    }

    func testMasteryRequiresSpacedRecallAndDifficultyCanOverlapLearning() {
        let calendar = Calendar(identifier: .gregorian)
        let state = StudyPlanner.Progress(introduced: now, due: now, days: 8, streak: 3)
        func recall(_ rating: Rating, daysAgo: Int) -> Recall {
            Recall(cardID: card.id, date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!,
                   rating: rating)
        }
        let quick = [recall(.good, daysAgo: 0), recall(.easy, daysAgo: 0), recall(.good, daysAgo: 0)]
        XCTAssertEqual(VocabularyStatus(progress: state, recalls: quick, calendar: calendar).stage, .learning)
        let spaced = [recall(.good, daysAgo: 0), recall(.good, daysAgo: 4), recall(.good, daysAgo: 6)]
        XCTAssertEqual(VocabularyStatus(progress: state, recalls: spaced, calendar: calendar).stage, .mastered)
        let lapsed = [recall(.again, daysAgo: 0), recall(.again, daysAgo: 1)] + spaced.dropFirst()
        let status = VocabularyStatus(progress: state, recalls: lapsed, calendar: calendar)
        XCTAssertEqual(status.stage, .learning)
        XCTAssertTrue(status.isDifficult)
    }

    func testDifficultPracticeHasAnEmptyPlanForNewLearnersAndFivePracticedCards() {
        let cards = (0..<6).map { index in
            var item = card
            item.id = "word-\(index)"
            return item
        }
        let calendar = Calendar(identifier: .gregorian)
        let firstLaunch = StudyPlanner(cards: cards, progress: [:], goal: 5, at: now, calendar: calendar)
        XCTAssertEqual(firstLaunch.difficultPlan.mode, .difficult)
        XCTAssertTrue(firstLaunch.difficultPlan.cards.isEmpty)
        XCTAssertNil(StudySession(plan: firstLaunch.difficultPlan).currentCard)

        let progress = Dictionary(uniqueKeysWithValues: cards.prefix(5).map {
            ($0.id, StudyPlanner.Progress(introduced: now, due: now.addingTimeInterval(600)))
        })
        // A single miss on each card is not enough to classify a word.
        let recalls = cards.prefix(5).map { Recall(cardID: $0.id, date: now, rating: .again) }
        let afterFive = StudyPlanner(cards: cards, progress: progress, goal: 5, at: now,
                                     calendar: calendar, recalls: recalls)
        XCTAssertEqual(afterFive.introducedToday, 5)
        XCTAssertEqual(afterFive.difficultPlan.mode, .difficult)
        XCTAssertTrue(afterFive.difficultPlan.cards.isEmpty)
    }

    func testDifficultPracticeUsesRecallHistoryAcrossInactivityAndRecoversAfterTwoConfidentRecalls() {
        let calendar = Calendar(identifier: .gregorian)
        var other = card
        other.id = "other"
        let old = now.addingTimeInterval(-7 * 86_400)
        let due = old.addingTimeInterval(600)
        let progress: [String: StudyPlanner.Progress] = [
            card.id: .init(introduced: old, due: due),
            other.id: .init(introduced: old, due: due)
        ]
        let misses = [
            Recall(cardID: card.id, date: old, rating: .again),
            Recall(cardID: card.id, date: due, rating: .again),
            Recall(cardID: other.id, date: old, rating: .again)
        ]
        func planner(at date: Date, with recalls: [Recall]) -> StudyPlanner {
            StudyPlanner(cards: [card, other], progress: progress, goal: 5, at: date,
                         calendar: calendar, recalls: recalls)
        }
        XCTAssertEqual(planner(at: due, with: misses).difficultPlan.cards.map(\.id), [card.id])
        let afterAbsence = planner(at: now, with: misses)
        XCTAssertEqual(afterAbsence.difficultPlan.cards.map(\.id), [card.id])
        XCTAssertEqual(Set(afterAbsence.dueCards.map(\.id)), [card.id, other.id])
        XCTAssertEqual(afterAbsence.introducedToday, 0)

        let firstRecall = misses + [Recall(cardID: card.id, date: now, rating: .good)]
        XCTAssertEqual(planner(at: now, with: firstRecall).difficultCards.map(\.id), [card.id])
        let later = now.addingTimeInterval(2 * 86_400)
        let recovered = planner(at: later, with: firstRecall + [Recall(cardID: card.id, date: later, rating: .easy)])
        XCTAssertEqual(recovered.difficultPlan.mode, .difficult)
        XCTAssertTrue(recovered.difficultPlan.cards.isEmpty)
    }

    @MainActor func testDifficultPracticeKeepsOverdueReviewAndRestoresDifficultyAfterRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([PersonalCard.self, ReviewState.self, ReviewEvent.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"))
        let firstMiss = now.addingTimeInterval(-86_400)
        let secondMiss = firstMiss.addingTimeInterval(600)
        let overdue = secondMiss.addingTimeInterval(600)

        func planner(in context: ModelContext) throws -> StudyPlanner {
            let state = try XCTUnwrap(context.fetch(FetchDescriptor<ReviewState>()).first)
            let recalls = try context.fetch(FetchDescriptor<ReviewEvent>()).compactMap(\.recall)
            XCTAssertEqual(recalls.count, 2)
            XCTAssertEqual(state.introduced, firstMiss)
            XCTAssertEqual(state.due, overdue)
            XCTAssertEqual(state.days, 0)
            XCTAssertEqual(state.streak, 0)
            return StudyPlanner(cards: [card], progress: [card.id: state.progress], goal: 5, at: now,
                                calendar: .current, recalls: recalls)
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            try ReviewStore.record(card, rating: .again, attemptID: UUID(), date: firstMiss, in: context)
            try ReviewStore.record(card, rating: .again, attemptID: UUID(), date: secondMiss, in: context)
            let before = try planner(in: context)
            var practice = StudySession(plan: before.difficultPlan)
            XCTAssertFalse(practice.isRevealed)
            XCTAssertEqual(practice.currentCard?.id, card.id)
            practice.reveal()
            practice.submit(.easy, for: practice.attemptID) { _, _, _ in
                XCTFail("Difficult practice tried to record a scheduled review")
            }
            XCTAssertNil(practice.currentCard)
            XCTAssertEqual(practice.queue.successful, [card.id])
            XCTAssertEqual(practice.newCardsPracticed, 0)
            let after = try planner(in: context)
            XCTAssertEqual(after.introducedToday, before.introducedToday)
            XCTAssertEqual(after.dailyPlan?.cards.map(\.id), [card.id])
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let restored = try planner(in: reopened.mainContext)
        XCTAssertEqual(restored.difficultPlan.cards.map(\.id), [card.id])
        XCTAssertEqual(restored.dueCards.map(\.id), [card.id])
        XCTAssertEqual(restored.introducedToday, 0)
    }

    func testReviewClockRefreshesAtTheExactDueTimeOrMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let midnight = try XCTUnwrap(calendar.dateInterval(of: .day, for: now)?.end)
        let due = midnight.addingTimeInterval(-126)
        XCTAssertEqual(ReviewClock.nextRefresh(at: due.addingTimeInterval(-1), nextDue: due, calendar: calendar), due)
        XCTAssertEqual(ReviewClock.nextRefresh(at: due, nextDue: due, calendar: calendar), midnight)
        XCTAssertEqual(ReviewClock.nextRefresh(at: due, nextDue: midnight.addingTimeInterval(60), calendar: calendar), midnight)
    }

    func testPlannerSeparatesOverdueLaterTodayAndTomorrowAndResetsAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tehran"))
        let midnight = try XCTUnwrap(calendar.dateInterval(of: .day, for: now)?.end)
        let before = midnight.addingTimeInterval(-120)
        let dates = [before.addingTimeInterval(-30), before.addingTimeInterval(30), midnight]
        let cards = dates.indices.map { index in
            var item = card
            item.id = "scheduled-\(index)"
            return item
        }
        let states = Dictionary(uniqueKeysWithValues: zip(cards, dates).map { item, date in
            (item.id, StudyPlanner.Progress(introduced: before, due: date))
        })
        let evening = StudyPlanner(cards: cards, progress: states, goal: 5, at: before, calendar: calendar)
        XCTAssertEqual(evening.dueCards.map(\.id), [cards[0].id])
        XCTAssertEqual(evening.scheduledLaterToday, 1)
        XCTAssertEqual(evening.nextDue, dates[1])
        XCTAssertEqual(evening.introducedToday, 3)
        XCTAssertTrue(evening.reachedGoalToday)
        let due = StudyPlanner(cards: cards, progress: states, goal: 5, at: dates[1], calendar: calendar)
        XCTAssertEqual(due.dueCards.count, 2)
        XCTAssertEqual(due.scheduledLaterToday, 0)
        XCTAssertEqual(ReviewClock.nextRefresh(at: dates[1], nextDue: due.nextDue, calendar: calendar),
                       midnight)
        let tomorrow = StudyPlanner(cards: cards, progress: states, goal: 5, at: midnight, calendar: calendar)
        XCTAssertEqual(tomorrow.dueCards.count, 3)
        XCTAssertEqual(tomorrow.introducedToday, 0)
        XCTAssertFalse(tomorrow.reachedGoalToday)
    }

    func testMasterySegmentsAccountForEveryWordAndHandleEmptyAndMasteredDecks() {
        let calendar = Calendar(identifier: .gregorian)
        var learned = card
        learned.id = "mastered"
        var fresh = card
        fresh.id = "fresh"
        let old = calendar.date(byAdding: .day, value: -6, to: now)!
        let states: [String: StudyPlanner.Progress] = [
            learned.id: .init(introduced: old, due: now, days: 8, streak: 3),
            card.id: .init(introduced: old, due: now)
        ]
        let history = [6, 4, 0].map { offset in
            Recall(cardID: learned.id, date: calendar.date(byAdding: .day, value: -offset, to: now)!, rating: .good)
        }
        let mixed = StudyPlanner(cards: [learned, card, fresh], progress: states, goal: 10,
                                 at: now, calendar: calendar, recalls: history).mastery
        XCTAssertEqual([mixed.mastered, mixed.learning, mixed.new], [1, 1, 1])
        XCTAssertEqual(mixed.total, 3)
        XCTAssertEqual(mixed.fraction(mixed.learning), 1.0 / 3.0)
        let empty = StudyPlanner(cards: [], progress: states, goal: 10, at: now, calendar: calendar).mastery
        XCTAssertEqual(empty.total, 0)
        XCTAssertEqual(empty.fraction(empty.new), 0)
        let complete = StudyPlanner(cards: [learned], progress: states, goal: 10,
                                    at: now, calendar: calendar, recalls: history).mastery
        XCTAssertEqual(complete.fraction(complete.mastered), 1)
        XCTAssertEqual(complete.learning, 0)
    }

    @MainActor func testRetryKeepsShortDueDateAndEarlyScheduledSubmissionDoesNotDuplicate() throws {
        let container = try ModelContainer(for: PersonalCard.self, ReviewState.self, ReviewEvent.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        try ReviewStore.record(card, rating: .again, attemptID: UUID(), date: now, in: context)
        try ReviewStore.record(card, rating: .good, attemptID: UUID(), date: now.addingTimeInterval(30), in: context)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<ReviewState>()).first)
        XCTAssertEqual(state.due, now.addingTimeInterval(600))
        XCTAssertEqual(state.streak, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewEvent>()), 2)
        let due = state.due
        try ReviewStore.record(card, rating: .easy, attemptID: UUID(), date: due, in: context)
        try ReviewStore.record(card, rating: .again, attemptID: UUID(), date: due, in: context)
        XCTAssertEqual(state.days, 4)
        XCTAssertEqual(state.streak, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewEvent>()), 3)
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
        let restored = try XCTUnwrap(reopened.fetch(FetchDescriptor<ReviewState>()).first)
        XCTAssertEqual(restored.streak, 1)
        XCTAssertEqual(restored.introduced, now)
        XCTAssertEqual(restored.days, 2)
        XCTAssertEqual(restored.due, Calendar.current.date(byAdding: .day, value: 2, to: now))
        let event = try XCTUnwrap(reopened.fetch(FetchDescriptor<ReviewEvent>()).first)
        XCTAssertEqual(event.rating, "good")
        XCTAssertEqual(event.recall?.rating, .good)
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

    func testQuizSkipsDuplicateHeadwordsAndAvoidsOtherKnownSenses() throws {
        var random = SeededRandom()
        var close = card("close", "بستن")
        var nearby = card(" Close ", "نزدیک")
        close.id = "close-verb"
        nearby.id = "close-adjective"
        let pool = [close, nearby, card("near", "نزدیک"), card("wait", "منتظر ماندن"),
                    card("bring", "آوردن"), card("leave", "رفتن")]
        let questions = QuizSession.makeQuestions(
            practicedCards: [close, nearby], distractorPool: pool, limit: 10, using: &random
        )
        let question = try XCTUnwrap(questions.first)
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(question.choices.count, 4)
        XCTAssertFalse(question.choices.contains(question.card.id == close.id ? "نزدیک" : "بستن"))
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
        XCTAssertEqual(quiz.missedCards.map(\.id), [first.id])
    }
}
