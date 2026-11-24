#if DEBUG
import Foundation
import Observation
import SwiftData

@Model final class SimulationCheckpoint {
    @Attribute(.unique) var day: String
    var start: Date
    var snapshot: Data
    var celebratedDay: String

    init(day: String, start: Date, snapshot: Data, celebratedDay: String) {
        self.day = day
        self.start = start
        self.snapshot = snapshot
        self.celebratedDay = celebratedDay
    }
}

@Model final class SimulationReadingCompletion {
    var storyID: String
    var date: Date
    var isBaseline: Bool

    init(storyID: String, date: Date, isBaseline: Bool = false) {
        self.storyID = storyID
        self.date = date
        self.isBaseline = isBaseline
    }
}

@MainActor @Observable final class DeveloperSimulation {
    struct Session: Codable {
        let id: UUID
        let started: Date
        var date: Date
        let calendar: Calendar
    }

    enum Failure: LocalizedError {
        case unavailable, pastActivity, missingCheckpoint

        var errorDescription: String? {
            switch self {
            case .unavailable: "Simulation storage is unavailable."
            case .pastActivity: "This date precedes saved activity. Move forward or reset simulated progress before writing here."
            case .missingCheckpoint: "There is no simulated learning activity to reset on this day."
            }
        }
    }

    private var session: Session
    private let directory: URL
    let preferences: UserDefaults
    let container: ModelContainer

    var id: UUID { session.id }
    var date: Date { session.date }
    var calendar: Calendar { session.calendar }
    var day: ReadingDay { ReadingDay(at: date, calendar: calendar) }
    var learningDay: Int {
        1 + (calendar.dateComponents([.day], from: calendar.startOfDay(for: session.started),
                                    to: calendar.startOfDay(for: date)).day ?? 0)
    }

