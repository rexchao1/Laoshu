# Checkpoint 5 decisions: Make it stick

The level list's toolbar now carries a flame and a number: how many days in a row the user has studied, in a run that forgives one missed day a week and no more. Tapping it opens a Progress screen showing that same streak, how many words are waiting to be reviewed across all six levels today, and for each level how many words it has learned, has in progress, and has left. Nothing about study itself changed: no new writes, no new schema, no new dependency, and no daily reminder, which was cut to route line 12.

One line per decision: what was decided, and the citation from the frozen plan, copied rather than paraphrased.

### The streak

D1. The streak is derived from the review log on every read and is not stored anywhere. No table and no migration carries it. Cited: `LaoshuKit/Sources/LaoshuKit/ReviewLog.swift:34-38` writes one row per swipe holding `word_index`, `reviewed_at` as a Unix timestamp, and a grade; `LaoshuKit/Sources/LaoshuKit/ReviewLogReplay.swift:35` already turns those timestamps into local days with `TodayProvider.businessDay(for:)`, so the grouping this needs is a proven read of an existing table.

D2. A day counts as studied when at least one review row falls in it. The day is the business day, which begins at 04:00 rather than midnight. Cited: `LaoshuKit/Sources/LaoshuKit/TodayProvider.swift`, whose `today()` and `businessDay(for:)` both call `LocalDate.businessDay`, and checkpoint 2 D9.

D3. The streak forgives one missed day, and at most one in any seven days. Two consecutive missed days end it, and so does a second missed day within a week of the last one forgiven. Cited: research 2026-09-09, both sides written out here rather than pointed at, since the note lives outside the repository and the decision record has to carry its own citation, as checkpoint 2 D9 does. For the slack: Duolingo's published A/B tests, blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals/, report the Weekend Amulet, which protects a streak across a weekend with no practice, made users 4 per cent more likely to return a week later and 5 per cent less likely to lose the streak, and Streak Freeze cut churn 21 per cent among users at risk. That is the vendor measuring its own feature, and it measures engagement rather than learning, so it settles the shape of the slack and not whether a streak belongs here. For the bound: Mogavi, Zhao, Hui and others, "When Gamification Spoils Your Learning", ACM Learning @ Scale 2022, dl.acm.org/doi/abs/10.1145/3491140.3528274, found learners fixate on the number and run minimum-effort sessions purely to preserve a streak. Forgiveness renewed at every step would make studying every other day grow the number without limit, which is that pattern made safe; one a week is the narrowest slack that keeps the first result and denies the second, and it is closer to the Amulet's own shape, scoped to one weekend and not self-renewing.

D4. The exact rule, which a builder implements without deciding anything. Let S be the distinct studied business days that are on or before today, sorted descending, and let `gap(a, b)` be `a.daysSince(b)`.
- S empty: streak 0, state `none`.
- `headGap = today.daysSince(S[0])`. If `headGap >= 3` the streak is broken: streak 0, state `none`. Today is not counted as a miss, because the day is not over, so a head two days back still leaves only one missed day.
- Carry `lastForgiven: LocalDate?`, the missed day most recently forgiven, starting nil. Forgiving a missed day `m` is allowed only when `lastForgiven` is nil or `lastForgiven.daysSince(m) >= 7`; otherwise the run ends there. Forgiving sets `lastForgiven = m`.
- `headGap == 2` is itself a forgiven day, `m = today.addingDays(-1)`, and consumes the allowance before the walk starts.
- Otherwise streak starts at 1 and walks the list: for each i from 1, `let g = gap(S[i-1], S[i])`. If `g == 1`, add one and continue. If `g == 2`, the missed day is `m = S[i-1].addingDays(-1)`: forgive it if the allowance permits, then add one and continue, else stop. If `g >= 3`, stop, since that is two consecutive missed days.
- The walk always stops rather than skipping, so the streak is the run ending at the most recent studied day and never a count of scattered days.

D5. The streak is a count of days studied, not of days elapsed. A streak of five can span six calendar days if one was forgiven. The screen says "5 days studied" for exactly this reason.

D6. The state shown beside the number is one of four, from `headGap` in D4: `studiedToday` (0), `notYetToday` (1), `restDayUsed` (2), `none` (broken, or never started). Cited: D4.

