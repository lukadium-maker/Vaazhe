import SwiftUI
import SwiftData

struct StudyView: View {
    @State private var session: StudySession
    @State private var failed = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(plan: StudyPlan) {
        _session = State(initialValue: StudySession(plan: plan))
    }

    var body: some View {
        NavigationStack {
            Page {
                if let card = session.currentCard {
                    let queue = session.queue
                    Text("\(fa(queue.cards.count)) کارت در صف").font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                    ProgressView(value: Double(queue.count), total: Double(queue.count + queue.cards.count))
                        .progressViewStyle(StudyProgressStyle())
                        .accessibilityLabel("پیشرفت تمرین")
                    CardContent(card: card, revealed: session.isRevealed).id(session.attemptID)
                    if session.isRevealed {
                        let currentAttempt = session.attemptID
                        Text("چقدر خوب به یاد آوردی؟").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
                        ForEach(Rating.allCases, id: \.self) { rating in
                            Button(rating.label) { record(rating, attemptID: currentAttempt) }
                                .buttonStyle(rating == .good ? AnyStudyButton.primary : .secondary)
                        }
                    } else {
                        Button("نمایش معنی") {
                            TapCue.reveal.play()
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { session.reveal() }
                        }
                        .buttonStyle(PrimaryButton())
                    }
                } else {
                    Heading(title: "تمرین تمام شد", subtitle: "آفرین! مرور بعدی به تثبیت واژه‌ها کمک می‌کند.")
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(fa(session.newCardsPracticed)) واژهٔ جدید تمرین شد")
                        Text("\(fa(session.queue.count)) مرور انجام شد")
                        Text("\(fa(session.queue.needsPractice.count)) واژه برای تمرین بیشتر")
                    }
                    .modifier(Panel(fill: Palette.tint))
                    Button("بازگشت به امروز") { dismiss() }.buttonStyle(PrimaryButton())
                }
            }
            .persianNavigationTitle("تمرین واژه‌ها")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("بستن") { dismiss() } } }
        }
        .alert("ذخیرهٔ مرور ممکن نشد", isPresented: $failed) { Button("باشه", role: .cancel) {} }
    }

    private func record(_ rating: Rating, attemptID: UUID) {
        do {
            try session.submit(rating, for: attemptID) { card, rating, id in
                try ReviewStore.record(card, rating: rating, attemptID: id, date: .now, in: context)
                (rating == .again ? TapCue.retry : .rate).play()
            }
        } catch { failed = true }
    }
}

private enum AnyStudyButton: ButtonStyle {
    case primary, secondary

