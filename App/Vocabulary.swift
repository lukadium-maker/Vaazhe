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

    static func normalizedMeaning(_ value: String) -> String {
        value.replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fa_IR"))
            .filter { !$0.isWhitespace && $0 != "\u{200c}" }
    }

    var meaningKeys: Set<String> {
        Set(([meaningFa] + alternativeMeaningsFa)
            .flatMap { $0.split(whereSeparator: { "،,؛;/".contains($0) }) }
            .map { Self.normalizedMeaning(String($0)) }
            .filter { !$0.isEmpty })
    }

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
    static let presets = [5, 10, 20]

    static func preferred(_ saved: Int) -> Int {
        presets.last { $0 <= saved } ?? presets[0]
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
    enum Mode { case scheduled, practice, difficult }

    let id = UUID()
    let cards: [Card]
    let newIDs: Set<String>
    var mode: Mode = .scheduled
}

enum ReviewClock {
    static func nextRefresh(at date: Date, nextDue: Date?, calendar: Calendar) -> Date? {
        let midnight = calendar.dateInterval(of: .day, for: date)?.end
        guard let nextDue, nextDue > date else { return midnight }
        return min(nextDue, midnight ?? nextDue)
    }
}

struct DailyLearningProgress: Equatable {
    let day: Date
    let count: Int
    let target: Int
    let configuredGoal: Int

    var fraction: Double {
        target > 0 ? min(1, Double(count) / Double(target)) : 0
    }

    func reachedGoal(since previous: Self) -> Bool {
        day == previous.day && target > 0 && target == previous.target &&
            configuredGoal == previous.configuredGoal && previous.count < target && count >= target
    }
}

enum TodayLearningState: Equatable {
    case goalComplete(action: StudyPlan.Mode?)
    case next(StudyPlanner.NextAction)

