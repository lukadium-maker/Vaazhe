import Foundation
import Observation
import SwiftData

@MainActor @Observable final class AppClock {
    var systemNow: Date { systemDate() }
    var now: Date {
        #if DEBUG
        if let simulation { return simulation.date }
        #endif
        return systemNow
    }

    var calendar: Calendar {
        #if DEBUG
        if let simulation { return simulation.calendar }
        #endif
        return systemCalendar()
    }

    var isSimulating: Bool {
        #if DEBUG
        simulation != nil
        #else
        false
        #endif
    }

    private let systemDate: () -> Date
    private let systemCalendar: () -> Calendar

    #if DEBUG
    var simulation: DeveloperSimulation?
    var simulationRecoveryError: String?
    #endif

    init(systemDate: @escaping () -> Date = { .now },
         systemCalendar: @escaping () -> Calendar = { .current }) {
        self.systemDate = systemDate
        self.systemCalendar = systemCalendar
    }

    func record(_ card: Card, rating: Rating, attemptID: UUID, in context: ModelContext) throws {
        let date = now
        #if DEBUG
        try simulation?.prepareLearningWrite(at: date, in: context)
        #endif
        try ReviewStore.record(card, rating: rating, attemptID: attemptID, date: date,
                               in: context, calendar: calendar)
    }

    func markRead(_ storyID: String, in context: ModelContext) throws {
        let date = now
        #if DEBUG
        try simulation?.prepareLearningWrite(at: date, in: context)
        #endif
        try ReadingStore.markRead(storyID, at: date, in: context)
    }

    func complete(_ story: ReadingStory, score: Int, in context: ModelContext) throws {
        let date = now
        #if DEBUG
        try simulation?.prepareLearningWrite(at: date, in: context)
        try ReadingStore.complete(story, score: score, at: date, in: context) {
            simulation?.recordReadingCompletion(story.id, at: date, in: context)
        }
        #else
        try ReadingStore.complete(story, score: score, at: date, in: context)
        #endif
    }

    func relativeDate(_ date: Date, to reference: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: reference)
    }
}
