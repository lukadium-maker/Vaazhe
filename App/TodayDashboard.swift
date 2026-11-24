import SwiftUI

struct TodayWelcomeCard: View {
    let title: String
    let detail: String
    let button: String?
    let completed: Bool
    let start: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var message: some View {
        VStack(alignment: .leading, spacing: completed ? 3 : 5) {
            Text(title)
                .font(completed ? HeadingFont.section : HeadingFont.title)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(PersianFont.body)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: completed ? 8 : 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    ElphyMascotView(mood: mascotMood, size: 128)
                    message
                }
            } else {
                WelcomeCardRow {
                    message.fixedSize(horizontal: false, vertical: true)
                    ElphyMascotView(mood: mascotMood, size: nil)
                }
            }
            if let button {
                Button(button, action: start)
                    .buttonStyle(PrimaryButton())
            }
        }
        .modifier(Panel(fill: Palette.tint, padding: completed ? 14 : 16))
    }
    private var mascotMood: ElphyMascotView.Mood {
        completed ? .celebrating : .welcome
    }
}

private struct WelcomeCardRow: Layout {
    private let spacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 318
        let mascot = mascotSize(for: width)
        let messageWidth = max(0, width - mascot - spacing)
        let message = subviews[0].sizeThatFits(ProposedViewSize(width: messageWidth, height: nil))
        return CGSize(width: width, height: max(message.height, mascot))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let mascot = mascotSize(for: bounds.width)
        let messageWidth = max(0, bounds.width - mascot - spacing)
        // SwiftUI mirrors these positions in a right-to-left environment.
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: messageWidth, height: nil))
        subviews[1].place(at: CGPoint(x: bounds.maxX - mascot / 2, y: bounds.midY), anchor: .center,
                          proposal: ProposedViewSize(width: mascot, height: mascot))
    }

    private func mascotSize(for width: CGFloat) -> CGFloat {
        // Spend spare space on the mascot while keeping room for the Persian message.
        min(128, max(0, width - spacing) / 2, max(104, width - spacing - 174))
    }
}

#Preview("Elphy mascot poses") {
    Page {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132))], spacing: 20) {
            ForEach(ElphyMascotView.Mood.allCases, id: \.self) { mood in
                VStack(spacing: 6) {
                    ElphyMascotView(mood: mood, size: 104, decorative: false)
                    Text(mood.accessibilityLabel).font(PersianFont.subheadline)
                }
            }
        }
    }
    .environment(\.layoutDirection, .rightToLeft)
}

struct DailyProgressRing: View {
    let progress: DailyLearningProgress
    let celebration: UUID?
    @ScaledMetric(relativeTo: .body) private var diameter = 84.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sparkleVisible = false
    @State private var playedCelebration: UUID?

    private var count: Int { progress.count }
    private var target: Int { progress.target }

    var body: some View {
        ZStack {
            Circle().strokeBorder(Palette.goalTrack, lineWidth: 7)
            if target > 0 {
                Circle()
                    .inset(by: 3.5)
                    .trim(from: 0, to: progress.fraction)
                    .stroke(Palette.sage, style: StrokeStyle(lineWidth: sparkleVisible ? 9 : 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(progress.fraction == 0 ? 0 : 1)
                VStack(spacing: 0) {
                    Text(fa(count))
                        .font(PersianFont.meaning)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(count)))
                    Text("از \(fa(target))").font(PersianFont.subheadline).foregroundStyle(Palette.muted)
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(target)))
                }
            } else {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title2)
                    .foregroundStyle(Palette.sage)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: progress)
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topTrailing) {
            if sparkleVisible {
                Image(systemName: "sparkle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.celebrationGold)
                    .padding(4)
                    .background(Palette.paper, in: Circle())
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("هدف واژه‌های جدید")
        .accessibilityValue(target > 0 ? "\(fa(count)) از \(fa(target)) واژه" : "بدون هدف واژهٔ جدید")
        .task(id: celebration) {
            sparkleVisible = false
            guard let celebration, celebration != playedCelebration, !reduceMotion else { return }
            playedCelebration = celebration
            withAnimation(.easeOut(duration: 0.2)) { sparkleVisible = true }
            do {
                try await Task.sleep(for: .milliseconds(700))
                withAnimation(.easeOut(duration: 0.22)) { sparkleVisible = false }
            } catch {
                sparkleVisible = false
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { sparkleVisible = false }
        }
    }
}
