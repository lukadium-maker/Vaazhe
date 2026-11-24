import Foundation

enum PracticeGame: String, CaseIterable, Identifiable, Codable {
    case matching, sentence, builder
    var id: Self { self }
    var title: String {
        switch self {
        case .matching: "جفت واژه‌ها"
        case .sentence: "جمله را کامل کن"
        case .builder: "واژه‌ساز"
        }
    }
    var icon: String {
        switch self {
        case .matching: "rectangle.on.rectangle"
        case .sentence: "text.insert"
        case .builder: "textformat.abc"
        }
    }
    var description: String {
        switch self {
        case .matching: "هر واژهٔ انگلیسی را به معنی فارسی‌اش وصل کن."
        case .sentence: "واژه‌ای را پیدا کن که جمله را کامل می‌کند."
        case .builder: "با حروف درهم، املای واژه را از روی معنی بساز."
        }
    }
    var duration: String {
        switch self {
        case .matching: "۱ تا ۲ دقیقه"
        case .sentence: "۲ تا ۴ دقیقه"
        case .builder: "۲ تا ۵ دقیقه"
        }
    }
}

enum PracticeMode: String, CaseIterable, Identifiable {
    case quick, standard, weak, endless
    var id: Self { self }
    var title: String {
        switch self {
        case .quick: "تمرین سریع"
        case .standard: "تمرین معمولی"
        case .weak: "تمرین واژه‌های دشوار"
        case .endless: "تمرین آزاد"
        }
    }
}

enum PracticeDifficulty: Int, CaseIterable, Identifiable {
    case easy, medium, hard
    var id: Self { self }
    var title: String {
        switch self {
        case .easy: "آسان"
        case .medium: "متوسط"
        case .hard: "دشوار"
        }
    }
}

struct PracticeAnswer: Codable, Equatable {
    let cardID: String
    let correct: Bool
    let attempts: Int
    let hints: Int

    var firstAttempt: Bool { correct && attempts == 1 }
    var independent: Bool { firstAttempt && hints == 0 }
}

struct PracticeResult: Identifiable, Codable {
    let id: UUID
    let game: PracticeGame
    let date: Date
    let seconds: Int
    let answers: [PracticeAnswer]

    var correct: Int { answers.filter(\.correct).count }
    var mistakes: Int { answers.reduce(0) { $0 + $1.attempts - ($1.correct ? 1 : 0) } }
    var hints: Int { answers.reduce(0) { $0 + $1.hints } }
    var firstAttempt: Int { answers.filter(\.firstAttempt).count }
    var independent: Int { answers.filter(\.independent).count }
    var challengingIDs: [String] { answers.filter { !$0.independent }.map(\.cardID) }
    var accuracy: Int {
        guard !answers.isEmpty else { return 0 }
        if game == .matching { return 100 * correct / max(1, correct + mistakes) }
        return 100 * firstAttempt / answers.count
    }

    func beats(_ other: Self) -> Bool {
        if game == .builder, independent * other.answers.count != other.independent * answers.count {
            return independent * other.answers.count > other.independent * answers.count
        }
        if accuracy != other.accuracy { return accuracy > other.accuracy }
        if answers.count != other.answers.count { return answers.count > other.answers.count }
        return game == .matching && seconds < other.seconds
    }
}

struct PracticeStatistics {
    let results: [PracticeResult]
    var questions: Int { results.reduce(0) { $0 + $1.answers.count } }
    var correct: Int { results.reduce(0) { $0 + $1.correct } }
    var firstAttemptAccuracy: Int { 100 * results.reduce(0) { $0 + $1.firstAttempt } / max(1, questions) }
    var best: PracticeResult? { results.reduce(nil) { best, result in
        guard let best else { return result }
        return result.beats(best) ? result : best
    } }
    var mostMissed: [String] {
        var misses: [String: Int] = [:]
        for answer in results.flatMap(\.answers) {
            let count = answer.attempts - (answer.correct ? 1 : 0)
            if count > 0 { misses[answer.cardID, default: 0] += count }
        }
        return misses.keys.sorted {
            if misses[$0] == misses[$1] { return $0 < $1 }
            return misses[$0, default: 0] > misses[$1, default: 0]
        }
    }
}

