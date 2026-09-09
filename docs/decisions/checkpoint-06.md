# Checkpoint 6 decisions: Tune it

The app gets a settings screen, reached from a gear in the level list's toolbar, and two things that were fixed in the code become the user's to set: how many new words a day, and whether the meaning speaks itself when a card is first turned over. The study direction control moves off the toolbar into the same screen, which is where checkpoint 11's record said it would end up. Both settings are columns on the single `preference` row, so a session drawn after a change uses the new value and a session already running does not, and the "draw more" buttons stop saying "eight" and say the number the user chose. Choosing the voice and the speaking speed is not here: D31 cuts it to its own route line, along with the speaker's voice-by-language defect and the audio session, because the count came to seven pull requests against a ceiling of five. Nothing about the batch ladder, the swipe, the streak or the level counts changes.

One line per decision: what was decided, and the citation from the frozen plan, copied rather than paraphrased.

### The screen

D1. A new screen titled "Settings", pushed onto the level list's navigation stack as a fourth `LevelDestination` case, `case settings`. Cited: checkpoint 5 D17 did exactly this for `case progress`, and `Laoshu/LevelListView.swift:6-10` is the enum it added it to.

D2. Its entry point is a trailing toolbar item showing a `gearshape` glyph, in the slot the direction control vacates under D3, keeping the `ToolbarSpacer` that sits between the two trailing items today. Cited: checkpoint 5 D19, "both trailing toolbar slots are taken, by the placement checklist and the direction control", which is why the streak took the leading slot; moving the direction control frees one of the two. `Laoshu/LevelListView.swift:119-122` is the spacer and its comment, which says that without it iOS 26 packs both trailing items into one glass capsule with no divider.

D2b. The gear's accessibility label is the word "Settings". Cited: every toolbar item in this list carries one that a decision fixed word for word, at `Laoshu/LevelListView.swift:108`, `:117` and `:129`; checkpoint 5 D19 fixed the flame's and checkpoint 11 D4a fixed the direction control's. A glyph with no text and no label is unreachable by voice. Critique round 3 finding F5.

D2a. The gear is drawn only while `loadError` is nil, unlike the direction control it replaces. Cited: checkpoint 5 D20a, which decided exactly this for the flame and gave the reason: `Laoshu/LevelListView.swift:75-84` puts the `navigationDestination` inside the `else` branch that the database error screen replaces, so a toolbar item left live over that screen would push a destination with no view registered. The direction control could stay outside the guard because it pushes nothing; a gear pushes `.settings`. Critique round 2 finding F4.

D3. The direction control moves off the toolbar and becomes a row on the settings screen. Its label keeps the exact words checkpoint 11 D4a fixed, "Pinyin first" and "English first", and it keeps reading the value back from the database rather than setting it optimistically. Cited: the checkpoint 11 decision record's own failure-mode entry, "The toolbar gains a second control and the level list's header starts to look like a settings screen. Route line 6 is the settings screen and will move this control into it; until then the toolbar carries two."

D3a. On the settings screen the control is a labelled picker, not a button that toggles when tapped. The row reads "Ask with" and offers "Pinyin first" and "English first". Cited: checkpoint 11 D4a chose a tapping text button because a toolbar has room for one word and no label; a list row has a leading label, so the state and the choice can both be visible, which a button that silently swaps its own text cannot do.

D4. The placement re-run button stays in the toolbar. Cited: checkpoint 3 D12 put it there and nothing has promised to move it, unlike the direction control; route line 6's summary names the word count and the audio settings and not placement. Leaving it also keeps this checkpoint's diff off the placement flow entirely.

D5. The screen is a `List` of `Section`s in the app's existing style: `.listStyle(.plain)`, `.scrollContentBackground(.hidden)`, `LaoshuTheme.background`, an inline navigation title. Cited: `Laoshu/ProgressScreen.swift:29-35`, the screen checkpoint 5 added, which is the only other pushed screen of this shape.

D6. Two sections, in this order: "Study", holding new words a day and the direction; "Audio", holding the one switch. Cited: route line 6, which names the word count first and the audio settings second. The voice and speed rows that would otherwise sit in the Audio section are cut by D31 and belong to route line 13, which is where they are recorded. Critique round 2 finding F5.

D7. Every control writes on change. There is no save button, no cancel, and no confirmation. Cited: checkpoint 11 D4a, whose direction control writes on tap and has no save step.

