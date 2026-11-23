import Foundation
import SwiftData

@Model final class PersonalCard {
    @Attribute(.unique) var id: String
    var word: String
    var meaning: String
    var part: String
    var example: String
    var translation: String

    init(_ card: Card) {
        id = card.id
        word = card.word
        meaning = card.meaningFa
        part = card.partOfSpeech
        example = card.exampleEn
        translation = card.exampleFa
    }

    var card: Card {
        Card(id: id, word: word, partOfSpeech: part, level: "", meaningFa: meaning,
             exampleEn: example, exampleFa: translation, topic: "")
    }
}

@Model final class ReviewState {
    @Attribute(.unique) var cardID: String
    var introduced: Date
    var days: Int
    var streak: Int
    var due: Date

    init(cardID: String, date: Date) {
        self.cardID = cardID
        introduced = date
        days = 0
        streak = 0
        due = date
    }
}

@Model final class ReviewEvent {
    @Attribute(.unique) var attemptID: UUID
    var cardID: String
    var word: String
    var date: Date
    var rating: String

    init(attemptID: UUID, card: Card, date: Date, rating: Rating) {
        self.attemptID = attemptID
        cardID = card.id
        word = card.word
        self.date = date
        self.rating = rating.rawValue
    }
}

@MainActor enum ReviewStore {
    static func record(_ card: Card, rating: Rating, attemptID: UUID, date: Date,
                       in context: ModelContext, calendar: Calendar = .current) throws {
        let attempts = FetchDescriptor<ReviewEvent>(predicate: #Predicate { $0.attemptID == attemptID })
        guard try context.fetchCount(attempts) == 0 else { return }
        let cardID = card.id
        let states = FetchDescriptor<ReviewState>(predicate: #Predicate { $0.cardID == cardID })
        let existing = try context.fetch(states).first
        let state = existing ?? ReviewState(cardID: cardID, date: date)
        if existing == nil { context.insert(state) }
        let result = Schedule(days: state.days, streak: state.streak, due: state.due)
            .rated(rating, at: date, calendar: calendar)
        state.days = result.days
        state.streak = result.streak
        state.due = result.due
        context.insert(ReviewEvent(attemptID: attemptID, card: card, date: date, rating: rating))
        try save(context)
    }

    static func save(_ context: ModelContext) throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }
}
