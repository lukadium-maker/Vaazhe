import SwiftUI
import SwiftData

struct CollectionView: View {
    let bundled: [Card]
    let personal: [PersonalCard]
    let states: [String: ReviewState]
    let statuses: [String: VocabularyStatus]
    @State private var search = ""
    @State private var filter = "همه"
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Picker("وضعیت یادگیری", selection: $filter) {
                    ForEach(["همه", "جدید", "در حال یادگیری", "تثبیت‌شده", "دشوار"], id: \.self) { Text($0) }
                }
                .listRowBackground(Palette.card)
                let personalMatches = personal.filter { matches($0.card) }
                let bundledMatches = bundled.filter(matches)
                if !personalMatches.isEmpty {
                    Section("واژه‌های شخصی") {
                        ForEach(personalMatches) { item in
                            row(item.card, personal: item)
                        }
                    }
                }
                if !bundledMatches.isEmpty {
                    Section("مجموعهٔ آزمایشی") {
                        ForEach(bundledMatches) { row($0, personal: nil) }
                    }
                }
                if personalMatches.isEmpty && bundledMatches.isEmpty {
                    ContentUnavailableView("واژه‌ای پیدا نشد", systemImage: "magnifyingglass")
                        .listRowBackground(Palette.paper)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .persianNavigationTitle("واژه‌ها")
            .searchable(text: $search, prompt: "جست‌وجوی واژه یا معنی")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("افزودن واژه", systemImage: "plus") { adding = true }
                }
            }
            .sheet(isPresented: $adding) { CardEditor(item: nil) }
        }
    }

    private func row(_ card: Card, personal: PersonalCard?) -> some View {
        NavigationLink {
            DetailView(initial: card, item: personal, state: states[card.id], status: statuses[card.id])
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.word).font(.system(.title3, design: .serif))
                    .environment(\.layoutDirection, .leftToRight)
                Text(card.meaningFa).font(PersianFont.subheadline).foregroundStyle(Palette.muted)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Palette.card)
    }

    private func matches(_ card: Card) -> Bool {
        let query = normalized(search.trimmingCharacters(in: .whitespacesAndNewlines))
        guard query.isEmpty || ([card.word, card.meaningFa] + card.alternativeMeaningsFa)
            .contains(where: { normalized($0).localizedCaseInsensitiveContains(query) }) else { return false }
        let status = statuses[card.id]
        switch filter {
        case "جدید": return status?.stage == .new
        case "در حال یادگیری": return status?.stage == .learning
        case "تثبیت‌شده": return status?.stage == .mastered
        case "دشوار": return status?.isDifficult == true
        default: return true
        }
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
            .replacingOccurrences(of: "\u{200c}", with: "")
    }
}

private struct DetailView: View {
    let initial: Card
    let item: PersonalCard?
    let state: ReviewState?
    let status: VocabularyStatus?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirming = false
    @State private var failed = false

    var body: some View {
        Page {
            CardContent(card: item?.card ?? initial, revealed: true)
            if let state {
                if status?.stage == .mastered { Text("تثبیت‌شده").foregroundStyle(Palette.sage) }
                if status?.isDifficult == true { Text("نیاز به تمرین بیشتر").foregroundStyle(Palette.muted) }
                Text("مرور بعدی").font(HeadingFont.section).accessibilityAddTraits(.isHeader)
                Text(state.due.formatted(.relative(presentation: .named)))
            } else {
                Text("هنوز تمرین نشده").foregroundStyle(Palette.muted)
            }
            if item != nil {
                Button("ویرایش واژه") { editing = true }.buttonStyle(PrimaryButton())
                Button("حذف واژه", role: .destructive) { confirming = true }
            }
        }
        .persianNavigationTitle(item == nil ? "مجموعهٔ آزمایشی" : "واژهٔ شخصی")
        .sheet(isPresented: $editing) { CardEditor(item: item) }
        .confirmationDialog("این واژه و برنامهٔ مرور آن حذف شود؟", isPresented: $confirming, titleVisibility: .visible) {
            Button("حذف واژه", role: .destructive) {
                guard let item else { return }
                context.delete(item)
                if let state { context.delete(state) }
                do { try ReviewStore.save(context); dismiss() }
                catch { failed = true }
            }
        }
        .alert("حذف واژه ممکن نشد", isPresented: $failed) { Button("باشه", role: .cancel) {} }
    }
}

private struct CardEditor: View {
    let item: PersonalCard?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var word: String
    @State private var meaning: String
    @State private var part: String
    @State private var example: String
    @State private var translation: String
    @State private var failed = false

    init(item: PersonalCard?) {
        self.item = item
        _word = State(initialValue: item?.word ?? "")
        _meaning = State(initialValue: item?.meaning ?? "")
        _part = State(initialValue: item?.part ?? "")
        _example = State(initialValue: item?.example ?? "")
        _translation = State(initialValue: item?.translation ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("واژهٔ انگلیسی", text: $word)
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .environment(\.layoutDirection, .leftToRight)
                TextField("معنی فارسی", text: $meaning)
                TextField("نقش دستوری (اختیاری)", text: $part)
                TextField("مثال انگلیسی (اختیاری)", text: $example, axis: .vertical)
                    .font(.body)
                    .environment(\.layoutDirection, .leftToRight)
                TextField("ترجمهٔ مثال (اختیاری)", text: $translation, axis: .vertical)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .persianNavigationTitle(item == nil ? "واژهٔ تازه" : "ویرایش واژه")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("لغو") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ذخیره", action: save).disabled(clean(word).isEmpty || clean(meaning).isEmpty)
                }
            }
            .alert("ذخیرهٔ واژه ممکن نشد", isPresented: $failed) { Button("باشه", role: .cancel) {} }
        }
    }

    private func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        let card = Card(id: item?.id ?? "personal-\(UUID().uuidString)", word: clean(word),
                        partOfSpeech: clean(part), level: "", meaningFa: clean(meaning),
                        exampleEn: clean(example), exampleFa: clean(translation), topic: "")
        if let item {
            item.word = card.word
            item.meaning = card.meaningFa
            item.part = card.partOfSpeech
            item.example = card.exampleEn
            item.translation = card.exampleFa
        } else {
            context.insert(PersonalCard(card))
        }
        do { try ReviewStore.save(context); dismiss() }
        catch { failed = true }
    }
}
