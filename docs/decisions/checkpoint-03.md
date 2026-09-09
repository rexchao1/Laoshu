# Checkpoint 3 decisions: Place a new user, and let anyone re-place themselves

One line per decision: what was decided, and the citation copied rather than paraphrased.
This checkpoint's decisions live in the shipped code and its own comments and commit messages, not in a separate PRD file in this repository — no such file is committed here, and the closure task received no PRD text to quote from directly.
Every citation below points at the actual source: a doc comment, a commit message, or a review finding, each copied verbatim.

D1. The walk begins at level 2 and moves one level up or down a block at a time.
Cited: `LaoshuKit/Sources/LaoshuKit/PlacementTest.swift` line 17, "`public static let startingLevel = 2`"; line 34-35, "What a fresh walk does first — always the starting level's block. `public static var initialStep: Step { .testLevel(startingLevel) }`".

D5. A block of five words is scored: four or five known moves up a level, zero or one moves down, two or three stops the walk with a recommendation.
Cited: `LaoshuKit/Sources/LaoshuKit/PlacementTest.swift` lines 37-39, "Scores a block of `PlacementTest.blockSize` words at `level`: `knownCount` of them answered \"know it\". Four or five known moves up a level; zero or one moves down; two or three stops the walk."

D7c. A placement block draws from the same unseen pool a study session's new-word draw uses, so a word already sitting in any batch — including one the test itself already wrote — is unreachable to it.
Cited: `LaoshuKit/Sources/LaoshuKit/PlacementSession.swift` lines 81-84, "Draws a level's block from the same unseen pool a study session's new-word draw uses (D7c) — a word already sitting in another batch, including one this test itself already wrote, is unreachable here."

D7e. A level whose pool of unbatched words comes up short of a full block is treated as known outright, with no block ever shown, and always calls a move up, stopping if that move is refused.
Cited: `LaoshuKit/Sources/LaoshuKit/PlacementTest.swift` lines 56-58, "A level whose pool of unbatched words came up short of a full block (D7e): treated as known outright, with no block ever shown, and always calling a move up — stopping if that move is refused."

D10. A word answered "know it" is written as a retired batch only once the whole walk finishes, one batch per level marked, never as each answer comes in — so a test abandoned partway through leaves no trace, the same way a study session defers its first write to the first swipe.
Cited: `LaoshuKit/Sources/LaoshuKit/PlacementSession.swift` lines 14-17, "D10: a word answered \"know it\" is written as a retired batch only once the whole walk finishes, one batch per level marked — never as each answer comes in — so a test abandoned partway through leaves no trace, the same way `Session` defers its first write to the first swipe."

D11. The placement test is presented as a full-screen cover over the level list rather than replacing it; the list and the navigation stack that owns its path stay mounted underneath for the whole time the cover is up.
Cited: `Laoshu/LevelListView.swift` lines 68-70, "D11: presented over the level list rather than replacing it — the list, and the `NavigationStack` that owns `path`, stay mounted underneath for the whole time this cover is up."

D11a. The first-launch gate fires only when placement genuinely has not been taken; a test already taken or declined leaves it a no-op even though the check runs again every time the level list comes back to the top.
Cited: `Laoshu/LevelListView.swift` lines 98-101, "Fires the first-launch gate only when placement genuinely has not been taken (D11a) — a test already taken or declined leaves this a no-op even though `onAppear` runs again every time the list comes back to the top."

D12. The recommendation is the lowest level tested whose block had three or fewer of five known, or the highest level reached when every level tested had four or more known.
Cited: `LaoshuKit/Sources/LaoshuKit/PlacementTest.swift` lines 73-75, "The lowest level tested whose block had three or fewer of five known, or the highest level reached when every level tested had four or more known (D12)."

