import SwiftUI
import SwiftData

struct SettingsView: View {
    let states: [ReviewState]
    let events: [ReviewEvent]
    @Environment(\.modelContext) private var context
    @AppStorage("dailyGoal") private var goal = DailyGoal.defaultValue
    @AppStorage(TapCue.preferenceKey) private var tapSounds = TapCue.enabledByDefault
    @AppStorage("voice") private var voice = EnglishAccent.american.rawValue
    @AppStorage("slowPronunciation") private var slowPronunciation = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("reminder") private var reminder = false
    @AppStorage("reminderHour") private var hour = 19
    @AppStorage("reminderMinute") private var minute = 0
    @State private var updating = false
    @State private var confirming = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("تمرین") {
                    Picker("هدف روزانه", selection: $goal) {
                        ForEach(DailyGoal.choices(including: goal), id: \.self) { count in
                            Text(count == 0 ? "فقط مرور" : "\(fa(count)) واژهٔ جدید").tag(count)
                        }
                    }
                    Toggle("صدای لمس", isOn: $tapSounds)
                        .onChange(of: tapSounds) { _, enabled in
                            if enabled {
                                TapCue.reveal.play()
                            } else {
                                TapSoundPlayer.shared.stop()
                            }
                        }
                }
                Section("تلفظ") {
                    Picker("لهجهٔ پیش‌فرض", selection: preferredAccent) {
                        ForEach(EnglishAccent.allCases, id: \.self) { accent in
                            Text(accent.title).tag(accent)
                        }
                    }
                    Toggle("پخش آهسته", isOn: $slowPronunciation)
                }
                Section("نمایش") {
                    Picker("ظاهر برنامه", selection: $appearance) {
                        Text("هماهنگ با دستگاه").tag("system")
                        Text("روشن").tag("light")
                        Text("تیره").tag("dark")
                    }
                }
                Section("یادآوری") {
                    Toggle("یادآوری روزانه", isOn: Binding(get: { reminder }, set: updateReminder))
                        .disabled(updating)
                    if reminder {
                        DatePicker("زمان یادآوری", selection: reminderTime, displayedComponents: .hourAndMinute)
                            .disabled(updating)
                    }
                }
                Section("داده‌ها") {
                    Button("پاک کردن پیشرفت", role: .destructive) { confirming = true }
                }
                .listRowBackground(Palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .persianNavigationTitle("تنظیمات")
            .confirmationDialog("همهٔ مرورها و برنامهٔ یادگیری پاک شوند؟", isPresented: $confirming, titleVisibility: .visible) {
                Button("پاک کردن پیشرفت", role: .destructive) { reset() }
            } message: {
                Text("واژه‌های شخصی‌ات حفظ می‌شوند.")
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("باشه", role: .cancel) { message = nil }
            }
        }
    }

    private var preferredAccent: Binding<EnglishAccent> {
        Binding(get: { .preferred(voice) }, set: { voice = $0.rawValue })
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            updateReminder(true, hour: parts.hour ?? 19, minute: parts.minute ?? 0)
        }
    }

    private func updateReminder(_ enabled: Bool) {
        updateReminder(enabled, hour: hour, minute: minute)
    }

    private func updateReminder(_ enabled: Bool, hour: Int, minute: Int) {
        guard !updating else { return }
        updating = true
        Task {
            defer { updating = false }
            do {
                reminder = try await Reminder.update(enabled: enabled, hour: hour, minute: minute)
                if reminder {
                    self.hour = hour
                    self.minute = minute
                } else if enabled {
                    message = "اجازهٔ اعلان‌ها را می‌توانی در تنظیمات دستگاه فعال کنی."
                }
            } catch {
                message = "تنظیم یادآوری ممکن نشد."
            }
        }
    }

    private func reset() {
        for state in states { context.delete(state) }
        for event in events { context.delete(event) }
        do { try ReviewStore.save(context) }
        catch { message = "پاک کردن پیشرفت ممکن نشد." }
    }
}
