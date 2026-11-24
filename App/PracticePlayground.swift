import SwiftUI
import SwiftData

struct PracticePlayground: View {
    let cards: [Card]
    let progress: [String: StudyPlanner.Progress]
    let difficult: Set<String>
    let container: ModelContainer

    @Environment(AppClock.self) private var clock
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PracticeMode = .standard
    @State private var showsModes = false
    @State private var difficulty: PracticeDifficulty = .easy
    @State private var history: [PracticeResult] = []
    @State private var game: PracticeGame?
    @State private var storageError = false

    private var engine: PracticeEngine {
        PracticeEngine(cards: cards, progress: progress, difficult: difficult, history: history,
                       date: clock.now, calendar: clock.calendar)
    }

    var body: some View {
        NavigationStack {
            Page {
                HStack(spacing: 12) {
                    Heading(title: "زمین بازی واژه‌ها", subtitle: "واژه‌هایی را که یاد گرفتی با بازی‌های کوتاه تمرین کن.")
                    ElphyMascotView(mood: .encouraging, size: 58)
                }
                practiceControls
                if engine.encountered.isEmpty {
                    ContentUnavailableView("هنوز واژه‌ای برای بازی نداری", systemImage: "character.book.closed",
                                           description: Text("چند واژه را در بخش امروز تمرین کن و بعد برگرد."))
                }
                ForEach(PracticeGame.allCases) { game in
                    gameCard(game)
                }
                if storageError {
                    Text("آمار تمرین در دسترس نیست.").foregroundStyle(Palette.muted)
                }
            }
            .persianNavigationTitle("زمین بازی واژه‌ها")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("بستن") { dismiss() } } }
            .sheet(isPresented: $showsModes) { modeChoices }
            .fullScreenCover(item: $game) { game in
                PracticeGameView(game: game, mode: mode, difficulty: difficulty, makeRound: {
                    var random = SystemRandomNumberGenerator()
                    return engine.round(for: game, mode: mode, difficulty: difficulty, using: &random)
                }, personalBest: {
                    PracticeStatistics(results: history.filter { $0.game == game && $0.date <= clock.now }).best
                }, save: save, vocabulary: vocabulary)
            }
        }
        .onAppear { reload() }
    }

    private var practiceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showsModes = true
            } label: {
                HStack(spacing: 8) {
                    Label("نوع تمرین", systemImage: "slider.horizontal.3")
                        .foregroundStyle(Palette.muted)
                    Spacer(minLength: 8)
                    Text(mode.title).font(PersianFont.emphasis)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Palette.sage)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("نوع تمرین")
            .accessibilityValue(mode.title)

            VStack(alignment: .leading, spacing: 6) {
                Text("سختی").font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        difficultyOptions
                    }
                    VStack(spacing: 4) {
                        difficultyOptions
                    }
                }
                .padding(4)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("سختی")
        }
    }

    private var difficultyOptions: some View {
        ForEach(PracticeDifficulty.allCases) { option in
            let selected = option == difficulty
            Button {
                difficulty = option
            } label: {
                HStack(spacing: 5) {
                    if selected {
                        Image(systemName: "checkmark").font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    Text(option.title)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? Palette.buttonText : Palette.ink)
                .background(selected ? Palette.sage : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private var modeChoices: some View {
        NavigationStack {
            Page {
                VStack(spacing: 4) {
                    ForEach(PracticeMode.allCases) { option in
                        Button {
                            mode = option
                            showsModes = false
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title).font(PersianFont.emphasis)
                                    Text(modeDescription(option)).font(PersianFont.subheadline)
                                        .foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                if option == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Palette.sage)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.vertical, 8)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == mode ? .isSelected : [])
                    }
                }
                .modifier(Panel())
            }
            .persianNavigationTitle("نوع تمرین")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("بستن") { showsModes = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func modeDescription(_ option: PracticeMode) -> String {
        switch option {
        case .quick: "یک دور کوتاه، تا ۵ واژه."
        case .standard: "یک دور کامل با تعداد معمول پرسش‌های هر بازی."
        case .weak: "با واژه‌هایی شروع کن که بیشتر به تمرین نیاز دارند."
        case .endless: "هر چند دور که خواستی ادامه بده."
        }
    }

    private func vocabulary(_ id: String) -> String { cards.first { $0.id == id }?.word ?? id }

    private func reload() {
        do { history = try PracticeStore.results(in: container.mainContext) }
        catch { storageError = true }
    }

    private func save(_ result: PracticeResult) throws {
        try PracticeStore.save(result, in: container.mainContext)
        reload()
    }

    private func gameCard(_ game: PracticeGame) -> some View {
        var random = SystemRandomNumberGenerator()
        let available = !engine.round(for: game, mode: mode, difficulty: difficulty, using: &random).isEmpty
        let stats = PracticeStatistics(results: history.filter { $0.game == game && $0.date <= clock.now })
        return VStack(alignment: .leading, spacing: 10) {
            Label(game.title, systemImage: game.icon)
                .font(HeadingFont.section)
                .foregroundStyle(Palette.sage)
                .accessibilityAddTraits(.isHeader)
            Text(game.description)
            Text("\(game.duration) · \(difficulty.title)")
                .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
            if let best = stats.best {
                Text("بهترین نتیجه: \(fa(best.accuracy))٪")
                NavigationLink("آمار و فعالیت اخیر") {
                    statistics(game, stats: stats)
                }
                .frame(minHeight: 44)
            }
            if available {
                Button("شروع بازی") { self.game = game }
                    .buttonStyle(PrimaryButton())
                    .accessibilityLabel("شروع بازی \(game.title)")
            } else {
                Text("برای این بازی هنوز واژهٔ مناسبی نداری. یکی از بازی‌های دیگر را امتحان کن.")
                    .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
            }
        }
        .modifier(Panel(fill: game == .matching ? Palette.tint : Palette.card))
    }

    private func statistics(_ game: PracticeGame, stats: PracticeStatistics) -> some View {
        Page {
            Heading(title: game.title, subtitle: "آمار بازی")
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("دورهای کامل‌شده", value: fa(stats.results.count))
                LabeledContent("پرسش‌ها", value: fa(stats.questions))
                LabeledContent("پاسخ‌های درست", value: fa(stats.correct))
                LabeledContent("درستی در تلاش اول", value: "\(fa(stats.firstAttemptAccuracy))٪")
                if let best = stats.best {
                    LabeledContent("بهترین نتیجه", value: "\(fa(best.accuracy))٪")
                }
            }
            .modifier(Panel())
            if !stats.mostMissed.isEmpty {
                Text("واژه‌های نیازمند تمرین").font(HeadingFont.section)
                Text(stats.mostMissed.prefix(10).map(vocabulary).joined(separator: ", ")).practiceEnglish()
            }
            Text("فعالیت اخیر").font(HeadingFont.section)
            ForEach(stats.results.prefix(8)) { result in
                LabeledContent {
                    Text("\(fa(result.accuracy))٪")
                } label: {
                    Text(result.date.formatted(.dateTime.day().month().year()))
                }
                .modifier(Panel())
            }
        }
        .persianNavigationTitle("آمار بازی")
    }
}

struct PracticeGameView: View {
    let game: PracticeGame
    let mode: PracticeMode
    let difficulty: PracticeDifficulty
    let makeRound: () -> [PracticeQuestion]
    let personalBest: () -> PracticeResult?
    let save: (PracticeResult) throws -> Void
    let vocabulary: (String) -> String

    @Environment(AppClock.self) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var round: [PracticeQuestion] = []
    @State private var matchingRound: PracticeMatchingRound?
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var answers: [PracticeAnswer] = []
    @State private var index = 0
    @State private var selectedOption: String?
    @State private var tiles: PracticeTiles?
    @State private var attempts = 0
    @State private var hints = 0
    @State private var showsExample = false
    @State private var feedback: Bool?
    @State private var feedbackCount = 0
    @State private var result: PracticeResult?
    @State private var best: PracticeResult?
    @State private var newBest = false
    @State private var saveFailed = false
    @State private var confirmingExit = false
    @State private var started = ContinuousClock.now
    @State private var roundNumber = 0
    #if DEBUG
    @State private var startedIn: UUID?
    #endif

    var body: some View {
        NavigationStack {
            Page {
                if let result {
                    summary(result)
                } else if round.isEmpty {
                    ContentUnavailableView("واژه‌ای برای این دور پیدا نشد", systemImage: game.icon)
                } else {
                    if mode == .endless {
                        Text("دور \(fa(roundNumber)) · \(mode.title)")
                            .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                    }
                    if showsIntroduction {
                        HStack(spacing: 10) {
                            ElphyMascotView(mood: .thinking, size: 36)
                            Text(game.description).font(PersianFont.subheadline)
                        }
                    }
                    let completed = game == .matching ? matchingRound?.matched.count ?? 0 : index
                    ProgressView(value: Double(completed), total: Double(round.count))
                        .accessibilityLabel("پیشرفت دور")
                        .accessibilityValue("\(fa(completed)) از \(fa(round.count))")
                    switch game {
                    case .matching:
                        if let matchingRound { matching(matchingRound) }
                    case .sentence: sentence(round[index])
                    case .builder: builder(round[index])
                    }
                }
            }
            .persianNavigationTitle(game.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("خروج") {
                        if result != nil || round.isEmpty { dismiss() }
                        else { confirmingExit = true }
                    }
                }
            }
            .confirmationDialog("از این دور خارج می‌شی؟", isPresented: $confirmingExit, titleVisibility: .visible) {
                Button("خروج از بازی", role: .destructive) { dismiss() }
                Button("ادامهٔ بازی", role: .cancel) {}
            } message: {
                Text("فقط دورهای کامل‌شده در آمار بازی ثبت می‌شوند.")
            }
            .sensoryFeedback(trigger: feedbackCount) { _, _ in
                feedback == true ? .success : .warning
            }
        }
        .task { if roundNumber == 0 { restart() } }
    }

    private var showsIntroduction: Bool {
        (matchingRound?.matched.isEmpty ?? true) && matchingRound?.selected == nil &&
        index == 0 && answers.isEmpty && attempts == 0 && tiles?.placed.isEmpty != false
    }

    private func matching(_ state: PracticeMatchingRound) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("اول واژهٔ انگلیسی، بعد معنی فارسی را بزن.").font(PersianFont.body)
            if dynamicType.isAccessibilitySize {
                VStack(spacing: 12) {
                    wordColumn(state)
                    meaningColumn(state)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        wordColumn(state).frame(minWidth: 116)
                        meaningColumn(state).frame(minWidth: 142)
                    }
                    VStack(spacing: 12) {
                        wordColumn(state)
                        meaningColumn(state)
                    }
                }
            }
            feedbackLabel
        }
        .modifier(Panel())
    }

    private func wordColumn(_ state: PracticeMatchingRound) -> some View {
        VStack(spacing: 6) {
            ForEach(state.questions.indices, id: \.self) { i in
                Button {
                    matchingRound?.select(i)
                    feedback = nil
                } label: {
                    matchingLabel(state.questions[i].card.word, done: state.matched.contains(i),
                                  selected: state.selected == i)
                        .practiceEnglish()
                }
                .buttonStyle(.plain)
                .disabled(state.matched.contains(i))
                .accessibilityAddTraits(state.selected == i ? .isSelected : [])
            }
        }
    }

    private func meaningColumn(_ state: PracticeMatchingRound) -> some View {
        VStack(spacing: 6) {
            ForEach(state.meanings, id: \.self) { i in
                Button {
                    var correct: Bool?
                    animate { correct = matchingRound?.answer(i) }
                    guard let correct else { return }
                    signal(correct)
                    if let completed = matchingRound?.completedAnswers {
                        answers = completed
                        finish()
                    }
                } label: {
                    matchingLabel(state.questions[i].card.meaningFa, done: state.matched.contains(i), selected: false)
                }
                .buttonStyle(.plain)
                .disabled(state.matched.contains(i) || state.selected == nil)
            }
        }
    }

    private func matchingLabel(_ text: String, done: Bool, selected: Bool) -> some View {
        HStack {
            Text(text).fixedSize(horizontal: false, vertical: true)
            if done || selected {
                Image(systemName: done ? "checkmark.circle.fill" : "circle.inset.filled")
                    .accessibilityLabel(done ? "جفت شده" : "انتخاب‌شده")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(done || selected ? Palette.tint : Palette.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Palette.sage : Palette.border) }
    }

    private func sentence(_ question: PracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedOption == nil ? question.blank : question.card.exampleEn)
                .font(.title3).practiceEnglish()
            ForEach(question.options, id: \.self) { option in
                Button {
                    guard selectedOption == nil else { return }
                    selectedOption = option
                    let correct = option == question.answer
                    answers.append(PracticeAnswer(cardID: question.card.id, correct: correct, attempts: 1, hints: 0))
                    signal(correct)
                } label: {
                    HStack {
                        Text(option)
                        Spacer()
                        if selectedOption != nil && (option == question.answer || option == selectedOption) {
                            Image(systemName: option == question.answer ? "checkmark.circle.fill" : "xmark.circle")
                                .accessibilityLabel(option == question.answer ? "پاسخ درست" : "پاسخ نادرست")
                        }
                    }
                    .padding(.horizontal)
                    .frame(minHeight: 48)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
                    .practiceEnglish()
                }
                .buttonStyle(.plain)
                .disabled(selectedOption != nil)
            }
            if selectedOption != nil {
                feedbackLabel
                Text("پاسخ درست: \(question.answer)")
                Text(question.card.meaningFa)
                if !question.card.exampleFa.isEmpty { Text(question.card.exampleFa).foregroundStyle(Palette.muted) }
                Button(nextTitle) { next() }.buttonStyle(PrimaryButton())
            }
        }
        .modifier(Panel())
    }

    private func builder(_ question: PracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.card.meaningFa).font(HeadingFont.section)
            if let tiles {
                let columns = [GridItem(.adaptive(minimum: 48), spacing: 6)]
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(0..<question.answer.count, id: \.self) { position in
                        let letters = Array(tiles.value)
                        let letter = letters.indices.contains(position) ? String(letters[position]).uppercased() : ""
                        Button { animate { self.tiles?.remove(at: position) } } label: {
                            tileFace(letter.isEmpty ? "＿" : letter)
                        }
                        .buttonStyle(.plain)
                        .disabled(letter.isEmpty || feedback == true || selectedOption != nil)
                        .accessibilityLabel(letter.isEmpty ? "خانهٔ خالی \(fa(position + 1))" : "برداشتن حرف \(letter)")
                    }
                }
                .practiceEnglish()
                Divider()
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(tiles.tiles) { tile in
                        let used = tiles.placed.contains(tile.id)
                        Button { animate { self.tiles?.tap(tile.id) } } label: {
                            tileFace(String(tile.letter).uppercased()).opacity(used ? 0.3 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(used || tiles.full || feedback == true || selectedOption != nil)
                    }
                }
                .practiceEnglish()
                if feedback != true && selectedOption == nil {
                    ViewThatFits(in: .horizontal) {
                        HStack { builderActions(question, tiles: tiles) }
                        VStack(alignment: .leading) { builderActions(question, tiles: tiles) }
                    }
                    if showsExample { Text(question.blank).practiceEnglish() }
                    feedbackLabel
                    Button("بررسی واژه") { submitSpelling(question) }
                        .buttonStyle(PrimaryButton())
                        .disabled(!tiles.full)
                    Button("نمایش پاسخ و ادامه") {
                        answers.append(PracticeAnswer(cardID: question.card.id, correct: false,
                                                      attempts: max(1, attempts), hints: hints))
                        selectedOption = question.answer
                        signal(false)
                    }
                    .disabled(selectedOption != nil)
                    .frame(minHeight: 44)
                }
                if feedback == true || selectedOption != nil {
                    if feedback == true { feedbackLabel }
                    Text(question.answer).font(.title3).practiceEnglish()
                    Button(nextTitle) { next() }.buttonStyle(PrimaryButton())
                }
            }
        }
        .modifier(Panel())
    }

    @ViewBuilder private func builderActions(_ question: PracticeQuestion, tiles: PracticeTiles) -> some View {
        Button { animate { self.tiles?.remove(at: tiles.placed.count - 1) } } label: {
            Text("واگرد").frame(minHeight: 44)
        }
            .disabled(tiles.placed.isEmpty || selectedOption != nil)
        Button { animate { self.tiles?.clear() } } label: {
            Text("پاک کردن").frame(minHeight: 44)
        }
            .disabled(tiles.placed.isEmpty || selectedOption != nil)
        Button {
            var random = SystemRandomNumberGenerator()
            animate { self.tiles?.shuffle(using: &random) }
        } label: {
            Text("بر زدن").frame(minHeight: 44)
        }
        .disabled(selectedOption != nil)
        Menu("راهنما") {
            Button("حرف اول") { reveal(first: true) }
            Button("حرف بعدی") { reveal(first: false) }
            if !question.blank.isEmpty {
                Button("جملهٔ نمونه") {
                    if !showsExample { hints += 1; showsExample = true }
                }
                .disabled(showsExample)
            }
        }
        .disabled(selectedOption != nil)
    }

    private func tileFace(_ letter: String) -> some View {
        Text(letter).font(.system(.title3, design: .monospaced, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.border) }
    }

    @ViewBuilder private var feedbackLabel: some View {
        if let feedback {
            Label(feedback ? "آفرین! درست بود." : "این بار درست نبود.", systemImage: feedback ? "checkmark.circle.fill" : "xmark.circle")
                .font(PersianFont.emphasis)
                .foregroundStyle(feedback ? Palette.sage : Palette.muted)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var nextTitle: String { index + 1 == round.count ? "دیدن نتیجه" : "ادامه" }

    private func summary(_ result: PracticeResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ElphyMascotView(mood: newBest ? .celebrating : .encouraging, size: 76)
            Text(newBest ? "بهترین نتیجه‌ات رو بهتر کردی!" : "آفرین! این دور تموم شد.")
                .font(HeadingFont.section)
            LabeledContent("پاسخ درست", value: "\(fa(result.correct)) از \(fa(result.answers.count))")
            LabeledContent("اشتباه‌ها", value: fa(result.mistakes))
            LabeledContent(game == .matching ? "درستی پاسخ‌ها" : "درستی در تلاش اول", value: "\(fa(result.accuracy))٪")
            if game == .matching { LabeledContent("زمان", value: "\(fa(result.seconds)) ثانیه") }
            if game == .builder {
                LabeledContent("پاسخ مستقل در تلاش اول", value: fa(result.independent))
                LabeledContent("راهنماهای استفاده‌شده", value: fa(result.hints))
            }
            if let best { LabeledContent("بهترین نتیجه", value: "\(fa(best.accuracy))٪") }
            if !result.challengingIDs.isEmpty {
                Text("برای تمرین دوباره").font(PersianFont.emphasis)
                Text(result.challengingIDs.map(vocabulary).joined(separator: ", ")).practiceEnglish()
            }
            if saveFailed {
                Text("نتیجه هنوز ذخیره نشده.").foregroundStyle(Palette.muted)
                Button("تلاش دوباره برای ذخیره") { persist(result) }.frame(minHeight: 44)
            }
            Button(mode == .endless ? "دور بعدی" : "دوباره بازی کن") { restart() }.buttonStyle(PrimaryButton())
            Button("بازگشت به زمین بازی") { dismiss() }.frame(minHeight: 44)
        }
        .modifier(Panel())
    }

    private func signal(_ correct: Bool) {
        feedback = correct
        feedbackCount += 1
    }

    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.17), change)
    }

    private func reveal(first: Bool) {
        animate {
            if tiles?.reveal(first: first) == true { hints += 1 }
        }
    }

    private func submitSpelling(_ question: PracticeQuestion) {
        guard selectedOption == nil, tiles?.full == true else { return }
        attempts += 1
        let correct = tiles?.value == question.answer
        if correct {
            answers.append(PracticeAnswer(cardID: question.card.id, correct: true, attempts: attempts, hints: hints))
        }
        signal(correct)
    }

    private func next() {
        if index + 1 == round.count {
            finish()
        } else {
            index += 1
            prepareQuestion()
        }
    }

    private func prepareQuestion() {
        selectedOption = nil
        attempts = 0
        hints = 0
        showsExample = false
        feedback = nil
        if game == .builder, round.indices.contains(index) {
            var random = SystemRandomNumberGenerator()
            tiles = PracticeTiles(answer: round[index].answer, difficulty: difficulty, using: &random)
        }
    }

    private func restart() {
        round = makeRound()
        roundNumber += 1
        if game == .matching {
            var random = SystemRandomNumberGenerator()
            matchingRound = PracticeMatchingRound(questions: round, using: &random)
        }
        answers = []
        index = 0
        result = nil
        saveFailed = false
        started = .now
        #if DEBUG
        startedIn = clock.simulation?.id
        #endif
        prepareQuestion()
    }

    private func finish() {
        guard result == nil else { return }
        let result = PracticeResult(id: UUID(), game: game, date: clock.now,
                                    seconds: Int(started.duration(to: .now).components.seconds), answers: answers)
        let previous = personalBest()
        newBest = previous.map { result.beats($0) } ?? false
        best = previous.flatMap { result.beats($0) ? nil : $0 } ?? result
        self.result = result
        persist(result)
    }

    private func persist(_ result: PracticeResult) {
        do {
            #if DEBUG
            guard startedIn == clock.simulation?.id else { throw CocoaError(.fileWriteNoPermission) }
            #endif
            try save(result)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }
}

private extension View {
    func practiceEnglish() -> some View {
        environment(\.layoutDirection, .leftToRight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