    init(planner: StudyPlanner) {
        self = planner.reachedGoalToday ? .goalComplete(action: planner.completionPlan()?.mode)
            : .next(planner.nextAction)
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

struct DailyWorkloadPolicy {
    var reviewLimit = 25
    var newWordLimits = [(through: 15, limit: 20), (through: 25, limit: 10),
                         (through: 40, limit: 5), (through: 60, limit: 3)]
    var recoveryThreshold = 26
    var secondsPerNewWord = 24
    var secondsPerReview = 10

    func newWordLimit(for reviewDemand: Int, preference: Int) -> Int {
        let limit = newWordLimits.first { reviewDemand <= $0.through }?.limit ?? 0
        return max(0, min(limit, preference))
    }

    func estimatedMinutes(new: Int, reviews: Int) -> Int {
        (new * secondsPerNewWord + reviews * secondsPerReview + 59) / 60
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

    // Teach vocabulary that supports the early reading stories before following catalog order.
    private static let starterReadingWords = [
        "en-train-noun", "en-ticket-noun", "en-station-noun", "en-wait-verb", "en-arrive-verb",
        "en-early-adverb", "en-leave-verb", "en-meet-verb", "en-morning-noun", "en-late-adjective",
        "en-airport-noun", "en-passport-noun", "en-traffic-noun", "en-trip-noun", "en-airline-noun",
        "en-find-verb", "en-bag-noun", "en-plane-noun", "en-plan-noun", "en-enough-adverb"
    ]

    private static let fifthLessonWords = [
        "en-dictionary-noun", "en-learn-verb", "en-question-noun", "en-choose-verb", "en-spell-verb",
        "en-repeat-verb", "en-remember-verb", "en-look-verb", "en-bed-noun", "en-door-noun"
    ]

    let newCards: [Card]
    let dueCards: [Card]
    let recommendedReviews: [Card]
    let reviewedToday: Int
    let isRecoveryDay: Bool
    let estimatedMinutes: Int
    var additionalDueCount: Int { dueCards.count - recommendedReviews.count }
    var completedCoreToday: Bool {
        recommendedReviews.isEmpty && newCards.isEmpty && (introducedToday > 0 || reviewedToday > 0)
    }
    private let reviewLimit: Int
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
    let cardsIntroducedToday: [Card]

    init(cards: [Card], progress: [String: Progress], goal: Int,
         at date: Date, calendar: Calendar, recalls: [Recall] = [],
         workload: DailyWorkloadPolicy = DailyWorkloadPolicy()) {
        let history = Dictionary(grouping: recalls.filter { $0.date <= date }, by: \.cardID)
        let active = cards.filter { progress[$0.id] != nil }
        let fresh = cards.filter { progress[$0.id] == nil }
        let introducedTodayCards = active.filter { card in
            guard let state = progress[card.id] else { return false }
            return calendar.isDate(state.introduced, inSameDayAs: date)
        }
        let seenToday = introducedTodayCards.count
        let personal = fresh.filter(\.isPersonal)
        let bundled = cards.filter { !$0.isPersonal }
        let byID = Dictionary(uniqueKeysWithValues: bundled.map { ($0.id, $0) })
        let starter = Self.starterReadingWords.compactMap { byID[$0] }
        let fifthLesson = Self.fifthLessonWords.compactMap { byID[$0] }
        let reserved = Set((starter + fifthLesson).map(\.id))
        let catalogOrder = bundled.filter { !reserved.contains($0.id) }
        let middle = max(0, 40 - starter.count)
        let sequence = starter + Array(catalogOrder.prefix(middle)) + fifthLesson + Array(catalogOrder.dropFirst(middle))
        let available = personal + sequence.filter { progress[$0.id] == nil }
        cardsIntroducedToday = introducedTodayCards
        introducedToday = seenToday
        remainingNew = fresh.count
        remainingStarter = fresh.filter { !$0.isPersonal }.count
        let scheduled = active.compactMap { card -> (card: Card, due: Date)? in
            progress[card.id].map { (card, $0.due) }
        }
        let due = scheduled.filter { $0.due <= date }
        let dayStart = calendar.startOfDay(for: date)
        let misses = history.mapValues {
            $0.sorted { $0.date > $1.date }.prefix(5).filter { $0.rating == .again }.count
        }
        let orderedDue = due.sorted { left, right in
            let leftDay = calendar.startOfDay(for: left.due)
            let rightDay = calendar.startOfDay(for: right.due)
            if leftDay != rightDay { return leftDay < rightDay }
            let leftMisses = misses[left.card.id, default: 0]
            let rightMisses = misses[right.card.id, default: 0]
            if leftMisses != rightMisses { return leftMisses > rightMisses }
            let leftStability = progress[left.card.id]?.days ?? 0
            let rightStability = progress[right.card.id]?.days ?? 0
            if leftStability != rightStability { return leftStability < rightStability }
            if left.due != right.due { return left.due < right.due }
            return left.card.id < right.card.id
        }.map(\.card)
        dueCards = orderedDue
        let firstActivity = recalls.lazy.filter { $0.date >= dayStart && $0.date <= date }.map(\.date).min()
        let reviewCutoff = firstActivity ?? date
        let attempted = Set(active.filter { card in
            progress[card.id].map { $0.introduced < dayStart } == true &&
            history[card.id, default: []].contains { $0.date >= dayStart }
        }.map(\.id))
        let unattempted = orderedDue.filter { card in
            !attempted.contains(card.id) && progress[card.id].map {
                $0.introduced < dayStart && $0.due <= reviewCutoff
            } == true
        }
        reviewedToday = attempted.count
        let reviewDemand = unattempted.count + attempted.count
        reviewLimit = max(0, workload.reviewLimit)
        recommendedReviews = Array(unattempted.prefix(max(0, workload.reviewLimit - attempted.count)))
        isRecoveryDay = reviewDemand >= workload.recoveryThreshold
        let target = workload.newWordLimit(for: reviewDemand, preference: goal)
        effectiveGoal = min(target, seenToday + fresh.count)
        newCards = Array(available.prefix(max(0, target - seenToday)))
        estimatedMinutes = workload.estimatedMinutes(new: newCards.count, reviews: recommendedReviews.count)
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
        guard !recommendedReviews.isEmpty || !newCards.isEmpty else { return nil }
        return StudyPlan(cards: recommendedReviews + newCards, newIDs: Set(newCards.map(\.id)))
    }

    func completionPlan(shufflePractice: Bool = false) -> StudyPlan? {
        if !dueCards.isEmpty {
            return StudyPlan(cards: Array(dueCards.prefix(reviewLimit)), newIDs: [])
        }
        return morePracticePlan(shuffle: shufflePractice)
    }

    func morePracticePlan(shuffle: Bool) -> StudyPlan? {
        let difficultIDs = Set(difficultCards.map(\.id))
        let todayIDs = Set(cardsIntroducedToday.map(\.id))
        let today = cardsIntroducedToday.filter { !difficultIDs.contains($0.id) }
        let other = practicedCards.filter { !difficultIDs.contains($0.id) && !todayIDs.contains($0.id) }
        return optionalPlan(for: difficultCards + today + (shuffle ? other.shuffled() : other), shuffle: shuffle)
    }

    var difficultPlan: StudyPlan {
        StudyPlan(cards: difficultCards, newIDs: [], mode: .difficult)
    }

    func optionalPlan(for cards: [Card], limit: Int = 10, shuffle: Bool = false) -> StudyPlan? {
        guard limit > 0 else { return nil }
        let eligible = cards.filter {
            guard let stage = status[$0.id]?.stage else { return false }
            return stage != .new
        }
        guard !eligible.isEmpty else { return nil }
        let selected = Array(eligible.prefix(limit))
        return StudyPlan(cards: shuffle ? selected.shuffled() : selected, newIDs: [], mode: .practice)
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
        // Optional ratings give feedback within the session. Scheduled review
        // events remain the source of difficulty, mastery, and review statistics.
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
            let primary = Card.normalizedMeaning(card.meaningFa)
            guard !key.isEmpty, !primary.isEmpty, !usedHeadwords.contains(key) else { continue }
            var reserved = card.meaningKeys
            for sense in byHeadword[key] ?? [] {
                reserved.formUnion(sense.meaningKeys)
            }
            var distractors: [String] = []
            let alternatives = candidates.filter { $0.id != card.id && headwordKey($0) != key }
            let matchingPart = alternatives.filter { $0.partOfSpeech == card.partOfSpeech }
            let ordered = matchingPart.filter { $0.level == card.level }
                + matchingPart.filter { $0.level != card.level }
                + alternatives.filter { $0.partOfSpeech != card.partOfSpeech }

            for candidate in ordered {
                let keys = candidate.meaningKeys
                guard !Card.normalizedMeaning(candidate.meaningFa).isEmpty,
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


}