D8. A write that throws leaves the control reading the value still in the database and shows nothing. It does not set the load error that replaces the screen. Cited: checkpoint 11 D4a, "A write that throws therefore leaves the label where it was, which is the truth, and does nothing else: it does not set the load error that replaces the whole level list with the database error screen".

D8a. A read that throws on appear does replace the whole screen with `DatabaseErrorView`, because a settings screen with no values on it has nothing to show. Cited: `Laoshu/ProgressScreen.swift:16-19`, which does exactly this for the same reason.

### How many new words a day

D9. The setting is the batch size: how many unseen words the day's first session draws, and how many the "draw more" button draws. Cited: `LaoshuKit/Sources/LaoshuKit/SessionEngine.swift:353`, `Array(unseenPool.shuffled(using: &rng).prefix(8))` in `startSession`, and `:392`, the same expression in `startBonusSession`. Those two literals are the whole of the current rule.

D10. The default is 8 and does not change. A phone already in use must behave the same after the update as before it. Cited: checkpoint 1 D19, "review answer 2026-09-07 choosing 8", and checkpoint 2 D5, "review answer 2026-09-08 accepting design line 2, 'A day is 8 new words plus whichever batches are up. Steady state is 24 cards.'"

D11. The range is 4 to 20 inclusive, whole numbers, set with a `Stepper`. Cited: research `new-words-a-day.md`. Nation 2001 reports 6 to 10 new items per lesson as effective and Hulstijn 2001 finds more than 10 at once overloads processing, which puts the classroom ceiling near 10; the practitioner range across the Skritter and WaniKani communities is 10 to 20. Anki's default of 20 is not the number to copy, because Anki's setting caps the cards shown while this one is a batch size the ladder multiplies by three, so 20 here is already 60 cards a day, two and a half times what the user accepted. 4 is half the user's own number and still fills a batch worth returning to.

D12. The row's label is the words "New words a day", with the number on the trailing side, and beneath it the subtitle "about N cards a day once the ladder fills", where N is three times the setting. Every string on this screen is fixed here rather than left to a builder, the way checkpoint 5 D22a fixed every string on the progress screen (critique round 2 finding F2). Cited: checkpoint 2 D5, "At steady state that is twenty-four cards: today's eight new, yesterday's batch taking its first look, and the batch created eight days ago taking its second, its first look having been seven days earlier". Three is that decision's own arithmetic, not an estimate.

D13. The two buttons stop saying "eight". They read "Draw N more". The doc comment and the two closure names that also say "eight" go with them: `drawEightMore` and `onDrawEightMore` become `drawMore` and `onDrawMore`. Cited: `Laoshu/SessionSummaryView.swift:46` and `Laoshu/SessionEmptyStateView.swift:28`, both `Button("Draw eight more", ...)`, and `Laoshu/SessionView.swift:110`, the doc comment that is the third match in the tree and would otherwise leave the grep check under Acceptance checks red for a builder who did exactly what this decision said. Critique round 3 finding F4.

D13c. N comes from the session itself: `Session` carries the configured batch size read at the draw, which is not the same thing as the count of new words the draw actually took, and both views read it off the session they are already given. The allowance-spent session drew no new words while the setting was, say, twelve, and still draws the button, so its button says "Draw 12 more" and never "Draw 0 more" (critique round 3 finding F1). Cited: `Laoshu/SessionSummaryView.swift:9-11` and `Laoshu/SessionEmptyStateView.swift:8-10` take a `Session` and a closure and nothing else, so a view cannot reach a preference; `SessionEngine.swift:378-382` already hands the session every other value it was drawn with, `direction` among them, and D29 makes the size one of those values. Critique round 1 finding F4.

D13d. The allowance-spent detail loses its number rather than gaining a live one, and keeps its second sentence, which is the only thing on that screen explaining why the draw button is there: "Another level already used today's new words. This level still has unseen words waiting." (critique round 3 finding F5). Cited: D13a records that no batch stores its size, so the sentence describes an event whose size is unknowable. A user who drew eight in the morning and then raised the setting to twenty would otherwise be told that twenty new words were used today, which never happened. Critique round 1 finding F4. The old sentence at `Laoshu/SessionEmptyStateView.swift:57` was accurate only while the size was a constant.

D13a. Changing the number never touches a batch already written, and a batch does not record how big it was. Cited: `LaoshuKit/Sources/LaoshuKit/BatchStore.swift:211-219`, `hasBatchCreatedToday`, which asks only whether a batch dated today exists; the batch tables carry no size column, so nothing already on the ladder can disagree with the new setting.

