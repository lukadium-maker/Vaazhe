import SwiftUI
import UIKit

enum Palette {
    static let paper = adaptive(0xF7F3EB, 0x211F1B)
    static let ink = adaptive(0x292724, 0xF7F0E4)
    static let muted = adaptive(0x625E54, 0xC3BBAD)
    static let card = adaptive(0xEFE7DB, 0x312D26)
    static let border = adaptive(0xDED5C6, 0x524A40)
    static let goalTrack = adaptive(0xDFE1D7, 0x444B40)
    static let learningProgress = adaptive(0x829477, 0x788F72)
    static let mascotGreen = adaptive(0x254936, 0x88B39A)
    static let celebrationGold = adaptive(0x9A7138, 0xDAB277)
    static let sage = adaptive(0x465741, 0xBAC9AF)
    static let tint = adaptive(0xE1E7DA, 0x323C30)
    static let buttonText = adaptive(0xFFFFFF, 0x212B20)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

func fa(_ number: Int) -> String {
    number.formatted(.number.locale(Locale(identifier: "fa_IR")))
}

struct ElphyMascotView: View {
    enum Mood: String, CaseIterable {
        case welcome, studying, thinking, celebrating, encouraging, sleepy, reading, proud

        var assetName: String {
            switch self {
            case .encouraging, .sleepy: "elphy_mark_neutral"
            case .welcome: "elphy_mark_welcoming"
            case .studying, .thinking, .reading: "elphy_mark_focused"
            case .celebrating, .proud: "elphy_mark_proud"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .welcome: "الفی خوش‌آمد می‌گوید"
            case .studying: "الفی در حال تمرین واژه‌هاست"
            case .thinking: "الفی فکر می‌کند"
            case .celebrating: "الفی جشن می‌گیرد"
            case .encouraging: "الفی تشویقت می‌کند"
            case .sleepy: "الفی استراحت می‌کند"
            case .reading: "الفی کتاب می‌خواند"
            case .proud: "الفی به پیشرفتت افتخار می‌کند"
            }
        }
    }

    let mood: Mood
    let size: CGFloat?
    var animatesAppearance = false
    var decorative = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Image(mood.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Palette.mascotGreen)
                .id(mood.assetName)
                .transition(reduceMotion ? .identity : .opacity)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: mood.assetName)
        .opacity(animatesAppearance && !appeared && !reduceMotion ? 0.76 : 1)
        .onAppear {
            guard animatesAppearance, !appeared else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                appeared = true
            }
        }
        .accessibilityLabel(mood.accessibilityLabel)
        .accessibilityHidden(decorative)
        .allowsHitTesting(false)
    }
}

struct Page<Content: View>: View {
    enum Density { case standard, compact }

    private let avoidsFloatingTabBar: Bool
    private let readingPosition: Binding<Double>?
    private let density: Density
    let content: Content
    @State private var tabBarOverlap: CGFloat?
    init(avoidsFloatingTabBar: Bool = false, readingPosition: Binding<Double>? = nil,
         density: Density = .standard,
         @ViewBuilder content: () -> Content) {
        self.avoidsFloatingTabBar = avoidsFloatingTabBar
        self.readingPosition = readingPosition
        self.density = density
        self.content = content()
    }

    var body: some View {
        let scrollView = ScrollView {
            VStack(alignment: .leading, spacing: density == .compact ? DashboardMetrics.padding : 22) { content }
                .frame(maxWidth: 560)
                .padding(.horizontal, density == .compact ? 20 : 24)
                .padding(.top, density == .compact ? DashboardMetrics.inline : 24)
                .padding(.bottom, density == .compact ? 20 : 24)
                .frame(maxWidth: .infinity)
        }
        Group {
            if let readingPosition {
                scrollView.modifier(ReadingScrollMemory(position: readingPosition))
            } else if avoidsFloatingTabBar, #available(iOS 26, *) {
                // Page padding already leaves breathing room below the final control.
                // Reserve the additional space inside the scrollable content.
                scrollView.contentMargins(.bottom, tabBarOverlap ?? 44, for: .scrollContent)
            } else {
                scrollView
            }
        }
        .background {
            if avoidsFloatingTabBar, #available(iOS 26, *) {
                TabBarOverlapReader { tabBarOverlap = $0 }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
    }
}

