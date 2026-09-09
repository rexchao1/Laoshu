# Checkpoint 9 decisions: What the batches never re-taught

A finished level — every word introduced, every batch retired — now offers a level test from the screen checkpoint 2 D22 left bare for exactly this. The test samples up to twenty of the level's words at random, in whichever direction the user currently studies, and grades each one once: flip to see the answer, swipe right if it was known, left if it wasn't. There is no second chance inside the test and no requeue. The user chose, when asked on 2026-09-09, to make this diagnostic only: nothing about the ladder changes regardless of the score. Passing or failing writes one row recording the attempt and nothing else — no batch is created, advanced, retired, or unretired by a level test, ever.

One line per decision: what was decided, and why.

D1. A level test is diagnostic, full stop. Cited: the review answer of 2026-09-09, choosing "diagnostic only, no schedule change" over requeuing failed words for more practice. `LevelTest.answer(_:)` at `LaoshuKit/Sources/LaoshuKit/LevelTest.swift` never calls anything in `BatchStore`; the only write it makes is its own `level_test` row. A left swipe drops the card from the queue for good rather than requeuing it, unlike a study session's left swipe — this is a single graded pass, not another drill on the same words.

D2. The test is reachable from exactly one place: the finished-level empty state, `SessionEmptyStateView`'s `.levelComplete` case, via a new "Take the level test" button. Cited: checkpoint 2 D22, "Route line 9 puts its graded level test on this screen, which is where the user asked for it," and its own note that state (c) "ships bare" until this checkpoint. The button is not gated on having never been taken — every level test result is a `level_test` row keyed on `level`, overwritten by the next attempt, so the button stays available for a retake at any time, and the empty state also shows the last attempt's score once one exists.

D3. A level test samples 20 words from every word `cat.word` has for the level, not from whatever a batch happens to be carrying. `SessionEngine.startLevelTest(level:)` queries `cat.word` directly. This is reachable only from `.levelComplete`, where every word in the level is already introduced and every batch has already retired, so "every word in the level" and "every word already met" are the same set at the moment the button can be tapped — there is no risk of testing an unseen word. 20 is a constant (`LevelTest.size`), not a setting: it is comfortably more than an ordinary session's default eight, without asking for anywhere near a full level (300 to 1,800 words) in one sitting, and it is one line to change later if it turns out wrong.

D4. The pass mark is 80% (`LevelTest.passThreshold`). Since D1 makes the result diagnostic, nothing downstream depends on this number being exactly right — it decides only whether the empty state's last-score line also says "passed," and whether `LevelTestResult.passed` is `true`. Kept as a constant for the same reason as D3's 20.

D5. The test asks in whichever direction (`StudyDirection`) the user currently has set, read from the same `preference` row a study session reads. A level test that quizzed the opposite direction from what the user actually practises would not be testing what the batches taught. `LevelTest.speakOnFlip` is read from the same row too, so the first reveal speaks the word exactly as it would in an ordinary session (checkpoint 1 D7, checkpoint 6 D9-D11).

D6. One row per level in a new `level_test` table (migration `v8_level_test`), shaped like `preference` and `placement`: `level` as the primary key, so a second attempt overwrites rather than accumulating history. Cited: `LaoshuKit/Sources/LaoshuKit/LaoshuDatabase.swift`'s existing `preference` and `placement` migrations as the pattern; nothing in this checkpoint needs to know when an earlier attempt happened, only the most recent one.

D7. `LevelTest` reuses `Card` and `CardView` exactly as a study session does — same two faces, same flip gating on `hasBeenRevealed` before a swipe can grade it. `LevelTestView.swift` is its own view (mirroring `PlacementTestView`'s reasoning for not reusing `SessionView`'s gesture) because a level test's swipe means something different — right means "I knew it," permanently, not "advance the ladder" — even though the mechanics of flipping and swiping are identical.

## Failure modes

Testing 20 of a level's words rather than all of them means a level test's score is a sample, not a census; a level with 1,800 words (level 6) is checked roughly 1% at a time per attempt, and a user could pass several attempts in a row while a portion of the level neither attempt happened to draw stays genuinely shaky. Nothing detects this, and nothing here claims a passed level test means every word in the level is known.

The 80% pass mark and 20-word sample size are both picked, not derived — there is no literature citation behind either number the way earlier checkpoints cite one for the direction or the pacing cap, because the diagnostic-only decision (D1) means neither number changes what the app actually does for the user. If either turns out to feel wrong once used, it is one line in `LevelTest.swift`.

A user who retakes a level test loses the previous attempt's row outright (D6) — there is no way to see whether a score is improving over time, only the single latest one.

## Checks run

- `swift test --package-path LaoshuKit --filter LevelTestTests` — passed, 8 tests: the sample-size cap, that a left answer never requeues and every word is seen exactly once, that the result is written only once the last card is answered (and never before), the 80% pass/fail boundary, that a second attempt overwrites the first rather than accumulating, that the current study direction is respected, that `levelTestResult` reads `nil` before any attempt, and that migration `v8_level_test` adds the table to a database built the way checkpoint 11 shipped without touching a single existing `batch`, `batch_word`, or `review` row.
- `swift test --package-path LaoshuKit` — passed, 202 tests total.
- `scripts/check-full` — all six checks and the app build pass.
- Seeded a level-1 database on the simulator directly (a retired batch holding all 300 of the level's words, so the level reads `.levelComplete`) and confirmed by screenshot that the level list still renders and the app launches cleanly against the new `level_test` table with no migration failure.

## Not run here

This environment has no accessibility permission for UI automation and no `idb` installed, so the level test screen itself — the card, the flip, the swipe, the result screen — could not be driven and screenshotted here the way `scripts/run` plus `scripts/screenshot` verify a UI change on a real machine. The user runs this on the phone or in Xcode directly:

1. Finish a small level (or seed one, as this task did on the simulator) and confirm the empty state shows "Take the level test" and, after one attempt, a "Last level test: N%" line.
2. Take the test: confirm each card flips to reveal the answer, a right swipe advances without requeuing, a left swipe does the same, and the queue never grows.
3. Confirm the result screen shows the correct count and percentage, and reads "Passed" only at 80% or above.
4. Take it again and confirm the level list's empty state now shows the new score, not the old one.
5. Confirm nothing about the level's batches or waiting count changed because of taking the test, in either direction.
