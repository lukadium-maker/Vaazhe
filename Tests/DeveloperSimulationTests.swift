#if DEBUG
import Foundation
import SwiftData
import XCTest
@testable import Elphy

final class DeveloperSimulationTests: XCTestCase {
    private struct Fixture {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "ElphyTests.\(UUID())"
        let calendar: Calendar
        let date: Date

        init() throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
            self.calendar = calendar
            date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        }

        var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

        @MainActor func start(copying source: (ModelContext, ModelContext)? = nil) throws -> DeveloperSimulation {
            try DeveloperSimulation.start(at: date, calendar: calendar, in: directory, defaults: defaults, copying: source)
        }

        func clean() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }

    @MainActor func testCalendarDaysAcrossDSTAndRelaunch() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        var simulation: DeveloperSimulation? = try fixture.start()
        let id = try XCTUnwrap(simulation?.id)
        XCTAssertEqual(simulation?.learningDay, 1)
        try simulation?.move(days: 1)
        let nextDay = try XCTUnwrap(simulation?.date)
        XCTAssertEqual(nextDay.timeIntervalSince(fixture.date), 23 * 60 * 60)
        XCTAssertEqual(fixture.calendar.component(.hour, from: nextDay), 12)
        XCTAssertEqual(simulation?.learningDay, 2)
        try simulation?.move(days: 7)
        XCTAssertEqual(simulation?.learningDay, 9)
        try simulation?.move(days: 30)
        XCTAssertEqual(simulation?.learningDay, 39)
        try simulation?.midnight()
        let midnight = try XCTUnwrap(simulation?.date)
        XCTAssertEqual(midnight, fixture.calendar.startOfDay(for: midnight))
        XCTAssertEqual(simulation?.learningDay, 40)
        simulation = nil
        simulation = try DeveloperSimulation.resume(in: fixture.directory)
        XCTAssertEqual(simulation?.id, id)
        XCTAssertEqual(simulation?.date, midnight)
        XCTAssertEqual(simulation?.calendar.timeZone, fixture.calendar.timeZone)
        try simulation?.stop()
        XCTAssertNil(try DeveloperSimulation.resume(in: fixture.directory))
        simulation = nil
        DeveloperSimulation.removeInactiveProfiles(in: fixture.directory, keeping: nil)
    }

    @MainActor func testDailyLearningUsesRealPlannerAndRespectsMissedDaysAndBackwardWrites() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let simulation = try fixture.start()
        let clock = AppClock(systemDate: { fixture.date }, systemCalendar: { fixture.calendar })
        clock.simulation = simulation
        let cards = Array(try Card.load(from: bundle).prefix(4))
        let context = simulation.container.mainContext
        func planner() throws -> StudyPlanner {
            let states = try context.fetch(FetchDescriptor<ReviewState>())
            return StudyPlanner(cards: cards, progress: Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0.progress) }),
                                goal: 1, at: clock.now, calendar: clock.calendar)
        }
        let first = try XCTUnwrap(planner().newCards.first)
        let attempt = UUID()
        try clock.record(first, rating: .good, attemptID: attempt, in: context)
        try clock.record(first, rating: .good, attemptID: attempt, in: context)
        XCTAssertTrue(try planner().reachedGoalToday)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewEvent>()), 1)
        try simulation.move(days: 1)
        XCTAssertEqual(try planner().newCards.count, 1)
        XCTAssertFalse(try planner().reachedGoalToday)
        XCTAssertTrue(try planner().dueCards.isEmpty)
        let second = try XCTUnwrap(planner().newCards.first)
        try clock.record(second, rating: .good, attemptID: UUID(), in: context)
        try simulation.move(days: 1)
        XCTAssertEqual(try planner().dueCards.map(\.id), [first.id])
        let third = try XCTUnwrap(planner().newCards.first)
        try clock.record(third, rating: .good, attemptID: UUID(), in: context)
        XCTAssertEqual(try streak(context, clock).current, 3)
        try simulation.move(days: 4)
        XCTAssertEqual(try streak(context, clock).current, 0)
        XCTAssertEqual(try streak(context, clock).longest, 3)
        XCTAssertEqual(try planner().dueCards.count, 3)
        try simulation.jump(to: fixture.date)
        XCTAssertEqual(try streak(context, clock).current, 1)
        XCTAssertThrowsError(try clock.record(third, rating: .again, attemptID: UUID(), in: context))
        XCTAssertThrowsError(try simulation.resetDay())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewEvent>()), 3)
        try simulation.move(days: 2)
        try simulation.resetDay()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewEvent>()), 2)
        XCTAssertFalse(try planner().reachedGoalToday)
        try simulation.resetProgress()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewEvent>()), 0)
        XCTAssertEqual(try planner().introducedCount, 0)
        try simulation.stop()
        clock.simulation = nil
        XCTAssertEqual(clock.now, fixture.date)
    }

    @MainActor func testCopyIsIsolatedAndReadingAssignmentStaysStableAfterCompletion() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        fixture.defaults.set(5, forKey: "dailyGoal")
        let cards = try Card.load(from: bundle)
        let stories = try ReadingContent.load(cards: cards, from: bundle)
        let card = try XCTUnwrap(cards.first)
        let vocabulary = try ModelContainer(for: PersonalCard.self, ReviewState.self, ReviewEvent.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let reading = try ReadingStore.makeContainer(at: FileManager.default.temporaryDirectory
            .appending(path: "\(UUID()).store"))
        let readingURL = try XCTUnwrap(reading.configurations.first?.url)
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: readingURL.path + suffix)
            }
        }
        let original = try XCTUnwrap(stories.first)
        let previous = try XCTUnwrap(fixture.calendar.date(byAdding: .day, value: -1, to: fixture.date))
        try ReviewStore.record(card, rating: .good, attemptID: UUID(), date: previous,
                               in: vocabulary.mainContext, calendar: fixture.calendar)
        try ReadingStore.complete(original, score: 1, at: previous, in: reading.mainContext)
        let simulation = try fixture.start(copying: (vocabulary.mainContext, reading.mainContext))
        let clock = AppClock(systemDate: { fixture.date }, systemCalendar: { fixture.calendar })
        clock.simulation = simulation
        XCTAssertEqual(simulation.preferences.integer(forKey: "dailyGoal"), 5)
        simulation.preferences.set(20, forKey: "dailyGoal")
        let context = simulation.container.mainContext
        func assignment() throws -> String? {
            let states = try context.fetch(FetchDescriptor<ReviewState>())
            let progress = Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0.progress) })
            let recalls = try context.fetch(FetchDescriptor<ReviewEvent>()).compactMap(\.recall)
            let planner = StudyPlanner(cards: cards, progress: progress, goal: 5,
                                       at: clock.now, calendar: clock.calendar, recalls: recalls)
            return try ReadingStore.dailyStoryID(stories: stories, planner: planner, progress: progress, recalls: recalls,
                                                 records: ReadingStore.records(in: context), at: clock.now,
                                                 calendar: clock.calendar, in: context)
        }
        let id = try XCTUnwrap(assignment())
        let story = try XCTUnwrap(stories.first { $0.id == id })
        try clock.complete(story, score: story.questions.count, in: context)
        XCTAssertEqual(try assignment(), id)
        XCTAssertEqual(try assignment(), id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyReadingPick>()), 1)
        XCTAssertEqual(try simulation.readingCompletions().count, 2)
        XCTAssertThrowsError(try clock.complete(story, score: 0, in: reading.mainContext))
        try simulation.resetDay()
        XCTAssertEqual(try assignment(), id)
        XCTAssertEqual(try simulation.readingCompletions().count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewState>()), 1)
        try simulation.move(days: 1)
        XCTAssertNotEqual(try assignment(), id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyReadingPick>()), 2)
        try simulation.resetProgress()
        XCTAssertTrue(try ReadingStore.records(in: context).isEmpty)
        XCTAssertEqual(try ReadingStore.records(in: reading.mainContext)[original.id]?.attempts, 1)
        XCTAssertEqual(try vocabulary.mainContext.fetchCount(FetchDescriptor<ReviewEvent>()), 1)
        XCTAssertEqual(fixture.defaults.integer(forKey: "dailyGoal"), 5)
    }

    @MainActor func testSingleStoryAndExhaustedVocabularyRemainUsableOverAMonth() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let simulation = try fixture.start()
        let clock = AppClock()
        clock.simulation = simulation
        let cards = try Card.load(from: bundle)
        let card = try XCTUnwrap(cards.first)
        let story = try XCTUnwrap(ReadingContent.load(cards: cards, from: bundle).first)
        let context = simulation.container.mainContext
        try clock.record(card, rating: .good, attemptID: UUID(), in: context)

        for index in 0..<30 {
            let states = try context.fetch(FetchDescriptor<ReviewState>())
            let progress = Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0.progress) })
            let recalls = try context.fetch(FetchDescriptor<ReviewEvent>()).compactMap(\.recall)
            let planner = StudyPlanner(cards: [card], progress: progress, goal: 10,
                                       at: clock.now, calendar: clock.calendar, recalls: recalls)
            XCTAssertEqual(simulation.learningDay, index + 1)
            XCTAssertTrue(planner.newCards.isEmpty)
            XCTAssertEqual(planner.remainingNew, 0)
            if let due = planner.dueCards.first {
                try clock.record(due, rating: .good, attemptID: UUID(), in: context)
            }
            let assigned = try ReadingStore.dailyStoryID(
                stories: [story], planner: planner, progress: progress, recalls: recalls,
                records: ReadingStore.records(in: context), at: clock.now, calendar: clock.calendar, in: context
            )
            XCTAssertEqual(assigned, story.id)
            try clock.complete(story, score: story.questions.count, in: context)
            try simulation.move(days: 1)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyReadingPick>()), 30)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewState>()), 1)
        let dates = try simulation.readingCompletions().map(\.date)
        XCTAssertEqual(LearningStreak(activity: dates, at: clock.now, calendar: clock.calendar).current, 30)
    }

    @MainActor private func streak(_ context: ModelContext, _ clock: AppClock) throws -> LearningStreak {
        let activity = try context.fetch(FetchDescriptor<ReviewEvent>()).map(\.date)
        return LearningStreak(activity: activity, at: clock.now, calendar: clock.calendar)
    }
}
#endif
