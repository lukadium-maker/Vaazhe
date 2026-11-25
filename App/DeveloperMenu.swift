#if DEBUG
import SwiftData
import SwiftUI

struct DeveloperMenu: View {
    let deck: [Card]
    let stories: [ReadingStory]
    let readingContainer: ModelContainer?
    let startSimulation: (Bool) throws -> Void
    let onReadingChange: () -> Void
    let onProgressReset: () -> Void

    @Environment(AppClock.self) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("dailyGoal") private var goal = DailyGoal.defaultValue
    @Query private var personal: [PersonalCard]
    @Query private var states: [ReviewState]
    @Query private var events: [ReviewEvent]
    @State private var selectedStory: ReadingStory?
    @State private var completedReadingDates: [Date] = []
    @State private var assignmentDay: ReadingDay?
    @State private var pending: Confirmation?
    @State private var error: String?
    @State private var jumpDate: Date?
    @State private var missedDays = 3

    private enum Confirmation: String, Identifiable {
        case start = "Start time simulation"
        case fresh = "Start a fresh simulation"
        case day = "Reset simulated daily progress"
        case all = "Reset all simulated learning progress"
        case exit = "Exit simulation and restore real date"

        var id: Self { self }

        var detail: String {
            switch self {
            case .start: "Choose the initial progress for your isolated simulation profile."
            case .fresh: "This replaces the current simulated profile with an empty one."
            case .day: "Restore progress to before this day’s first simulated learning action. The daily story assignment is kept. Playground rounds played on this day are removed."
            case .all: "Remove all simulated reviews, reading progress, daily assignments and Playground results. Personal vocabulary is kept."
            case .exit: "Your simulated profile will be discarded and your real learning progress will reopen."
            }
        }
    }

    private struct QueueEntry: Identifiable {
        let id: String
        let word: String
        let due: Date
    }

    private struct Diagnostics {
        let planner: StudyPlanner
        let queue: [QueueEntry]
        let streak: LearningStreak
        let words: [String]
        let vocabularyComplete: Bool
        let readingComplete: Bool
    }

