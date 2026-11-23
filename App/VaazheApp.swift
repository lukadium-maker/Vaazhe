import SwiftData
import SwiftUI

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
    @State private var quizUnavailable = false

    private var cards: [Card] { (deck ?? []) + personal.map(\.card) }
    private var stateByID: [String: ReviewState] { Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0) }) }

    var body: some View {
        let index = stateByID
        let recalls = events.compactMap(\.recall)
        TabView(selection: $selection) {
            Tab("امروز", systemImage: "sun.max", value: Destination.today) {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    today(at: timeline.date, planner: makePlanner(at: timeline.date, recalls: recalls))
                }
            }
            Tab("واژه‌ها", systemImage: "rectangle.on.rectangle", value: Destination.vocabulary) {
                CollectionView(bundled: deck ?? [], personal: personal, states: index,
                               statuses: makePlanner(at: .now, recalls: recalls).status)
            }
            Tab("پیشرفت", systemImage: "chart.bar.xaxis", value: Destination.progress) {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    progress(makePlanner(at: timeline.date, recalls: recalls))
                }
            }
            Tab("تنظیمات", systemImage: "gearshape", value: Destination.settings) {
                SettingsView(states: states, events: events)
            }
        }
        .sheet(item: $session) { StudyView(plan: $0) }
        .sheet(item: $quiz) { QuizView(quiz: $0.session) }
        .alert("برای این آزمون گزینه‌های کافی پیدا نشد", isPresented: $quizUnavailable) {
            Button("باشه", role: .cancel) {}
        } message: {
            Text("می‌توانی با کارت‌های تمرین، واژه‌ها را مرور کنی.")
        }
    }

    private func makePlanner(at date: Date, recalls: [Recall]) -> StudyPlanner {
        StudyPlanner(cards: cards, progress: stateByID.mapValues(\.progress), goal: goal,
                     at: date, calendar: .current, recalls: recalls)
    }

    private func today(at date: Date, planner: StudyPlanner) -> some View {
        let next = todayMessage(for: planner)
        let dateFormat = Date.FormatStyle(date: .complete, time: .omitted,
                                         locale: Locale(identifier: "fa_IR"),
                                         calendar: Calendar(identifier: .persian))
        return Page {
            HStack {
                Text("واژه").font(HeadingFont.title).foregroundStyle(Palette.sage)
                Spacer()
                Text(date.formatted(dateFormat))
                    .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
            }

            VStack(alignment: .leading, spacing: 13) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text(next.title).font(HeadingFont.title)
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        ElephantMascot(mood: planner.nextAction == .practice ? .resting : .welcoming)
                            .frame(width: 72, height: 66)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ElephantMascot(mood: planner.nextAction == .practice ? .resting : .welcoming)
                            .frame(width: 66, height: 60)
                        Text(next.title).font(HeadingFont.title).accessibilityAddTraits(.isHeader)
                    }
                }
                Text(next.detail).foregroundStyle(Palette.muted)
                Button(next.button) { startNextAction() }
                    .buttonStyle(PrimaryButton())
            }
            .modifier(Panel(fill: Palette.tint))

            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { dailyHeading; Spacer(); dailyGoalPicker }
                    VStack(alignment: .leading, spacing: 4) { dailyHeading; dailyGoalPicker }
                }
                if planner.effectiveGoal > 0 {
                    ProgressView(value: Double(min(planner.introducedToday, planner.effectiveGoal)),
                                 total: Double(planner.effectiveGoal))
                        .progressViewStyle(StudyProgressStyle())
                        .accessibilityLabel("پیشرفت هدف واژه‌های جدید")
                    Text("امروز \(fa(planner.introducedToday)) واژهٔ جدید تمرین شد. هدف: \(fa(planner.effectiveGoal)) واژه.")
                } else {
                    Text(goal == 0 ? "امروز به مرور اختصاص دارد." : "واژهٔ جدیدی باقی نمانده.")
                }
                Text("\(fa(planner.dueCards.count)) آمادهٔ مرور · \(fa(planner.scheduledToday - planner.dueCards.count)) مرورِ دیگر تا پایان امروز")
                if planner.dueCards.isEmpty, let nextDue = planner.nextDue {
                    Text("مرور بعدی: \(nextDue.formatted(.relative(presentation: .named)))")
                        .foregroundStyle(Palette.muted)
                }
                if deck != nil && planner.remainingStarter == 0 && planner.remainingNew > 0 {
                    Text("همهٔ واژه‌های مجموعهٔ آغازین را تمرین کرده‌ای.")
                        .foregroundStyle(Palette.muted)
                }
            }
            .font(PersianFont.subheadline)
            .modifier(Panel())

            masteryPanel(planner)

            if !planner.practicedCards.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("تمرین اختیاری").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
                    if let plan = planner.optionalPlan(for: planner.difficultCards) {
                        Button("تمرین واژه‌های دشوار", systemImage: "arrow.counterclockwise") { open(plan) }
                    }
                    if !planner.masteredCards.isEmpty {
                        Button("تمرین واژه‌های تثبیت‌شده", systemImage: "checkmark.circle") {
                            if let plan = planner.optionalPlan(for: planner.masteredCards.shuffled()) { open(plan) }
                        }
                    }
                    Button("آزمون چهارگزینه‌ای", systemImage: "checklist") {
                        startQuiz(with: planner.practicedCards)
                    }
                    Text("این تمرین‌ها زمان مرورهای برنامه‌ریزی‌شده را تغییر نمی‌دهند.")
                        .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                }
                .buttonStyle(.borderless)
                .modifier(Panel())
            }

            if deck == nil {
                Label("مجموعهٔ اصلی بارگیری نشد. واژه‌های شخصی در دسترس‌اند.", systemImage: "exclamationmark.circle")
            }
        }
    }

    private var dailyHeading: some View {
        Text("برنامهٔ امروز").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
    }

    private func todayMessage(for planner: StudyPlanner) -> (title: String, detail: String, button: String) {
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
            let title = planner.remainingNew == 0 ? "همهٔ واژه‌ها را تمرین کرده‌ای"
                : goal > 0 ? "به هدف امروز رسیدی" : "فعلاً مرورِ آماده‌ای نداری"
            let detail = planner.scheduledToday > 0 ? "مرورهای بعدی هنوز آماده نیستند. اگر دوست داری، کمی بیشتر تمرین کن."
                : "اگر دوست داری، واژه‌های آشنا را دوباره به یاد بیاور."
            let button = planner.difficultCards.isEmpty ? "تمرین بیشتر" : "تمرین واژه‌های دشوار"
            return (title, detail, button)
        case .setGoal:
            return ("آمادهٔ یادگیری هستی؟", "برای شروع، تعداد واژه‌های جدید روزانه را انتخاب کن.", "انتخاب هدف روزانه")
        case .browse:
            return ("مجموعه‌ات را بساز", "برای شروع تمرین، یک واژه با معنی فارسی اضافه کن.", "رفتن به واژه‌ها")
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

    private func startQuiz(with practiced: [Card]) {
        var random = SystemRandomNumberGenerator()
        let questions = QuizSession.makeQuestions(
            practicedCards: practiced, distractorPool: cards, limit: 10, using: &random
        )
        if questions.isEmpty {
            quizUnavailable = true
        } else {
            TapCue.open.play()
            quiz = QuizPresentation(session: QuizSession(questions: questions))
        }
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

    private func masteryPanel(_ planner: StudyPlanner) -> some View {
        let mastered = planner.masteredCards.count
        let total = planner.status.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("تسلط بر واژه‌ها").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
            Text("\(fa(mastered)) واژهٔ تثبیت‌شده از \(fa(total)) واژه").font(PersianFont.emphasis)
            ProgressView(value: Double(mastered), total: Double(max(1, total)))
                .progressViewStyle(StudyProgressStyle())
                .accessibilityLabel("سهم واژه‌های تثبیت‌شده")
            Text("\(fa(planner.introducedCount - mastered)) در حال یادگیری · \(fa(planner.remainingNew)) جدید")
                .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
        }
        .modifier(Panel())
    }

    private func progress(_ planner: StudyPlanner) -> some View {
        Page {
            Heading(title: "پیشرفت", subtitle: "تسلط با یادآوری درست در چند نوبتِ بافاصله به دست می‌آید.")
            masteryPanel(planner)
            VStack(alignment: .leading, spacing: 12) {
                Text("مرور").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
                Text("\(fa(planner.scheduledToday)) واژه برای مرور تا پایان امروز")
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
