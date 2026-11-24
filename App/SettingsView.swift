import SwiftUI
import SwiftData
#if DEBUG
import UIKit
#endif

struct SettingsView: View {
    let states: [ReviewState]
    let events: [ReviewEvent]
    let readingContainer: ModelContainer?
    let onReadingReset: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(AppClock.self) private var clock
    @AppStorage("dailyGoal") private var goal = DailyGoal.defaultValue
    @AppStorage(TapCue.preferenceKey, store: .standard) private var tapSounds = TapCue.enabledByDefault
    @AppStorage("voice", store: .standard) private var voice = EnglishAccent.american.rawValue
    @AppStorage("slowPronunciation", store: .standard) private var slowPronunciation = false
    @AppStorage("appearance", store: .standard) private var appearance = "system"
    @AppStorage("reminder", store: .standard) private var reminder = false
    @AppStorage("reminderHour", store: .standard) private var hour = 19
    @AppStorage("reminderMinute", store: .standard) private var minute = 0
    #if DEBUG
    var openDeveloperMenu: (() -> Void)?
    @State private var mascotTaps = 0
    @State private var lastMascotTap: TimeInterval?
    #endif
    @State private var updating = false
    @State private var confirming = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                #if DEBUG
                Section {
                    ElphyMascotView(mood: .encouraging, size: 64)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let time = ProcessInfo.processInfo.systemUptime
                            if let lastMascotTap, time - lastMascotTap > 1.5 { mascotTaps = 0 }
                            lastMascotTap = time
                            mascotTaps += 1
                            guard mascotTaps == 7 else { return }
                            mascotTaps = 0
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            openDeveloperMenu?()
                        }
                        .accessibilityIdentifier("settings-mascot")
                }
                .listRowBackground(Palette.card)
                #endif
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
                .disabled(clock.isSimulating)
                Section("داده‌ها") {
                    Button("پاک کردن پیشرفت", role: .destructive) { confirming = true }
                }
                .listRowBackground(Palette.card)
                .disabled(clock.isSimulating)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .persianNavigationTitle("تنظیمات")
            .confirmationDialog("پیشرفت یادگیری و داستان‌خوانی پاک شود؟", isPresented: $confirming, titleVisibility: .visible) {
                Button("پاک کردن پیشرفت", role: .destructive) { reset() }
            } message: {
                Text("مرورها، وضعیت مطالعه و امتیاز آزمون‌های داستان‌ها پاک می‌شوند. واژه‌های شخصی‌ات حفظ می‌شوند.")
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
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: clock.systemNow) ?? clock.systemNow
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
        guard let readingContainer else {
            message = "دسترسی به پیشرفت داستان‌خوانی ممکن نشد. برنامه را دوباره باز کن و امتحان کن."
            return
        }
        do { try ReadingStore.reset(in: readingContainer.mainContext) }
        catch {
            message = "پاک کردن پیشرفت داستان‌خوانی ممکن نشد."
            return
        }
        onReadingReset()
        for state in states { context.delete(state) }
        for event in events { context.delete(event) }
        do { try ReviewStore.save(context) }
        catch { message = "پیشرفت داستان‌خوانی پاک شد، اما پاک کردن مرور واژه‌ها ممکن نشد. دوباره امتحان کن." }
    }
}