    var body: some View {
        NavigationStack {
            Form {
                if let simulation = clock.simulation {
                    let date = simulation.date
                    let diagnostics = diagnostics(at: date, calendar: simulation.calendar)
                    timeControls(simulation)
                    learningControls(simulation, diagnostics: diagnostics)
                    diagnosticRows(simulation, diagnostics: diagnostics)
                    playgroundDiagnostics(simulation)
                    dataControls
                } else {
                    Section("Time Simulation") {
                        Toggle("Simulation Mode", isOn: simulationToggle)
                        TimelineView(.periodic(from: clock.systemNow, by: 1)) { _ in
                            LabeledContent("Actual system date", value: timestamp(clock.systemNow))
                        }
                        LabeledContent("Simulated date", value: "Off")
                        if let error = clock.simulationRecoveryError {
                            Text("Could not resume the previous simulation. \(error)")
                                .font(.footnote)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle("Developer Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog(pending?.rawValue ?? "", isPresented: Binding(
                get: { pending != nil }, set: { if !$0 { pending = nil } }
            ), titleVisibility: .visible, presenting: pending) { action in
                confirmationButtons(action)
            } message: { action in
                Text(action.detail)
            }
            .alert("Simulation Error", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
            .task(id: clock.simulation?.day.key) { refreshReading() }
        }
        .font(.body)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.calendar, clock.calendar)
        .environment(\.timeZone, clock.calendar.timeZone)
    }

    private var simulationToggle: Binding<Bool> {
        Binding(get: { clock.isSimulating }, set: { pending = $0 ? .start : .exit })
    }

    private func timeControls(_ simulation: DeveloperSimulation) -> some View {
        Section {
            Toggle("Simulation Mode", isOn: simulationToggle)
            TimelineView(.periodic(from: clock.systemNow, by: 1)) { _ in
                LabeledContent("Actual system date", value: timestamp(clock.systemNow, calendar: .current))
            }
            LabeledContent("Simulated date and time", value: timestamp(simulation.date))
            LabeledContent("Simulated learning day", value: String(simulation.learningDay))
            Button {
                perform { try simulation.move(days: 1) }
            } label: {
                Label("Next Day", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("simulation-next-day")
            Button("Previous Day") { perform { try simulation.move(days: -1) } }
            Button("Advance 7 Days") { perform { try simulation.move(days: 7) } }
            Button("Advance 30 Days") { perform { try simulation.move(days: 30) } }
            DatePicker("Specific Date and Time", selection: Binding(
                get: { jumpDate ?? simulation.date }, set: { jumpDate = $0 }
            ))
            Button("Jump to a Specific Date") {
                guard let jumpDate else { return }
                perform {
                    try simulation.jump(to: jumpDate)
                    self.jumpDate = nil
                }
            }
            .disabled(jumpDate == nil)
            Button("Simulate Midnight") { perform { try simulation.midnight() } }
            Button("Restore Real Date") { pending = .exit }
        } header: {
            Text("Time Simulation")
        } footer: {
            Text("Moving backward keeps saved progress. Learning actions before saved activity are blocked until you move forward or reset progress.")
        }
    }

    private func learningControls(_ simulation: DeveloperSimulation, diagnostics: Diagnostics) -> some View {
        Section("Learning Simulation") {
            Button("Complete Recommended Session") {
                perform {
                    guard let plan = diagnostics.planner.dailyPlan else { return }
                    var session = StudySession(plan: plan)
                    while session.currentCard != nil {
                        session.reveal()
                        let attempt = session.attemptID
                        try session.submit(.good, for: attempt) { card, rating, id in
                            try clock.record(card, rating: rating, attemptID: id, in: context)
                        }
                    }
                }
            }
            .disabled(diagnostics.planner.dailyPlan == nil)
            Button("Simulate Successful Recall") { simulateRecall(.good, planner: diagnostics.planner) }
                .disabled(diagnostics.planner.dueCards.isEmpty)
            Button("Simulate Unsuccessful Recall") { simulateRecall(.again, planner: diagnostics.planner) }
                .disabled(diagnostics.planner.dueCards.isEmpty)
            Button("Complete Today’s Reading") {
                perform {
                    guard let selectedStory, assignmentDay == simulation.day else { return }
                    try clock.complete(selectedStory, score: selectedStory.questions.count, in: context)
                    refreshReading()
                    onReadingChange()
                }
            }
            .disabled(selectedStory == nil || assignmentDay != simulation.day || diagnostics.readingComplete)
            Button("Simulate a Missed Day") { perform { try simulation.move(days: 1) } }
            Stepper("Consecutive missed days: \(missedDays)", value: $missedDays, in: 2...30)
            Button("Simulate \(missedDays) Missed Days") { perform { try simulation.move(days: missedDays) } }
            NavigationLink("Inspect Review Queue") {
                List(diagnostics.queue) { entry in
                    LabeledContent(entry.word, value: timestamp(entry.due))
                }
                .overlay {
                    if diagnostics.queue.isEmpty {
                        ContentUnavailableView("Review Queue Is Empty", systemImage: "clock")
                    }
                }
                .navigationTitle("Review Queue")
            }
        }
    }

    private func simulateRecall(_ rating: Rating, planner: StudyPlanner) {
        perform {
            guard let card = planner.dueCards.first else { return }
            try clock.record(card, rating: rating, attemptID: UUID(), in: context)
        }
    }

    private func diagnosticRows(_ simulation: DeveloperSimulation, diagnostics: Diagnostics) -> some View {
        Section("Diagnostics") {
            LabeledContent("Effective date", value: timestamp(simulation.date))
            LabeledContent("Learning day identifier", value: simulation.day.key)
            LabeledContent("Today’s vocabulary", value: diagnostics.words.isEmpty ? "None" : diagnostics.words.joined(separator: ", "))
            LabeledContent("Learned words", value: String(diagnostics.planner.introducedCount))
            LabeledContent("Due for review", value: String(diagnostics.planner.dueCards.count))
            let upcoming = diagnostics.queue.filter { $0.due > simulation.date }
            LabeledContent("Recommended reviews", value: String(diagnostics.planner.recommendedReviews.count))
            LabeledContent("Additional due reviews", value: String(diagnostics.planner.additionalDueCount))
            LabeledContent("Recommended new words", value: String(diagnostics.planner.newCards.count))
            LabeledContent("Recovery mode", value: diagnostics.planner.isRecoveryDay ? "On" : "Off")
            LabeledContent("Upcoming reviews", value: String(upcoming.count))
            LabeledContent("Current streak", value: String(diagnostics.streak.current))
            LabeledContent("Longest streak", value: String(diagnostics.streak.longest))
            LabeledContent("Today’s story", value: assignmentDay == simulation.day ? selectedStory?.titleEn ?? "None" : "Loading…")
            LabeledContent("Vocabulary complete", value: diagnostics.vocabularyComplete ? "Yes" : "No")
            LabeledContent("Reading complete", value: diagnostics.readingComplete ? "Yes" : "No")
            ForEach(upcoming.prefix(5)) { entry in
                LabeledContent(entry.word, value: timestamp(entry.due))
            }
        }
    }

    private func playgroundDiagnostics(_ simulation: DeveloperSimulation) -> some View {
        let cards = deck + personal.map(\.card)
        let progress = Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0.progress) })
        let recalls = events.compactMap(\.recall)
        let planner = StudyPlanner(cards: cards, progress: progress, goal: DailyGoal.preferred(goal), at: simulation.date,
                                   calendar: simulation.calendar, recalls: recalls)
        let history = (try? PracticeStore.results(in: simulation.container.mainContext)) ?? []
        let engine = PracticeEngine(cards: cards, progress: progress, difficult: Set(planner.difficultCards.map(\.id)),
                                    history: history, date: simulation.date, calendar: simulation.calendar)
        return Section("Vocabulary Playground") {
            LabeledContent("Practice date", value: timestamp(simulation.date))
            LabeledContent("Eligible words", value: String(engine.encountered.count))
            Text(engine.encountered.map(\.word).sorted().joined(separator: ", ")).font(.footnote)
            ForEach(PracticeGame.allCases) { game in
                let round = sampleRound(engine, game: game)
                let stats = PracticeStatistics(results: history.filter { $0.game == game && $0.date <= simulation.date })
                LabeledContent(game.rawValue.capitalized, value: "\(round.count) generated · \(stats.results.count) rounds · \(stats.questions) answers")
                if !round.isEmpty {
                    Text("Weak-word sample: \(round.map { $0.card.word }.joined(separator: ", "))").font(.footnote)
                }
            }
        }
    }

    private func sampleRound(_ engine: PracticeEngine, game: PracticeGame) -> [PracticeQuestion] {
        var random = SystemRandomNumberGenerator()
        return engine.round(for: game, mode: .weak, difficulty: .medium, using: &random)
    }

    private var dataControls: some View {
        Section("Data Management") {
            Button("Start a Fresh Simulation", role: .destructive) { pending = .fresh }
            Button("Reset Simulated Daily Progress", role: .destructive) { pending = .day }
            Button("Reset All Simulated Learning Progress", role: .destructive) { pending = .all }
            Button("Exit Simulation", role: .destructive) { pending = .exit }
        }
    }

    @ViewBuilder private func confirmationButtons(_ action: Confirmation) -> some View {
        switch action {
        case .start:
            Button("Copy Current Progress") { perform { try startSimulation(true) } }
            Button("Start Fresh Profile") { perform { try startSimulation(false) } }
        case .fresh:
            Button("Replace Simulation", role: .destructive) { perform { try startSimulation(false) } }
        case .day, .all:
            Button("Reset Progress", role: .destructive) {
                perform {
                    if action == .day {
                        try clock.simulation?.resetDay()
                    } else {
                        try clock.simulation?.resetProgress()
                    }
                    refreshReading()
                    onProgressReset()
                }
            }
        case .exit:
            Button("Exit and Restore", role: .destructive) {
                perform {
                    try clock.simulation?.stop()
                    clock.simulation = nil
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func diagnostics(at date: Date, calendar: Calendar) -> Diagnostics {
        let cards = deck + personal.map(\.card)
        let progress = Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0.progress) })
        let recalls = events.compactMap(\.recall)
        let planner = StudyPlanner(cards: cards, progress: progress, goal: DailyGoal.preferred(goal), at: date,
                                   calendar: calendar, recalls: recalls)
        let entries: [QueueEntry] = cards.compactMap { card in
            guard let state = progress[card.id] else { return nil }
            return QueueEntry(id: card.id, word: card.word, due: state.due)
        }
        let queue = entries.sorted {
            if $0.due == $1.due { return $0.id < $1.id }
            return $0.due < $1.due
        }
        let today = cards.filter { card in
            progress[card.id].map { $0.introduced <= date && calendar.isDate($0.introduced, inSameDayAs: date) } == true
        }
        let words = (today + planner.newCards).map(\.word)
        let readingDates = (try? clock.simulation?.readingCompletions()) ?? []
        let streak = LearningStreak(activity: events.map(\.date) + readingDates.map(\.date), at: date, calendar: calendar)
        let readingComplete = assignmentDay == clock.simulation?.day && completedReadingDates.contains {
            $0 <= date && calendar.isDate($0, inSameDayAs: date)
        }
        return Diagnostics(planner: planner, queue: queue, streak: streak, words: words,
                           vocabularyComplete: planner.completedCoreToday,
                           readingComplete: readingComplete)
    }

    private func refreshReading() {
        guard let simulation = clock.simulation, let readingContainer else { return }
        perform {
            let date = simulation.date
            let calendar = simulation.calendar
            let readingContext = readingContainer.mainContext
            let records = try ReadingStore.records(in: readingContext)
            // Fetch from the context so a reset is visible before SwiftUI refreshes its queries.
            let states = try context.fetch(FetchDescriptor<ReviewState>())
            let progress = Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0.progress) })
            let recalls = try context.fetch(FetchDescriptor<ReviewEvent>()).compactMap(\.recall)
            let planner = StudyPlanner(cards: deck + personal.map(\.card), progress: progress, goal: DailyGoal.preferred(goal),
                                       at: date, calendar: calendar, recalls: recalls)
            let id = try ReadingStore.dailyStoryID(stories: stories, planner: planner, progress: progress, recalls: recalls,
                                                   records: records, at: date, calendar: calendar, in: readingContext)
            selectedStory = stories.first { $0.id == id }
            completedReadingDates = try simulation.readingCompletions().filter { $0.storyID == id }.map(\.date)
            assignmentDay = simulation.day
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { self.error = error.localizedDescription }
    }

    private func timestamp(_ date: Date, calendar: Calendar? = nil) -> String {
        let calendar = calendar ?? clock.calendar
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
#endif