D7. The read is one full scan of `review`, grouping every row into its business day, with no early stop and no new index. Cited: `LaoshuDatabase.swift:80` creates `review_word_index` on `review(word_index)` and nothing else, so any order on `reviewed_at` is a scan and a sort whatever the query says, and an early stop would need an index D1 forbids. The size is bounded: `SessionEngine.swift:199` writes a row on every swipe and `:219-227` requeues a left-swiped card twice before parking it on the third, so a word takes at most nine rows across its three presentations, about 50,000 if all 5,400 words were failed at every look. A scan of 50,000 rows on a local SQLite file is cheap.

D8. Days the placement test was taken do not count as studied days. Cited: `PlacementSession.swift` and `PlacementStore.swift` contain no reference to `ReviewLog` (checked 2026-09-09), so the test writes batches and no review rows. A user who took the placement test and swiped nothing has a streak of 0, which is correct: they have not studied.

D9. The streak lives in a new file `LaoshuKit/Sources/LaoshuKit/Streak.swift`, holding a `Streak` value with `days: Int` and `state: StreakState`, and a `StreakReader` built from a `DatabaseQueue` and a `TodayProvider`. It is not added to `SessionEngine`. Cited: the rule, written out here because it lives in a working note rather than in this repository. Two pebbles in one wave build in separate worktrees off the same commit and merge independently, so two that edit one file conflict on merge even when their subjects share nothing. Checkpoint 4 met it: its browse query and its level-row change both wanted `SessionEngine.swift` and `LevelListView.swift`, and the cut had to give each a file of its own. This checkpoint sends two kit pebbles in one wave, so each gets a new file and neither touches `SessionEngine.swift`.

### What is waiting and what is learned

D10. A word is learned when it belongs to a batch whose `next_look_on` is NULL, by either of the two paths that write one. Cited: `LaoshuKit/Sources/LaoshuKit/Batch.swift:39`, where `lookTaken` nils it once `lookNumber` reaches 2, the end of the ladder; and `:47-52`, where `retiredForStaleness` nils it and forces `lookNumber` to 2 for a look the app gave up on. Both read as learned and the screen does not tell them apart, because it cannot: `look_number` is 2 on both and no column records which path wrote the row.

D10a. Counting the given-up batches as learned is honest here, and the reason is written down rather than assumed. `retiredForStaleness` has exactly one caller, `BatchScheduler.replayBatch` at `Batch.swift:85-87` (checked 2026-09-09), and that runs only in the v3 replay migration, over words that already had review rows. Every word it retires was therefore studied by the user on the pre-batch app; what the ladder gave up on was a second look more than seven days overdue, not the word. No path in the running app produces one. Cited: `LaoshuKit/Sources/LaoshuKit/Batch.swift:79-90` and checkpoint 2 D18.

D11. Words the placement test marked known count as learned. Cited: checkpoint 3 D5 and `BatchStore.createRetiredBatch`, which writes them as a batch with `next_look_on` NULL and `look_number` 2 precisely so the ladder is done with them. The user asserted they know those words, which is the same claim the screen makes.

D12. A word is in progress when it belongs to a batch whose `next_look_on` is not NULL, and is left when it belongs to no batch at all. The three counts partition the level and nothing else is counted, so the screen shows all three and they visibly sum to the level's word count.

D13. Waiting is the number of distinct words in batches of that level whose `next_look_on` is not NULL and is on or before today. The level list's own query counts rows rather than distinct words. Cited: `LaoshuKit/Sources/LaoshuKit/SessionEngine.swift:305-315`, which is `COUNT(*)` over `batch JOIN batch_word`. The two agree on every state reachable today, for the reason D16 gives, and D15 leaves the level list's query alone rather than editing `SessionEngine` to make them agree by construction. Should a later checkpoint make a word reachable in two due batches, this screen would show the smaller, truer number and the level list the larger one, and that is a defect to fix in the level list, not here.

D14. Waiting is a subset of in progress and the screen must not add them together. Each level row reads learned, in progress and left; waiting appears once, as one total at the top.

