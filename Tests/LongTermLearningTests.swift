import Foundation
import SwiftData
import XCTest
@testable import Elphy

final class LongTermLearningTests: XCTestCase {
    private enum Learner: String, CaseIterable {
        case high = "A", average = "B", struggling = "C", returning = "D"

        var recallRate: Int {
            switch self {
            case .high: 95
            case .average: 78
            case .struggling: 55
            case .returning: 85
            }
        }

        func studies(on day: Int) -> Bool {
            switch self {
            case .high: true
            case .average: day % 9 != 0
            case .struggling: ![8, 9, 10, 23, 24, 25, 26, 50, 51, 52].contains(day) && day % 13 != 0
            case .returning: !(18...31).contains(day)
            }
        }
    }

    private struct Day {
        let number: Int
        let learned: Int
        let new: Int
        let due: Int
        let recommended: Int
        let reviewed: Int
        let remaining: Int
        let workload: Int
        let mastery: MasteryBreakdown
        let story: String
        let revision: Bool
        let duplicateIDs: Int
    }

    private var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }

    @MainActor func testNinetyDaysForFourLearnersAgainstUncappedBaseline() throws {
        let cards = try Card.load(from: bundle)
        let stories = try ReadingContent.load(cards: cards, from: bundle)
        let milestones = [1, 3, 7, 10, 15, 30, 60, 90]
        for learner in Learner.allCases {
            let baseline = try simulate(learner, cards: cards, stories: stories, adaptive: false)
            let adaptive = try simulate(learner, cards: cards, stories: stories, adaptive: true)
            XCTAssertEqual(adaptive.count, 90)
            XCTAssertTrue(adaptive.allSatisfy { $0.workload <= 35 && $0.recommended <= 25 && $0.duplicateIDs == 0 })
            XCTAssertTrue(adaptive.allSatisfy { $0.remaining == $0.due - $0.reviewed })
            XCTAssertLessThanOrEqual(adaptive.last!.learned, cards.count)
            if learner == .high {
                XCTAssertLessThanOrEqual(adaptive.suffix(30).map(\.remaining).max()!, 25)
                XCTAssertEqual(adaptive.last?.learned, cards.count)
                XCTAssertEqual(Set(adaptive.filter { !$0.revision }.map(\.story)).count, stories.count)
            }
            if learner == .returning {
                XCTAssertGreaterThan(adaptive[31].due, adaptive[16].due)
                XCTAssertLessThan(adaptive[39].remaining, adaptive[31].remaining)
            }

            for (variant, days) in [("baseline", baseline), ("adaptive", adaptive)] {
                let maximum = days.map(\.workload).max() ?? 0
                let average = Double(days.reduce(0) { $0 + $1.workload }) / Double(days.count)
                let vocabularyExhausted = days.first { $0.learned == cards.count }?.number ?? 0
                let storiesExhausted = days.first { $0.revision }?.number ?? 0
                print("S6SUMMARY|\(learner.rawValue)|\(variant)|\(average)|\(maximum)|\(vocabularyExhausted)|\(storiesExhausted)|\(days.reduce(0) { $0 + $1.duplicateIDs })")
                for day in days where milestones.contains(day.number) {
                    let values = [day.number, day.learned, day.new, day.due, day.recommended, day.reviewed,
                                  day.remaining, day.workload, day.mastery.new, day.mastery.learning, day.mastery.mastered]
                    print("S6DAY|\(learner.rawValue)|\(variant)|\(values.map(String.init).joined(separator: "|"))|\(day.story)|\(day.revision)")
                }
            }
        }
    }

    @MainActor private func simulate(_ learner: Learner, cards: [Card], stories: [ReadingStory],
                                     adaptive: Bool) throws -> [Day] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12)))
        let reading = try ModelContainer(for: ReadingProgress.self, DailyReadingPick.self,
                                         configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = reading.mainContext
        let clock = AppClock(systemDate: { start }, systemCalendar: { calendar })
        var progress: [String: StudyPlanner.Progress] = [:]
        var recalls: [Recall] = []
        var output: [Day] = []
        let passageIndex = ReadingPassageIndex(stories: stories, cards: cards)

        for day in 1...90 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: day - 1, to: clock.now))
            let planner = StudyPlanner(cards: cards, progress: progress, goal: 10,
                                       at: date, calendar: calendar, recalls: recalls)
            let new = adaptive ? planner.newCards : Array(cards.filter { progress[$0.id] == nil }.prefix(10))
            let reviews = adaptive ? planner.recommendedReviews : planner.dueCards
            let studies = learner.studies(on: day)
            let session = studies ? (reviews + new) : []
            let duplicates = session.count - Set(session.map(\.id)).count
            for card in session {
                let old = progress[card.id]
                let rating: Rating = old == nil || sample(card.id, day: day) < learner.recallRate ? .good : .again
                let schedule = Schedule(days: old?.days ?? 0, streak: old?.streak ?? 0, due: old?.due ?? date)
                    .rated(rating, at: date, calendar: calendar)
                progress[card.id] = .init(introduced: old?.introduced ?? date, due: schedule.due,
                                          days: schedule.days, streak: schedule.streak)
                recalls.append(Recall(cardID: card.id, date: date, rating: rating))
            }

            var storyID = "—"
            var revision = false
            if adaptive && studies {
                let records = try ReadingStore.records(in: context)
                let pick = try XCTUnwrap(ReadingStore.dailyAssignment(stories: stories, planner: planner,
                    progress: progress, recalls: recalls, records: records, at: date, calendar: calendar, in: context, passageIndex: passageIndex))
                let story = try XCTUnwrap(stories.first { $0.id == pick.storyID })
                let allCompleted = stories.allSatisfy { records[$0.id]?.completed == true }
                XCTAssertEqual(pick.isRevision, allCompleted)
                if !allCompleted { XCTAssertFalse(records[story.id]?.completed == true) }
                try ReadingStore.complete(story, score: story.questions.count, at: date, in: context)
                let refreshed = try ReadingStore.dailyAssignment(stories: stories, planner: planner,
                    progress: progress, recalls: recalls, records: ReadingStore.records(in: context),
                    at: date, calendar: calendar, in: context, passageIndex: passageIndex)
                XCTAssertEqual(refreshed?.storyID, pick.storyID)
                XCTAssertEqual(refreshed?.isRevision, pick.isRevision)
                storyID = story.id
                revision = allCompleted
            }

            let after = StudyPlanner(cards: cards, progress: progress, goal: 10,
                                      at: date, calendar: calendar, recalls: recalls)
            let reviewed = studies ? reviews.count : 0
            output.append(Day(number: day, learned: progress.count, new: new.count, due: planner.dueCards.count,
                              recommended: reviews.count, reviewed: reviewed, remaining: after.dueCards.count,
                              workload: session.count, mastery: after.mastery, story: storyID, revision: revision,
                              duplicateIDs: duplicates))
        }
        return output
    }

    private func sample(_ id: String, day: Int) -> Int {
        var seed = UInt64(day) &* 0x9E3779B97F4A7C15
        for byte in id.utf8 { seed = (seed ^ UInt64(byte)) &* 0x100000001B3 }
        seed ^= seed >> 33
        seed = seed &* 0xFF51AFD7ED558CCD
        seed ^= seed >> 33
        return Int(seed % 100)
    }

    func testReviewBatchLeavesExtraAndLaterReviewsOptional() throws {
        let cards = Array(try Card.load(from: bundle).prefix(36))
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: day))
        let later = day.addingTimeInterval(600)
        var progress = Dictionary(uniqueKeysWithValues: cards.prefix(31).map {
            ($0.id, StudyPlanner.Progress(introduced: yesterday, due: day))
        })
        progress[cards[30].id] = .init(introduced: yesterday, due: later)
        let start = StudyPlanner(cards: cards, progress: progress, goal: 10, at: day, calendar: calendar)
        XCTAssertEqual(start.recommendedReviews.count, 25)
        XCTAssertEqual(start.additionalDueCount, 5)
        XCTAssertEqual(start.newCards.count, 5)
        var recalls: [Recall] = []
        for card in try XCTUnwrap(start.dailyPlan).cards {
            progress[card.id] = .init(introduced: progress[card.id]?.introduced ?? day,
                                      due: day.addingTimeInterval(86_400), days: 1)
            recalls.append(Recall(cardID: card.id, date: day, rating: .good))
        }
        let after = StudyPlanner(cards: cards, progress: progress, goal: 10, at: later,
                                 calendar: calendar, recalls: recalls)
        XCTAssertTrue(after.completedCoreToday)
        XCTAssertEqual(after.additionalDueCount, 6)
        XCTAssertEqual(after.completionPlan()?.cards.count, 6)
    }

    func testWorkloadPolicyBoundariesAndPreference() {
        let policy = DailyWorkloadPolicy()
        for (due, limit) in [(0, 20), (15, 20), (16, 10), (25, 10), (26, 5), (40, 5),
                             (41, 3), (60, 3), (61, 0)] {
            XCTAssertEqual(policy.newWordLimit(for: due, preference: 20), limit)
            XCTAssertEqual(policy.newWordLimit(for: due, preference: 5), min(limit, 5))
            XCTAssertEqual(policy.newWordLimit(for: due, preference: 0), 0)
        }
        XCTAssertEqual(policy.estimatedMinutes(new: 10, reviews: 25), 9)
    }
}
