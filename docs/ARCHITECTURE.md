# Laoshu architecture

Two Swift modules and one data pipeline. `LaoshuKit/` is a Swift package that holds every rule and every database access; it builds for macOS as well as iOS so `swift test` runs without Xcode. `Laoshu/` is the iPhone app, one SwiftUI view per screen, which opens the databases through the kit and renders what the kit hands back. `data/` is the vocabulary source, built offline into a SQLite file the app ships read-only.

## Domains

| Domain | Lives in | Entry point | What it owns |
|---|---|---|---|
| Catalogue | `LaoshuKit/Sources/LaoshuKit/Word.swift`, `CatalogueBuilder.swift`, `LaoshuKit/Sources/laoshu-build-db/`, `data/` | `laoshu-build-db` (command line), `Word` (read) | The 5,400 HSK words, their pinyin, hanzi, and one-line gloss. Built from `data/hsk_word_list.tsv` and `data/glosses.tsv` into `data/laoshu.sqlite`, copied to `Laoshu/laoshu.sqlite` for the bundle. |
| Study | `Batch.swift`, `BatchStore.swift`, `ReviewLog.swift`, `ReviewLogReplay.swift`, `SessionEngine.swift`, `SessionStore.swift`, `TodayProvider.swift`, `LocalDate.swift` | `SessionEngine` | Drawing a session, grading a swipe, the batch ladder (introduced, next day, seven days on, retired), resuming a session, the review log. |
| Placement | `PlacementTest.swift`, `PlacementSession.swift`, `PlacementStore.swift` | `PlacementSession` | The level walk that marks words already known, and the one-row `placement` table. |
| Progress | `ProgressStore.swift`, `Streak.swift` | `ProgressStore`, `StreakReader` | Per-level counts and today's waiting total, the streak and its forgiveness rule. |
| Preferences | `PreferenceStore.swift` | `PreferenceStore` | Study direction, new-word count, speech on flip. |
| Storage | `LaoshuDatabase.swift`, `LaoshuKit.swift` | `LaoshuDatabase.open` | Opening the read-only catalogue and the writable review log as one connection, and the numbered migrations v1 to v7 that shape the writable side. |
| App shell | `Laoshu/*.swift` | `RootView` | Screens, navigation, the swipe gesture, the theme, speech through `SpeechSpeaker`. |

Each domain in the kit is a few files, not a directory. That is the right size today; a domain gets a directory when it outgrows a screenful of files.

## Allowed dependencies

| From | May import | Enforced by |
|---|---|---|
| `LaoshuKit/Sources/LaoshuKit` | Foundation, GRDB, Observation | `scripts/check-imports`, run by `scripts/check`. |
| `LaoshuKit/Sources/laoshu-build-db` | LaoshuKit, Foundation, SQLite3, CryptoKit | `scripts/check-imports` and the package manifest. |
| `LaoshuKit/Tests` | LaoshuKit, GRDB, XCTest | Package manifest. |
| `Laoshu/` | LaoshuKit, SwiftUI, Foundation, AVFoundation (only `SpeechSpeaker.swift`) | `scripts/check-imports`. |
| `Laoshu/` | GRDB | Never. Views reach the database only through the kit's stores. `scripts/check-imports` fails on it. |

Inside the kit: Study depends on Storage (the connection), Catalogue (`Word`), and `TodayProvider`. Placement writes a known word as a retired batch, but only through `BatchStore`, never with its own SQL against Study's tables. Progress reads Study's tables (`review`, `batch_word`) and writes nothing. Preferences depends on Storage only. Nothing in the kit depends on the app.

## Where data enters

- Vocabulary enters once, offline: `data/hsk_word_list.tsv` (HSK 3.0 list joined to CC-CEDICT) and `data/glosses.tsv` (hand-written one-line meanings) go through `CatalogueBuilder`, which validates every row against the same rules `docs/check_glosses.py` applies, and `laoshu-build-db` writes `data/laoshu.sqlite`. The app never parses text.
- User input enters through swipes and taps in `Laoshu/` views, which call `SessionEngine`, `PlacementSession`, or a store. The kit writes rows; views hold no state that outlives a screen except what the kit gave them.
- The clock enters through `TodayProvider`, the one seam, so a test can be any day it likes.

## Storage

- Catalogue: `laoshu.sqlite` in the app bundle, read-only, schema version in `LaoshuKit.catalogueSchemaVersion`.
- Review log: a second SQLite file in Application Support, created on first launch, migrated by GRDB's migrator in `LaoshuDatabase.swift` (tables `review`, `batch`, `batch_word`, `placement`, `preference`, `session`, `session_card`; v6 adds the settings columns to `preference`).
- Both are opened as one `DatabaseQueue` by `LaoshuDatabase.open`, which `RootView` calls once at launch.

## Runtime

One process, one user, no network. iPhone only. Speech comes from the system Mandarin voice through `SpeechSpeaker`; when no voice is installed the glyph is disabled and nothing else changes.

## Checks that hold this shape

- `scripts/check-imports`: the three import rules above. `--self-test` plants one forbidden import per rule in a scratch tree and shows the check rejecting exactly those; `scripts/check` runs the self-test and then the real tree.
- `scripts/check`: the kit test suite, `docs/check_glosses.py`, `docs/measure.py` against `docs/measurements.md`, the level counts and integrity of `data/laoshu.sqlite`, and that the bundled copy equals it.
- `scripts/build` (in `scripts/check-full`): the app compiles against the kit's public surface.

## Not yet enforced

- Import rules say which module a file may reach, not what it does with it. A view that reaches a store it should not, or a kit type that decides a view's layout, is still caught only by review and by the rule that every kit rule has a test.
- `Laoshu/laoshu.sqlite` is a byte copy of `data/laoshu.sqlite` rather than a build step. `scripts/check` catches drift; the duplication stays because Xcode resources are simplest as a checked-in file.

## Reference implementation

`PreferenceStore.swift` with `PreferenceTests.swift` and `SettingsScreen.swift` is the smallest complete slice: a kit type owning the rule and the table, a test that pins the rule, and a view that reads and writes only through the store. New work in any domain follows that shape.
