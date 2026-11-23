import SwiftData
import SwiftUI
import UIKit

@main struct ElphyApp: App {
    @AppStorage("appearance") private var appearance = "system"
    private let container: ModelContainer?
    private let deck: [Card]?
    private let readingContainer: ModelContainer?
    private let stories: [ReadingStory]

    init() {
        container = try? ModelContainer(for: PersonalCard.self, ReviewState.self, ReviewEvent.self)
        let deck = try? Card.load()
        self.deck = deck
        stories = deck.flatMap { try? ReadingContent.load(cards: $0) } ?? []
        readingContainer = try? ReadingStore.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    Library(deck: deck, stories: stories, readingContainer: readingContainer)
                        .modelContainer(container)
                } else {
                    ContentUnavailableView("دسترسی به داده‌ها ممکن نیست", systemImage: "externaldrive",
                                           description: Text("برنامه را ببند و دوباره باز کن."))
                }
            }
            .font(PersianFont.body)
            .environment(\.locale, Locale(identifier: "fa_IR"))
            .environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .tint(Palette.sage)
        }
    }
}

struct Library: View {
    private enum Destination { case today, vocabulary, progress, settings }

    let deck: [Card]?
    let stories: [ReadingStory]
    let readingContainer: ModelContainer?
    @Query private var personal: [PersonalCard]
    @Query private var states: [ReviewState]
    @Query(sort: \ReviewEvent.date, order: .reverse) private var events: [ReviewEvent]
    @AppStorage("dailyGoal") private var goal = DailyGoal.defaultValue
    @State private var selection: Destination = .today
    @State private var session: StudyPlan?
    @State private var quiz: QuizPresentation?
    @State private var reading: ReadingPresentation?
    @State private var dailyReading: (day: ReadingDay, storyID: String?)?
    @State private var readingRecords: [String: ReadingRecord] = [:]
    @State private var showsPractice = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var now = Date.now