D13 / D13a. A single row in a new `placement` table records whether the test has been taken or declined, and the level it recommended, never set when declined. A phone that already holds weeks of study — any batch or review row — is seeded as already taken with no recommended level, since nothing recommended anything to it; an empty database is seeded not taken, so the gate fires only for a genuinely fresh install.
Cited: `LaoshuKit/Sources/LaoshuKit/LaoshuDatabase.swift` lines 113-119, "D13/D13a: a single row recording whether the placement test has been taken or declined, and the level it recommended (never set when declined). A phone that already holds weeks of study — any batch or review row — is seeded as already taken with no recommended level, so the first-run gate this table backs never fires for a user who has been studying for weeks (D14). An empty database is seeded not taken, so the gate fires."; schema constraint at lines 122-132, "CHECK (status IN ('not_taken', 'taken', 'declined')) ... CHECK (status = 'taken' OR recommended_level IS NULL)".

D14. Seeding an already-studied phone as taken, with no recommendation, is what keeps the first-run gate from firing for a user who has been studying for weeks.
Cited: same passage as D13/D13a above, parenthetical "(D14)"; PR #11 commit message, "There was nowhere to record that the placement test had been taken or declined, so a first-run gate had nothing to read. The v4 migration adds that table and seeds it: already taken with no recommended level when the database it runs on already holds any batch or review row, not taken otherwise, so the gate only fires for a genuinely fresh install."; the same commit records the fixture rule this decision depends on: "The upgrade fixture is built on the schema checkpoint 2 actually shipped rather than through the migrator under test, per the D14 lesson from 6b1b765 - a fixture built by the migrator under test proves nothing about upgrades."

D13a (payload). The recommended level carried by a taken placement is optional, because a taken placement does not always carry one — a seeded-taken phone has none.
Cited: `LaoshuKit/Sources/LaoshuKit/PlacementStore.swift` lines 9-11, "The level is optional because a taken placement does not always carry one: D13a seeds a phone that already holds study as taken with no recommendation, since nothing recommended anything to it."
This decision was nearly shipped broken: the first cut of `PlacementStore.status()` decoded the seeded-taken row's null level into a non-optional `Int`, which traps. Cited, PR #13 review, "GRDB's non-optional `Row` subscript is `try! decode(...)`, so a NULL traps. ... `LevelListView.onAppear` → `checkPlacementGate()` → `placementStatus()` runs on the very first frame after the level list appears, so an upgrading user's app dies before the list draws." The type was made optional and the fix landed in the same task; see Checks run below for the state as merged.

D17. A placement card looks like a study card's front — pinyin large, hanzi small and grey beneath it — but has no back and no speaker glyph, since there is nothing to replay and nothing to reveal; a placement card never asks to be flipped, and checkpoint 1's swipe-after-reveal gate has nothing to protect here, so the test owns its own swipe gesture rather than reusing the study session's. The end screen names the recommended level and lists, by pinyin and meaning, every word the walk marked as known.
Cited: `Laoshu/PlacementCardView.swift` lines 4-7, "The placement test's card: pinyin large with the hanzi small and grey beneath it, as the study card front does (D17). No speaker glyph and no back — there is nothing to replay and nothing to reveal, since a placement card never asks to be flipped."; `Laoshu/PlacementTestView.swift` lines 7-11, "D17: checkpoint 1's D26/D26a gate a study card's swipe on the card having been revealed, so a card whose meaning was never shown cannot write a review row. A placement card has no back and writes no review row, so that gate has nothing to protect and would only make the card unswipeable — this view owns its own gesture rather than reusing `SessionView`'s."; `Laoshu/PlacementResultView.swift` lines 5-6, "The placement test's end screen: the level it recommends and, by pinyin and meaning, every word the walk marked as known (D17)."

D17a. The end screen's empty case — no words marked known — follows the voice the end-of-session summary already uses for its own empty case.
Cited: `Laoshu/PlacementResultView.swift` line 6, "Follows the voice `SessionSummaryView` already uses for its own empty case (D17a)."; `LaoshuKit/Sources/LaoshuKit/PlacementSession.swift` lines 38-41, "Every word answered \"know it\", in answer order — the end screen's list, by pinyin and meaning, of what the test marked as known (D17, D17a)."