    static func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appending(path: "DeveloperSimulation", directoryHint: .isDirectory)
    }

    private init(session: Session, directory: URL, create: Bool) throws {
        let profile = directory.appending(path: session.id.uuidString, directoryHint: .isDirectory)
        let url = profile.appending(path: "Learning.store")
        if create {
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        } else if !FileManager.default.fileExists(atPath: url.path) {
            throw Failure.unavailable
        }
        guard let preferences = UserDefaults(suiteName: "Elphy.DeveloperSimulation.\(session.id)") else {
            throw Failure.unavailable
        }
        self.preferences = preferences
        self.session = session
        self.directory = directory
        let schema = Schema([PersonalCard.self, ReviewState.self, ReviewEvent.self,
                             ReadingProgress.self, DailyReadingPick.self, SimulationCheckpoint.self,
                             SimulationReadingCompletion.self, PracticeSessionRecord.self])
        let configuration = ModelConfiguration("Simulation", schema: schema, url: url, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func sessionURL(in directory: URL) -> URL {
        directory.appending(path: "ActiveSession.json")
    }

    static func resume(in directory: URL) throws -> DeveloperSimulation? {
        let url = sessionURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let session = try JSONDecoder().decode(Session.self, from: Data(contentsOf: url))
        return try DeveloperSimulation(session: session, directory: directory, create: false)
    }

    static func start(at date: Date, calendar: Calendar, in directory: URL, defaults: UserDefaults = .standard,
                      copying source: (vocabulary: ModelContext, reading: ModelContext)? = nil,
                      practice: ModelContext? = nil) throws -> DeveloperSimulation {
        let session = Session(id: UUID(), started: date, date: date, calendar: calendar)
        let simulation = try DeveloperSimulation(session: session, directory: directory, create: true)
        if let source {
            let destination = simulation.container.mainContext
            for card in try source.vocabulary.fetch(FetchDescriptor<PersonalCard>()) {
                destination.insert(PersonalCard(card.card))
            }
            let snapshot = try LearningSnapshot(vocabulary: source.vocabulary, reading: source.reading)
            try snapshot.restore(in: destination)
            for progress in snapshot.reading {
                if let date = progress.completed {
                    destination.insert(SimulationReadingCompletion(storyID: progress.id, date: date, isBaseline: true))
                }
            }
            for pick in try source.reading.fetch(FetchDescriptor<DailyReadingPick>()) {
                destination.insert(DailyReadingPick(dayKey: pick.dayKey, storyID: pick.storyID, isRevision: pick.isRevision))
            }
            if let practice {
                for record in try practice.fetch(FetchDescriptor<PracticeSessionRecord>()) {
                    destination.insert(PracticeSessionRecord(id: record.id, date: record.date, payload: record.payload,
                                                             sequence: record.sequence, copiedBaseline: true))
                }
            }
            try ReviewStore.save(destination)
            simulation.preferences.set(defaults.object(forKey: "dailyGoal"), forKey: "dailyGoal")
            simulation.preferences.set(defaults.string(forKey: "lastCelebratedLearningDay"),
                                       forKey: "lastCelebratedLearningDay")
        }
        try simulation.persist(session)
        return simulation
    }

    func stop() throws {
        try FileManager.default.removeItem(at: Self.sessionURL(in: directory))
    }

    // Run before opening a profile on launch, when no old stores are in use.
    static func removeInactiveProfiles(in directory: URL, keeping id: UUID?) {
        guard let profiles = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for profile in profiles {
            guard let profileID = UUID(uuidString: profile.lastPathComponent), profileID != id else { continue }
            try? FileManager.default.removeItem(at: profile)
            let suite = "Elphy.DeveloperSimulation.\(profileID)"
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    func move(days: Int) throws {
        guard let next = calendar.date(byAdding: .day, value: days, to: date) else { return }
        try jump(to: next)
    }

    func midnight() throws {
        guard let next = calendar.dateInterval(of: .day, for: date)?.end else { return }
        try jump(to: next)
    }

    func jump(to date: Date) throws {
        var updated = session
        updated.date = date
        try persist(updated)
    }

    private func persist(_ updated: Session) throws {
        try JSONEncoder().encode(updated).write(to: Self.sessionURL(in: directory), options: .atomic)
        session = updated
    }

    func prepareLearningWrite(at date: Date, in context: ModelContext) throws {
        guard context.container === container else { throw Failure.unavailable }
        let snapshot = try LearningSnapshot(vocabulary: context, reading: context)
        if let latest = snapshot.latestActivity, date < latest { throw Failure.pastActivity }
        let key = ReadingDay(at: date, calendar: calendar).key
        guard try checkpoint(for: key, in: context) == nil else { return }
        context.insert(SimulationCheckpoint(day: key, start: calendar.startOfDay(for: date),
                                            snapshot: try JSONEncoder().encode(snapshot),
                                            celebratedDay: preferences.string(forKey: "lastCelebratedLearningDay") ?? ""))
        try ReviewStore.save(context)
    }

    func recordReadingCompletion(_ storyID: String, at date: Date, in context: ModelContext) {
        context.insert(SimulationReadingCompletion(storyID: storyID, date: date))
    }

    func readingCompletions() throws -> [SimulationReadingCompletion] {
        try container.mainContext.fetch(FetchDescriptor<SimulationReadingCompletion>())
    }

    func resetDay() throws {
        let context = container.mainContext
        let checkpoint = try checkpoint(for: day.key, in: context)
        let practice = try context.fetch(FetchDescriptor<PracticeSessionRecord>()).filter {
            !$0.copiedBaseline && calendar.isDate($0.date, inSameDayAs: date)
        }
        guard let checkpoint else {
            guard !practice.isEmpty else { throw Failure.missingCheckpoint }
            for record in practice { context.delete(record) }
            try ReviewStore.save(context)
            return
        }
        let current = try LearningSnapshot(vocabulary: context, reading: context)
        if let latest = current.latestActivity, calendar.startOfDay(for: latest) > calendar.startOfDay(for: date) {
            throw Failure.pastActivity
        }
        let snapshot = try JSONDecoder().decode(LearningSnapshot.self, from: checkpoint.snapshot)
        let celebrated = checkpoint.celebratedDay
        let completions = try readingCompletions().filter {
            !$0.isBaseline && calendar.isDate($0.date, inSameDayAs: date)
        }
        let start = checkpoint.start
        let invalidated = try context.fetch(FetchDescriptor<SimulationCheckpoint>(predicate: #Predicate {
            $0.start >= start
        }))
        // Restore in place so SwiftData retains one row per unique key throughout the transaction.
        try snapshot.restore(in: context)
        for record in practice { context.delete(record) }
        for completion in completions { context.delete(completion) }
        for checkpoint in invalidated { context.delete(checkpoint) }
        try ReviewStore.save(context)
        preferences.set(celebrated, forKey: "lastCelebratedLearningDay")
    }

    func resetProgress() throws {
        let context = container.mainContext
        let picks = try context.fetch(FetchDescriptor<DailyReadingPick>())
        let checkpoints = try context.fetch(FetchDescriptor<SimulationCheckpoint>())
        let completions = try readingCompletions()
        let practice = try context.fetch(FetchDescriptor<PracticeSessionRecord>())
        try LearningSnapshot.empty.restore(in: context)
        for record in practice { context.delete(record) }
        for pick in picks { context.delete(pick) }
        for checkpoint in checkpoints { context.delete(checkpoint) }
        for completion in completions { context.delete(completion) }
        try ReviewStore.save(context)
        preferences.removeObject(forKey: "lastCelebratedLearningDay")
    }

    private func checkpoint(for key: String, in context: ModelContext) throws -> SimulationCheckpoint? {
        let query = FetchDescriptor<SimulationCheckpoint>(predicate: #Predicate { $0.day == key })
        return try context.fetch(query).first
    }
}

private struct LearningSnapshot: Codable {
    struct State: Codable {
        let id: String
        let introduced: Date
        let days: Int
        let streak: Int
        let due: Date

        func apply(to row: ReviewState) {
            row.introduced = introduced
            row.days = days
            row.streak = streak
            row.due = due
        }
    }

    struct Event: Codable {
        let id: UUID
        let cardID: String
        let word: String
        let date: Date
        let rating: String
    }

    struct Reading: Codable {
        let id: String
        let readAt: Date?
        let best: Int
        let recent: Int?
        let attempts: Int
        let completed: Date?

        func apply(to row: ReadingProgress) {
            row.readAt = readAt
            row.bestScore = best
            row.recentScore = recent
            row.attempts = attempts
            row.lastCompletion = completed
        }
    }

    let states: [State]
    let events: [Event]
    let reading: [Reading]
    static let empty = Self(states: [], events: [], reading: [])

    var latestActivity: Date? {
        (events.map(\.date) + states.map(\.introduced) + reading.flatMap { [$0.readAt, $0.completed].compactMap { $0 } })
            .max()
    }

    private init(states: [State], events: [Event], reading: [Reading]) {
        self.states = states
        self.events = events
        self.reading = reading
    }

    @MainActor init(vocabulary: ModelContext, reading: ModelContext) throws {
        states = try vocabulary.fetch(FetchDescriptor<ReviewState>()).map {
            State(id: $0.cardID, introduced: $0.introduced, days: $0.days, streak: $0.streak, due: $0.due)
        }
        events = try vocabulary.fetch(FetchDescriptor<ReviewEvent>()).map {
            Event(id: $0.attemptID, cardID: $0.cardID, word: $0.word, date: $0.date, rating: $0.rating)
        }
        self.reading = try reading.fetch(FetchDescriptor<ReadingProgress>()).map {
            Reading(id: $0.storyID, readAt: $0.readAt, best: $0.bestScore, recent: $0.recentScore,
                    attempts: $0.attempts, completed: $0.lastCompletion)
        }
    }

    @MainActor func restore(in context: ModelContext) throws {
        let existingStates = try context.fetch(FetchDescriptor<ReviewState>())
        let existingEvents = try context.fetch(FetchDescriptor<ReviewEvent>())
        let existingReading = try context.fetch(FetchDescriptor<ReadingProgress>())
        let statesByID = Dictionary(uniqueKeysWithValues: existingStates.map { ($0.cardID, $0) })
        let readingByID = Dictionary(uniqueKeysWithValues: existingReading.map { ($0.storyID, $0) })
        let stateIDs = Set(states.map(\.id))
        let eventIDs = Set(events.map(\.id))
        let readingIDs = Set(reading.map(\.id))
        let existingEventIDs = Set(existingEvents.map(\.attemptID))
        for row in existingStates where !stateIDs.contains(row.cardID) { context.delete(row) }
        for row in existingEvents where !eventIDs.contains(row.attemptID) { context.delete(row) }
        for row in existingReading where !readingIDs.contains(row.storyID) { context.delete(row) }
        for state in states {
            let row = statesByID[state.id] ?? ReviewState(cardID: state.id, date: state.introduced)
            state.apply(to: row)
            if statesByID[state.id] == nil { context.insert(row) }
        }
        for event in events where !existingEventIDs.contains(event.id) {
            context.insert(ReviewEvent(attemptID: event.id, cardID: event.cardID, word: event.word,
                                       date: event.date, rating: event.rating))
        }
        for progress in reading {
            let row = readingByID[progress.id] ?? ReadingProgress(storyID: progress.id)
            progress.apply(to: row)
            if readingByID[progress.id] == nil { context.insert(row) }
        }
    }
}

struct LearningStreak {
    let current: Int
    let longest: Int

    init(activity: [Date], at date: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: date)
        let days = Set(activity.filter { $0 <= date }.map { calendar.startOfDay(for: $0) }).sorted()
        var run = 0
        var longest = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        self.longest = longest
        let daysSinceLast = previous.flatMap { calendar.dateComponents([.day], from: $0, to: today).day }
        current = daysSinceLast == 0 || daysSinceLast == 1 ? run : 0
    }
}
#endif