    func makeBody(configuration: Configuration) -> some View {
        switch self {
        case .primary:
            PrimaryButton().makeBody(configuration: configuration)
        case .secondary:
            configuration.label.font(PersianFont.emphasis)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

struct QuizView: View {
    @State var quiz: QuizSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Page {
                if let question = quiz.currentQuestion {
                    Text("پرسش \(fa(quiz.index + 1)) از \(fa(quiz.questions.count))")
                        .font(PersianFont.subheadline)
                        .foregroundStyle(Palette.muted)
                    ProgressView(value: Double(quiz.index + (quiz.selected == nil ? 0 : 1)),
                                 total: Double(quiz.questions.count))
                        .progressViewStyle(StudyProgressStyle())
                        .accessibilityLabel("پیشرفت آزمون")
                    Text("معنی درست را انتخاب کن.").font(HeadingFont.section)
                    Text(question.card.word)
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityAddTraits(.isHeader)
                        .modifier(Panel())
                    VStack(spacing: 10) {
                        ForEach(question.choices, id: \.self) { choice in
                            answerButton(choice, correct: question.card.meaningFa)
                        }
                    }
                    if let selected = quiz.selected {
                        Text(selected == question.card.meaningFa ? "درست بود!" : "پاسخ درست: \(question.card.meaningFa)")
                            .font(HeadingFont.section)
                            .accessibilityAddTraits(.isHeader)
                        examples(for: question.card)
                        Button(quiz.index + 1 == quiz.questions.count ? "دیدن نتیجه" : "پرسش بعدی") {
                            TapCue.advance.play()
                            quiz.next()
                        }
                        .buttonStyle(PrimaryButton())
                    }
                } else {
                    QuizResultView(correct: quiz.correctCount, total: quiz.questions.count)
                    Button("بازگشت به امروز") { dismiss() }
                        .buttonStyle(PrimaryButton())
                }
            }
            .id(quiz.index)
            .persianNavigationTitle("آزمون چهارگزینه‌ای")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("بستن") { dismiss() } } }
        }
    }

    private func answerButton(_ choice: String, correct: String) -> some View {
        let isCorrect = quiz.selected != nil && choice == correct
        let isWrong = quiz.selected == choice && choice != correct
        return Button {
            guard quiz.selected == nil else { return }
            quiz.answer(choice)
            (choice == correct ? TapCue.correct : .retry).play()
        } label: {
            HStack {
                Text(choice)
                Spacer(minLength: 0)
                if isCorrect || isWrong {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle")
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .foregroundStyle(isCorrect ? Palette.sage : Palette.ink)
            .background(isCorrect ? Palette.tint : Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(quiz.selected != nil)
        .accessibilityValue(isCorrect ? "پاسخ درست" : isWrong ? "پاسخ نادرست" : "")
    }

    @ViewBuilder private func examples(for card: Card) -> some View {
        if !card.exampleEn.isEmpty || !card.exampleFa.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !card.exampleEn.isEmpty {
                    Text(card.exampleEn)
                        .font(.system(.title3, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .leftToRight)
                }
                if !card.exampleFa.isEmpty { Text(card.exampleFa).foregroundStyle(Palette.muted) }
            }
            .modifier(Panel())
        }
    }
}

private struct QuizResultView: View {
    let correct: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    private var perfect: Bool { total > 0 && correct == total }
    private var fraction: Double { total > 0 ? Double(correct) / Double(total) : 0 }
    private var score: String { "\(fa(correct)) پاسخ درست از \(fa(total))" }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(Palette.border, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: entered || reduceMotion ? fraction : 0)
                    .stroke(Palette.sage, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                Image(systemName: perfect ? "checkmark.seal.fill" : "checkmark")
                    .font(.system(size: 41, weight: .medium))
                    .foregroundStyle(Palette.sage)
                    .scaleEffect(entered || reduceMotion ? 1 : 0.72)
            }
            .frame(width: 102, height: 102)
            .frame(width: 174, height: 156)
            .overlay {
                if perfect && !reduceMotion { sparkleBurst }
            }
            .accessibilityHidden(true)

            Text(perfect ? "آفرین، بی‌نقص بود!" : "آزمون تمام شد")
                .font(HeadingFont.large)
                .accessibilityAddTraits(.isHeader)
            Text(score).font(PersianFont.meaning)
            Text(perfect ? "همهٔ واژه‌ها را درست به یاد آوردی." : "آفرین که تا پایان ادامه دادی.")
                .font(PersianFont.body)
                .foregroundStyle(Palette.muted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .modifier(Panel(fill: Palette.tint))
        .task {
            guard !entered else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.83)) {
                entered = true
            }
        }
    }

    private var sparkleBurst: some View {
        ZStack {
            ForEach(0..<8) { index in
                let angle = Double(index) * .pi / 4 + .pi / 8
                Image(systemName: "sparkle")
                    .font(.system(size: index.isMultiple(of: 2) ? 12 : 8, weight: .semibold))
                    .foregroundStyle(index.isMultiple(of: 2) ? Palette.celebrationGold : Palette.sage)
                    .phaseAnimator([0, 1, 2], trigger: entered) { sparkle, phase in
                        let distance = phase == 0 ? 49.0 : phase == 1 ? 73.0 : 83.0
                        sparkle
                            .offset(x: CGFloat(cos(angle) * distance), y: CGFloat(sin(angle) * distance))
                            .scaleEffect(phase == 1 ? 1 : 0.5)
                            .opacity(phase == 1 ? 1 : 0)
                    } animation: { phase in
                        phase == 1 ? .easeOut(duration: 0.28).delay(0.16) : .easeIn(duration: 0.4)
                    }
            }
        }
        .allowsHitTesting(false)
    }
}
