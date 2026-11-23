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

    init(day: ReadingDay, storyID: String) {
        self.dayKey = day.key
        self.storyID = storyID
    }
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

    static func dailyStoryID(at date: Date, calendar: Calendar, availableIDs: Set<String>,
                             in context: ModelContext, select: (String?) -> String?) throws -> String? {
        let today = ReadingDay(at: date, calendar: calendar)
        let existing = try pick(for: today, in: context)
        if let existing, availableIDs.contains(existing.storyID) { return existing.storyID }

        let previousID = try calendar.date(byAdding: .day, value: -1, to: date)
            .flatMap { try pick(for: ReadingDay(at: $0, calendar: calendar), in: context)?.storyID }
        guard let selected = select(previousID), availableIDs.contains(selected) else { return nil }
        if let existing {
            existing.storyID = selected
        } else {
            context.insert(DailyReadingPick(day: today, storyID: selected))
        }
        try save(context)
        return selected
    }

    private static func pick(for day: ReadingDay, in context: ModelContext) throws -> DailyReadingPick? {
        let key = day.key
        var query = FetchDescriptor<DailyReadingPick>(predicate: #Predicate { $0.dayKey == key })
        query.fetchLimit = 1
        return try context.fetch(query).first
    }

    static func markRead(_ storyID: String, at date: Date = .now, in context: ModelContext) throws {
        let progress = try progress(for: storyID, in: context)
        guard progress.readAt == nil else { return }
        progress.readAt = date
        try save(context)
    }

    static func complete(_ story: ReadingStory, score: Int, at date: Date = .now, in context: ModelContext) throws {
        guard (0...story.questions.count).contains(score) else { throw CocoaError(.coderInvalidValue) }
        let progress = try progress(for: story.id, in: context)
        if progress.readAt == nil { progress.readAt = date }
        progress.attempts += 1
        progress.bestScore = max(progress.bestScore, score)
        progress.recentScore = score
        progress.lastCompletion = date
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
