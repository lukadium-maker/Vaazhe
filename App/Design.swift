import SwiftUI
import UIKit

enum Palette {
    static let paper = adaptive(0xF7F3EB, 0x211F1B)
    static let ink = adaptive(0x292724, 0xF7F0E4)
    static let muted = adaptive(0x625E54, 0xC3BBAD)
    static let card = adaptive(0xEFE7DB, 0x312D26)
    static let border = adaptive(0xDED5C6, 0x524A40)
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

struct ElephantMascot: View {
    enum Mood { case welcoming, happy, encouraging, celebrating, resting }

    var mood: Mood = .welcoming
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = false

    var body: some View {
        Image("ElphyMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(mood == .resting ? Palette.sage : Palette.mascotGreen)
            .rotationEffect(.degrees(motion && mood == .encouraging ? -5 : 0))
            .offset(y: motion && mood == .happy ? -3 : 0)
            .scaleEffect(motion && mood == .celebrating ? 1.08 : 1)
            .task(id: mood) {
                motion = false
                guard !reduceMotion, mood != .welcoming, mood != .resting else { return }
                withAnimation(.easeOut(duration: 0.18)) { motion = true }
                do {
                    try await Task.sleep(for: .milliseconds(220))
                    withAnimation(.easeInOut(duration: 0.26)) { motion = false }
                } catch {
                    // The view disappeared or moved to a new mood.
                }
            }
            .accessibilityHidden(true)
    }
}

struct Page<Content: View>: View {
    private let avoidsFloatingTabBar: Bool
    let content: Content
    @State private var tabBarOverlap: CGFloat?
    // Reserve at least one standard tap target for the floating bar and its edge effect.
    @ScaledMetric(relativeTo: .body) private var minimumTabClearance = 44.0

    init(avoidsFloatingTabBar: Bool = false, @ViewBuilder content: () -> Content) {
        self.avoidsFloatingTabBar = avoidsFloatingTabBar
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if avoidsFloatingTabBar, #available(iOS 26, *) {
                Color.clear
                    .frame(height: max(tabBarOverlap ?? 0, minimumTabClearance))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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

// Measure in the same window coordinate space as the native tab bar. The reader
// sits outside the scroll inset so its measurement never includes its correction.
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

    func body(content: Content) -> some View {
        content.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.border))
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PersianFont.emphasis)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(12)
            .foregroundStyle(Palette.buttonText)
            .background(Palette.sage, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
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
    @AppStorage("voice") private var voice = EnglishAccent.american.rawValue
    @AppStorage("slowPronunciation") private var slowPronunciation = false
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
                }
            } else {
                Divider()
                Text("معنی فارسی این واژه را به یاد بیاور.").foregroundStyle(Palette.muted)
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
