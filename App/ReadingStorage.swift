import Foundation
import SwiftData

@Model final class ReadingProgress {
    @Attribute(.unique) var storyID: String
    var readAt: Date?
    var bestScore = 0
    var recentScore: Int?
    var attempts = 0
    var lastCompletion: Date?

    init(storyID: String) {
        self.storyID = storyID
    }

    var record: ReadingRecord {
        ReadingRecord(read: readAt != nil, bestScore: bestScore, recentScore: recentScore,
                      attempts: attempts, lastCompletion: lastCompletion)
    }
}

@Model final class DailyReadingPick {
    @Attribute(.unique) var dayKey: String
    var storyID: String
    var isRevision: Bool?
    var isLocked: Bool?

    init(day: ReadingDay, storyID: String) {
        self.dayKey = day.key
        self.storyID = storyID
    }

    #if DEBUG
    init(dayKey: String, storyID: String, isRevision: Bool? = nil, isLocked: Bool? = nil) {
        self.dayKey = dayKey
        self.storyID = storyID
        self.isRevision = isRevision
        self.isLocked = isLocked
    }
    #endif
}

@MainActor enum ReadingStore {
    static func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        // A named store allows the installed vocabulary store and its schema
        // to stay intact. This context stores reading records and daily picks.
        let schema = Schema([ReadingProgress.self, DailyReadingPick.self])
        let configuration = if let url {
            ModelConfiguration("ReadingProgress", schema: schema, url: url)
        } else {
            ModelConfiguration("ReadingProgress", schema: schema)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func records(in context: ModelContext) throws -> [String: ReadingRecord] {
        try Dictionary(uniqueKeysWithValues: context.fetch(FetchDescriptor<ReadingProgress>()).map {
            ($0.storyID, $0.record)
        })
    }

    static func reset(in context: ModelContext) throws {
        let progress = try context.fetch(FetchDescriptor<ReadingProgress>())
        let picks = try context.fetch(FetchDescriptor<DailyReadingPick>())
        for record in progress { context.delete(record) }
        for pick in picks { context.delete(pick) }
        try save(context)
    }

    static func dailyStoryID(stories: [ReadingStory], planner: StudyPlanner,
                             progress: [String: StudyPlanner.Progress], recalls: [Recall],
                             records: [String: ReadingRecord], at date: Date,
                             calendar: Calendar, in context: ModelContext,
                             passageIndex: ReadingPassageIndex = ReadingPassageIndex()) throws -> String? {
        try dailyAssignment(stories: stories, planner: planner, progress: progress, recalls: recalls,
                            records: records, at: date, calendar: calendar, in: context, passageIndex: passageIndex)?.storyID
    }

    static func dailyAssignment(stories: [ReadingStory], planner: StudyPlanner,
                                progress: [String: StudyPlanner.Progress], recalls: [Recall],
                                records: [String: ReadingRecord], at date: Date,
                                calendar: Calendar, in context: ModelContext,
                                passageIndex: ReadingPassageIndex = ReadingPassageIndex()) throws -> DailyReadingPick? {
        let day = ReadingDay(at: date, calendar: calendar)
        let start = calendar.startOfDay(for: date)
        var available = Set(stories.map(\.id))
        let previousCompletion = Set(available.filter { records[$0]?.lastCompletion.map { $0 < start } == true })
        if let legacy = try pick(for: day, in: context), legacy.isRevision == nil,
           previousCompletion.contains(legacy.storyID), previousCompletion != available,
           stories.contains(where: { records[$0.id]?.completed != true }) {
            available.remove(legacy.storyID)
        }
        let introducedToday = Set(planner.cardsIntroducedToday.map(\.id))
        let lessonIDs = introducedToday.union(planner.newCards.map(\.id))
        func recommend(previousID: String?, lesson: Set<String>) -> ReadingRecommendationEngine.Recommendation? {
            ReadingRecommendationEngine.recommend(
                stories: stories.filter { available.contains($0.id) }, statuses: planner.status, progress: progress,
                recalls: recalls, records: records, at: date, calendar: calendar, previousStoryID: previousID, passageIndex: passageIndex,
                lessonIDs: lesson
            )
        }
        let existingID = try pick(for: day, in: context)?.storyID
        let id = try dailyStoryID(at: date, calendar: calendar, availableIDs: available, in: context) {
            recommend(previousID: $0, lesson: lessonIDs)?.storyID
        }
        guard let id, let assignment = try pick(for: day, in: context) else { return nil }
        if planner.reachedGoalToday, assignment.isLocked != true {
            if existingID == id, !previousCompletion.contains(id), records[id]?.read != true,
               let candidate = recommend(previousID: try previousStoryID(at: date, calendar: calendar, in: context),
                                         lesson: introducedToday),
               candidate.storyID != id, records[candidate.storyID]?.completed != true,
               let current = stories.first(where: { $0.id == id }),
               candidate.lessonOverlap >
                passageIndex.familiarity(for: current, encountered: introducedToday).familiarPassageIDs.count {
                assignment.storyID = candidate.storyID
                assignment.isRevision = false
            }
            assignment.isLocked = true
        }
        if assignment.isRevision == nil {
            assignment.isRevision = previousCompletion.contains(assignment.storyID)
        }
        if context.hasChanges { try save(context) }
        return assignment
    }

    static func dailyStoryID(at date: Date, calendar: Calendar, availableIDs: Set<String>,
                             in context: ModelContext, select: (String?) -> String?) throws -> String? {
        let today = ReadingDay(at: date, calendar: calendar)
        let existing = try pick(for: today, in: context)
        if let existing, availableIDs.contains(existing.storyID) { return existing.storyID }

        let previousID = try previousStoryID(at: date, calendar: calendar, in: context)
        guard let selected = select(previousID), availableIDs.contains(selected) else { return nil }
        if let existing {
            existing.storyID = selected
            existing.isRevision = nil
            existing.isLocked = nil
        } else {
            context.insert(DailyReadingPick(day: today, storyID: selected))
        }
        try save(context)
        return selected
    }

    static func lockDailyStory(_ storyID: String, at date: Date, calendar: Calendar, in context: ModelContext) throws {
        guard let assignment = try pick(for: ReadingDay(at: date, calendar: calendar), in: context),
              assignment.storyID == storyID, assignment.isLocked != true else { return }
        assignment.isLocked = true
        try save(context)
    }

    private static func previousStoryID(at date: Date, calendar: Calendar, in context: ModelContext) throws -> String? {
        try calendar.date(byAdding: .day, value: -1, to: date)
            .flatMap { try pick(for: ReadingDay(at: $0, calendar: calendar), in: context)?.storyID }
    }

    private static func pick(for day: ReadingDay, in context: ModelContext) throws -> DailyReadingPick? {
        let key = day.key
        var query = FetchDescriptor<DailyReadingPick>(predicate: #Predicate { $0.dayKey == key })
        query.fetchLimit = 1
        return try context.fetch(query).first
    }

    static func markRead(_ storyID: String, at date: Date, in context: ModelContext) throws {
        let progress = try progress(for: storyID, in: context)
        guard progress.readAt == nil else { return }
        progress.readAt = date
        try save(context)
    }

    static func complete(_ story: ReadingStory, score: Int, at date: Date,
                         in context: ModelContext, beforeSave: () -> Void = {}) throws {
        guard (0...story.questions.count).contains(score) else { throw CocoaError(.coderInvalidValue) }
        let progress = try progress(for: story.id, in: context)
        if progress.readAt == nil { progress.readAt = date }
        progress.attempts += 1
        progress.bestScore = max(progress.bestScore, score)
        progress.recentScore = score
        progress.lastCompletion = date
        beforeSave()
        try save(context)
    }

    private static func progress(for storyID: String, in context: ModelContext) throws -> ReadingProgress {
        let query = FetchDescriptor<ReadingProgress>(predicate: #Predicate { $0.storyID == storyID })
        if let existing = try context.fetch(query).first { return existing }
        let progress = ReadingProgress(storyID: storyID)
        context.insert(progress)
        return progress
    }

    private static func save(_ context: ModelContext) throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }
}
