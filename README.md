# واژه · English vocabulary for Persian speakers

A native, offline SwiftUI prototype for iPhone on iOS 18 or later. The first version contains 100 provisional English–Persian cards.

## Run on an iPhone

1. Open `Vaazhe.xcodeproj` and select the **Vaazhe** scheme.
2. Under the **Vaazhe** target’s **Signing & Capabilities**, select your Apple development team. If the bundle identifier is taken, change `com.example.vaazhe` to one you control.
3. Connect and unlock your iPhone. If prompted, trust the Mac and enable Developer Mode on the iPhone.
4. Choose the iPhone as the run destination and press **⌘R**. An iPhone simulator in Xcode also works for testing.
5. From **امروز**, start a study session, reveal each card, and rate your recall. Relaunch the app to confirm that progress persists. Add a personal word from the **واژه‌ها** tab to see it prioritized for the next available new-card slot.

Press **⌘U** on an iPhone simulator to run the scheduler, session queue, and persistence tests. US and UK word buttons use installed system voices for their respective accents. In **تنظیمات → تلفظ**, choose the accent for example sentences and enable slow playback for both words and sentences. Reminders require permission to post notifications.

## Project layout

- `App/VaazheApp.swift` contains the app entry point, Today, and Progress.
- `App/StudyView.swift`, `App/CollectionView.swift`, and `App/SettingsView.swift` contain the main screens and editing flows.
- `App/Design.swift` contains the palette and reusable SwiftUI components. Persian body text uses bundled Vazirmatn, and headings use bundled Lalezar.
- `App/Vocabulary.swift` defines the deck format, scheduler, and study queue. `App/Storage.swift` holds SwiftData records and writes. `App/PronunciationService.swift` handles speech and `App/Services.swift` handles local reminders.
- `App/vocabulary.json` is the bundled deck. `Tests/VaazheTests.swift` contains the unit tests.

## Replace the starter deck

Replace `App/vocabulary.json` with the reviewed entries in the same format. Keep a card’s ID when correcting its wording or example. Assign a new ID if the headword or teaching sense changes, so the new card starts with its own review history.

The current levels are provisional. IPA fields are blank pending phonetic review. Pronunciation is available through the system speech voice when supported.

## Prototype review policy

The default daily goal is five new words and can be set to zero. Due reviews appear first. A forgotten card returns once after up to two other cards when possible, and is due again after ten minutes if it stays unresolved. Hard schedules a review in one to seven days. Good starts at two days and doubles the previous interval up to 90 days. Three consecutive Good ratings mark strong review performance.