private struct ReadingScrollMemory: ViewModifier {
    @Binding var position: Double
    @State private var initialPosition: Double
    @State private var currentPosition: Double

    init(position: Binding<Double>) {
        _position = position
        _initialPosition = State(initialValue: position.wrappedValue)
        _currentPosition = State(initialValue: position.wrappedValue)
    }

    func body(content: Content) -> some View {
        content
            .defaultScrollAnchor(UnitPoint(x: 0.5, y: initialPosition), for: .initialOffset)
            .onScrollGeometryChange(for: Double.self) { geometry in
                let extent = geometry.contentSize.height - geometry.containerSize.height
                    + geometry.contentInsets.top + geometry.contentInsets.bottom
                guard extent > 0 else { return 0 }
                let fraction = (geometry.contentOffset.y + geometry.contentInsets.top) / extent
                return min(1, max(0, Double(fraction) * 100).rounded() / 100)
            } action: { _, value in
                currentPosition = value
            }
            .onDisappear { position = currentPosition }
    }
}

// Measure in the same window coordinate space as the native tab bar. The reader
// sits outside the scroll-content margin so the measurement excludes its correction.
private struct TabBarOverlapReader: UIViewRepresentable {
    let onChange: (CGFloat?) -> Void

    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ view: Probe, context: Context) {
        view.onChange = onChange
        view.measureAfterLayout()
    }

    final class Probe: UIView {
        var onChange: ((CGFloat?) -> Void)?
        private var lastOverlap: CGFloat?
        private var measurementPending = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            measureAfterLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            measureAfterLayout()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            measureAfterLayout()
        }

        func measureAfterLayout() {
            guard !measurementPending else { return }
            measurementPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                measurementPending = false
                guard let window, !bounds.isEmpty else { return }
                let overlap = tabBarOverlap(in: window)
                guard overlap != lastOverlap else { return }
                lastOverlap = overlap
                onChange?(overlap)
            }
        }

        private func tabBarOverlap(in window: UIWindow) -> CGFloat? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   let tabs = (controller as? UITabBarController) ?? controller.tabBarController,
                   tabs.tabBar.window === window, !tabs.tabBar.bounds.isEmpty {
                    let bar = tabs.tabBar
                    guard !bar.isHidden, bar.alpha > 0 else { return 0 }
                    let viewport = convert(safeAreaLayoutGuide.layoutFrame, to: window)
                    let occlusion = bar.convert(bar.bounds, to: window)
                    guard viewport.intersects(occlusion) else { return 0 }
                    return ceil(max(0, viewport.maxY - occlusion.minY))
                }
                responder = current.next
            }
            return nil
        }
    }
}

struct Panel: ViewModifier {
    var fill = Palette.card
    var padding: CGFloat = 20
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Palette.border).allowsHitTesting(false))
    }
}

struct PrimaryButton: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? DashboardFont.action : PersianFont.emphasis)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? DashboardMetrics.inline : 12)
            .foregroundStyle(Palette.buttonText)
            .background(Palette.sage, in: RoundedRectangle(cornerRadius: compact ? DashboardMetrics.controlRadius : 16))
            .modifier(PressFeedback(pressed: configuration.isPressed))
    }
}

struct PressFeedback: ViewModifier {
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(pressed ? 0.82 : 1)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: pressed)
    }
}

enum PersianFont {
    static let body = Font.custom("Vazirmatn-Regular", size: 17, relativeTo: .body)
    static let subheadline = Font.custom("Vazirmatn-Regular", size: 15, relativeTo: .subheadline)
    static let emphasis = Font.custom("Vazirmatn-SemiBold", size: 17, relativeTo: .headline)
    static let subheadlineEmphasis = Font.custom("Vazirmatn-SemiBold", size: 15, relativeTo: .subheadline)
    static let meaning = Font.custom("Vazirmatn-SemiBold", size: 28, relativeTo: .title)
}

enum HeadingFont {
    static let large = Font.custom("Lalezar-Regular", size: 36, relativeTo: .largeTitle)
    static let title = Font.custom("Lalezar-Regular", size: 28, relativeTo: .title)
    static let section = Font.custom("Lalezar-Regular", size: 21, relativeTo: .headline)
}

