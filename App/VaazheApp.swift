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
    let deck: [Card]?
    @Query private var personal: [PersonalCard]
    @Query private var states: [ReviewState]
    @Query(sort: \ReviewEvent.date, order: .reverse) private var events: [ReviewEvent]
    @AppStorage("dailyGoal") private var goal = 5
    @State private var session: StudyPlan?
    @State private var quiz: QuizPresentation?
    @State private var quizUnavailable: String?

    private var cards: [Card] { (deck ?? []) + personal.map(\.card) }
    private var stateByID: [String: ReviewState] { Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0) }) }

    var body: some View {
        let index = stateByID
        TabView {
            Tab("امروز", systemImage: "sun.max") {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    today(at: timeline.date, states: index)
                }
            }
            Tab("واژه‌ها", systemImage: "rectangle.on.rectangle") {
                CollectionView(bundled: deck ?? [], personal: personal, states: index)
            }
            Tab("پیشرفت", systemImage: "chart.bar.xaxis") {
                progress(states: index)
            }
            Tab("تنظیمات", systemImage: "gearshape") {
                SettingsView(states: states, events: events)
            }
        }
        .sheet(item: $session) { StudyView(plan: $0) }
        .sheet(item: $quiz) { QuizView(quiz: $0.session) }
        .alert("آزمون چهارگزینه‌ای", isPresented: Binding(
            get: { quizUnavailable != nil },
            set: { if !$0 { quizUnavailable = nil } }
        ), presenting: quizUnavailable) { _ in
            Button("باشه", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func today(at date: Date, states: [String: ReviewState]) -> some View {
        let planner = StudyPlanner(
            cards: cards,
            progress: states.mapValues { .init(introduced: $0.introduced, due: $0.due) },
            goal: goal,
            at: date,
            calendar: .current
        )
        let introduced = planner.introducedCount
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fa_IR")
        formatter.calendar = Calendar(identifier: .persian)
        formatter.dateFormat = "EEEE d MMMM y"

        return Page {
            HStack {
                Text("واژه").font(HeadingFont.title).foregroundStyle(Palette.sage)
                Spacer()
                Text(formatter.string(from: date)).font(PersianFont.subheadline).foregroundStyle(Palette.muted)
            }

            VStack(alignment: .leading, spacing: 14) {
                let hasPractice = !planner.newCards.isEmpty || !planner.dueCards.isEmpty
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        todayGreeting(hasPractice: hasPractice).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        ElephantMascot(finished: !hasPractice).frame(width: 88, height: 88)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ElephantMascot(finished: !hasPractice).frame(width: 88, height: 88)
                        todayGreeting(hasPractice: hasPractice)
                    }
                }
                HStack {
                    Text("هدف روزانه").font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                        .accessibilityHidden(true)
                    Spacer()
                    dailyGoalPicker
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { metric(planner.newCards.count, "واژهٔ جدید"); metric(planner.dueCards.count, "آمادهٔ مرور") }
                    VStack(alignment: .leading, spacing: 12) { metric(planner.newCards.count, "واژهٔ جدید"); metric(planner.dueCards.count, "آمادهٔ مرور") }
                }
                .padding(.vertical, 8)
                if let plan = planner.dailyPlan {
                    Button("شروع تمرین") {
                        TapCue.open.play()
                        session = plan
                    }
                    .buttonStyle(PrimaryButton())
                } else {
                    Text("فعلاً واژه‌ای برای تمرین آماده نیست.").foregroundStyle(Palette.muted)
                }
            }
            .modifier(Panel(fill: Palette.tint))

            Button(action: startQuiz) {
                Label("آزمون چهارگزینه‌ای", systemImage: "checklist")
                    .font(HeadingFont.section)
                    .frame(minHeight: 44)
                    .modifier(Panel())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.sage)

            VStack(alignment: .leading, spacing: 12) {
                Text("پیشرفت مجموعه").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
                ProgressView(value: Double(introduced), total: Double(max(1, cards.count)))
                    .progressViewStyle(StudyProgressStyle())
                    .accessibilityLabel("واژه‌های دیده‌شده")
                Text("\(fa(introduced)) از \(fa(cards.count)) واژه را تمرین کرده‌ای.")
                    .font(PersianFont.subheadline).foregroundStyle(Palette.muted)
            }
            .modifier(Panel())

            if deck == nil {
                Label("مجموعهٔ اصلی بارگذاری نشد. واژه‌های شخصی همچنان در دسترس‌اند.", systemImage: "exclamationmark.circle")
            }
        }
    }

    private func todayGreeting(hasPractice: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("سلام!")
            Text(hasPractice ? "آماده‌ای تمرین کنیم؟" : "فعلاً وقت استراحت است")
        }
        .font(HeadingFont.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private struct QuizPresentation: Identifiable {
        let id = UUID()
        let session: QuizSession
    }

    private func startQuiz() {
        let practicedIDs = Set(states.map(\.cardID))
        let practiced = cards.filter { practicedIDs.contains($0.id) }
        guard !practiced.isEmpty else {
            quizUnavailable = "برای شروع آزمون، اول دست‌کم یک واژه را در تمرین مرور کن."
            return
        }

        var random = SystemRandomNumberGenerator()
        let questions = QuizSession.makeQuestions(
            practicedCards: practiced, distractorPool: cards, limit: 10, using: &random
        )
        if questions.isEmpty {
            quizUnavailable = "برای ساختن چهار گزینهٔ متفاوت، واژه‌های کافی در دسترس نیست."
        } else {
            TapCue.open.play()
            quiz = QuizPresentation(session: QuizSession(questions: questions))
        }
    }

    private var dailyGoalPicker: some View {
        let choices = Set([0, 5, 10, 15, 20, 25, 30, goal]).sorted()
        return Picker(selection: $goal) {
            ForEach(choices, id: \.self) { count in
                Text(count == 0 ? "فقط مرور" : "\(fa(count)) واژهٔ جدید").tag(count)
            }
        } label: {
            Text("هدف روزانه")
        } currentValueLabel: {
            Text(goal == 0 ? "فقط مرور" : "\(fa(goal)) واژهٔ جدید")
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
    }

    private func progress(states: [String: ReviewState]) -> some View {
        let active = cards.compactMap { states[$0.id] }
        let strong = active.filter { $0.streak >= 3 }.count
        return Page {
            Heading(title: "پیشرفت", subtitle: "مرورهای منظم، مسیر یادگیری را نشان می‌دهند.")
            VStack(alignment: .leading, spacing: 16) {
                metric(active.count, "واژهٔ دیده‌شده")
                ProgressView(value: Double(active.count), total: Double(max(1, cards.count)))
                    .progressViewStyle(StudyProgressStyle())
                    .accessibilityLabel("سهم واژه‌های دیده‌شده از مجموعه")
                Divider()
                metric(active.count - strong, "در حال یادگیری")
                metric(strong, "با عملکرد قوی")
                metric(events.count, "مرور انجام‌شده")
            }
            .modifier(Panel())
            Text("فعالیت اخیر").font(HeadingFont.title).accessibilityAddTraits(.isHeader)
            if events.isEmpty { Text("پس از اولین تمرین، فعالیتت اینجا دیده می‌شود.").foregroundStyle(Palette.muted) }
            ForEach(events.prefix(10)) { event in
                HStack {
                    Text(event.word).font(.system(.headline, design: .serif))
                    Spacer()
                    Text(event.date, format: .relative(presentation: .named)).font(PersianFont.subheadline)
                }
                .modifier(Panel())
            }
        }
    }

    private func metric(_ count: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(fa(count)).font(PersianFont.meaning).monospacedDigit()
            Text(label).font(PersianFont.subheadline).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