D13b. The allowance stays one batch a day, not a running total of words. Lowering the number after the day's batch is written does not hand back an allowance, and raising it does not top the day's batch up. Cited: the same `hasBatchCreatedToday`, which is the whole allowance rule, and checkpoint 2 D7, which made the allowance per day across the app.

### Speaking on flip

D20. The switch's label is the words "Say the word when a card turns over". Off means nothing speaks by itself at the reveal. It governs the reveal in both directions, not the meaning face in particular. Cited: checkpoint 1 D7a fixed auto-play as once on the first flip and put the replay button on the front, but that decision predates the reverse direction; checkpoint 11 D8 kept auto-play on the reveal in the reverse direction for a different reason, "the reveal is now the side carrying the pronunciation". One switch over both is what makes the setting mean what its words say. Critique round 2 findings F2 and F3.

D20c. Turning the switch off never takes away the ability to hear a word, in either direction. The speaker glyph lives on the Chinese face, which is the front in the receptive direction and the revealed back in the reverse one, so in both cases a tap still plays it. Cited: `Laoshu/CardView.swift:38-54`, where the replay button is inside `case .chinese` and the `case .meaning` face has none, and checkpoint 11 D7, "Back: pinyin large, hanzi small and grey beneath it, speaker below both". Critique round 2 finding F3.

D20a. `SpeechSpeaker` does not learn about the setting. `Session` carries `speakOnFlip`, captured at the draw, and the flip site reads it off the session it already holds; the switch is one more condition where `isFirstReveal` is already tested. Cited: `Laoshu/SessionView.swift:6-16` takes only `engine` and `level` and `Laoshu/LevelListView.swift:78` builds it with those two, while `SessionEngine.swift:271` keeps `preferenceStore` private, so the screen can reach no preference of its own; `SessionEngine.swift:378-382` already hands the session `direction`, and D13c puts the batch size there for the same reason. `Laoshu/SessionView.swift:55-65` is the `isFirstReveal` computation and the `speaker.speak(card.word.hanzi)` call it guards. Nothing about the browse screen's speaker changes, because it has no auto-play to switch off. Critique round 2 finding F1.

D20b. The value is captured at the draw, like the direction and the size, so a change made while a session runs does not reach it. Cited: checkpoint 11 D6, "A session drawn one way is graded that way to its end"; a switch that changed the sound halfway through a session would be the one setting behaving differently from the other two.

D20d. A read that throws while the session is being drawn is the draw throwing, and the session screen already has that path: it sets `loadError` and shows the database error screen. Nothing new is needed, because the value is read inside `startSession` rather than by the view. Cited: `Laoshu/SessionView.swift:11` and `:21-22`, the existing `loadError` state and the branch that renders `DatabaseErrorView`, and D8a, which covers only the settings screen and does not have to cover this one. Critique round 2 finding F1.

### Storage and wiring

D23. Both settings live in the existing singleton `preference` row, added by a migration named `v6_settings`. Cited: `LaoshuKit/Sources/LaoshuKit/LaoshuDatabase.swift:149-157`, the `v5_preference` migration and its own comment, "Lives in the database, not `UserDefaults`, so a test can reach it (checkpoint 1 D10). One setting for the whole app".

D24. The columns, with their constraints: `new_words_per_day INTEGER NOT NULL DEFAULT 8 CHECK (new_words_per_day BETWEEN 4 AND 20)` and `speak_on_flip INTEGER NOT NULL DEFAULT 1 CHECK (speak_on_flip IN (0, 1))`. Cited: the v5 table at the same lines already constrains its one column with a `CHECK`, so this follows the shape the table already has. The defaults restate D10 and D20, so a row a shipped version wrote comes back with the behaviour it had.

D24a. The migration and the read of the new columns on the launch path are tested against a database built the way checkpoint 11 shipped it, not one built by the code under test. Cited: checkpoint 11 D11, which said exactly this for migration v5 against a checkpoint 4 database, resting on checkpoint 4 D10, which widened checkpoint 3 D14 from migrations to "any read of state a previously shipped version wrote" after a launch crash that stayed green because every test database had been built by the current code. `LaoshuKit/Tests/LaoshuKitTests/TestFixtures.swift:119` and `:200` already carry `makeCheckpoint2ReviewLog` and `makeCheckpoint4ReviewLog`; a `makeCheckpoint11ReviewLog` goes beside them. This checkpoint alters a table a shipped version created and left a row in, so the rule bites harder here than where it was written. Critique round 1 finding F5.