D15. The counts live in a new file `LaoshuKit/Sources/LaoshuKit/ProgressStore.swift`, holding `LevelProgress` with `level`, `wordCount`, `learnedCount`, `inProgressCount`, `leftCount` and `waitingCount`, and a `ProgressStore` built from a `DatabaseQueue` and a `TodayProvider`, reading them all in one `dbQueue.read`. It takes the provider for the same reason `StreakReader` does in D9 and `SessionEngine` does at `SessionEngine.swift:282`: D13's waiting count is relative to today, and a store that called `Date()` itself could not be tested against a fixed day. Its initialiser defaults the provider to `TodayProvider()`, as `SessionEngine`'s does. `LevelSummary` and `SessionEngine` are not edited. Cited: D9's reason.

D16. Every count is over distinct `word_index`, and learned means the word is in no batch that still has a `next_look_on`, not merely that it is in one retired batch. This is a guard, not a repair: no path today puts a word in two batches. Cited: `BatchStore.swift:96-109`, whose `unseenWordIndices` excludes any word already in `batch_word`, so neither a study batch nor the placement test's retired batches can draw one twice; `ReviewLogReplay.swift:20-37` groups with `GROUP BY r.word_index` and writes one batch per group, against batch tables the preceding migration had just created empty. Checkpoint 3 D7c is why the guard is worth having: `batch_word`'s composite key permits the state, and that checkpoint had to exclude it at the source rather than call it unlikely.

### The screen

D17. A new screen titled "Progress", pushed onto the level list's navigation stack as a third `LevelDestination` case, `case progress`. Cited: `Laoshu/LevelListView.swift:6-9`, the existing `LevelDestination` enum, and `:71-77`, its `navigationDestination`.

D18. The file and type are named `ProgressScreen`, not `ProgressView`. Cited: `ProgressView` is a SwiftUI type in scope in every file that imports SwiftUI, and `Laoshu/ProgressBar.swift` already exists, so the obvious name shadows a framework type in a file that also uses it.

D19. Its entry point is a leading toolbar item on the level list showing a `flame` glyph and the streak number, accessibility label "Progress, N days studied", or "Progress, 1 day studied" at one, or "Progress, no days yet" at zero (D22a). Cited: `Laoshu/LevelListView.swift:82-100` — both trailing toolbar slots are taken, by the placement checklist and the direction control, and checkpoint 11 D4a fixed the direction control's label as the exact words "Pinyin first" or "English first", so neither may be displaced.

D20. When the streak is 0 the toolbar item shows the flame alone with no number, and still opens the screen.

D20a. The toolbar item is not drawn at all while `loadError` is set. Cited: `Laoshu/LevelListView.swift:26-79` puts the `navigationDestination` inside the `else` branch that the database error screen replaces, while `:82-104` puts the toolbar outside it, so a badge left live over the error screen would push a destination with no view registered. The alternative, moving the `navigationDestination` out beside the toolbar, is rejected: it would also make the study and browse destinations resolvable in a state where their rows are not drawn, which is a wider change than this checkpoint needs. A progress screen reading the same database that just failed has nothing to add.

D21. The streak is not the largest thing on the Progress screen. It is one row at the top in the same type size as the counts below it. Cited: research 2026-09-09 — Mogavi, Zhao, Hui and others, "When Gamification Spoils Your Learning: A Qualitative Case Study of Gamification Misuse in a Language-Learning App", ACM Learning @ Scale 2022, dl.acm.org/doi/abs/10.1145/3491140.3528274, a qualitative study finding learners fixate on the streak number, run minimum-effort sessions to preserve it, and report stress tied to maintaining it rather than motivation to learn.

D22. Layout, top to bottom: a streak row, a waiting row, then six level rows, each "Level n" with learned, in progress and left.

D22a. Every string on the screen is fixed here, singular and plural and zero, so no builder invents one.
- Streak row, streak 0: one line reading "No days yet" and nothing underneath.
- Streak row, streak 1: "1 day studied".
- Streak row, streak 2 or more: "N days studied".
- Underneath a non-zero streak, D6's state as one of "Studied today", "Not yet today", or "Rest day used, study today to keep it". The fourth state, `none`, is the streak-0 case and has no second line.
- Waiting row, 0: "Nothing waiting today".
- Waiting row, 1: "1 word waiting today".
- Waiting row, 2 or more: "N words waiting today".
- Level row: "Level n" on the leading side, and one line on the trailing side reading "L learned, P in progress, R left", in that order, with all three numbers always shown including zero.
- The level row's three labels are not nouns and take no plural: "1 learned" and "0 in progress" read correctly as written, which is why this row needs no singular form and the two rows above it do.
- The level row's accessibility label is "Level n, L learned, P in progress, R left".

