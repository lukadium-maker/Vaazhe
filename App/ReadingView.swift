import SwiftData
import SwiftUI

private enum ReadingRoute: Hashable {
    case passage(String), quiz(String)
}

struct ReadingLibrary: View {
    let stories: [ReadingStory]
    let cards: [String: Card]
    let statuses: [String: VocabularyStatus]
    let dailyStoryID: String?
    let isRevision: Bool
    let now: Date
    @Binding private var positions: [String: Double]

    @Query private var progress: [ReadingProgress]
    @State private var path: [ReadingRoute] = []
    @State private var filter: ReadingFilter = .all
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppClock.self) private var clock

    init(stories: [ReadingStory], cards: [String: Card], statuses: [String: VocabularyStatus],
         dailyStoryID: String?, isRevision: Bool, now: Date,
         initialStoryID: String?, positions: Binding<[String: Double]>) {
        self.stories = stories
        self.cards = cards
        self.statuses = statuses
        self.dailyStoryID = dailyStoryID
        self.isRevision = isRevision
        self.now = now
        _positions = positions
        _path = State(initialValue: initialStoryID.map { [.passage($0)] } ?? [])
    }

    private var records: [String: ReadingRecord] {
        Dictionary(uniqueKeysWithValues: progress.map { ($0.storyID, $0.record) })
    }

    var body: some View {
        let records = records
        NavigationStack(path: $path) {
            Page {
                if let featured = stories.first(where: { $0.id == dailyStoryID }) {
                    let completion = records[featured.id]?.lastCompletion
                    ReadingRecommendationCard(story: featured,
                                              matchingVocabularyCount: featured.targetWordIds.filter {
                                                  statuses[$0].map { $0.stage != .new } == true
                                              }.count,
                                              record: records[featured.id],
                                              hasReadingPosition: (positions[featured.id] ?? 0) > 0,
                                              isRevision: isRevision,
                                              completedToday: completion.map { clock.calendar.isDate($0, inSameDayAs: now) } == true,
                                              inLibrary: true,
                                              start: { path.append(.passage(featured.id)) })
                }

                Picker("فیلتر داستان‌ها", selection: $filter) {
                    ForEach(ReadingFilter.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44, alignment: .leading)

                let filtered = stories.filter { filter.includes($0, record: records[$0.id]) }
                if filtered.isEmpty {
                    ContentUnavailableView("داستانی در این فهرست نیست", systemImage: "book",
                                           description: Text("فیلتر دیگری را انتخاب کن."))
                }
                ForEach(filtered) { story in
                    NavigationLink(value: ReadingRoute.passage(story.id)) {
                        storyRow(story, record: records[story.id])
                    }
                    .buttonStyle(.plain)
                }
            }
            .persianNavigationTitle("داستان‌خوانی")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("بستن") { dismiss() } } }
            .navigationDestination(for: ReadingRoute.self) { route in
                switch route {
                case .passage(let id):
                    if let story = stories.first(where: { $0.id == id }) {
                        ReadingPassageView(story: story, cards: cards, statuses: statuses,
                                           hasRead: records[id]?.read == true,
                                           position: Binding(get: { positions[id, default: 0] },
                                                             set: { positions[id] = $0 })) {
                            path.append(.quiz(id))
                        }
                    }
                case .quiz(let id):
                    if let story = stories.first(where: { $0.id == id }) {
                        ReadingQuizView(story: story, cards: cards, reread: { _ = path.popLast() },
                                        returnToLibrary: { path.removeAll() })
                    }
                }
            }
        }
    }

    private func storyRow(_ story: ReadingStory, record: ReadingRecord?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ReadingLevelLabel(level: story.level)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward").font(.footnote)
                    .foregroundStyle(Palette.sage).accessibilityHidden(true)
            }
            if dynamicTypeSize.isAccessibilitySize {
                ReadingStoryCover(storyID: story.id, width: 92)
                ReadingStoryTitle(story: story)
            } else {
                HStack(spacing: 12) {
                    ReadingStoryTitle(story: story)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    ReadingStoryCover(storyID: story.id, width: 92)
                }
            }
            if let record, record.completed {
                Text("آزمون کامل شد • بهترین امتیاز \(fa(record.bestScore)) از \(fa(story.questions.count))")
                    .font(PersianFont.subheadline).foregroundStyle(Palette.sage)
                ProgressView(value: Double(record.bestScore), total: Double(story.questions.count))
                    .progressViewStyle(StudyProgressStyle())
                    .accessibilityLabel("بهترین نتیجهٔ آزمون")
            } else {
                Text(record?.read == true ? "خوانده‌شده" : "خوانده‌نشده")
                    .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
            }
        }
        .modifier(Panel())
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ReadingRecommendationCard: View {
    let story: ReadingStory
    let matchingVocabularyCount: Int
    let record: ReadingRecord?
    var hasReadingPosition = false
    var isRevision = false
    var completedToday = false
    var inLibrary = false
    let start: () -> Void
    var showLibrary: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var completed: Bool { completedToday }
    private var hasCover: Bool { ReadingCover.assetName(for: story.id) != nil }

    var body: some View {
        if let showLibrary {
            todayCard(showLibrary: showLibrary)
        } else {
            libraryCard
        }
    }

    private func todayCard(showLibrary: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: DashboardMetrics.inline) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DashboardMetrics.inline) {
                    heading.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    completionBadge.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: DashboardMetrics.micro) {
                    heading
                    completionBadge
                }
            }
            if completed && !isRevision {
                Text("فردا با یک داستان تازه برمی‌گردیم.")
                    .font(DashboardFont.metadata).foregroundStyle(Palette.muted)
            }
            if isRevision {
                Text("همهٔ داستان‌ها را خوانده‌ای. این داستان را برای مرور واژه‌ها پیشنهاد می‌کنیم.")
                    .font(DashboardFont.metadata)
                    .foregroundStyle(Palette.sage)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DashboardMetrics.inline) {
                    todayStoryDetails
                    if hasCover {
                        ReadingStoryCover(storyID: story.id, width: 152)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: DashboardMetrics.group) {
                    todayStoryDetails
                    ReadingStoryCover(storyID: story.id, width: hasCover ? 120 : 52)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DashboardMetrics.group) {
                    dailyReadButton
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    libraryButton(showLibrary).fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 0) {
                    dailyReadButton
                    libraryButton(showLibrary)
                }
            }
        }
        .modifier(Panel(padding: DashboardMetrics.group, radius: DashboardMetrics.cardRadius))
    }

    @ViewBuilder private var dailyReadButton: some View {
        if completed {
            Button(actionTitle, action: start)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
        } else {
            Button(actionTitle, action: start).buttonStyle(PrimaryButton(compact: true))
        }
    }

    private var todayStoryDetails: some View {
        VStack(alignment: .leading, spacing: DashboardMetrics.micro) {
            ReadingStoryTitle(story: story, featured: true, dashboard: true)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DashboardMetrics.micro) { todayStoryMetadata }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: DashboardMetrics.micro) { todayStoryMetadata }
            }
            if matchingVocabularyCount > 0 {
                Text("\(fa(matchingVocabularyCount)) واژهٔ آشنا")
                    .font(DashboardFont.metadata)
                    .foregroundStyle(Palette.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var todayStoryMetadata: some View {
        ReadingLevelLabel(level: story.level, compact: true)
            .padding(.horizontal, DashboardMetrics.inline)
            .padding(.vertical, 2)
            .background(Palette.paper, in: Capsule())
        Text("حدود \(fa(story.readingMinutes)) دقیقه")
            .font(DashboardFont.metadata)
            .foregroundStyle(Palette.muted)
    }

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    heading.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    completionBadge.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    heading
                    completionBadge
                }
            }
            if dynamicTypeSize.isAccessibilitySize && hasCover {
                ReadingStoryCover(storyID: story.id, width: 104)
                ReadingStoryTitle(story: story, featured: true)
            } else {
                HStack(spacing: 12) {
                    ReadingStoryTitle(story: story, featured: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    if hasCover {
                        ReadingStoryCover(storyID: story.id, width: 104)
                    } else if inLibrary {
                        ElphyMascotView(mood: .reading, size: dynamicTypeSize.isAccessibilitySize ? 44 : 60,
                                       animatesAppearance: true)
                    } else if !dynamicTypeSize.isAccessibilitySize {
                        ReadingStoryCover(storyID: story.id, width: 56)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { metadata }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { metadata }
            }
            if isRevision {
                Text("همهٔ داستان‌ها را خوانده‌ای. این داستان برای مرور واژه‌هاست.")
                    .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
            }
            Button(actionTitle, action: start)
                .buttonStyle(.plain)
                .foregroundStyle(Palette.sage)
                .frame(minHeight: 44)
        }
        .modifier(Panel(padding: 16))
    }

    private var heading: some View {
        HStack(spacing: 6) {
            Text(isRevision ? "مرور داستان" : "داستان پیشنهادی امروز")
                .font(inLibrary ? HeadingFont.section : DashboardFont.section)
                .accessibilityAddTraits(.isHeader)
            if inLibrary && hasCover {
                ElphyMascotView(mood: .reading, size: 36, animatesAppearance: true)
            }
        }
    }

    @ViewBuilder private var completionBadge: some View {
        if completed {
            Label("آفرین! داستان امروز تکمیل شد.", systemImage: "checkmark.circle")
                .font(inLibrary ? PersianFont.subheadlineEmphasis : DashboardFont.metadata)
                .foregroundStyle(Palette.sage)
        }
    }

    private var actionTitle: String {
        if completed { return "مطالعه دوباره" }
        if isRevision { return "مرور داستان" }
        return ReadingCardAction(record: record, hasReadingPosition: hasReadingPosition).title
    }

    private func libraryButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(completed ? "کشف داستان‌های بیشتر" : "همهٔ داستان‌ها")
                .font(DashboardFont.action)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.sage)
    }

    @ViewBuilder private var metadata: some View {
        ReadingLevelLabel(level: story.level)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.paper, in: Capsule())
        Text(inLibrary ? "\(fa(story.questions.count)) پرسش • حدود \(fa(story.readingMinutes)) دقیقه"
             : "حدود \(fa(story.readingMinutes)) دقیقه")
            .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
        if matchingVocabularyCount > 0 {
            Text("\(fa(matchingVocabularyCount)) واژهٔ آشنا")
                .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
        }
    }
}