D22 (from checkpoint 2, closed here). Checkpoint 2 shipped the finished-level screen bare, with a note that a self-review or a test belonged there. This checkpoint is that button, reached instead from a toolbar control on the level list, runnable any time after the first-launch gate has fired once.
Cited: checkpoint 2 D22, "state (c) ships bare (review annotation 2026-09-08 on the finished-level mockup, \"This is where a button for a self review should be or a test\")"; PR #13 commit message, "Adds the first-launch gate, the test card, its progress bar, and the end screen naming the recommended level and every word marked known. A skip records the decline so the gate never fires again, and a toolbar control on the level list runs the test any time after that."

## The research on self-report over-claiming

The placement test's method is self-report: the user says whether she already knows a word, and that answer alone decides whether the word is ever taught. Research on vocabulary self-assessment finds people reliably over-claim words they do not actually know, which is exactly the failure mode this design is exposed to — a word marked "know it" is retired and never looked at again, so an over-claim here is not a small error, it is a word the app will never teach.

This risk was put to the user and declined as a reason to change the design: no test, quiz-back, or production check was added to the placement walk to catch an over-claimed word, and D7 (checkpoint 2) and D10/D12 above show the walk still turns bare self-report answers directly into recommendations and retired batches. What the user chose instead is not recorded in this repository: no commit, comment, or measurement in this codebase names the research, the conversation that raised it, or the alternative offered. The closure task's own brief states plainly that this exchange happened and that its outcome should be written down here, but the frozen PRD text carrying the actual research citation and the user's answer was not available to the agent completing this closure task, so it cannot be copied here rather than paraphrased.

**This line needs the user's attention**: the record above states that the risk was measured and declined, per the closure task's own instruction, but the specific research citation and the alternative the user chose could not be recovered from anything committed to this repository. Whoever holds the frozen checkpoint 3 PRD should paste the actual decision and citation into this section verbatim.

## Checks run

All commands below were run on a machine with Xcode installed, which the `xcodebuild` gate requires.

- `swift test --package-path LaoshuKit` — passed, 86 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Laoshu -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — BUILD SUCCEEDED.
- `python3 docs/measure.py > /tmp/m.md && diff /tmp/m.md docs/measurements.md` — empty diff.
- `swift run --package-path LaoshuKit laoshu-build-db --checksum data/laoshu.sqlite` — `c4a5f6c2d416185e1f7f3bc071268cfa282ae78d66ddb834e5fb91c413f360a5`, unchanged from the checkpoint 1 and checkpoint 2 records: this checkpoint touches no catalogue data.
- `sqlite3 data/laoshu.sqlite "select level, count(*) from word group by level order by level"` — 1|300, 2|200, 3|500, 4|1000, 5|1600, 6|1800, unchanged.

## Not run here

The manual pass on the phone is the user's to run after this closure task merges, since it needs a physical device and eyes on it. The review log lives in the app container, and a delete-and-reinstall destroys the studied database that the first two steps are the only check of, so those two run first and nothing here deletes the app before they are done.

1. Open the app on a phone still holding checkpoint 1 study (review rows, no batches yet) and confirm it opens without crashing and the placement gate does not fire.
2. Open the app on a phone already holding checkpoint 2 study (batches on the ladder) and confirm the same: no crash, no gate, and no recommended level shown anywhere for it.
3. Only after both of those, delete and reinstall for a genuinely fresh phone and confirm the placement gate fires on first launch.
4. Swipe through the test's blocks and confirm the walk moves as D5 says: four or five known in a block moves up a level, zero or one moves down, two or three stops with a recommendation.
5. Finish the test and confirm the end screen names the recommended level and lists every word marked known, and that those words never come up again as new study words in any level.
6. Decline the test on a fresh phone and confirm the gate never fires again, while the toolbar checklist button still opens it on request.
7. Run the test again later from the toolbar button, mark a word known, and confirm it is retired the same way and spends none of the day's eight-word allowance.