struct PracticeQuestion {
    let card: Card
    let blank: String
    let answer: String
    let options: [String]
}

struct PracticeEngine {
    let cards: [Card]
    let progress: [String: StudyPlanner.Progress]
    let difficult: Set<String>
    let history: [PracticeResult]
    let date: Date
    let calendar: Calendar

    var encountered: [Card] { cards.filter { progress[$0.id].map { $0.introduced <= date } == true } }

    func ranked(for game: PracticeGame, mode: PracticeMode, difficulty: PracticeDifficulty,
                using random: inout some RandomNumberGenerator) -> [Card] {
        let recent = history.filter { $0.game == game && $0.date <= date }.prefix(2)
        let repetition = Dictionary(grouping: recent.flatMap(\.answers), by: \.cardID).mapValues(\.count)
        let evidence = Dictionary(grouping: history.filter { $0.date <= date }.prefix(24).flatMap { result in
            result.answers.map { (game: result.game, answer: $0) }
        }, by: { $0.answer.cardID })
        let cutoff = calendar.date(byAdding: .day, value: -7, to: date) ?? date
        let scored = encountered.shuffled(using: &random).map { card -> (Card, Int) in
            let logs = evidence[card.id] ?? []
            let weakness = logs.reduce(0) { sum, entry in
                let weight = entry.game == game ? 2 : 1
                return sum + (entry.answer.independent ? -weight : weight)
            }
            let due = progress[card.id].map { $0.due <= date } ?? false
            let learnedRecently = progress[card.id].map { $0.introduced >= cutoff } ?? false
            let challenge: Int
            if game == .builder {
                let length = card.word.count
                switch difficulty {
                case .easy: challenge = length <= 5 ? 4 : 0
                case .medium: challenge = (5...8).contains(length) ? 4 : 0
                case .hard: challenge = length >= 7 ? 6 : 0
                }
            } else {
                switch difficulty {
                case .easy: challenge = card.word.count <= 6 ? 3 : 0
                case .medium: challenge = card.level.hasPrefix("A2") ? 3 : 0
                case .hard: challenge = difficult.contains(card.id) || card.level.hasPrefix("B") ? 5 : 0
                }
            }
            let stability = progress[card.id]?.streak ?? 0
            let priority = max(-3, min(5, weakness)) + (difficult.contains(card.id) ? 4 : 0) +
                (due ? 2 : 0) + (stability <= 1 ? 2 : 0)
            return (card, priority * (mode == .weak ? 2 : 1) + challenge + (learnedRecently ? 1 : 0)
                    - 7 * repetition[card.id, default: 0])
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    func round(for game: PracticeGame, mode: PracticeMode, difficulty: PracticeDifficulty,
               using random: inout some RandomNumberGenerator) -> [PracticeQuestion] {
        let ranked = ranked(for: game, mode: mode, difficulty: difficulty, using: &random)
        let count = mode == .quick || game == .matching ? 5 : 10
        var words = Set<String>()
        var meanings = Set<String>()
        var questions: [PracticeQuestion] = []
        for card in ranked {
            let word = card.word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let translations = Set(([card.meaningFa] + card.alternativeMeaningsFa).map(Self.normalizedMeaning))
            guard !words.contains(word), !Self.normalizedMeaning(card.meaningFa).isEmpty else { continue }
            let question: PracticeQuestion
            switch game {
            case .matching:
                guard meanings.isDisjoint(with: translations) else { continue }
                question = PracticeQuestion(card: card, blank: "", answer: word, options: [])
            case .sentence:
                guard let validated = PracticeCloze.question(for: card, using: &random) else { continue }
                question = validated
            case .builder:
                guard (3...14).contains(word.count), word.utf8.allSatisfy({ (97...122).contains($0) }),
                      meanings.isDisjoint(with: translations) else { continue }
                // A Persian clue shared by two known spellings cannot uniquely identify either.
                guard !encountered.contains(where: {
                    $0.id != card.id && $0.word.lowercased() != word &&
                    !translations.isDisjoint(with: ([ $0.meaningFa ] + $0.alternativeMeaningsFa).map(Self.normalizedMeaning))
                }) else { continue }
                question = PracticeQuestion(card: card, blank: PracticeCloze.blank(for: card) ?? "", answer: word, options: [])
            }
            words.insert(word)
            meanings.formUnion(translations)
            questions.append(question)
            if questions.count == count { break }
        }
        return questions
    }

    static func normalizedMeaning(_ text: String) -> String {
        text.replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
            .replacingOccurrences(of: "\u{200c}", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}

struct PracticeTiles {
    struct Tile: Identifiable {
        let id: Int
        let letter: Character
    }
    let answer: String
    private(set) var tiles: [Tile]
    private(set) var placed: [Int] = []

    init(answer: String, difficulty: PracticeDifficulty, using random: inout some RandomNumberGenerator) {
        self.answer = answer
        var letters = Array(answer)
        if difficulty == .hard {
            letters += Array("aeiostrln".filter { !answer.contains($0) }.shuffled(using: &random).prefix(2))
        }
        tiles = letters.enumerated().map { Tile(id: $0.offset, letter: $0.element) }.shuffled(using: &random)
    }

    var value: String { String(placed.compactMap { id in tiles.first { $0.id == id }?.letter }) }
    var full: Bool { placed.count == answer.count }
    mutating func tap(_ id: Int) {
        guard !full, tiles.contains(where: { $0.id == id }), !placed.contains(id) else { return }
        placed.append(id)
    }
    mutating func remove(at index: Int) {
        if placed.indices.contains(index) { placed.remove(at: index) }
    }
    mutating func clear() { placed.removeAll() }
    mutating func shuffle(using random: inout some RandomNumberGenerator) { tiles.shuffle(using: &random) }

    @discardableResult mutating func reveal(first: Bool) -> Bool {
        let target = Array(answer)
        let prefix = zip(value, target).prefix { $0 == $1 }.count
        let index = first ? 0 : prefix
        guard index < target.count, !first || prefix == 0 else { return false }
        placed = Array(placed.prefix(index))
        guard let tile = tiles.first(where: { $0.letter == target[index] && !placed.contains($0.id) }) else { return false }
        tap(tile.id)
        return true
    }
}

struct PracticeMatchingRound {
    let questions: [PracticeQuestion]
    let meanings: [Int]
    private(set) var selected: Int?
    private(set) var matched: Set<Int> = []
    private var attempts: [Int: Int] = [:]

    init(questions: [PracticeQuestion], using random: inout some RandomNumberGenerator) {
        self.questions = questions.shuffled(using: &random)
        meanings = Array(questions.indices).shuffled(using: &random)
    }

    var completedAnswers: [PracticeAnswer]? {
        guard !questions.isEmpty, matched.count == questions.count else { return nil }
        return questions.indices.map {
            PracticeAnswer(cardID: questions[$0].card.id, correct: true, attempts: attempts[$0, default: 1], hints: 0)
        }
    }

    mutating func select(_ word: Int) {
        guard questions.indices.contains(word), !matched.contains(word) else { return }
        selected = word
    }

    mutating func answer(_ meaning: Int) -> Bool? {
        guard let selected, questions.indices.contains(meaning), !matched.contains(meaning) else { return nil }
        attempts[selected, default: 0] += 1
        guard selected == meaning else { return false }
        matched.insert(meaning)
        self.selected = nil
        return true
    }
}
