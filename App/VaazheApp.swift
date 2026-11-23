import SwiftData
import SwiftUI
import UIKit

@main struct VaazheApp: App {
    @AppStorage("appearance") private var appearance = "system"
    private let container: ModelContainer?
    private let deck = try? Card.load()

    init() {
        container = try? ModelContainer(for: PersonalCard.self, ReviewState.self, ReviewEvent.self)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    Library(deck: deck).modelContainer(container)
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
    @Query private var personal: [PersonalCard]
    @Query private var states: [ReviewState]
    @Query(sort: \ReviewEvent.date, order: .reverse) private var events: [ReviewEvent]
    @AppStorage("dailyGoal") private var goal = DailyGoal.defaultValue
    @State private var selection: Destination = .today
    @State private var session: StudyPlan?
    @State private var quiz: QuizPresentation?
    @State private var showsPractice = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var now = Date.now

    private var cards: [Card] { (deck ?? []) + personal.map(\.card) }
    private var stateByID: [String: ReviewState] { Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0) }) }

    var body: some View {
        let index = stateByID
        let calendar = Calendar.current
        let planner = makePlanner(at: now, recalls: events.compactMap(\.recall), calendar: calendar)
        let showsSchedule = selection == .today || selection == .progress
        let wake = scenePhase == .active && showsSchedule
            ? ReviewClock.nextRefresh(at: now, nextDue: planner.nextDue, calendar: calendar) : nil

        TabView(selection: $selection) {
            Tab("امروز", systemImage: "sun.max", value: Destination.today) {
                today(at: now, planner: planner)
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { now = .now }
        }
        .onChange(of: selection) { _, _ in now = .now }
        .onChange(of: events.first?.attemptID) { _, _ in now = .now }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
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

    private func today(at date: Date, planner: StudyPlanner) -> some View {
        let next = todayMessage(for: planner)
        let title = Text(next.title).font(HeadingFont.title).accessibilityAddTraits(.isHeader)
        let mood: ElephantMascot.Mood = planner.nextAction != .practice ? .welcoming
            : planner.reachedGoalToday ? .happy : .resting
        let dateFormat = Date.FormatStyle(date: .complete, time: .omitted,
                                         locale: Locale(identifier: "fa_IR"),
                                         calendar: Calendar(identifier: .persian))
        return Page(avoidsFloatingTabBar: true) {
            HStack {
                Text("واژه").font(HeadingFont.title).foregroundStyle(Palette.sage)
                Spacer()
                Text(date.formatted(dateFormat))
                    .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
            }

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
            optionalPracticePanel(planner)

            if deck == nil {
                Label("مجموعهٔ اصلی بارگیری نشد. واژه‌های شخصی در دسترس‌اند.", systemImage: "exclamationmark.circle")
            }
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
            return (planner.introducedCount == 0 ? "به واژه خوش اومدی!" : "واژه‌های تازه آماده‌اند",
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
            VStack(alignment: .leading, spacing: 4) {
                Text("تمرین اختیاری").font(HeadingFont.section)
                Text("آزمون چهارگزینه‌ای، مرور آزاد و تمرین واژه‌های دشوار")
                    .font(PersianFont.subheadline)
                    .foregroundStyle(Palette.muted)
            }
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
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            if hasPracticed {
                if !questions.isEmpty {
                    Button {
                        TapCue.open.play()
                        quiz = QuizPresentation(session: QuizSession(questions: questions))
                    } label: {
                        practiceActivity("آزمون چهارگزینه‌ای", icon: "checklist",
                                         detail: "معنی فارسی واژه‌هایی را که تمرین کرده‌ای انتخاب کن.")
                    }
                } else {
                    practiceActivity("آزمون چهارگزینه‌ای", icon: "lock",
                                     detail: "برای ساختن چهار گزینهٔ متفاوت، واژه‌های بیشتری لازم است.")
                }
                Button {
                    startOptionalPractice(planner.practicedCards, planner: planner)
                } label: {
                    practiceActivity("مرور آزاد", icon: "rectangle.on.rectangle",
                                     detail: "معنی واژه‌های آشنا را به یاد بیاور، بعد پاسخ را ببین.")
                }
                if let plan = planner.optionalPlan(for: planner.difficultCards) {
                    Button { open(plan) } label: {
                        practiceActivity("تمرین واژه‌های دشوار", icon: "arrow.counterclockwise")
                    }
                }
                if !planner.masteredCards.isEmpty {
                    Button {
                        startOptionalPractice(planner.masteredCards, planner: planner)
                    } label: {
                        practiceActivity("تمرین واژه‌های تثبیت‌شده", icon: "checkmark.circle")
                    }
                }
                Text("زمان مرورهای برنامه‌ریزی‌شده با این تمرین‌ها تغییر نمی‌کند.")
                    .font(PersianFont.subheadline)
                    .foregroundStyle(Palette.muted)
            } else {
                practiceActivity("آزمون چهارگزینه‌ای", icon: "lock")
                practiceActivity("مرور آزاد", icon: "lock")
                Text("بعد از تمرین اولین واژه، می‌توانی آزمون بدهی یا مرور آزاد را شروع کنی.")
                    .font(PersianFont.subheadline)
                    .foregroundStyle(Palette.muted)
                Button {
                    selection = .vocabulary
                } label: {
                    practiceActivity("دیدن مجموعهٔ واژه‌ها", icon: "book")
                }
            }
        }
        .padding(.top, 6)
        .buttonStyle(.plain)
    }

    private func practiceActivity(_ title: String, icon: String, detail: String? = nil) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(PersianFont.emphasis)
                if let detail {
                    Text(detail).font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                }
            }
        } icon: {
            Image(systemName: icon).accessibilityHidden(true)
        }
        .foregroundStyle(icon == "lock" ? Palette.muted : Palette.sage)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(icon == "lock" ? "هنوز در دسترس نیست" : "")
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