D25. `PreferenceStore` gains the readers and writers. No new type is introduced. Cited: `LaoshuKit/Sources/LaoshuKit/PreferenceStore.swift:13-18`, one struct over the one row, which is already where `direction` lives.

D26. It gains a `Preferences` value read in one query, so a screen showing three rows does one read rather than three. The per-setting writers stay separate, one statement each, because D7 writes on change. Cited: `PreferenceStore.swift:20-31`, the existing `direction()` reader, which is the shape the whole-row reader generalises.

D26a. A missing `preference` row reads as the D24 defaults with the direction receptive, and does not trap. Cited: `PreferenceStore.swift:22-27`, whose comment says a missing row "should be unreachable, since the migration writes one" and reads it as receptive anyway, "the way `PlacementStore.status()` reads a missing row as not taken". A whole-row reader that trapped would crash on a state the code beside it already treats as survivable. Critique round 1 finding F7.

D27. The kit does not import AVFoundation. `speak_on_flip` is a boolean column to the kit, and every decision about what makes a sound stays in the app target. Cited: checkpoint 1 D10, "a pure Swift package `LaoshuKit` that builds and tests with `swift test` and imports no UIKit or SwiftUI"; AVFoundation would compile on the package's macOS platform, but the voices it returns on a Mac are not the phone's, so anything the kit proved about speech would be about the wrong machine.

D28. `SessionEngine` reads the batch size from `PreferenceStore` at draw time, in both `startSession` and `startBonusSession`. Cited: `SessionEngine.swift:346`, `let direction = try preferenceStore.direction()`, which is the engine already reading a preference at the top of a draw; the size read goes beside it.

D29. A session captures the size at the draw and is unaffected by a change made while it runs, exactly as the direction is. Cited: checkpoint 11 D6, "The direction cannot change while a session is running. A session drawn one way is graded that way to its end", and checkpoint 1 D22, which keeps session state in memory only.

D30. Nothing about the ladder, the swipe, the review row, the streak or the level counts changes. Cited: checkpoint 2 D5 fixes the ladder's two looks at one day and seven days, and no decision here touches `BatchScheduler`, `ReviewLog`, `Streak` or `ProgressStore`.

D31. Choosing the Mandarin voice and the speaking speed is not in this checkpoint, and neither is the audio session or the speaker's voice-by-language defect. They go to the route as a new line with the four findings that belong to them recorded there. Cited: critique round 1 finding F6 counted seven pull requests against the ceiling of five, and named the boundary this PRD's own D6 already draws between its two sections. Checkpoint 4 D12 cut a checkpoint at six the same way and for the same reason. The half that leaves is also the half nobody has heard on a device and the half that carries every platform bug, so it is the half that most needs a checkpoint of its own rather than a corner of this one.

## Failure modes

A write throws. The control stays where it was, which is what the database still says, and nothing else happens (D8).

The read throws when the screen appears. The whole screen becomes the database error screen, because a settings screen with no values on it has nothing to show (D8a).

The migration fails on a phone carrying a checkpoint 11 database. The app shows the database error screen at launch, as it does for any failed migration today, and no setting is reachable. The migration adds two columns with defaults and writes no rows, so there is nothing in it to conflict with existing data, and D24a is the check that this is true of a database a shipped version actually wrote.

The user lowers the number after the day's batch is already written. Nothing is handed back and nothing is topped up; the allowance is one batch a day, not a running total (D13b). The allowance-spent screen says so without naming a number, because the number that was used is not recorded (D13d).

The user changes the number while batches are still on the ladder. Batches already written keep their old size and come back at it, so for about eight days the day's card count disagrees with D12's subtitle: a drop from 20 to 4 gives 4 new words plus a 20-word first look the next day, and 4 plus a 20-word second look eight days later. Cited: `LaoshuKit/Sources/LaoshuKit/Batch.swift:35-41`, where the second look is seven days after the first, so two older batches are outstanding at any time, and D13a, which says nothing already written is touched. Nothing rescales them and nothing should: a batch is the unit the ladder moves. Raising the number is the mirror of this. D12's subtitle describes the ladder filled at the current setting, which is what "once the ladder fills" says. Critique round 3 finding F3.

The user changes the number while a session is running. The running session keeps the size it drew with, exactly as it keeps its direction (D29), and the buttons on its summary read that size rather than the new one (D13c).

