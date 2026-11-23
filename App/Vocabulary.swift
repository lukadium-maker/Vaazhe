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
    case again, hard, good

    var label: String {
        switch self {
        case .again: "فراموش کردم"
        case .hard: "سخت بود"
        case .good: "بلد بودم"
        }
    }
}

struct Schedule: Equatable {
    var days = 0
    var streak = 0
    var due: Date

    // Prototype policy: 10 minutes for Again, 1–7 days for Hard,
    // and 2–90 days for Good. Three consecutive Good ratings count as strong.
    func rated(_ rating: Rating, at date: Date, calendar: Calendar) -> Schedule {
        switch rating {
        case .again:
            return Schedule(due: date.addingTimeInterval(600))
        case .hard, .good:
            let interval = rating == .hard ? min(7, max(1, days)) : min(90, max(2, days * 2))
            let next = calendar.date(byAdding: .day, value: interval, to: date)
                ?? date.addingTimeInterval(Double(interval) * 86_400)
            return Schedule(days: interval, streak: rating == .good ? streak + 1 : 0, due: next)
        }
    }
}

struct StudyQueue {
    private(set) var cards: [Card]
    private(set) var practiced: Set<String> = []
    private(set) var needsPractice: Set<String> = []
    private var repeated: Set<String> = []
    private(set) var count = 0

    init(cards: [Card]) { self.cards = cards }

    mutating func advance(_ rating: Rating) {
        guard !cards.isEmpty else { return }
        let card = cards.removeFirst()
        practiced.insert(card.id)
        count += 1
        if rating == .again {
            needsPractice.insert(card.id)
            if !cards.isEmpty, repeated.insert(card.id).inserted {
                cards.insert(card, at: min(2, cards.count))
            }
        } else {
            needsPractice.remove(card.id)
        }
    }
}

struct StudyPlan: Identifiable {
    let id = UUID()
    let cards: [Card]
    let newIDs: Set<String>
}

struct StudyPlanner {
    struct Progress {
        let introduced: Date
        let due: Date
    }

    let newCards: [Card]
    let dueCards: [Card]
    let introducedCount: Int

    init(cards: [Card], progress: [String: Progress], goal: Int,
         at date: Date, calendar: Calendar) {
        let seenToday = progress.values.filter { calendar.isDate($0.introduced, inSameDayAs: date) }.count
        let fresh = cards.filter { progress[$0.id] == nil }
        let available = fresh.filter(\.isPersonal) + fresh.filter { !$0.isPersonal }
        newCards = Array(available.prefix(max(0, goal - seenToday)))
        dueCards = cards.compactMap { card -> (card: Card, due: Date)? in
            guard let state = progress[card.id], state.due <= date else { return nil }
            return (card, state.due)
        }
        .sorted { $0.due < $1.due }
        .map(\.card)
        introducedCount = cards.count - fresh.count
    }

    var dailyPlan: StudyPlan? {
        guard !dueCards.isEmpty || !newCards.isEmpty else { return nil }
        return StudyPlan(cards: dueCards + newCards, newIDs: Set(newCards.map(\.id)))
    }
}

struct StudySession {
    let plan: StudyPlan
    private(set) var queue: StudyQueue
    private(set) var attemptID = UUID()
    private(set) var isRevealed = false

    init(plan: StudyPlan) {
        self.plan = plan
        queue = StudyQueue(cards: plan.cards)
    }

    var currentCard: Card? { queue.cards.first }
    var newCardsPracticed: Int { queue.practiced.intersection(plan.newIDs).count }

    mutating func reveal() {
        guard currentCard != nil else { return }
        isRevealed = true
    }

    mutating func submit(_ rating: Rating, for attemptID: UUID,
                         save: (Card, Rating, UUID) throws -> Void) rethrows {
        guard isRevealed, self.attemptID == attemptID, let card = currentCard else { return }
        try save(card, rating, attemptID)
        queue.advance(rating)
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

    init(questions: [QuizQuestion]) { self.questions = questions }

    var currentQuestion: QuizQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    static func makeQuestions<R: RandomNumberGenerator>(
        practicedCards: [Card], distractorPool: [Card], limit: Int, using random: inout R
    ) -> [QuizQuestion] {
        guard limit > 0 else { return [] }
        let candidates = distractorPool.shuffled(using: &random)
        var questions: [QuizQuestion] = []

        for card in practicedCards.shuffled(using: &random) {
            let correct = meaningKeys(for: card)
            var reserved = correct
            var distractors: [String] = []
            let alternatives = candidates.filter {
                $0.id != card.id && $0.word.caseInsensitiveCompare(card.word) != .orderedSame
            }
            let ordered = alternatives.filter { $0.partOfSpeech == card.partOfSpeech }
                + alternatives.filter { $0.partOfSpeech != card.partOfSpeech }

            for candidate in ordered {
                let keys = meaningKeys(for: candidate)
                guard !keys.isEmpty, reserved.isDisjoint(with: keys) else { continue }
                distractors.append(candidate.meaningFa)
                reserved.formUnion(keys)
                if distractors.count == 3 { break }
            }
            guard !correct.isEmpty, distractors.count == 3 else { continue }
            let choices = ([card.meaningFa] + distractors).shuffled(using: &random)
            questions.append(QuizQuestion(card: card, choices: choices))
            if questions.count == limit { break }
        }
        return questions
    }

    mutating func answer(_ choice: String) {
        guard selected == nil, let question = currentQuestion, question.choices.contains(choice) else { return }
        selected = choice
        if choice == question.card.meaningFa { correctCount += 1 }
    }

    mutating func next() {
        guard selected != nil else { return }
        index += 1
        selected = nil
    }

    private static func meaningKeys(for card: Card) -> Set<String> {
        Set(([card.meaningFa] + card.alternativeMeaningsFa)
            .flatMap { $0.split(whereSeparator: { "،,؛;/".contains($0) }) }
            .map {
                $0.replacingOccurrences(of: "ي", with: "ی")
                    .replacingOccurrences(of: "ك", with: "ک")
                    .filter { !$0.isWhitespace && $0 != "\u{200c}" }
            }
            .filter { !$0.isEmpty })
    }
}