    private var cards: [Card] { (deck ?? []) + personal.map(\.card) }
    private var stateByID: [String: ReviewState] { Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0) }) }

    var body: some View {
        let index = stateByID
        let calendar = Calendar.current
        let recalls = events.compactMap(\.recall)
        let planner = makePlanner(at: now, recalls: recalls, calendar: calendar)
        let showsSchedule = selection == .today || selection == .progress
        let wake = scenePhase == .active && showsSchedule
            ? ReviewClock.nextRefresh(at: now, nextDue: planner.nextDue, calendar: calendar) : nil
        let day = ReadingDay(at: now, calendar: calendar)
        let readingRefreshDay = scenePhase == .active && selection == .today && reading == nil ? day : nil

        TabView(selection: $selection) {
            Tab("امروز", systemImage: "sun.max", value: Destination.today) {
                today(at: now, planner: planner, day: day)
            }
            Tab("واژه‌ها", systemImage: "rectangle.on.rectangle", value: Destination.vocabulary) {
                CollectionView(bundled: deck ?? [], personal: personal, states: index, statuses: planner.status)
            }
            Tab("پیشرفت", systemImage: "chart.bar.xaxis", value: Destination.progress) {
                progress(planner)
            }
            Tab("تنظیمات", systemImage: "gearshape", value: Destination.settings) {
                SettingsView(states: states, events: events)
            }
        }
        .sheet(item: $session) { StudyView(plan: $0) }
        .sheet(item: $quiz) { QuizView(quiz: $0.session) }
        .sheet(item: $reading, onDismiss: { now = .now }) { presentation in
            if let readingContainer {
                ReadingLibrary(stories: stories,
                               cards: Dictionary(uniqueKeysWithValues: (deck ?? []).map { ($0.id, $0) }),
                               statuses: planner.status, vocabularyProgress: index.mapValues(\.progress),
                               recalls: recalls, now: now, initialStoryID: presentation.storyID)
                    .modelContainer(readingContainer)
            }
        }
        .task(id: readingRefreshDay) {
            guard readingRefreshDay != nil, !Task.isCancelled else { return }
            refreshDailyReading(at: .now, calendar: .current)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { now = .now }
        }
        .onChange(of: selection) { _, _ in now = .now }
        .onChange(of: events.first?.attemptID) { _, _ in now = .now }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            now = .now
        }
        .task(id: [now, wake]) {
            guard let wake else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, wake.timeIntervalSinceNow)))
                try Task.checkCancellation()
                now = .now
            } catch {
                // The activity, clock, or nearest review changed.
            }
        }
    }

    private func makePlanner(at date: Date, recalls: [Recall], calendar: Calendar = .current) -> StudyPlanner {
        StudyPlanner(cards: cards, progress: stateByID.mapValues(\.progress), goal: goal,
                     at: date, calendar: calendar, recalls: recalls)
    }

    private func today(at date: Date, planner: StudyPlanner, day: ReadingDay) -> some View {
        let next = todayMessage(for: planner)
        let title = Text(next.title).font(HeadingFont.title).accessibilityAddTraits(.isHeader)
        let mood: ElephantMascot.Mood = planner.nextAction != .practice ? .welcoming
            : planner.reachedGoalToday ? .happy : .resting
        return Page(avoidsFloatingTabBar: true) {
            todayHeader(at: date)

            VStack(alignment: .leading, spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        ElephantMascot(mood: mood).frame(width: 64, height: 58)
                        title.multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 12) {
                        title
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ElephantMascot(mood: mood).frame(width: 64, height: 58)
                    }
                }
                if let detail = next.detail { Text(detail).foregroundStyle(Palette.muted) }
                Button(next.button) { startNextAction() }
                    .buttonStyle(PrimaryButton())
            }
            .modifier(Panel(fill: Palette.tint))

            dailyPlanPanel(planner)
            masteryPanel(planner.mastery)
            readingPanel(for: day, planner: planner)
            optionalPracticePanel(planner)

            if deck == nil {
                Label("مجموعهٔ اصلی بارگیری نشد. واژه‌های شخصی در دسترس‌اند.", systemImage: "exclamationmark.circle")
            }
        }
    }

    private struct ReadingPresentation: Identifiable {
        let id = UUID()
        let storyID: String?
    }

    private func refreshDailyReading(at date: Date, calendar: Calendar) {
        guard let readingContainer, !stories.isEmpty else { return }
        let day = ReadingDay(at: date, calendar: calendar)
        let context = readingContainer.mainContext
        do {
            let records = try ReadingStore.records(in: context)
            readingRecords = records
            let storyID = try ReadingStore.dailyStoryID(at: date, calendar: calendar,
                                                       availableIDs: Set(stories.map(\.id)), in: context) { previousID in
                let recalls = events.compactMap(\.recall)
                let planner = makePlanner(at: date, recalls: recalls, calendar: calendar)
                return ReadingRecommendationEngine.recommend(
                    stories: stories, statuses: planner.status, progress: stateByID.mapValues(\.progress),
                    recalls: recalls, records: records, at: date, calendar: calendar, previousStoryID: previousID
                )?.storyID
            }
            dailyReading = (day, storyID)
        } catch {
            if dailyReading?.day != day { dailyReading = (day, nil) }
        }
    }

    private func openReading(storyID: String? = nil) {
        TapCue.open.play()
        reading = ReadingPresentation(storyID: storyID)
    }

    @ViewBuilder
    private func readingPanel(for day: ReadingDay, planner: StudyPlanner) -> some View {
        if readingContainer != nil, let dailyReading, dailyReading.day == day,
           let story = stories.first(where: { $0.id == dailyReading.storyID }) {
            let count = story.targetWordIds.filter { id in
                guard let status = planner.status[id] else { return false }
                return status.stage != .new
            }.count
            ReadingRecommendationCard(story: story, matchingVocabularyCount: count,
                                      completed: readingRecords[story.id]?.completed == true,
                                      start: { openReading(storyID: story.id) }, showLibrary: { openReading() })
        } else if readingContainer != nil, !stories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("داستان پیشنهادی امروز").font(HeadingFont.section)
                if dailyReading?.day == day {
                    Text("داستان امروز در دسترس نیست.").foregroundStyle(Palette.muted)
                }
                Button("همهٔ داستان‌ها") { openReading() }
                    .frame(minHeight: 44)
            }
            .modifier(Panel(fill: Palette.tint))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("داستان‌خوانی").font(HeadingFont.section)
                Text("داستان‌ها در دسترس نیستند. برنامه را دوباره باز کن.")
                    .foregroundStyle(Palette.muted)
            }
            .modifier(Panel())
        }
    }

    private func todayHeader(at date: Date) -> some View {
        let persianDate = Date.FormatStyle(locale: Locale(identifier: "fa_IR"),
                                           calendar: Calendar(identifier: .persian))
        let dateBlock = VStack(alignment: .leading, spacing: 2) {
            Text(date.formatted(persianDate.weekday(.wide)))
                .font(HeadingFont.section)
            Text(date.formatted(persianDate.day().month(.wide).year()))
                .font(PersianFont.subheadline)
                .foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)

        let wordmark = Text("Elphy")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(Palette.sage)
            .environment(\.layoutDirection, .leftToRight)

        return VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    dateBlock.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    wordmark.fixedSize(horizontal: true, vertical: false)
                }
                VStack(spacing: 6) {
                    dateBlock.frame(maxWidth: .infinity, alignment: .leading)
                    wordmark.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private func dailyPlanPanel(_ planner: StudyPlanner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack { dailyHeading; Spacer(minLength: 4); dailyGoalPicker }
                VStack(alignment: .leading, spacing: 4) { dailyHeading; dailyGoalPicker }
            }
            if planner.effectiveGoal > 0 {
                ProgressView(value: Double(min(planner.introducedToday, planner.effectiveGoal)),
                             total: Double(planner.effectiveGoal))
                    .progressViewStyle(StudyProgressStyle())
                    .accessibilityLabel("پیشرفت هدف واژه‌های جدید")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { dailyStats(planner) }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 7) { dailyStats(planner) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if deck != nil && planner.remainingStarter == 0 && planner.remainingNew > 0 {
                Text("همهٔ واژه‌های مجموعهٔ آغازین را تمرین کرده‌ای.").foregroundStyle(Palette.muted)
            }
        }
        .font(PersianFont.subheadline)
        .modifier(Panel())
    }

    @ViewBuilder private func dailyStats(_ planner: StudyPlanner) -> some View {
        let introduced = planner.introducedToday
        let target = planner.effectiveGoal
        stat(target > 0 ? "\(fa(introduced)) از \(fa(target))" : fa(introduced),
             label: "یادگیری امروز",
             explanation: target > 0 ? "\(fa(introduced)) واژهٔ جدید از هدف \(fa(target)) واژه"
                : "\(fa(introduced)) واژهٔ جدید تمرین شد")
        stat(fa(planner.dueCards.count), label: "آمادهٔ مرور",
             explanation: "\(fa(planner.dueCards.count)) واژه که همین حالا می‌توان مرور کرد")
        stat(fa(planner.scheduledLaterToday), label: "بعدتر امروز",
             explanation: "\(fa(planner.scheduledLaterToday)) واژه که تا پایان امروز آمادهٔ مرور می‌شود")
    }

    private func stat(_ value: String, label: String, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(PersianFont.emphasis)
            Text(label).font(PersianFont.subheadline).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(explanation)
    }

    private var dailyHeading: some View {
        Text("برنامهٔ امروز").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
    }

    private func todayMessage(for planner: StudyPlanner) -> (title: String, detail: String?, button: String) {
        let new = "\(fa(planner.newCards.count)) واژهٔ جدید"
        let due = "\(fa(planner.dueCards.count)) واژه برای مرور"
        switch planner.nextAction {
        case .learn:
            return (planner.introducedCount == 0 ? "به Elphy خوش اومدی!" : "واژه‌های تازه آماده‌اند",
                    "امروز با \(new) شروع کن.", "شروع یادگیری")
        case .review:
            return ("وقت مرور واژه‌هاست", "\(due) آماده است.", "مرور واژه‌ها")
        case .mixed:
            return ("برنامهٔ یادگیری آماده است", "\(due) و \(new) آماده است.", "شروع یادگیری")
        case .continueStudy:
            let detail = planner.dueCards.isEmpty ? "\(new) برای امروز باقی مانده."
                : "\(due) و \(new) باقی مانده."
            return ("از همین‌جا ادامه بده", detail, "ادامهٔ تمرین")
        case .practice:
            let title: String
            if planner.reachedGoalToday {
                title = "آفرین! امروز \(fa(planner.introducedToday)) واژهٔ تازه تمرین کردی."
            } else if planner.remainingNew == 0 {
                title = "همهٔ واژه‌ها را تمرین کرده‌ای"
            } else {
                title = "فعلاً مرورِ آماده‌ای نداری"
            }
            return (title, nil, "تمرین بیشتر")
        case .setGoal:
            return ("آمادهٔ یادگیری هستی؟", "برای شروع، تعداد واژه‌های جدید روزانه را انتخاب کن.", "انتخاب هدف روزانه")
        case .browse:
            return ("مجموعه‌ات را بساز", "برای شروع، یک واژه با معنی فارسی اضافه کن.", "رفتن به واژه‌ها")
        }
    }

    private func startNextAction() {
        let planner = makePlanner(at: .now, recalls: events.compactMap(\.recall))
        if let plan = planner.dailyPlan {
            open(plan)
        } else {
            switch planner.nextAction {
            case .practice:
                let pool = planner.difficultCards.isEmpty ? planner.practicedCards.shuffled() : planner.difficultCards
                if let plan = planner.optionalPlan(for: pool) { open(plan) }
            case .setGoal: selection = .settings
            case .browse: selection = .vocabulary
            default: break
            }
        }
    }

    private func open(_ plan: StudyPlan) {
        TapCue.open.play()
        session = plan
    }

    private struct QuizPresentation: Identifiable {
        let id = UUID()
        let session: QuizSession
    }

    private func optionalPracticePanel(_ planner: StudyPlanner) -> some View {
        DisclosureGroup(isExpanded: $showsPractice) {
            if showsPractice { practiceActivities(planner) }
        } label: {
            Text("تمرین اختیاری").font(HeadingFont.section)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .modifier(Panel())
    }

    private func practiceActivities(_ planner: StudyPlanner) -> some View {
        var random = SystemRandomNumberGenerator()
        let questions = QuizSession.makeQuestions(
            practicedCards: planner.practicedCards, distractorPool: cards, limit: 10, using: &random
        )
        let hasPracticed = !planner.practicedCards.isEmpty
        let quizDetail: String
        if !hasPracticed {
            quizDetail = "پس از تمرین اولین واژه در دسترس است."
        } else if questions.isEmpty {
            quizDetail = "برای ساختن چهار گزینهٔ متفاوت، واژه‌های بیشتری لازم است."
        } else {
            quizDetail = "معنی درست واژه‌ها را انتخاب کن."
        }
        return VStack(alignment: .leading, spacing: 4) {
            Divider()
            Button {
                TapCue.open.play()
                quiz = QuizPresentation(session: QuizSession(questions: questions))
            } label: {
                practiceActivity("آزمون چهارگزینه‌ای", icon: "checklist",
                                 detail: quizDetail,
                                 available: !questions.isEmpty)
            }
            .disabled(questions.isEmpty)
            Divider().accessibilityHidden(true)
            Button {
                startOptionalPractice(planner.practicedCards, planner: planner)
            } label: {
                practiceActivity("مرور آزاد", icon: "rectangle.on.rectangle",
                                 detail: hasPracticed ? "معنی واژه‌های آشنا را به یاد بیاور."
                                     : "پس از تمرین اولین واژه در دسترس است.",
                                 available: hasPracticed)
            }
            .disabled(!hasPracticed)
            Divider().accessibilityHidden(true)
            Button {
                open(planner.difficultPlan)
            } label: {
                practiceActivity("واژه‌های دشوار", icon: "arrow.counterclockwise.circle",
                                 detail: "واژه‌هایی را که یادگیری‌شان برایت سخت‌تر بوده، دوباره تمرین کن.",
                                 status: planner.difficultCards.isEmpty
                                     ? "هنوز واژهٔ دشواری شناسایی نشده."
                                     : "\(fa(planner.difficultCards.count)) واژه برای تمرین")
            }
            .accessibilityIdentifier("practice.difficult")
        }
        .padding(.top, 6)
        .buttonStyle(.plain)
    }

    private func practiceActivity(_ title: String, icon: String, detail: String? = nil,
                                  status: String? = nil, available: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(PersianFont.emphasis)
                if let detail {
                    Text(detail).font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                }
                if let status {
                    Text(status).font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: available ? "chevron.forward" : "lock")
                .font(.footnote)
                .accessibilityHidden(true)
        }
        .foregroundStyle(available ? Palette.sage : Palette.muted)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func startOptionalPractice(_ pool: [Card], planner: StudyPlanner) {
        if let plan = planner.optionalPlan(for: pool.shuffled()) { open(plan) }
    }

    private var dailyGoalPicker: some View {
        Picker("هدف روزانه", selection: $goal) {
            ForEach(DailyGoal.choices(including: goal), id: \.self) { count in
                Text(count == 0 ? "فقط مرور" : "\(fa(count)) واژهٔ جدید").tag(count)
            }
        }
        .pickerStyle(.menu)
        .frame(minHeight: 44)
    }

    private func masteryPanel(_ mastery: MasteryBreakdown) -> some View {
        let stages: [(String, Int, Color)] = [
            ("تثبیت‌شده", mastery.mastered, Palette.sage),
            ("در حال یادگیری", mastery.learning, Palette.learningProgress),
            ("جدید", mastery.new, Palette.border)
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("تسلط بر واژه‌ها").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
            if mastery.total == 0 {
                Text("هنوز واژه‌ای در مجموعه نیست.").foregroundStyle(Palette.muted)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(stages.indices, id: \.self) { index in
                            Rectangle().fill(stages[index].2)
                                .frame(width: geometry.size.width * mastery.fraction(stages[index].1))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { masteryLegend(stages) }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 6) { masteryLegend(stages) }
                }
            }
        }
        .modifier(Panel())
    }

    private func masteryLegend(_ stages: [(String, Int, Color)]) -> some View {
        ForEach(stages.indices, id: \.self) { index in
            let (label, count, color) = stages[index]
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                Text("\(fa(count)) \(label)").font(PersianFont.subheadline)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue("\(fa(count)) واژه")
        }
    }

    private func progress(_ planner: StudyPlanner) -> some View {
        Page(avoidsFloatingTabBar: true) {
            Heading(title: "پیشرفت", subtitle: "تسلط با یادآوری درست در چند نوبتِ بافاصله به دست می‌آید.")
            masteryPanel(planner.mastery)
            VStack(alignment: .leading, spacing: 12) {
                Text("مرور").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
                Text("\(fa(planner.scheduledLaterToday)) واژه برای مرور در ادامهٔ امروز")
                Text("\(fa(planner.dueCards.count)) واژه آمادهٔ مرور")
                Text("\(fa(planner.difficultCards.count)) واژهٔ دشوار برای تمرین بیشتر")
                if !planner.masteredCards.isEmpty {
                    Button {
                        startOptionalPractice(planner.masteredCards, planner: planner)
                    } label: {
                        practiceActivity("تمرین واژه‌های تثبیت‌شده", icon: "checkmark.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            .modifier(Panel())
            Text("فعالیت اخیر").font(HeadingFont.title).accessibilityAddTraits(.isHeader)
            if events.isEmpty {
                Text("پس از اولین تمرین، فعالیتت اینجا دیده می‌شود.").foregroundStyle(Palette.muted)
            }
            ForEach(events.prefix(10)) { event in
                HStack {
                    Text(event.word).font(.system(.headline, design: .serif))
                        .environment(\.layoutDirection, .leftToRight)
                    Spacer()
                    Text(event.date, format: .relative(presentation: .named)).font(PersianFont.subheadline)
                }
                .modifier(Panel())
            }
        }
    }
}