The number is raised above what a level has left unseen. The draw takes what is there, which is what `prefix` already does, and the "draw more" button disappears when nothing is unseen, which checkpoint 2 D19 and D22 already handle.

Speak on flip is turned off mid-session. The cards already on screen keep the behaviour the session started with, because the value is read when the session screen appears (D20b). Turning it off does not silence the speaker glyph, which is a tap and not an auto-play (D20).

The `preference` row is missing entirely, which no shipped version can produce. Every setting reads as its default and the app runs (D26a).

The level list's own read fails and the error screen replaces it. The gear is not drawn, so nothing can push a settings screen onto a stack whose destinations are not registered (D2a). The placement button and the direction control stay drawn today because neither pushes anything; the gear is the first trailing item that does.

## The research the ranges rest on

Nation 2001 reports 6 to 10 new items per lesson as effective and Hulstijn 2001 finds more than 10 at once overloads processing, which puts the classroom ceiling near 10; the practitioner range across the Skritter and WaniKani communities is 10 to 20. This settles the 4-to-20 range in D11, together with the arithmetic already fixed by checkpoint 2 D5. Anki's default of 20 was considered and rejected as the number to copy: Anki's setting caps the cards shown while this one is a batch size the ladder multiplies by three, so 20 here is already 60 cards a day, two and a half times what the user accepted at checkpoint 1. The note itself, `new-words-a-day.md`, lives outside this repository, so this record carries the citation the plan gave it rather than a link.

## Checks run

All commands below were run from the repository root, on a machine with Xcode installed, which the compile gate requires.

- `swift test --package-path LaoshuKit` — passed, 162 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Laoshu -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — BUILD SUCCEEDED.
- `python3 docs/measure.py > /tmp/m.md && diff /tmp/m.md docs/measurements.md` — empty diff.
- `python3 docs/check_glosses.py` — `5400 glosses read, 5400 words expected, 0 problem(s)`.
- `swift run --package-path LaoshuKit laoshu-build-db --checksum data/laoshu.sqlite` — `5ecdd46167b033a7b6d235890148c3aa74726d5faaa9c576019397ba1e67b9a9`, unchanged from the checkpoint 5 record.
- `grep -rn 'import GRDB' Laoshu/` — empty.
- `grep -rn 'import AVFoundation' LaoshuKit/Sources/` — empty.
- `grep -rn 'eight more' Laoshu/` — empty.

## Not run here

These need a physical device, so the user runs them on the phone:

1. Set the count to twelve, study, and check that twelve new words arrive rather than eight.
2. Turn speak on flip off, flip a card, and check that nothing speaks until the speaker glyph is tapped.
3. Change the direction from the settings screen and check the next session opens the other way round.

## Screens

The screens are read at step 9 of the light factory's chain by the planning session, on a Mac with Xcode and a booted simulator, after every pebble merges and before the checkpoint is called built. This task took no screenshots and drove no simulator, since there is no UI test target in this repository and checkpoint 1 D10 says no automated check may depend on a simulator. All eight were read at step 9 on 2026-09-09, against a seeded database and, where a screen is not otherwise reachable, a temporary root view that was reverted afterwards. Every one matched, and the list below records what each was checked for:

- Settings as it opens: the Study section with the word count and the direction, the Audio section with the one switch.
- Settings with the stepper at 4, its subtitle reading "about 12 cards a day once the ladder fills", and again at 20 reading "about 60 cards a day once the ladder fills".
- The level list showing the gear in the toolbar where the direction control was, the placement checklist beside it, and the flame still leading.
- The level list with its read forced to fail: the database error screen with neither the flame nor the gear in the toolbar (D2a).
- The session summary reading "Draw 12 more" after the setting is changed to 12.
- The allowance-spent screen, seeded with the setting at 12, reading "Another level already used today's new words. This level still has unseen words waiting." with no number in the sentence, above a button reading "Draw 12 more" and not "Draw 0 more" (D13c, D13d).
- Settings with its read forced to fail, showing the database error screen.

## Defects

None. Every command above ran, every assertion held, and all eight screens matched when they were read at step 9.

Two things the screens showed that no command here could: the stepper greys out its minus at 4 and its plus at 20, so D11's range is visible rather than only enforced on write; and a session drawn with the setting at 12 ended reading "11 of 12 right the first time", which is D13 proved end to end on a device rather than in a test.