D23. Colours come from `LaoshuTheme` and nothing on the screen picks its own. Cited: `Laoshu/LaoshuTheme.swift`, whose comment says nothing else in the app picks its colors, and checkpoint 1 D28 and D29.

D24. Both reads run on every appearance, not once. Cited: checkpoint 2 D26 — `SessionEngine` is not `@Observable`, so nothing tells a view its counts are stale after a session or a day rollover, and the level list already solves this with `.onAppear` on the content inside the stack rather than on the stack itself.

### Wiring

D25. `RootView` builds `StreakReader` and `ProgressStore` inside `openDatabase()` from the same local queue that already builds the engine and the preference store, holds both in `@State`, and passes both to `LevelListView`. Both take the default `TodayProvider()`, which is the provider `SessionEngine` already gets there, so every number on both screens is relative to the same day. The queue itself is not held and no GRDB type is named anywhere in the app target. Cited: `Laoshu/RootView.swift:28-39`, where `dbQueue` is a local whose type is inferred and never written, and which builds `engine` and `preferenceStore` the same way; no file in `Laoshu/` imports GRDB (checked 2026-09-09), and `Laoshu.xcodeproj/project.pbxproj:223-228` declares exactly one package product dependency, `LaoshuKit`, so naming `DatabaseQueue` in the app would be a new import and possibly a new linked product.

D26. `LevelListView` gains two parameters, `streakReader` and `progressStore`, and passes both to `ProgressScreen`. Nothing else in the app changes shape. Cited: this is the pattern `RootView` and `LevelListView` already use for the engine and the preference store, `Laoshu/RootView.swift:28-39` and `Laoshu/LevelListView.swift:15-16`, so it adds no new idea to the app target.

D27. A failed streak read is swallowed and shows the bare flame, exactly as a failed direction write is swallowed and leaves the label where it was. It never sets `loadError`. Cited: checkpoint 11 D4a — "Losing the home screen because a preference did not save is worse than the preference not saving", and `Laoshu/LevelListView.swift:188-196`, which swallows on purpose for that reason. A cosmetic badge must not be a route that replaces the home screen with the database error screen.

D28. A failed read on the Progress screen replaces that screen's content with `DatabaseErrorView`, leaving the level list intact underneath. Cited: `Laoshu/LevelBrowseView.swift:14,23-24,93-97`, the pushed screen that already does exactly this. The two rules differ because the badge has something honest to show without its number and the screen has nothing.

D29. New Swift files in `Laoshu/` need no project file edit. Cited: `Laoshu.xcodeproj/project.pbxproj:17` is the one `PBXFileSystemSynchronizedRootGroup` entry, for the `Laoshu` directory, and `:61-63` lists it under the app target's `fileSystemSynchronizedGroups`, which is what makes a new file in that directory compile (checked 2026-09-09). An earlier round of this PRD said three entries, which was a count of grep hits including the section's begin and end comments.

D29a. The plan records that this screen is a motivation feature and not a retention mechanism, and no check or decision may claim otherwise. Cited: research 2026-09-09. "Stimulating learner engagement in app-based L2 vocabulary self-study: Goals and feedback for effective L2 pedagogy", System / ScienceDirect 2021, measures time on task rather than later recall, and no study in that literature isolates a retention gain from the feedback display itself; the Duolingo gamification systematic review, Computer Assisted Language Learning 2021, doi 10.1080/09588221.2021.1933540, finds learners struggle to translate visible in-app progress into real-world ability. What the evidence does support for a growing due queue is controlling the workload rather than showing it: Settles and Meeder, "A Trainable Spaced Repetition Model for Language Learning", ACL 2016, raised daily engagement 12 per cent in a live test that way. That is route line 10's job.

D30. This checkpoint adds no migration, no schema change and no package dependency. Every number it shows is a read of tables that already exist.

## Failure modes recorded in the plan

Nothing has ever been swiped: the streak is 0, the toolbar shows the bare flame, the streak row reads "No days yet", and every level reads 0 learned, 0 in progress, all left.

The user studied yesterday but not today: the streak holds its number and the state line reads "Not yet today".

The user studied two days ago and nothing since: the streak holds and the state line reads "Rest day used, study today to keep it".

