import SwiftData
import SwiftUI
import UIKit

@main struct ElphyApp: App {
    @AppStorage("appearance") private var appearance = "system"
    private let container: ModelContainer?
    private let deck: [Card]?
    private let readingContainer: ModelContainer?
    private let practiceContainer: ModelContainer?
    private let stories: [ReadingStory]
    @State private var clock: AppClock

    init() {
        container = try? ModelContainer(for: PersonalCard.self, ReviewState.self, ReviewEvent.self)
        let deck = try? Card.load()
        self.deck = deck
        stories = deck.flatMap { try? ReadingContent.load(cards: $0) } ?? []
        readingContainer = try? ReadingStore.makeContainer()
        practiceContainer = try? PracticeStore.makeContainer()
        let clock = AppClock()
        #if DEBUG
        do {
            let directory = try DeveloperSimulation.directory()
            clock.simulation = try DeveloperSimulation.resume(in: directory)
            DeveloperSimulation.removeInactiveProfiles(in: directory, keeping: clock.simulation?.id)
        } catch {
            clock.simulationRecoveryError = error.localizedDescription
        }
        #endif
        _clock = State(initialValue: clock)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let simulation = clock.simulation {
                    library(vocabulary: simulation.container, reading: simulation.container, practice: simulation.container)
                        .defaultAppStorage(simulation.preferences)
                        .id(simulation.id)
                } else if let container {
                    library(vocabulary: container, reading: readingContainer, practice: practiceContainer)
                } else {
                    unavailable
                }
                #else
                if let container {
                    library(vocabulary: container, reading: readingContainer, practice: practiceContainer)
                } else {
                    unavailable
                }
                #endif
            }
            .environment(clock)
            .font(PersianFont.body)
            .environment(\.locale, Locale(identifier: "fa_IR"))
            .environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .tint(Palette.sage)
        }
    }

    private var unavailable: some View {
        ContentUnavailableView("دسترسی به داده‌ها ممکن نیست", systemImage: "externaldrive",
                               description: Text("برنامه را ببند و دوباره باز کن."))
    }

    private func library(vocabulary: ModelContainer, reading: ModelContainer?, practice: ModelContainer?) -> some View {
        #if DEBUG
        Library(deck: deck, stories: stories, readingContainer: reading, practiceContainer: practice, startSimulation: startSimulation)
            .modelContainer(vocabulary)
        #else
        Library(deck: deck, stories: stories, readingContainer: reading, practiceContainer: practice)
            .modelContainer(vocabulary)
        #endif
    }

    #if DEBUG
    private func startSimulation(copyProgress: Bool) throws {
        var source: (ModelContext, ModelContext)?
        if copyProgress {
            guard let container, let readingContainer else { throw DeveloperSimulation.Failure.unavailable }
            source = (container.mainContext, readingContainer.mainContext)
        }
        clock.simulation = try DeveloperSimulation.start(at: clock.systemNow, calendar: .current,
                                                          in: DeveloperSimulation.directory(), copying: source,
                                                          practice: copyProgress ? practiceContainer?.mainContext : nil)
        clock.simulationRecoveryError = nil
    }
    #endif
}

struct Library: View {
    private enum Destination { case today, vocabulary, progress, settings }