private struct ReadingStoryCover: View {
    let storyID: String
    let width: CGFloat

    var body: some View {
        Group {
            if let asset = ReadingCover.assetName(for: storyID) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "book")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Palette.sage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.tint)
            }
        }
        .frame(width: width, height: width * 3 / 4)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

private struct ReadingLevelLabel: View {
    let level: ReadingLevel
    var compact = false

    var body: some View {
        Text(level.rawValue)
            .font((compact ? Font.footnote : .subheadline).monospaced().weight(.semibold))
            .foregroundStyle(Palette.sage)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel("سطح \(level.rawValue)")
    }
}

private struct ReadingStoryTitle: View {
    let story: ReadingStory
    var featured = false
    var dashboard = false

    var body: some View {
        VStack(alignment: .leading, spacing: featured ? 1 : 4) {
            Text(story.titleFa).font(dashboard ? DashboardFont.story : featured ? HeadingFont.title : HeadingFont.section)
            Text(story.titleEn)
                .font(.system(dashboard ? .subheadline : featured ? .body : .title3, design: .serif).weight(.semibold))
                .foregroundStyle(featured ? Palette.muted : Palette.ink)
                .readingEnglish(alignedWithPersian: dashboard)
        }
    }
}

private struct ReadingPassageView: View {
    let story: ReadingStory
    let cards: [String: Card]
    let statuses: [String: VocabularyStatus]
    let hasRead: Bool
    @Binding var position: Double
    let startQuiz: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppClock.self) private var clock
    @AppStorage("voice", store: .standard) private var voice = EnglishAccent.american.rawValue
    @AppStorage("slowPronunciation", store: .standard) private var slowPronunciation = false
    @State private var definition: Card?
    @State private var errorMessage: String?
    @State private var savedRead = false
    @State private var showsTranslation = false

    var body: some View {
        Page(readingPosition: $position) {
            VStack(alignment: .leading, spacing: 8) {
                ReadingLevelLabel(level: story.level)
                ReadingStoryTitle(story: story).accessibilityAddTraits(.isHeader)
            }
            if let cover = ReadingCover.assetName(for: story.id) {
                Image(decorative: cover)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
            }
            HStack(spacing: 12) {
                Button {
                    do throws(PronunciationService.PlaybackError) {
                        try PronunciationService.shared.speak(story.textEn, accent: .preferred(voice),
                                                              slowly: slowPronunciation)
                    } catch {
                        errorMessage = error.message
                    }
                } label: {
                    Label("پخش داستان", systemImage: "speaker.wave.2")
                        .frame(minHeight: 44)
                }
                Button {
                    PronunciationService.shared.stop(ifSpeaking: story.textEn)
                } label: {
                    Image(systemName: "stop.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("توقف پخش داستان")
            }
            .buttonStyle(.plain).foregroundStyle(Palette.sage)

            Text(linkedPassage)
                .font(.system(.title3, design: .serif))
                .lineSpacing(7)
                .textSelection(.enabled)
                .readingEnglish()
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "elphy-word", let id = url.host, let card = cards[id] else { return .discarded }
                    PronunciationService.shared.stop(ifSpeaking: story.textEn)
                    definition = card
                    return .handled
                })
                .modifier(Panel())

            if let translation = story.textFa {
                translationPanel(translation)
            }

            let vocabulary = encounteredCards(in: story, cards: cards)
            if !vocabulary.isEmpty {
                DisclosureGroup("واژه‌های داستان") {
                    ForEach(vocabulary) { card in
                        Button {
                            PronunciationService.shared.stop(ifSpeaking: story.textEn)
                            definition = card
                        } label: {
                            Text(card.word).font(.system(.body, design: .serif))
                                .frame(minHeight: 44)
                                .readingEnglish()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(PersianFont.emphasis).foregroundStyle(Palette.sage)
            }

            Button("شروع آزمون درک مطلب") {
                if recordRead() { startQuiz() }
            }
            .buttonStyle(PrimaryButton())
            if !hasRead && !savedRead {
                Button("علامت‌گذاری به‌عنوان خوانده‌شده") { _ = recordRead() }
                    .buttonStyle(.plain).frame(minHeight: 44).foregroundStyle(Palette.sage)
            }
        }
        .persianNavigationTitle("داستان")
        .onDisappear { PronunciationService.shared.stop(ifSpeaking: story.textEn) }
        .sheet(item: $definition) { card in
            ReadingDefinition(card: card, status: statuses[card.id])
        }
        .readingError($errorMessage)
    }

    private func translationPanel(_ translation: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showsTranslation.toggle()
            } label: {
                HStack(spacing: 10) {
                    Label(showsTranslation ? "پنهان کردن ترجمهٔ فارسی" : "نمایش ترجمهٔ فارسی",
                          systemImage: "character.bubble")
                        .font(PersianFont.emphasis)
                    Spacer(minLength: 8)
                    Image(systemName: showsTranslation ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.sage)

            if showsTranslation {
                Divider().overlay(Palette.border)
                Text(translation)
                    .font(PersianFont.body)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .modifier(Panel(fill: Palette.tint, padding: 12))
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var linkedPassage: AttributedString {
        var text = AttributedString()
        var start = story.textEn.startIndex
        for (range, id) in ReadingVocabulary.matches(in: story) where cards[id] != nil {
            text += AttributedString(String(story.textEn[start..<range.lowerBound]))
            var word = AttributedString(String(story.textEn[range]))
            word.link = URL(string: "elphy-word://\(id)")
            word.foregroundColor = Palette.sage
            word.underlineStyle = .single
            text += word
            start = range.upperBound
        }
        text += AttributedString(String(story.textEn[start...]))
        return text
    }

    private func recordRead() -> Bool {
        do {
            try clock.markRead(story.id, in: context)
            savedRead = true
            return true
        } catch {
            errorMessage = "ثبت وضعیت مطالعه ممکن نشد. دوباره امتحان کن."
            return false
        }
    }
}

private struct ReadingDefinition: View {
    let card: Card
    let status: VocabularyStatus?
    @Environment(\.dismiss) private var dismiss

    private var statusLabel: String? {
        if status?.isDifficult == true { return "نیاز به تمرین بیشتر" }
        return switch status?.stage {
        case .new: "جدید"
        case .learning: "در حال یادگیری"
        case .mastered: "تثبیت‌شده"
        case nil: nil
        }
    }

    var body: some View {
        NavigationStack {
            Page {
                if let statusLabel {
                    Text(statusLabel).font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                }
                CardContent(card: card, revealed: true)
            }
            .persianNavigationTitle("معنی واژه")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("بستن") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ReadingQuizView: View {
    let story: ReadingStory
    let cards: [String: Card]
    let reread: () -> Void
    let returnToLibrary: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppClock.self) private var clock
    @State private var quiz: ReadingQuiz
    @State private var errorMessage: String?

    init(story: ReadingStory, cards: [String: Card], reread: @escaping () -> Void,
         returnToLibrary: @escaping () -> Void) {
        self.story = story
        self.cards = cards
        self.reread = reread
        self.returnToLibrary = returnToLibrary
        _quiz = State(initialValue: ReadingQuiz(questions: story.questions))
    }

    var body: some View {
        Page {
            if let question = quiz.current {
                let index = quiz.index
                Text("پرسش \(fa(index + 1)) از \(fa(quiz.questions.count))")
                    .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                ProgressView(value: Double(index + (quiz.selection == nil ? 0 : 1)),
                             total: Double(quiz.questions.count))
                    .progressViewStyle(StudyProgressStyle())
                    .accessibilityLabel("پیشرفت آزمون درک مطلب")
                Text(question.promptEn).font(.system(.title2, design: .serif).weight(.semibold))
                    .readingEnglish().accessibilityAddTraits(.isHeader)
                ForEach(question.optionsEn.indices, id: \.self) { option in
                    answer(option, question: question, at: index)
                }
                if let selection = quiz.selection {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selection == question.correctIndex ? "درست بود!" : "به توضیح پاسخ نگاه کن.")
                            .font(HeadingFont.section).accessibilityAddTraits(.isHeader)
                        Text(question.explanationFa)
                    }
                    .modifier(Panel(fill: Palette.tint))
                    Button(quiz.isFinalAnswer ? "دیدن نتیجه" : "پرسش بعدی") { advance(from: index) }
                        .buttonStyle(PrimaryButton())
                }
            } else {
                results
            }
        }
        .id(quiz.index)
        .persianNavigationTitle("آزمون درک مطلب")
        .readingError($errorMessage)
    }

    private func answer(_ option: Int, question: ReadingQuestion, at index: Int) -> some View {
        let correct = quiz.selection != nil && option == question.correctIndex
        let incorrect = quiz.selection == option && !correct
        return Button {
            guard quiz.index == index, quiz.selection == nil else { return }
            quiz.select(option)
            (option == question.correctIndex ? TapCue.correct : .retry).play()
        } label: {
            HStack {
                Text(question.optionsEn[option]).font(.system(.body, design: .serif))
                Spacer(minLength: 0)
                if correct || incorrect {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle")
                        .accessibilityHidden(true)
                }
            }
            .readingEnglish()
            .padding(12).frame(minHeight: 48)
            .background(correct ? Palette.tint : Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(quiz.selection != nil)
        .accessibilityValue(correct ? "پاسخ درست" : incorrect ? "پاسخ نادرست" : "")
    }

    private var results: some View {
        let total = story.questions.count
        let percentage = Int((Double(quiz.score) / Double(total) * 100).rounded())
        return VStack(alignment: .leading, spacing: 16) {
            Heading(title: "آفرین! داستان رو تموم کردی.", subtitle: "داستان خوانده شد و آزمون کامل شد.")
            Text("\(fa(quiz.score)) از \(fa(total)) پاسخ درست • \(fa(percentage))٪")
                .font(PersianFont.emphasis)
            let vocabulary = encounteredCards(in: story, cards: cards)
            if !vocabulary.isEmpty {
                Text("واژه‌های داستان").font(HeadingFont.section)
                Text(vocabulary.map(\.word).joined(separator: ", "))
                    .font(.system(.body, design: .serif)).readingEnglish()
            }
            Button("بازگشت به فهرست داستان‌ها", action: returnToLibrary).buttonStyle(PrimaryButton())
            Button("دوباره خواندن داستان", action: reread)
                .buttonStyle(.plain).frame(minHeight: 44)
            Button("تکرار آزمون") { quiz = ReadingQuiz(questions: story.questions) }
                .buttonStyle(.plain).frame(minHeight: 44)
        }
        .modifier(Panel(fill: Palette.tint))
    }

    private func advance(from index: Int) {
        guard quiz.index == index, quiz.selection != nil else { return }
        if quiz.isFinalAnswer {
            do {
                try clock.complete(story, score: quiz.score, in: context)
            } catch {
                errorMessage = "ذخیرهٔ نتیجهٔ آزمون ممکن نشد. دوباره امتحان کن."
                return
            }
        }
        quiz.advance()
    }
}

private func encounteredCards(in story: ReadingStory, cards: [String: Card]) -> [Card] {
    let encountered = Set(ReadingVocabulary.matches(in: story).map(\.id))
    return story.targetWordIds.filter { encountered.contains($0) }.compactMap { cards[$0] }
}

private extension View {
    func readingEnglish(alignedWithPersian: Bool = false) -> some View {
        frame(maxWidth: .infinity, alignment: alignedWithPersian ? .trailing : .leading)
            .multilineTextAlignment(alignedWithPersian ? .trailing : .leading)
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.locale, Locale(identifier: "en_US"))
    }

    func readingError(_ message: Binding<String?>) -> some View {
        alert("داستان‌خوانی", isPresented: Binding(get: { message.wrappedValue != nil },
                                                           set: { if !$0 { message.wrappedValue = nil } })) {
            Button("باشه", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