The user studied every other day: the streak reaches 2 and stops growing, because the second missed day falls within a week of the first and is not forgiven (D3).

The user missed two full days: the streak reads 0 and the state line reads "No days yet", which is the same display as never having started. Deliberate; this plan does not build a separate broken wording.

The device clock moves backwards or the user travels across a date line: business days are computed on `Calendar.current`, so a streak can gain or lose a day. Nothing corrects it and no data is damaged, because the streak is derived and stores nothing.

The streak read throws: the toolbar shows the bare flame, the screen still opens, and nothing else changes (D27).

The Progress screen's read throws: the screen shows the database error message in place of its rows and the level list is untouched behind it (D28).

The level list's own read throws: the database error screen replaces the list and the flame is not drawn, so there is no way to push a screen the error state has no destination registered for (D20a).

The user took the placement test and has swiped nothing: the streak is 0 while the level rows already show a learned count. Correct on both counts, and the reason D8 exists.

A word was retired by the replay migration for staleness: it reads learned, alongside words that finished the ladder, because it was studied and nothing distinguishes the rows (D10a).

A word sits in two batches: it is counted once, and as in progress rather than learned while any of its batches still has a look due (D16).

## The research the streak rests on

Duolingo's published A/B tests, blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals/, report the Weekend Amulet, which protects a streak across a weekend with no practice, made users 4 per cent more likely to return a week later and 5 per cent less likely to lose the streak, and Streak Freeze cut churn 21 per cent among users at risk. This settles the shape of the slack the streak gives, per D3, but it is the vendor measuring its own feature's engagement rather than learning, and does not settle whether a streak belongs here at all.

Mogavi, Zhao, Hui and others, "When Gamification Spoils Your Learning: A Qualitative Case Study of Gamification Misuse in a Language-Learning App", ACM Learning @ Scale 2022, dl.acm.org/doi/abs/10.1145/3491140.3528274, found learners fixate on the streak number, run minimum-effort sessions purely to preserve it, and report stress tied to maintaining it rather than motivation to learn. This bounds the forgiveness rule at once a week, per D3, and keeps the streak from being the largest thing on the Progress screen, per D21.

## Checks run

All commands below were run from the repository root, on a machine with Xcode installed, which the compile gate requires.

- `swift test --package-path LaoshuKit` — passed, 148 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Laoshu -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — BUILD SUCCEEDED.
- `python3 docs/measure.py > /tmp/m.md && diff /tmp/m.md docs/measurements.md` — empty diff.
- `python3 docs/check_glosses.py` — `5400 glosses read, 5400 words expected, 0 problem(s)`.
- `swift run --package-path LaoshuKit laoshu-build-db --checksum data/laoshu.sqlite` — `5ecdd46167b033a7b6d235890148c3aa74726d5faaa9c576019397ba1e67b9a9`, unchanged from the checkpoint 8 record.
- `grep -rn 'import GRDB' Laoshu/` — empty.

## Not run here

These need a physical device and days of real time, so the user runs them on the phone:

1. Study on the phone today, then open the app tomorrow before studying and check the flame reads 2 only after tomorrow's session, and that the state line says "Not yet today" before it.
2. Skip a day on purpose, study on the day after, and check the streak carried through rather than resetting to 1.
3. Skip two days, and check the streak went to 0.
4. Study just before 04:00 and check the day it counted as.
5. Tap through the Slice's flow by hand: study a level, go back, see the flame, tap it, read the counts.

## Screens

The screens are read at step 9 of the light factory's chain by the planning session, on a Mac with Xcode and a booted simulator, after every pebble merges and before the checkpoint is called built. This task takes no screenshots and drives no simulator: there is no UI test target in this repository, and checkpoint 1 D10 says no automated check may depend on a simulator.

## Defects

The streak number did not render. `Label("\(streak.days)", systemImage: "flame")` inside a toolbar button draws as its icon alone on iOS 26, so the level list showed a flame with no number beside it, which is the one thing D17 and D22a exist to show. Setting `.labelStyle(.titleAndIcon)` on the label did not change it. The fix, in `Laoshu/LevelListView.swift`, is an explicit `HStack` holding an `Image` and a `Text`, which renders both. Found at step 9 by reading the screen in the simulator after this record's checks had already passed, which is why the commands above all held: no check in this repository can see a toolbar.

Every other command above ran and every assertion held.