    let deck: [Card]?
    let stories: [ReadingStory]
    let readingContainer: ModelContainer?
    let practiceContainer: ModelContainer?
    #if DEBUG
    let startSimulation: (Bool) throws -> Void
    @State private var showsDeveloperMenu = false
    @State private var readingRevision = 0
    #endif
    @Query private var personal: [PersonalCard]
    @Query private var states: [ReviewState]
    @Query(sort: \ReviewEvent.date, order: .reverse) private var events: [ReviewEvent]
    @AppStorage("dailyGoal") private var goal = DailyGoal.defaultValue
    @AppStorage("lastCelebratedLearningDay") private var lastCelebratedLearningDay = ""
    @State private var selection: Destination = .today
    @State private var session: StudyPlan?
    @State private var presentedStudyMode: StudyPlan.Mode?
    @State private var quiz: QuizPresentation?
    @State private var reading: ReadingPresentation?
    @State private var dailyReading: (day: ReadingDay, storyID: String?, isRevision: Bool)?
    @State private var readingRecords: [String: ReadingRecord] = [:]
    @State private var showsPractice = false
    @State private var showsPlayground = false
    @State private var welcomeVisible = false
    @State private var pendingGoalDay: String?
    @State private var goalCelebration: UUID?
    @State private var readingPositions: [String: Double] = [:]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppClock.self) private var clock
    @Environment(\.locale) private var locale
    @State private var refreshedAt: Date?

    private var now: Date { clock.isSimulating ? clock.now : refreshedAt ?? clock.now }

    private var cards: [Card] { (deck ?? []) + personal.map(\.card) }
    private var stateByID: [String: ReviewState] { Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0) }) }

    var body: some View {
        let index = stateByID
        let calendar = clock.calendar
        let recalls = events.compactMap(\.recall)
        let planner = makePlanner(at: now, recalls: recalls, calendar: calendar)
        let showsSchedule = selection == .today || selection == .progress
        let wake = !clock.isSimulating && scenePhase == .active && (showsSchedule || reading != nil)
            ? ReviewClock.nextRefresh(at: now, nextDue: planner.nextDue, calendar: calendar) : nil
        let day = ReadingDay(at: now, calendar: calendar)
        #if DEBUG
        let readingTask = ReadingRefresh(day: day, revision: readingRevision)
        #else
        let readingTask = ReadingRefresh(day: day, revision: 0)
        #endif
        let readingRefreshDay = scenePhase == .active && (selection == .today || reading != nil) ? readingTask : nil
        let dailyProgress = DailyLearningProgress(day: calendar.startOfDay(for: now),
                                                  count: planner.introducedToday, target: planner.effectiveGoal,
                                                  configuredGoal: DailyGoal.preferred(goal))
        let canCelebrate = pendingGoalDay == day.key && planner.reachedGoalToday && selection == .today
            && scenePhase == .active && presentedStudyMode == nil && quiz == nil && reading == nil

        tabs(at: now, index: index, planner: planner, day: day, dailyProgress: dailyProgress)
        .sheet(isPresented: $showsPlayground) { playground }
        .sheet(item: $session, onDismiss: { presentedStudyMode = nil }) { StudyView(plan: $0) }
        .sheet(item: $quiz) { QuizView(quiz: $0.session) }
        .sheet(item: $reading, onDismiss: {
            refreshClock()
            refreshDailyReading(at: clock.now, calendar: clock.calendar)
        }) { presentation in
            if let readingContainer {
                ReadingLibrary(stories: stories,
                               cards: Dictionary(uniqueKeysWithValues: (deck ?? []).map { ($0.id, $0) }),
                               statuses: planner.status, dailyStoryID: dailyReading?.day == day ? dailyReading?.storyID : nil,
                               isRevision: dailyReading?.isRevision == true, now: now, initialStoryID: presentation.storyID,
                               positions: $readingPositions)
                    .modelContainer(readingContainer)
            }
        }
        #if DEBUG
        .sheet(isPresented: $showsDeveloperMenu) {
            DeveloperMenu(deck: deck ?? [], stories: stories, readingContainer: readingContainer,
                          startSimulation: startSimulation, onReadingChange: {
                readingRevision += 1
                if selection == .today { refreshDailyReading(at: clock.now, calendar: clock.calendar) }
            }, onProgressReset: {
                goalCelebration = nil
                pendingGoalDay = nil
                clearReading()
                readingRevision += 1
            })
        }
        #endif
        .task(id: readingRefreshDay) {
            guard readingRefreshDay != nil, !Task.isCancelled else { return }
            refreshDailyReading(at: clock.now, calendar: clock.calendar)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { refreshClock() }
        }
        .onChange(of: selection) { _, tab in
            refreshClock()
            if tab != .today { goalCelebration = nil }
        }
        .onChange(of: events.first?.attemptID) { _, _ in refreshClock() }
        .onChange(of: dailyProgress) { previous, current in
            guard presentedStudyMode == .scheduled, current.reachedGoal(since: previous),
                  lastCelebratedLearningDay != day.key else { return }
            lastCelebratedLearningDay = day.key
            pendingGoalDay = day.key
        }
        .onChange(of: canCelebrate) { _, ready in
            guard ready else { return }
            pendingGoalDay = nil
            goalCelebration = UUID()
        }
        .sensoryFeedback(.success, trigger: goalCelebration) { _, next in next != nil }
        .task(id: goalCelebration) {
            guard goalCelebration != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                goalCelebration = nil
            } catch {
                // A newer presentation replaced this celebration.
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshClock()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshClock()
        }
        .task(id: [now, wake]) {
            guard let wake else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, wake.timeIntervalSince(clock.systemNow))))
                try Task.checkCancellation()
                refreshClock()
            } catch {
                // The activity, clock, or nearest review changed.
            }
        }
    }

    private func tabs(at date: Date, index: [String: ReviewState], planner: StudyPlanner,
                      day: ReadingDay, dailyProgress: DailyLearningProgress) -> some View {
        TabView(selection: $selection) {
            Tab(value: Destination.today) {
                today(at: date, planner: planner, day: day, dailyProgress: dailyProgress)
            } label: {
                tabLabel("امروز", destination: .today, icon: "sun.max", selectedIcon: "sun.max.fill")
            }
            Tab(value: Destination.vocabulary) {
                CollectionView(bundled: deck ?? [], personal: personal, states: index, statuses: planner.status)
            } label: {
                tabLabel("واژه‌ها", destination: .vocabulary, icon: "rectangle.on.rectangle", selectedIcon: "rectangle.on.rectangle.fill")
            }
            Tab(value: Destination.progress) {
                progress(planner)
            } label: {
                tabLabel("پیشرفت", destination: .progress, icon: "chart.bar", selectedIcon: "chart.bar.fill")
            }
            Tab(value: Destination.settings) {
                settings
            } label: {
                tabLabel("تنظیمات", destination: .settings, icon: "gearshape", selectedIcon: "gearshape.fill")
            }
        }
    }

    @ViewBuilder private var playground: some View {
        if let practiceContainer {
            let planner = makePlanner(at: clock.now, recalls: events.compactMap(\.recall), calendar: clock.calendar)
            PracticePlayground(cards: cards, progress: stateByID.mapValues(\.progress),
                               difficult: Set(planner.difficultCards.map(\.id)), container: practiceContainer)
        } else {
            ContentUnavailableView("زمین بازی در دسترس نیست", systemImage: "externaldrive")
                .presentationDragIndicator(.visible)
        }
    }

    private struct ReadingRefresh: Equatable {
        let day: ReadingDay
        let revision: Int
    }

    private var settings: some View {
        #if DEBUG
        SettingsView(states: states, events: events, readingContainer: readingContainer,
                     onReadingReset: clearReading, openDeveloperMenu: { showsDeveloperMenu = true })
        #else
        SettingsView(states: states, events: events, readingContainer: readingContainer, onReadingReset: clearReading)
        #endif
    }

    private func clearReading() {
        readingRecords = [:]
        dailyReading = nil
        readingPositions = [:]
    }

    private func refreshClock() {
        refreshedAt = clock.systemNow
    }

    private func tabLabel(_ title: String, destination: Destination, icon: String, selectedIcon: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: selection == destination ? selectedIcon : icon)
                .environment(\.symbolVariants, .none)
        }
    }

    private func makePlanner(at date: Date, recalls: [Recall], calendar: Calendar) -> StudyPlanner {
        StudyPlanner(cards: cards, progress: stateByID.mapValues(\.progress), goal: DailyGoal.preferred(goal),
                     at: date, calendar: calendar, recalls: recalls)
    }

    private func today(at date: Date, planner: StudyPlanner, day: ReadingDay,
                       dailyProgress: DailyLearningProgress) -> some View {
        let next = todayMessage(for: planner)
        return Page(avoidsFloatingTabBar: true, density: .compact) {
            TodayHeader(date: date, timeZone: clock.calendar.timeZone)
            #if DEBUG
            if let simulation = clock.simulation {
                Button {
                    showsDeveloperMenu = true
                } label: {
                    Label("SIMULATION · DAY \(simulation.learningDay)", systemImage: "clock.badge")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("simulation-indicator")
            }
            #endif

            TodayWelcomeCard(title: next.title, detail: next.detail, button: next.button,
                             completed: planner.completedCoreToday, start: startNextAction)
                .opacity(welcomeVisible || reduceMotion ? 1 : 0)
                .offset(y: welcomeVisible || reduceMotion ? 0 : 8)
                .onAppear {
                    guard !welcomeVisible else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { welcomeVisible = true }
                }
            dailyPlanPanel(planner, progress: dailyProgress)
            readingPanel(for: day, planner: planner)
            playgroundEntry(planner, afterDailyWork: planner.completedCoreToday || readingCompleted(on: day))

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
            let recalls = events.compactMap(\.recall)
            let planner = makePlanner(at: date, recalls: recalls, calendar: calendar)
            let assignment = try ReadingStore.dailyAssignment(stories: stories, planner: planner,
                                                       progress: stateByID.mapValues(\.progress), recalls: recalls,
                                                       records: records, at: date, calendar: calendar, in: context)
            dailyReading = (day, assignment?.storyID, assignment?.isRevision == true)
        } catch {
            if dailyReading?.day != day { dailyReading = (day, nil, false) }
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
                                      record: readingRecords[story.id],
                                      hasReadingPosition: (readingPositions[story.id] ?? 0) > 0,
                                      isRevision: dailyReading.isRevision,
                                      completedToday: readingCompleted(on: day),
                                      start: { openReading(storyID: story.id) }, showLibrary: { openReading() })
        } else if readingContainer != nil, !stories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("داستان پیشنهادی امروز").font(DashboardFont.section).accessibilityAddTraits(.isHeader)
                if dailyReading?.day == day {
                    Text("داستان امروز در دسترس نیست.").foregroundStyle(Palette.muted)
                } else {
                    ProgressView("در حال آماده‌کردن داستان…")
                        .font(PersianFont.subheadline)
                }
                Button("همهٔ داستان‌ها") { openReading() }
                    .frame(minHeight: 44)
            }
            .modifier(Panel(padding: DashboardMetrics.group, radius: DashboardMetrics.cardRadius))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("داستان‌خوانی").font(DashboardFont.section).accessibilityAddTraits(.isHeader)
                Text("داستان‌ها در دسترس نیستند. برنامه را دوباره باز کن.")
                    .foregroundStyle(Palette.muted)
            }
            .modifier(Panel(padding: DashboardMetrics.group, radius: DashboardMetrics.cardRadius))
        }
    }

    private func dailyPlanPanel(_ planner: StudyPlanner, progress: DailyLearningProgress) -> some View {
        let due = planner.recommendedReviews.count
        return VStack(alignment: .leading, spacing: DashboardMetrics.inline) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DashboardMetrics.inline) {
                    dailyHeading.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    dailyGoalPicker.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 0) {
                    dailyHeading
                    dailyGoalPicker
                }
            }
            if progress.target > 0 {
                DailyProgressMeter(progress: progress, celebration: goalCelebration)
            } else {
                Text(planner.introducedToday > 0
                     ? "\(fa(planner.introducedToday)) واژهٔ تازه تمرین کردی."
                     : planner.remainingNew == 0 ? "واژهٔ تازه‌ای در صف نیست" : "امروز فقط مرور")
                    .font(DashboardFont.action)
            }
            Divider().overlay(Palette.border).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DashboardMetrics.micro) {
                Label(due > 0 ? "\(fa(due)) واژه در مرور پیشنهادی" : "مرور پیشنهادی دیگری نداری",
                      systemImage: due > 0 ? "arrow.clockwise" : "checkmark.circle")
                    .font(due > 0 ? DashboardFont.action : DashboardFont.body)
                    .foregroundStyle(due > 0 ? Palette.sage : Palette.muted)
                if planner.additionalDueCount > 0 {
                    Text("\(fa(planner.additionalDueCount)) واژهٔ دیگر آمادهٔ مرور اختیاری")
                        .font(DashboardFont.metadata).foregroundStyle(Palette.muted)
                }
                if planner.scheduledLaterToday > 0 {
                    Text("\(fa(planner.scheduledLaterToday)) واژه برای مرور در ادامهٔ امروز")
                        .font(DashboardFont.metadata)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .modifier(Panel(fill: Palette.paper, padding: DashboardMetrics.group, radius: DashboardMetrics.cardRadius))
    }

    private var dailyHeading: some View {
        Text("برنامهٔ امروز").font(DashboardFont.section).accessibilityAddTraits(.isHeader)
    }

    private func todayMessage(for planner: StudyPlanner)
        -> (title: String, detail: String, button: String?) {
        if planner.dailyPlan != nil {
            let counts = "\(fa(planner.newCards.count)) واژهٔ جدید · \(fa(planner.recommendedReviews.count)) مرور · حدود \(fa(planner.estimatedMinutes)) دقیقه"
            return (planner.isRecoveryDay ? "امروز بیشتر روی مرور تمرکز می‌کنیم" : "آماده‌ای شروع کنیم؟",
                    counts, planner.introducedToday > 0 || planner.reviewedToday > 0 ? "ادامهٔ یادگیری" : "شروع یادگیری")
        }
        if planner.completedCoreToday {
            return ("آفرین! تمرین پیشنهادی امروز کامل شد",
                    "اگر دوست داری، می‌تونی به مرور یا بازی با واژه‌ها ادامه بدی.",
                    planner.dueCards.isEmpty ? "بریم بازی کنیم" : "مرور بیشتر")
        }
        if planner.remainingNew == 0 && planner.introducedCount > 0 {
            return ("همهٔ واژه‌های موجود را یاد گرفتی!",
                    "حالا می‌تونی دانسته‌هات رو با مرور و بازی محکم‌تر کنی.",
                    planner.dueCards.isEmpty ? "بریم بازی کنیم" : "مرور بیشتر")
        }
        if !planner.dueCards.isEmpty {
            return ("واژه‌هایی برای مرور آماده‌اند", "هر وقت خواستی، با یک دور کوتاه شروع کن.", "مرور بیشتر")
        }
        switch planner.nextAction {
        case .setGoal:
            return ("آماده‌ای شروع کنیم؟", "تعداد واژه‌های تازهٔ روزانه را انتخاب کن.", "انتخاب هدف روزانه")
        case .browse:
            return ("مجموعه‌ات را بساز", "یک واژه با معنی فارسی اضافه کن تا تمرین را شروع کنی.", "رفتن به واژه‌ها")
        default:
            return ("برای امروز آماده‌ای", "هر وقت خواستی، واژه‌های آشنا را تمرین کن.", "بریم بازی کنیم")
        }
    }

    private func startNextAction() {
        let planner = makePlanner(at: clock.now, recalls: events.compactMap(\.recall), calendar: clock.calendar)
        if let plan = planner.dailyPlan {
            open(plan)
        } else if !planner.dueCards.isEmpty, let plan = planner.completionPlan() {
            open(plan)
        } else {
            switch planner.nextAction {
            case .setGoal: selection = .settings
            case .browse: selection = .vocabulary
            default: showsPlayground = true
            }
        }
    }

    private func open(_ plan: StudyPlan) {
        TapCue.open.play()
        presentedStudyMode = plan.mode
        session = plan
    }

    private struct QuizPresentation: Identifiable {
        let id = UUID()
        let session: QuizSession
    }

    private func readingCompleted(on day: ReadingDay) -> Bool {
        guard dailyReading?.day == day, let storyID = dailyReading?.storyID,
              let completion = readingRecords[storyID]?.lastCompletion else { return false }
        return ReadingDay(at: completion, calendar: clock.calendar) == day
    }

    private func playgroundEntry(_ planner: StudyPlanner, afterDailyWork: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(afterDailyWork ? "هنوز انرژی داری؟" : "زمین بازی واژه‌ها", systemImage: "puzzlepiece")
                .font(DashboardFont.section).accessibilityAddTraits(.isHeader)
            Text("با چند بازی کوتاه، واژه‌هایی که یاد گرفتی رو بهتر به خاطر بسپار.")
                .font(DashboardFont.body).foregroundStyle(Palette.muted)
            Button("بریم بازی کنیم") { showsPlayground = true }
                .buttonStyle(PrimaryButton())
                .accessibilityIdentifier("playground.open")
            optionalPracticePanel(planner)
        }
        .modifier(Panel(fill: Palette.tint, padding: DashboardMetrics.group, radius: DashboardMetrics.cardRadius))
    }

    private func optionalPracticePanel(_ planner: StudyPlanner) -> some View {
        DisclosureGroup(isExpanded: $showsPractice) {
            if showsPractice { practiceActivities(planner) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("مرور و آزمون‌های بیشتر").font(DashboardFont.action)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
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
        DailyGoalSelector(goal: $goal)
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
                    Group {
                        if clock.isSimulating {
                            Text(clock.relativeDate(event.date, to: now, locale: locale))
                        } else {
                            Text(event.date, format: .relative(presentation: .named))
                        }
                    }
                    .font(PersianFont.subheadline)
                }
                .modifier(Panel())
            }
        }
    }
}
