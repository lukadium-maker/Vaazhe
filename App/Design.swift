import SwiftUI
import UIKit

enum Palette {
    static let paper = adaptive(0xF7F3EB, 0x211F1B)
    static let ink = adaptive(0x292724, 0xF7F0E4)
    static let muted = adaptive(0x625E54, 0xC3BBAD)
    static let card = adaptive(0xEFE7DB, 0x312D26)
    static let border = adaptive(0xDED5C6, 0x524A40)
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
    var body: some View {
        Image("ElphyMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Palette.mascotGreen)
            .accessibilityHidden(true)
    }
}

struct Page<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
        }
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
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
