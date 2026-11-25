import Foundation

enum ReadingLevel: String, Decodable, CaseIterable {
    case a1 = "A1", a2 = "A2", b1 = "B1"

    var beginnerPriority: Int {
        switch self {
        case .a1: 3
        case .a2: 1
        case .b1: 0
        }
    }
}

struct ReadingQuestion: Decodable, Identifiable {
    let id: String
    let promptEn: String
    let optionsEn: [String]
    let correctIndex: Int
    let explanationFa: String
}

struct ReadingStory: Decodable, Identifiable {
    let id: String
    let titleEn: String
    let titleFa: String
    let level: ReadingLevel
    let targetWords: [String]
    let targetWordIds: [String]
    let textEn: String
    let textFa: String?
    let questions: [ReadingQuestion]

    var readingMinutes: Int {
        max(1, Int(ceil(Double(ReadingVocabulary.tokens(in: textEn).count) / 110)))
    }
}

enum ReadingCover {
    private static let illustratedStoryIDs: Set<String> = [
        "elfy-reading-01", "elfy-reading-02", "elfy-reading-03", "elfy-reading-04", "elfy-reading-05",
        "elfy-reading-06", "elfy-reading-07", "elfy-reading-08", "elfy-reading-09", "elfy-reading-10",
        "elfy-reading-11", "elfy-reading-12", "elfy-reading-13", "elfy-reading-14", "elfy-reading-15",
        "elfy-reading-16", "elfy-reading-17", "elfy-reading-18", "elfy-reading-19", "elfy-reading-20",
        "elfy-reading-21", "elfy-reading-22", "elfy-reading-23", "elfy-reading-24", "elfy-reading-25",
        "elfy-reading-26", "elfy-reading-27", "elfy-reading-28", "elfy-reading-29", "elfy-reading-30"
    ]

    static func assetName(for storyID: String) -> String? {
        illustratedStoryIDs.contains(storyID) ? "story_\(storyID)_cover" : nil
    }
}

struct ReadingContent: Decodable {
    private let stories: [ReadingStory]

    static func load(cards: [Card], from bundle: Bundle = .main) throws -> [ReadingStory] {
        guard let url = bundle.url(forResource: "elfy-reading-stories-20", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url), cards: cards)
    }

    static func decode(_ data: Data, cards: [Card]) throws -> [ReadingStory] {
        let stories = try JSONDecoder().decode(Self.self, from: data).stories
        let wordsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.word.lowercased()) })
        guard !stories.isEmpty, Set(stories.map(\.id)).count == stories.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for story in stories {
            let wordsInPassage = Set(ReadingVocabulary.tokens(in: story.textEn).map { story.textEn[$0].lowercased() })
            guard [story.id, story.titleEn, story.titleFa, story.textEn].allSatisfy(hasText),
                  !story.targetWordIds.isEmpty, Set(story.targetWordIds).count == story.targetWordIds.count,
                  story.targetWordIds.count == story.targetWords.count,
                  zip(story.targetWordIds, story.targetWords).allSatisfy({ id, word in
                      wordsByID[id] == word.lowercased() &&
                          !ReadingVocabulary.forms(for: word).isDisjoint(with: wordsInPassage)
                  }),
                  story.questions.count == 3, Set(story.questions.map(\.id)).count == story.questions.count,
                  story.questions.allSatisfy({ question in
                      question.optionsEn.count == 4 && Set(question.optionsEn).count == 4 &&
                          question.optionsEn.indices.contains(question.correctIndex) &&
                          ([question.id, question.promptEn, question.explanationFa] + question.optionsEn).allSatisfy(hasText)
                  }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        return stories
    }

    private static func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum ReadingVocabulary {
    // Explicit forms are limited to the supplied passages and unambiguous variants
    // of their targets. A token must match a complete form of a target headword.
    private static let aliases: [String: [String]] = [
        "arrive": ["arrives", "arrived"], "leave": ["leaves", "left"],
        "bring": ["brings", "brought"], "open": ["opens"], "close": ["closes"],
        "need": ["needs"], "pay": ["pays", "paid"], "prefer": ["prefers"],
        "serve": ["serves"], "offer": ["offers"], "change": ["changes"],
        "invite": ["invites"], "prepare": ["prepares"], "order": ["orders"],
        "dictionary": ["dictionaries"], "mistake": ["mistakes"], "break": ["breaks", "broke", "broken"],
        "receive": ["receives"], "notice": ["notices"], "respond": ["responds"],
        "consider": ["considers"], "achieve": ["achieved"], "expect": ["expects"],
        "include": ["includes"], "check": ["checks"], "return": ["returns"],
        "recommend": ["recommends"], "tend": ["tends"], "habit": ["habits"],
        "ask": ["asks"], "show": ["shows"], "walk": ["walks"], "pick": ["picks"],
        "throw": ["throws"], "drop": ["drops"], "catch": ["catches"], "fall": ["fallen"],
        "push": ["pushes"], "sit": ["sits"], "student": ["students"], "laugh": ["laughs"]
    ]

    // These editorial targets appear as nouns, while the deck defines the verb.
    private static let nounUses: [String: String] = [
        "elfy-reading-05": "en-help-verb", "elfy-reading-07": "en-taste-verb",
        "elfy-reading-12": "en-repair-verb"
    ]
    private static let wordPattern = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)*")

    static func tokens(in text: String) -> [Range<String.Index>] {
        wordPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
    }

    static func forms(for word: String) -> Set<String> {
        let headword = word.lowercased()
        return Set([headword] + (aliases[headword] ?? []))
    }

    static func matches(in story: ReadingStory) -> [(range: Range<String.Index>, id: String)] {
        var idsByForm: [String: String] = [:]
        for (id, word) in zip(story.targetWordIds, story.targetWords) where id != nounUses[story.id] {
            for form in forms(for: word) {
                idsByForm[form] = id
            }
        }
        return tokens(in: story.textEn).compactMap { range in
            idsByForm[story.textEn[range].lowercased()].map { (range, $0) }
        }
    }
}

