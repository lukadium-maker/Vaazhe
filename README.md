# Elphy

Elphy is an offline English vocabulary and reading app for Persian-speaking learners. It is built with SwiftUI and SwiftData for **iPhone on iOS 18 or later**. The app bundles **300 English–Persian vocabulary cards**, **30 illustrated stories** with optional Persian translations, and **214 curated sentence-completion prompts**. The interface uses Persian right-to-left layout and left-to-right English text.

## Run locally

1. Open `Elphy.xcodeproj` in Xcode and select the shared **Elphy** scheme.
2. Choose an iPhone simulator and press **⌘R**. For a physical iPhone, select your development team under **Signing & Capabilities**, connect and unlock the phone, then select it as the run destination. Enable Developer Mode if prompted.
3. To update an existing installation, keep its bundle identifier. A build with a different identifier uses a separate local data container.

Press **⌘U** with an iPhone simulator selected to run the `ElphyTests` target. The tests cover scheduling and session behavior, SwiftData persistence, reading content and assignments, Playground generation and results, simulation isolation, and deterministic 90-day workload scenarios.

## Learning flows

- **Today (امروز)** recommends a study session, an illustrated story, and optional Playground practice. The new-word preference is **5, 10, or 20** per day, with **10** as the default. The recommendation can be lower when reviews accumulate or the deck is nearly exhausted.
- **Vocabulary (واژه‌ها)** shows the bundled deck, learning status, and personal vocabulary. Personal cards take priority in available new-word slots.
- **Reading** assigns one official story per local learning day and shares that saved assignment between Today and the Reading Library. Story pages offer linked vocabulary, English audio, a collapsible Persian translation, and a three-question comprehension quiz. New recommendations favor unfinished stories. Once those are exhausted, the app labels rereads as revision.
- **Playground (زمین بازی واژه‌ها)** offers Word Matching, Sentence Completion, and Word Builder. Rounds draw from previously practiced vocabulary and adapt to recent results and words that need reinforcement. Sentence Completion draws from its curated bank. Practice results and personal bests are stored separately from formal review schedules.
- **Progress and Settings** show vocabulary mastery and review activity and let learners set their daily preference, appearance, voice, playback speed, and local reminder. Pronunciation uses installed system voices, and reminders require notification permission.

## Daily workload and scheduling

The planner recommends **up to 25 due reviews** per session. Additional due cards stay available for voluntary review. New words are limited by the learner’s preference, the remaining catalog, and the following default workload policy.

| Due review demand | Maximum new words |
| --- | ---: |
| 0–15 | 20 |
| 16–25 | 10 |
| 26–40 | 5 |
| 41–60 | 3 |
| More than 60 | 0 |

Formal flashcard ratings drive the spaced-repetition schedule.

- **Again** schedules a retry ten minutes later. A successful retry before that deadline leaves the deadline in place.
- **Hard** keeps the previous interval, with a minimum of one day.
- **Good** starts at two days and doubles the previous interval, capped at 90 days.
- **Easy** starts at four days and triples the previous interval, capped at 90 days.

Mastery uses the interval, confident-recall streak, and the dates on which recall occurred. It is an in-app progress estimate. Optional recall practice, Playground rounds, and quizzes leave the formal review schedule unchanged.

## Project structure

| Path | Responsibility |
| --- | --- |
| [`Elphy.xcodeproj`](Elphy.xcodeproj) | iPhone app, shared scheme, and XCTest target |
| [`App/ElphyApp.swift`](App/ElphyApp.swift), [`App/TodayDashboard.swift`](App/TodayDashboard.swift) | App entry point, navigation, Today, and Progress |
| [`App/Vocabulary.swift`](App/Vocabulary.swift), [`App/Storage.swift`](App/Storage.swift) | Vocabulary, workload planning, scheduling, and SwiftData review records |
| [`App/StudyView.swift`](App/StudyView.swift), [`App/CollectionView.swift`](App/CollectionView.swift) | Flashcards, meaning quiz, and personal vocabulary |
| [`App/Reading.swift`](App/Reading.swift), [`App/ReadingStorage.swift`](App/ReadingStorage.swift), [`App/ReadingView.swift`](App/ReadingView.swift) | Story validation, recommendations, saved daily assignments, and reading UI |
| [`App/PracticeEngine.swift`](App/PracticeEngine.swift), [`App/PracticeCloze.swift`](App/PracticeCloze.swift), [`App/PracticeStore.swift`](App/PracticeStore.swift), [`App/PracticePlayground.swift`](App/PracticePlayground.swift) | Round generation, curated prompts, local results, and game UI |
| [`App/AppClock.swift`](App/AppClock.swift), [`App/DeveloperSimulation.swift`](App/DeveloperSimulation.swift), [`App/DeveloperMenu.swift`](App/DeveloperMenu.swift) | Shared learning clock and Debug-only simulation |
| [`App/Design.swift`](App/Design.swift), [`App/Assets.xcassets`](App/Assets.xcassets), [`App/Fonts`](App/Fonts) | Shared SwiftUI styling, mascot and wordmark, story covers, and Persian fonts |
| [`Tests/`](Tests) | Vocabulary, reading, Playground, persistence, and simulation coverage |

## Debug simulation

In a **Debug** build, open **Settings (تنظیمات)** and tap the elephant **seven times in quick succession**. Enable Simulation Mode and choose a fresh profile or a copy of your current progress. Use the simulation badge on Today to reopen the menu. You can advance dates, simulate reviews and missed days, and inspect the workload and Playground.

Simulated activity uses separate data and settings. Exit simulation to return to the real date and your original profile. Release builds exclude the Developer Menu.

## Updating bundled content

- **Vocabulary** lives in [`App/vocabulary.json`](App/vocabulary.json). Keep a card’s ID when editing its wording or example. Assign a new ID if the headword or teaching sense changes.
- **Stories** live in [`App/elfy-reading-stories-20.json`](App/elfy-reading-stories-20.json). This resource keeps its original filename and now contains 30 stories. Keep story IDs stable to preserve reading progress. Ensure that each target ID exists in the deck and that the target or a recognized inflection appears in the English passage. Check each quiz against the passage.
- **Sentence Completion** prompts in [`App/PracticeCloze.swift`](App/PracticeCloze.swift) match exact catalog examples. If an example changes, review the answer form and distractors before updating its prompt.
