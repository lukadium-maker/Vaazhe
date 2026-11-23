import Foundation

struct Card: Codable, Identifiable {
    var id: String
    var word: String
    var partOfSpeech: String
    var level: String
    var meaningFa: String
    var alternativeMeaningsFa: [String] = []
    var pronunciationIPA: String = ""
    var exampleEn: String
    var exampleFa: String
    var topic: String

    var isPersonal: Bool { id.hasPrefix("personal-") }

    static func load(from bundle: Bundle = .main) throws -> [Card] {
        guard let url = bundle.url(forResource: "vocabulary", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let cards = try JSONDecoder().decode([Card].self, from: Data(contentsOf: url))
        guard !cards.isEmpty, Set(cards.map(\.id)).count == cards.count,
              cards.allSatisfy({ !$0.isPersonal && !$0.id.isEmpty && !$0.word.isEmpty && !$0.meaningFa.isEmpty }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return cards
    }
}

enum Rating: String, CaseIterable {
    case again, hard, good, easy

    var label: String {
        switch self {
        case .again: "یادم نبود"
        case .hard: "سخت بود"
        case .good: "یادم بود"
        case .easy: "خیلی آسان بود"
        }
    }

    var isConfidentRecall: Bool { self == .good || self == .easy }
}

enum DailyGoal {
    static let defaultValue = 10
    static let presets = [0, 5, 10, 20, 30]

    static func choices(including current: Int) -> [Int] {
        Set(presets + [current]).sorted()
    }
}

struct Schedule: Equatable {
    var days = 0
    var streak = 0
    var due: Date

    // Expanding intervals keep the scheduler deterministic and easy to audit.
    // A retry before the 10-minute step is due cannot lengthen the interval.
    func rated(_ rating: Rating, at date: Date, calendar: Calendar) -> Schedule {
        if rating != .again && date < due { return self }

        let previous = min(90, max(0, days))
        let interval: Int
        switch rating {
        case .again: return Schedule(due: date.addingTimeInterval(600))
        case .hard: interval = max(1, previous)
        case .good: interval = min(90, max(2, previous * 2))
        case .easy: interval = min(90, max(4, previous * 3))
        }
        let next = calendar.date(byAdding: .day, value: interval, to: date)
            ?? date.addingTimeInterval(Double(interval) * 86_400)
        return Schedule(days: interval, streak: rating.isConfidentRecall ? streak + 1 : 0, due: next)
    }
}

struct Recall {
    let cardID: String
    let date: Date
    let rating: Rating
}

struct VocabularyStatus {
    enum Stage { case new, learning, mastered }

    let stage: Stage
    let isDifficult: Bool

    init(progress: StudyPlanner.Progress?, recalls: [Recall], calendar: Calendar) {
        guard let progress else {
            stage = .new
            isDifficult = false
            return
        }

        let ordered = recalls.sorted { $0.date > $1.date }
        let confident = ordered.prefix { $0.rating.isConfidentRecall }
        let recallDays = Set(confident.map { calendar.startOfDay(for: $0.date) })
        let separated = if let oldest = recallDays.min(), let newest = recallDays.max() {
            (calendar.dateComponents([.day], from: oldest, to: newest).day ?? 0) >= 6
        } else { false }

        stage = progress.streak >= 3 && progress.days >= 8 && recallDays.count >= 3 && separated
            ? .mastered : .learning
        isDifficult = confident.count < 2 && ordered.prefix(5).filter { $0.rating == .again }.count >= 2
    }
}

struct StudyQueue {
    private(set) var cards: [Card]
    private(set) var practiced: Set<String> = []
    private(set) var needsPractice: Set<String> = []
    private(set) var successful: Set<String> = []
    private var repeated: Set<String> = []
    private(set) var count = 0

    init(cards: [Card]) { self.cards = cards }

    mutating func advance(_ rating: Rating) {
        guard !cards.isEmpty else { return }
        let card = cards.removeFirst()
        practiced.insert(card.id)
        count += 1
        if rating == .again {
            successful.remove(card.id)
            needsPractice.insert(card.id)
            if !cards.isEmpty, repeated.insert(card.id).inserted {
                cards.insert(card, at: min(2, cards.count))
            }
        } else {
            successful.insert(card.id)
            needsPractice.remove(card.id)
        }
    }
}

struct StudyPlan: Identifiable {
    enum Mode { case scheduled, practice }

    let id = UUID()
    let cards: [Card]
    let newIDs: Set<String>
    var mode: Mode = .scheduled
}

enum ReviewClock {
    static func minutesRemaining(until due: Date, at date: Date) -> Int {
        Int(ceil(max(0, due.timeIntervalSince(date)) / 60))
    }

    static func nextRefresh(at date: Date, nextDue: Date?, calendar: Calendar) -> Date? {
        let midnight = calendar.dateInterval(of: .day, for: date)?.end
        guard let nextDue, nextDue > date else { return midnight }
        var next = min(nextDue, midnight ?? nextDue)
        let minutes = minutesRemaining(until: nextDue, at: date)
        // More distant reviews display a date/time. Wake once at the hour
        // threshold, then on countdown boundaries and at the exact due date.
        let nextMinute = nextDue.addingTimeInterval(-60 * Double(min(60, minutes - 1)))
        next = min(next, nextMinute)
        return next
    }
}

struct MasteryBreakdown {
    let mastered: Int
    let learning: Int
    let new: Int

    var total: Int { mastered + learning + new }

    func fraction(_ count: Int) -> Double {
        total == 0 ? 0 : Double(count) / Double(total)
    }
}

struct StudyPlanner {
    struct Progress {
        let introduced: Date
        let due: Date
        var days = 0
        var streak = 0
    }

    enum NextAction: Equatable {
        case learn, review, mixed, continueStudy, practice, setGoal, browse
    }

    let newCards: [Card]
    let dueCards: [Card]
    let scheduledLaterToday: Int
    let introducedCount: Int
    let introducedToday: Int
    let remainingNew: Int
    let remainingStarter: Int
    let nextDue: Date?
    let effectiveGoal: Int
    var reachedGoalToday: Bool { effectiveGoal > 0 && introducedToday >= effectiveGoal }
    let nextAction: NextAction
    let status: [String: VocabularyStatus]
    let practicedCards: [Card]
    let difficultCards: [Card]
    let masteredCards: [Card]

    init(cards: [Card], progress: [String: Progress], goal: Int,
         at date: Date, calendar: Calendar, recalls: [Recall] = []) {
        let history = Dictionary(grouping: recalls.filter { $0.date <= date }, by: \.cardID)
        let active = cards.filter { progress[$0.id] != nil }
        let fresh = cards.filter { progress[$0.id] == nil }
        let seenToday = active.filter { card in
            guard let state = progress[card.id] else { return false }
            return calendar.isDate(state.introduced, inSameDayAs: date)
        }.count
        let available = fresh.filter(\.isPersonal) + fresh.filter { !$0.isPersonal }
        introducedToday = seenToday
        remainingNew = fresh.count
        remainingStarter = fresh.filter { !$0.isPersonal }.count
        effectiveGoal = min(max(0, goal), seenToday + fresh.count)
        newCards = Array(available.prefix(max(0, goal - seenToday)))
        let scheduled = active.compactMap { card -> (card: Card, due: Date)? in
            progress[card.id].map { (card, $0.due) }
        }
        dueCards = scheduled.filter { $0.due <= date }.sorted { $0.due < $1.due }.map(\.card)
        let tomorrow = calendar.dateInterval(of: .day, for: date)?.end ?? date
        nextDue = scheduled.map(\.due).filter { $0 > date }.min()
        scheduledLaterToday = scheduled.filter { date < $0.due && $0.due < tomorrow }.count
        introducedCount = active.count

        let statuses = Dictionary(uniqueKeysWithValues: cards.map { card in
            (card.id, VocabularyStatus(progress: progress[card.id],
                                        recalls: history[card.id] ?? [], calendar: calendar))
        })
        status = statuses
        practicedCards = active
        difficultCards = active.filter { statuses[$0.id]?.isDifficult == true }
        masteredCards = active.filter { statuses[$0.id]?.stage == .mastered }

        let workedToday = seenToday > 0 || active.contains { card in
            history[card.id]?.contains { calendar.isDate($0.date, inSameDayAs: date) } == true
        }
        switch (newCards.isEmpty, dueCards.isEmpty) {
        case (false, false): nextAction = workedToday ? .continueStudy : .mixed
        case (false, true): nextAction = workedToday ? .continueStudy : .learn
        case (true, false): nextAction = .review
        case (true, true):
            nextAction = !active.isEmpty ? .practice : fresh.isEmpty ? .browse : .setGoal
        }
    }

    var mastery: MasteryBreakdown {
        MasteryBreakdown(mastered: masteredCards.count,
                         learning: introducedCount - masteredCards.count,
                         new: remainingNew)
    }

    var dailyPlan: StudyPlan? {
        guard !dueCards.isEmpty || !newCards.isEmpty else { return nil }
        return StudyPlan(cards: dueCards + newCards, newIDs: Set(newCards.map(\.id)))
    }

    func optionalPlan(for cards: [Card], limit: Int = 10) -> StudyPlan? {
        guard limit > 0 else { return nil }
        let eligible = cards.filter {
            guard let stage = status[$0.id]?.stage else { return false }
            return stage != .new
        }
        guard !eligible.isEmpty else { return nil }
        return StudyPlan(cards: Array(eligible.prefix(limit)), newIDs: [], mode: .practice)
    }
}

struct StudySession {
    let plan: StudyPlan
    private(set) var queue: StudyQueue
    private(set) var attemptID = UUID()
    private(set) var isRevealed = false
    private(set) var lastRating: Rating?

    init(plan: StudyPlan) {
        self.plan = plan
        queue = StudyQueue(cards: plan.cards)
    }

    var currentCard: Card? { queue.cards.first }
    var newCardsPracticed: Int { queue.practiced.intersection(plan.newIDs).count }
    var successfulReviews: Int { queue.successful.subtracting(plan.newIDs).count }

    mutating func reveal() {
        guard currentCard != nil else { return }
        isRevealed = true
    }

    mutating func submit(_ rating: Rating, for attemptID: UUID,
                         save: (Card, Rating, UUID) throws -> Void) rethrows {
        guard isRevealed, self.attemptID == attemptID, let card = currentCard else { return }
        if plan.mode == .scheduled { try save(card, rating, attemptID) }
        queue.advance(rating)
        lastRating = rating
        isRevealed = false
        self.attemptID = UUID()
    }
}

struct QuizQuestion: Identifiable {
    let card: Card
    let choices: [String]

    var id: String { card.id }
}

struct QuizSession {
    let questions: [QuizQuestion]
    private(set) var index = 0
    private(set) var selected: String?
    private(set) var correctCount = 0
    private(set) var missedCards: [Card] = []

    init(questions: [QuizQuestion]) { self.questions = questions }

    var currentQuestion: QuizQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    static func makeQuestions<R: RandomNumberGenerator>(
        practicedCards: [Card], distractorPool: [Card], limit: Int, using random: inout R
    ) -> [QuizQuestion] {
        guard limit > 0 else { return [] }
        let candidates = distractorPool.shuffled(using: &random)
        let byHeadword = Dictionary(grouping: distractorPool, by: headwordKey)
        var usedHeadwords = Set<String>()
        var questions: [QuizQuestion] = []

        for card in practicedCards.shuffled(using: &random) {
            let key = headwordKey(card)
            let primary = normalizedMeaning(card.meaningFa)
            guard !key.isEmpty, !primary.isEmpty, !usedHeadwords.contains(key) else { continue }
            var reserved = meaningKeys(for: card)
            for sense in byHeadword[key] ?? [] {
                reserved.formUnion(meaningKeys(for: sense))
            }
            var distractors: [String] = []
            let alternatives = candidates.filter { $0.id != card.id && headwordKey($0) != key }
            let matchingPart = alternatives.filter { $0.partOfSpeech == card.partOfSpeech }
            let ordered = matchingPart.filter { $0.level == card.level }
                + matchingPart.filter { $0.level != card.level }
                + alternatives.filter { $0.partOfSpeech != card.partOfSpeech }

            for candidate in ordered {
                let keys = meaningKeys(for: candidate)
                guard !normalizedMeaning(candidate.meaningFa).isEmpty,
                      reserved.isDisjoint(with: keys) else { continue }
                distractors.append(candidate.meaningFa)
                reserved.formUnion(keys)
                if distractors.count == 3 { break }
            }
            guard distractors.count == 3 else { continue }
            usedHeadwords.insert(key)
            let choices = ([card.meaningFa] + distractors).shuffled(using: &random)
            questions.append(QuizQuestion(card: card, choices: choices))
            if questions.count == limit { break }
        }
        return questions
    }

    mutating func answer(_ choice: String) {
        guard selected == nil, let question = currentQuestion, question.choices.contains(choice) else { return }
        selected = choice
        if choice == question.card.meaningFa {
            correctCount += 1
        } else {
            missedCards.append(question.card)
        }
    }

    mutating func next() {
        guard selected != nil else { return }
        index += 1
        selected = nil
    }

    private static func headwordKey(_ card: Card) -> String {
        card.word.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
    }

    private static func normalizedMeaning(_ value: String) -> String {
        value.replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fa_IR"))
            .filter { !$0.isWhitespace && $0 != "\u{200c}" }
    }

    private static func meaningKeys(for card: Card) -> Set<String> {
        Set(([card.meaningFa] + card.alternativeMeaningsFa)
            .flatMap { $0.split(whereSeparator: { "،,؛;/".contains($0) }) }
            .map { normalizedMeaning(String($0)) }
            .filter { !$0.isEmpty })
    }
}