enum DashboardMetrics {
    static let micro: CGFloat = 4
    static let inline: CGFloat = 8
    static let group: CGFloat = 12
    static let padding: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 12
}

enum DashboardFont {
    static let hero = Font.custom("Lalezar-Regular", size: 24, relativeTo: .title2)
    static let section = Font.custom("Vazirmatn-SemiBold", size: 18, relativeTo: .headline)
    static let story = Font.custom("Vazirmatn-SemiBold", size: 20, relativeTo: .title3)
    static let body = Font.custom("Vazirmatn-Regular", size: 16, relativeTo: .body)
    static let metadata = Font.custom("Vazirmatn-Regular", size: 13, relativeTo: .footnote)
    static let action = Font.custom("Vazirmatn-SemiBold", size: 16, relativeTo: .headline)
}

extension View {
    func persianNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(HeadingFont.section)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

struct Heading: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(HeadingFont.large).accessibilityAddTraits(.isHeader)
            Text(subtitle).foregroundStyle(Palette.muted)
        }
    }
}

struct CardContent: View {
    let card: Card
    let revealed: Bool
    @AppStorage("voice", store: .standard) private var voice = EnglishAccent.american.rawValue
    @AppStorage("slowPronunciation", store: .standard) private var slowPronunciation = false
    @State private var playbackError: PronunciationService.PlaybackError?

    private var preferredAccent: EnglishAccent { .preferred(voice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            metadata.foregroundStyle(Palette.sage)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    headword.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    accentButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    headword
                    accentButtons
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .leftToRight)
            if revealed {
                Divider()
                Text(card.meaningFa).font(PersianFont.meaning)
                    .transition(.opacity)
                ForEach(card.alternativeMeaningsFa, id: \.self) { Text($0) }
                if !card.exampleEn.isEmpty || !card.exampleFa.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !card.exampleEn.isEmpty {
                            Text(card.exampleEn).font(.system(.title3, design: .serif))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .environment(\.layoutDirection, .leftToRight)
                            Button {
                                speak(card.exampleEn, accent: preferredAccent)
                            } label: {
                                Label("پخش مثال · \(preferredAccent.abbreviation)", systemImage: "speaker.wave.2")
                                    .font(PersianFont.subheadlineEmphasis)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.sage)
                            .accessibilityLabel("پخش جملهٔ نمونه با تلفظ \(preferredAccent.title)")
                        }
                        if !card.exampleFa.isEmpty {
                            Text(card.exampleFa).foregroundStyle(Palette.muted)
                        }
                    }
                    .transition(.opacity)
                }
            } else {
                Divider()
                Text("معنی فارسی این واژه را به یاد بیاور.").foregroundStyle(Palette.muted)
                    .transition(.opacity)
            }
        }
        .modifier(Panel())
        .alert("تلفظ", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        ), presenting: playbackError) { _ in
            Button("باشه", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private var metadata: some View {
        Text([card.level, card.partOfSpeech].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.subheadline.monospaced())
            .environment(\.layoutDirection, .leftToRight)
    }

    private var headword: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.word).font(.system(.largeTitle, design: .serif).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if !card.pronunciationIPA.isEmpty {
                Text(card.pronunciationIPA).font(.body).foregroundStyle(Palette.muted)
            }
        }
    }

    private var accentButtons: some View {
        HStack(spacing: 8) {
            ForEach(EnglishAccent.allCases, id: \.self) { accent in
                Button {
                    speak(card.word, accent: accent)
                } label: {
                    Label(accent.abbreviation, systemImage: "speaker.wave.2")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(accent == preferredAccent ? Palette.tint : Palette.paper, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("پخش واژه با تلفظ \(accent.title)")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(Palette.sage)
    }

    private func speak(_ text: String, accent: EnglishAccent) {
        do {
            try PronunciationService.shared.speak(text, accent: accent, slowly: slowPronunciation)
        } catch {
            playbackError = error
        }
    }
}

struct StudyProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.border)
                Capsule().fill(Palette.sage)
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 6)
        .accessibilityValue(fa(Int((configuration.fractionCompleted ?? 0) * 100)) + " درصد")
    }
}