struct ReadingRecord {
    let read: Bool
    let bestScore: Int
    let recentScore: Int?
    let attempts: Int
    let lastCompletion: Date?

    var completed: Bool { attempts > 0 }
}

enum ReadingCardAction: Equatable {
    case start, resume, reread

    init(record: ReadingRecord?, hasReadingPosition: Bool) {
        if record?.completed == true {
            self = .reread
        } else if record?.read == true || hasReadingPosition {
            self = .resume
        } else {
            self = .start
        }
    }

    var title: String {
        switch self {
        case .start: "شروع مطالعه"
        case .resume: "ادامهٔ مطالعه"
        case .reread: "مطالعهٔ دوباره"
        }
    }
}

struct ReadingDay: Equatable {
    let key: String

    init(at date: Date, calendar: Calendar) {
        let day = calendar.dateComponents([.era, .year, .month, .day], from: date)
        key = "\(calendar.identifier):\(day.era ?? 0):\(day.year ?? 0):\(day.month ?? 0):\(day.day ?? 0):\(day.isLeapMonth == true)"
    }
}

enum ReadingFilter: CaseIterable {
    case all, a1, a2, b1, read

    var label: String {
        switch self {
        case .all: "همه"
        case .a1: ReadingLevel.a1.rawValue
        case .a2: ReadingLevel.a2.rawValue
        case .b1: ReadingLevel.b1.rawValue
        case .read: "خوانده‌شده‌ها"
        }
    }

    func includes(_ story: ReadingStory, record: ReadingRecord?) -> Bool {
        switch self {
        case .all: true
        case .a1: story.level == .a1
        case .a2: story.level == .a2
        case .b1: story.level == .b1
        case .read: record?.read == true
        }
    }
}

enum ReadingRecommendationEngine {
    struct Recommendation {
        let storyID: String
        let matchingVocabularyIDs: [String]
        let score: Int

        var explanation: String {
            matchingVocabularyIDs.isEmpty
                ? "یک داستان برای شروع، بدون نیاز به تمرین قبلی."
                : "این داستان واژه‌هایی دارد که قبلاً تمرین کرده‌ای."
        }
    }

    static func recommend(stories: [ReadingStory], statuses: [String: VocabularyStatus],
                          progress: [String: StudyPlanner.Progress], recalls: [Recall],
                          records: [String: ReadingRecord], at now: Date,
                          calendar: Calendar = .current, previousStoryID: String? = nil) -> Recommendation? {
        let recentCutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let recentIDs = Set(recalls.filter { (recentCutoff...now).contains($0.date) }.map(\.cardID))
            .union(progress.filter { (recentCutoff...now).contains($0.value.introduced) }.keys)

        let vocabularySize = progress.values.filter { $0.introduced <= now }.count
        let targetLevel: ReadingLevel = vocabularySize >= 90 ? .b1 : vocabularySize >= 40 ? .a2 : .a1
        let allCompleted = !stories.isEmpty && stories.allSatisfy {
            let record = records[$0.id]
            return record?.completed == true && record?.lastCompletion.map { $0 <= now } != false
        }
        let scored = stories.map { story in
            let matches = story.targetWordIds.filter { progress[$0].map { $0.introduced <= now } == true }
            let vocabularyScore = matches.reduce(0) { score, id in
                let status = statuses[id]
                return score + (status?.stage == .mastered ? 1 : 3) +
                    (status?.isDifficult == true ? (allCompleted ? 12 : 5) : 0) + (recentIDs.contains(id) ? 4 : 0)
            }
            let record = records[story.id]
            let recentlyCompleted = record?.lastCompletion.map { (recentCutoff...now).contains($0) } ?? false
            let penalty = (record?.read == true ? 2 : 0) + (record?.completed == true ? 1 : 0)
                + (recentlyCompleted ? 5 : 0)
            let recommendation = Recommendation(storyID: story.id, matchingVocabularyIDs: matches,
                                                score: vocabularyScore + (story.level == targetLevel ? 4 : 0) +
                                                    (targetLevel == .a1 ? story.level.beginnerPriority : 0) - penalty)
            return (story: story, result: recommendation)
        }
        let unfinished = scored.filter {
            let record = records[$0.story.id]
            return record?.completed != true || record?.lastCompletion.map { $0 > now } == true
        }
        let suitable = unfinished.isEmpty ? scored : unfinished
        let otherStories = suitable.filter { $0.story.id != previousStoryID }
        let pool = otherStories.isEmpty ? suitable : otherStories
        return pool.sorted { left, right in
            if left.result.score != right.result.score { return left.result.score > right.result.score }
            let leftDate = records[left.story.id]?.lastCompletion ?? .distantPast
            let rightDate = records[right.story.id]?.lastCompletion ?? .distantPast
            if leftDate != rightDate { return leftDate < rightDate }
            return left.story.id < right.story.id
        }.first?.result
    }
}

struct ReadingQuiz {
    let questions: [ReadingQuestion]
    private(set) var index = 0
    private(set) var selection: Int?
    private(set) var score = 0

    var current: ReadingQuestion? { questions.indices.contains(index) ? questions[index] : nil }
    var isFinalAnswer: Bool { index == questions.count - 1 && selection != nil }

    mutating func select(_ option: Int) {
        guard selection == nil, let current, current.optionsEn.indices.contains(option) else { return }
        selection = option
        if option == current.correctIndex { score += 1 }
    }

    mutating func advance() {
        guard selection != nil else { return }
        index += 1
        selection = nil
    }
}
