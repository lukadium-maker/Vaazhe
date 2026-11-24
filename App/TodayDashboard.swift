import SwiftUI

struct TodayHeader: View {
    let date: Date
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize = 31.0

    var body: some View {
        let persianDate = Date.FormatStyle(locale: Locale(identifier: "fa_IR"),
                                           calendar: Calendar(identifier: .persian))
        let dateBlock = VStack(alignment: .leading, spacing: 0) {
            Text(date.formatted(persianDate.weekday(.wide)))
                .font(DashboardFont.section)
            Text(date.formatted(persianDate.day().month(.wide).year()))
                .font(DashboardFont.metadata)
                .foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)

        let wordmark = Text("Elphy")
            .font(.system(size: wordmarkSize, weight: .bold, design: .rounded))
            .foregroundStyle(Palette.sage)
            .environment(\.layoutDirection, .leftToRight)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DashboardMetrics.padding) {
                dateBlock.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                wordmark.fixedSize(horizontal: true, vertical: false)
            }
            VStack(spacing: DashboardMetrics.micro) {
                dateBlock.frame(maxWidth: .infinity, alignment: .leading)
                wordmark.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

struct TodayWelcomeCard: View {
    let title: String
    let detail: String
    let button: String?
    let completed: Bool
    let start: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var message: some View {
        VStack(alignment: .leading, spacing: DashboardMetrics.micro) {
            Text(title)
                .font(DashboardFont.hero)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(DashboardFont.body)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardMetrics.inline) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DashboardMetrics.inline) {
                    ElphyMascotView(mood: mascotMood, size: 108)
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
                    .buttonStyle(PrimaryButton(compact: true))
            }
        }
        .modifier(Panel(fill: Palette.tint, padding: DashboardMetrics.group, radius: DashboardMetrics.cardRadius))
    }
    private var mascotMood: ElphyMascotView.Mood {
        completed ? .celebrating : .welcome
    }
}

private struct WelcomeCardRow: Layout {
    private let spacing = DashboardMetrics.group

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
        min(112, max(0, width - spacing) / 2, max(88, width - spacing - 174))
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

struct DailyProgressMeter: View {
    let progress: DailyLearningProgress
    let celebration: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sparkleVisible = false
    @State private var playedCelebration: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardMetrics.inline) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DashboardMetrics.inline) {
                    title.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    count.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: DashboardMetrics.micro) {
                    title
                    count
                }
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(Palette.goalTrack)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Palette.sage)
                            .frame(width: geometry.size.width * progress.fraction)
                    }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: progress)
        .overlay(alignment: .bottomTrailing) {
            if sparkleVisible {
                Image(systemName: "sparkle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.celebrationGold)
                    .padding(4)
                    .background(Palette.paper, in: Circle())
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.fraction == 1 ? "هدف امروز کامل شد" : "یادگیری واژه‌های جدید")
        .accessibilityValue("\(fa(progress.count)) از \(fa(progress.target)) واژه")
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

    private var title: some View {
        Text(progress.fraction == 1 ? "هدف امروز کامل شد" : "یادگیری واژه‌های جدید")
            .font(DashboardFont.action)
    }

    private var count: some View {
        Text("\(fa(progress.count)) از \(fa(progress.target)) واژه")
            .font(DashboardFont.metadata)
            .foregroundStyle(Palette.sage)
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(progress.count)))
    }
}
