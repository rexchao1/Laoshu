# Checkpoint 7 decisions: Finish what you started

A study session survives the app being closed. Today the queue lives only in memory, so quitting mid-session, or even navigating back to the level list and tapping the level again, loses the position; and because the first swipe has already written the day's batch and advanced every due batch, drawing again the same day returns nothing. The half-done day is not interrupted, it is gone, and the words of any batch taking its second look are gone for good (D15a). After this checkpoint the session is written into the review database as it goes, one short transaction per swipe, and reopening the level on the same day brings back the same cards in the same order with each left-swipe count intact, the progress bar where it was, and a summary counting the whole session rather than the part after reopening. Nothing about the ladder, the allowance, the settings or the level list changes. The day boundary and the new-word budget this route line once also carried are already built, by checkpoints 2 and 6, so only resumption is left.

One line per decision: what was decided, and the citation from the frozen plan, copied rather than paraphrased.

### What survives, and why it is not a redraw

D1. A session swiped at least once survives the app being closed, force-quit or killed, and resumes when the user next opens that level on the same business day. Cited: route line 7, "a session that survives the app being closed and reopened, so a half-done day is not lost"; checkpoint 1 D22, "Session state lives in memory only... critique round 2 finding F6 moved persistence of session position to route line 7". This checkpoint is that deferred work and amends D22.

D2. Resuming means the same queue in the same order, with each card's left-swipe count intact, not a fresh draw that happens to hold the same words. Cited: research 2026-09-09, `resume-or-restart.md`: every major app resumes rather than restarts, Anki saves review state, Quizlet's Flashcards mode preserves progress on quit, and SuperMemo keeps explicit read-points so an article resumes at the exact stopping point (help.supermemo.org/wiki/Incremental_reading; help.quizlet.com). A 2025 meta-analysis of the Ovsiankina effect found a robust tendency to resume interrupted tasks when given the chance (nature.com/articles/s41599-025-05000-w).

D2a. Redrawing is not a different choice, it is broken. The first swipe writes the batch the session drew and records a look on every due batch, in its own transaction (`LaoshuKit/Sources/LaoshuKit/SessionEngine.swift:205-241`, behind `hasWrittenFirstSwipe`). A second `startSession` the same day then finds `hasBatchCreatedToday` true and takes no new words (`:364-365`), finds no due batch, and returns a zero-card session reading `allowanceSpent`. Reachable today without force-quitting: `SessionView` holds the session in `@State` (`Laoshu/SessionView.swift:10`) and starts it in `.task` (`:38-40`), so navigating back and tapping again recomposes.

D2b. The swipes are already durable and are not what this saves. Cited: checkpoint 1 D16 logs every swipe regardless of outcome, and D22 says "nothing is lost but the position". What is added is the position, the queue order and the left-swipe counts.

### What is remembered

D3. The session lives in two new tables in the review database, `session` and `session_card`, not in `UserDefaults`, `@SceneStorage` or a serialised blob. Cited: checkpoint 1 D10 requires every rule to be provable by `swift test`, which a store the tests cannot reach is not; research `scene-lifecycle.md` found `@SceneStorage` holds only small scalars, is scene-bound and is wiped when the user swipes the app away, so it is not for model data; research `persisting-a-queue.md` recommends normal rows with a state column and an order column, in the database already open.

D4. The `session` row holds what cannot be recomputed later: `id`, `level`, `created_on`, `direction`, `speak_on_flip`, `new_words_batch_id`, `status`. `new_words_batch_id` is null when the session introduced no new words and otherwise names the batch its first swipe wrote, which D8 reads the return date from. `direction` and `speak_on_flip` are the values the draw captured, because a resumed session that read them fresh would change its own rules mid-session: `SessionEngine.swift:110-118`, "captured once at the draw and fixed for its lifetime".

D4a. `created_on` is `today.today()` read inside the first swipe's transaction, not captured on `Session` at the draw, so the row's date always equals that of the batch the same transaction writes. Capturing at the draw breaks a session drawn 03:55 and first swiped 04:05: the row would carry yesterday's business date, stale the instant it committed, so the next `startSession` would retire it under D11a and the fresh draw would find `hasBatchCreatedToday` true and every due batch looked at, giving the `allowanceSpent` screen D2a exists to remove. Cited: `SessionEngine.swift:210-221` is the write, `:356-399` the draw; `TodayProvider.swift:18-20`. Round 4 F1.

D5. The `session_card` row holds one drawn word: `session_id`, `word_index`, `position`, `left_swipe_count`, `outcome`, `settled_order`. `position` is the card's place in the queue and is null once the card is settled. `outcome` is null while the card is still in the queue and otherwise `finished` or `parked`. `settled_order` orders the settled cards among themselves and is null while a card is pending. Cited: research `persisting-a-queue.md`, "one per item, with a state column and an order column".

D5a. `position` is a dense ordinal, 0 upwards, over pending cards only, and every swipe rewrites the position of every still-pending card from the queue rather than patching the rows it moved, so the two orders are equal by construction. Two statements, in this order: clear `position` to null on every row of the session, then write the ordinals. The other order collides with positions unmoved cards still hold, and D5b's index turns an ordinary left swipe into a failed write. The swiped card's row is settled or renumbered by the same rewrite. Cited: `SessionEngine.swift:237-238`, `min(3, queue.count)`, which shifts every card behind the reinsertion point, so any incremental scheme rewrites most of the tail anyway; a session holds tens of rows, in a transaction the swipe has opened. Rounds 1 F4, 2 F2.

D5b. A partial unique index, `session_card (session_id, position) WHERE position IS NOT NULL`, makes a duplicate position a failed write rather than a queue resuming in whatever order SQLite chose. Critique round 1 finding F4.

D5c. `settled_order` is `MAX(settled_order) + 1` over the session's own rows, starting at 0 when there are none, computed in the same statement that settles the card. It is not a counter held on `Session`, so nothing has to be restored at resume and post-resume cards cannot sort before pre-resume ones. Cited: `SessionEngine.swift:124-136`, where `parkedWords` is appended in swipe order and `Session` holds no swipe counter that a resume could rebuild. Critique round 1 finding F3.

D6. Every count is rebuilt from `session_card` at resume, none stored as its own column. `drawnCount` is the row count, `finishedCount` counts `outcome = 'finished'`, `parkedCount` `'parked'`, `firstAttemptRightCount` `'finished' AND left_swipe_count = 0`, and `parkedWords` is the parked rows by `settled_order`. Cited: `SessionEngine.swift:124-136`, where each is maintained in step with the queue by `swipe`, so a stored copy is a second source of truth.

D6a. After the resume the counts are held in memory and advanced by `swipe` as they are today; nothing queries the database to render a count. Cited: `Laoshu/SessionView.swift:122-125`, `progress(for:)`, which reads three of them on every layout pass.

D7. `newWordIndices` and `dueBatchIDs` are not stored. A row exists only because a swipe happened, and that swipe wrote the batch and recorded every look, so a resumed session has `hasWrittenFirstSwipe` true and nothing left to write. Cited: `SessionEngine.swift:205-241` again, and the doc comment at `:76-80`, "a session entered and abandoned without a swipe leaves no trace".

D8. `newWordsReturnOn` always comes from the batch, never from a recomputation. The first swipe sets it from the `Batch` its own `BatchStore.createBatch` call returns (`BatchStore.swift:41-63`), so it becomes `private(set) var`; a resume reads `next_look_on` through `new_words_batch_id`. Recomputing drifts, because `BatchScheduler.createBatch` floors the first look against `today.wallClockToday()`, the raw calendar day, not the business day (`Batch.swift:64-65`; `TodayProvider.swift:26-28`), and the wall-clock day turns at midnight while the business day runs to 04:00. Two cases: drawn 22:00 and resumed 01:00, where recomputing names a day later than the batch holds; drawn 23:50 and first swiped 00:05, one business day with no resume, where the value `Session.init` guessed at the draw (`SessionEngine.swift:177-179`) names a day earlier. Reading the row makes the doc comment at `:139-141`, "never drifts from what gets written", true by construction. Critique rounds 3 F2 and 4 F3.

D9. `hasUnseenWordsRemaining` is recomputed at resume as `unseenWordIndices(level:).isEmpty == false`, not stored. At the draw it is `unseenPool.count > newWordIndices.count` (`SessionEngine.swift:366`) because the batch is not written yet; by resume it is, so those words have already left the pool and the comparison against zero asks the same question.

D10. The queue's order is restored by fetching in `position` order and handing the indices to `Word.fetch(indices:dbQueue:)`, which returns words in the order given. Cited: `LaoshuKit/Sources/LaoshuKit/Word.swift:59-60`, `indices.compactMap { byIndex[$0] }`.

### When it is written and when it is read

D11. The `session` row and all its `session_card` rows are written in the same transaction as the first swipe's review row, beside the batch creation and ladder advance already there. A session drawn and left without a swipe writes no session row, creates no batch and spends no allowance. Cited: checkpoint 2 D7a and `SessionEngine.swift:76-80`; the existing test `testEnteringAndLeavingWithoutSwipingWritesNothingAndSpendsNoAllowance` must keep passing unchanged.

D11a. The one write a draw may make is retiring a stale row under D15: `startSession` marks a live row whose `created_on` is any business date other than today's `abandoned`, in its own short write, before it draws. Any other date, not only an earlier one: a future-dated row, left by a backwards clock or a westward flight, is no more resumable than a week-old one, and leaving it live would make D17's index refuse every swipe on the level (round 2 F3). This is bookkeeping on a session already over, not state of the one being drawn, so D11 still holds for everything the new one owns. It cannot ride the new session's first swipe: D17's index refuses a second live row, and deferring would make the fresh `Session` carry the dead row's id, which D30 says it does not. Critique round 1 finding F1.

D11b. `swipe` is restructured so the state it writes exists when it writes it. Today it removes the head card (`SessionEngine.swift:207`), opens the write (`:210-221`), and only afterwards calls `card.requeued()`, chooses park or requeue on `leftSwipeCount >= 3` and reinserts at `min(3, queue.count)` (`:224-240`), so inside the transaction the left-swiped card is neither in the queue nor in its post-swipe form. New order: settle or requeue the card and build the post-swipe pending queue as local values; then one write holding the review row, D11's batch work, the card's `outcome`, `left_swipe_count` and `settled_order`, and the D5a rewrite; then commit those to the queue, the counts and `newWordsReturnOn`, which D8 takes from the `Batch` the write returned. Critique round 3 finding F1.

D12. Every swipe, the first included, writes in the same transaction as its own review row: on a right swipe or a third left swipe, the card's `outcome` and `settled_order` under D5c; on a left swipe below the third, its incremented `left_swipe_count` with `outcome` still null, settling nothing and leaving the card pending where `min(3, queue.count)` put it; and always the D5a position rewrite. Cited: `SessionEngine.swift:231-239`. Rounds 2 F2 and 5 F2. Nothing is written on a `scenePhase` change and nothing is flushed at termination. Cited: research `scene-lifecycle.md`, "There is no dependable 'about to terminate' signal... `applicationWillTerminate` is not guaranteed" (developer.apple.com/documentation/swiftui/scenephase); research `persisting-a-queue.md`, "Batching the queue and flushing at `applicationDidEnterBackground` reintroduces the failure it is meant to prevent", each short transaction commits before the call returns, so a kill leaves the pre-swipe or the post-swipe state, never a torn one (sqlite.org/wal.html).

D12a. A swipe whose write throws leaves the queue and every count exactly as they were, so the session and `session_card` stay equal. Under D11b nothing is committed to `Session` when the write runs: the settle, the requeue, the park, the counts and `newWordsReturnOn` are local values simply not applied, and the head card was only read, never removed. Nothing to undo. This fixes a defect persistence exposes rather than creates: today `swipe` does `queue.removeFirst()` before the write (`SessionEngine.swift:207`) and never puts the card back, so a failed swipe silently drops it, while `Laoshu/SessionView.swift:129-131` claims "a throw leaves the same card in place". Cited: critique round 1 F2.

D13. `startSession(level:)` resumes when a `session` row for that level has `status = 'live'` and `created_on` equal to today's business date. Otherwise it draws as it does today. Cited: `SessionEngine.swift:356-397`, the draw this branches in front of, unchanged behind the branch.

D14. The business date is `TodayProvider.today()`, the 04:00 rollover the app already computes; no separate staleness window in hours is invented. Cited: checkpoint 2 D9 fixed the boundary; research `resume-or-restart.md` names Anki's "Next day starts at", default 4am, as the precedent (docs.ankiweb.net/preferences.html).

D15. A live session whose `created_on` is not today's business date is marked `abandoned`, in D11a's write, and a fresh session drawn in its place. Cited: research `resume-or-restart.md`, "No literature quantifies how long an abandoned session should stay resumable. Any cutoff is a product choice, not a finding, and should be recorded as one." This is that record: one business day, because the app already has that boundary.

D15a. What an abandoned session's unswiped words cost, since D15 turns on it. New words come back at their batch's first look; a batch on its first look comes back seven days later; but a batch taking its **second** look was retired by this session's own first swipe and never comes back, because `lookTaken` nils `nextLookOn` at look two (`LaoshuKit/Sources/LaoshuKit/Batch.swift:35-41`), `isDue` is false for a retired batch (`:22-29`), and `unseenWordIndices` excludes any word in any batch (`BatchStore.swift:96-108`). In a steady-state day of three batches that is up to a third of the cards. Cited: critique round 3 F3, which caught this decision claiming they came back. The loss is not created here — abandoning has cost this since checkpoint 2, and persistence removes every case but crossing a day boundary — nor fixed here: bringing a retired batch's unswiped words back is a new mechanism, and route line 9 exists to catch "the words the batches never re-taught". Settled 2026-09-08, "Skip days and the batches wait for you", is about batches not yet looked at, not a look already recorded.

D16. A session whose queue empties is marked `done` in the transaction of the swipe that emptied it. Cited: `SessionEngine.swift:186`, `isFinished` is `queue.isEmpty`, the same moment the summary replaces the card.

D17. At most one live session per level, enforced by the database and not by the code that writes it: a partial unique index on `session (level) WHERE status = 'live'`. Two levels' live sessions are independent, because every query `SessionStore` runs is keyed by `session.level` and nothing reads another level's row. The reason is not that a second level cannot draw the same day, which is false both ways: a second level with a due batch draws a full session that day (`LaoshuKit/Tests/LaoshuKitTests/SessionEngineTests.swift:540-566`), and the draw-more button ignores the allowance (checkpoint 2 D7a). Critique round 2 finding F4.

D18. A bonus session persists the same way and can itself be resumed. `startBonusSession` makes D11a's retirement write against any live row on the level, not only a stale one, because drawing more explicitly replaces whatever is in progress — but only once it has a non-empty draw in hand. A bonus request on a level with no unseen words returns a named reason and no cards (`SessionEngine.swift:411-432`, whose comment says the button is hidden then but "nothing in this API enforces that"); retiring first would destroy a live, resumable session and hand back nothing. Round 5 F1. Cited: `SessionEngine.swift:405-441` retires nothing today, so only this decision keeps a bonus draw off D17's index; `LaoshuKit/Tests/LaoshuKitTests/SessionEngineTests.swift:288-304`, where `testBonusSessionIgnoresTheAllowanceAndDrawsEightMoreNewWords` starts a bonus session while the ordinary one is still live with seven pending, and must keep passing unchanged. Through the app the rule never fires: the button appears only where the replaced session is `done` or was never written (`Laoshu/SessionView.swift:26-30`). Round 2 F1.

D19. Resuming reads once, at `startSession`, and never polls. Cited: checkpoint 2 D26, "`SessionEngine` is not `@Observable`, so nothing can currently tell the list its numbers are stale" — there is no change to poll for. `Session` itself is `@Observable` (`SessionEngine.swift:82-83`), which already redraws the card screen as the queue advances. Critique round 1 finding F6.

### What the user sees

D20. The card screen gains one line: under the progress bar, a resumed session shows "Picking up where you left off" until its first swipe, then it is gone for the rest of the session. Cited: research `resume-or-restart.md`, "interruptions damage memory for position in a sequence... a resumed session must show the learner where they are rather than dropping them back into an unlabelled queue". The bar at `Laoshu/SessionView.swift:45-48` shows the position; this says why it is not at zero.

D20a. The line's lifetime belongs to the view. `Session` exposes `isResumed`, a plain `Bool`; `SessionView` holds a `@State` flag seeded from it and cleared in its swipe handler. Cited: checkpoint 6 D13c put the setting on `Session` and left the wording to the view for the same reason.

D21. A resumed card comes back showing its prompt face, whatever face it was on when the app closed; flip state is not stored. Cited: `SessionEngine.swift:63-67`, `Card.requeued()` already resets `isFlipped` and `hasBeenRevealed` inside a session, so a card returning after a gap behaves like one returning after three others.

D22. Because `hasBeenRevealed` starts false on every resumed card, the first flip after resuming speaks the word when speak-on-flip is on. That is the intended reading of "the first look at the meaning", not a defect. Cited: checkpoint 6 D20 and `Laoshu/SessionView.swift:55-65`.

D23. The summary after a resumed session counts the whole session, not the part after resuming. Cited: D6; `session_card` holds every word the original draw took.

D24. The level list is unchanged: no badge, no "in progress" marker, no resume button. Cited: `Laoshu/LevelListView.swift:34-51`, whose whole tap target already starts a session, so resumption needs no gesture of its own and is invisible until the level is opened.

D24a. A level with a live half-done session shows no waiting count, and this checkpoint leaves that alone. The badge is drawn only when `waitingCount > 0` (`Laoshu/LevelListView.swift:45-48`); the count comes from batches whose `next_look_on` is on or before today (`SessionEngine.swift:317-327`), which the first swipe has already moved past today (`:217-219`). The row has read "no waiting" mid-session since checkpoint 2, before anything was persisted, so changing it is a level-list decision, not this one's. Critique round 1 finding F5.

D25. A resumed session keeps the direction and the speak-on-flip value its draw captured, so changing either mid-session does not change the session in progress. Cited: `SessionEngine.swift:106-118`, "a session's direction cannot change once it has started"; every card in the queue is built from that direction.

D25a. `new_words_per_day` is the exception, not stored on the row at all: a resumed session reads it live. It governs nothing about the resumed queue, only the draw-more button's number, and `startBonusSession` reads the live preference when that button is pressed (`SessionEngine.swift:406-408`). Storing it would make the button say one number and the draw take another. Persistence makes that reachable: the settings screen opens only from the level list (`Laoshu/LevelListView.swift:126-133`), and until now that trip destroyed the session. Cited: `Laoshu/SessionSummaryView.swift:46`; checkpoint 6 D13c. Round 4 F2.

### Storage and wiring

D26. Migration `v7_session`, after `v6_settings`, creating both tables and the indexes. Cited: `LaoshuKit/Sources/LaoshuKit/LaoshuDatabase.swift:163-172` is the v6 migration this follows in shape; `:96` is `batch_word`'s `REFERENCES batch(id)`, the existing style, with no `ON DELETE` because nothing here deletes a parent row. `word_index` gets no reference for the same reason `batch_word.word_index` gets none: the catalogue is a separate attached database.

D27. The migration is tested against a database built the way the previous version shipped it, using a fixture registering its own hand-copied v1 through v6 rather than calling the migrator under test. Cited: checkpoint 6 D24a and `LaoshuKit/Tests/LaoshuKitTests/TestFixtures.swift`, where three such fixtures already exist; a fourth is added for v6.

D28. A new `SessionStore` beside `BatchStore` and `PreferenceStore` owns every query against the two tables; `Session` and `SessionEngine` write no SQL of their own. Cited: `BatchStore.swift` and `PreferenceStore.swift` are the existing shape, and `Session.swipe` already calls `BatchStore` statics from inside its own transaction (`SessionEngine.swift:213-221`), the seam these writes join.

D29. `SessionStore`'s write methods take a `Database`, not a `DatabaseQueue`, so they run inside the caller's transaction rather than opening their own. Cited: `BatchStore.swift:42` and `:78` already take this shape for this reason.

D30. `Session` gains a `sessionID`, nil until the first swipe writes the row, and a public `isResumed`. Nothing else about its public surface changes, so `SessionSummaryView`, `SessionEmptyStateView` and `CardView` are untouched. Cited: `Laoshu/SessionSummaryView.swift:10-11`, which reads only existing properties.

D31. The app imports no GRDB and the kit no AVFoundation. Cited: the two greps in every closure task since checkpoint 1.

D32. Two statements become false and are corrected. The doc comment at `SessionEngine.swift:72-74`, "D22: session state lives only in memory. Closing the app abandons whatever is left in the queue", states the decision D1 amends. And `WriteSnapshot` (`LaoshuKit/Tests/LaoshuKitTests/SessionEngineTests.swift:649-662`) calls itself "a snapshot of every row in the tables a swipe or a batch write could touch" while reading only `review`, `batch`, `batch_word` and `placement`; it gains `session` and `session_card`, so the browse-writes-nothing tests at `:793`, `:808` and `:819` keep proving what they claim. Round 5 F5.

## Failure modes

The app is killed between two swipes. The last committed swipe is the resume point; the review log and the queue agree, both being written in one transaction. Cited: research `persisting-a-queue.md`.

The app is killed during a swipe's transaction. SQLite rolls it back: the card is still pending, its review row absent. The user swipes it again, nothing double counted.

A swipe's write throws while the app runs. D12a leaves the queue untouched, so screen and database still agree; the user sees the existing message and swipes again.

The system suspends the app while it holds a SQLite lock and the watchdog kills it with `0xDEAD10CC`. The database is not damaged and the app reopens normally. Named and deliberately not guarded: every write here happens inside a user swipe, which requires the foreground, so no write is ever in flight during suspension. The guards, `beginBackgroundTask` or GRDB's `observesSuspensionNotifications`, are recorded rather than built. Cited: research `persisting-a-queue.md`, GRDB issue 957, Apple Developer Forums thread 126438.

The database read at resume throws. The screen shows `DatabaseErrorView`, the path `Laoshu/SessionView.swift:22-23` already takes for a failed draw.

A live row with no cards, which one transaction makes impossible through the API. If one is found anyway it is marked abandoned and a fresh session drawn.

A `session_card` row whose `word_index` the catalogue no longer resolves. `Word.fetch` drops it silently (`Word.swift:59-60`, `indices.compactMap`), so the queue would come back shorter than `drawnCount` and the bar would never fill. A resume whose fetched word count is not the stored row count is treated as corrupt: marked abandoned, fresh session drawn, as for the empty-card case. Round 5 F4.

Two live rows for one level. The partial unique index makes the second insert fail, so the bug surfaces as a failed swipe rather than a silently duplicated session.

The clock moves backwards or the device changes timezone, so a live row reads as created on a future date. D11a retires it and D15 draws fresh. That is why D11a is written against any date other than today's: a future-dated row left live would hold D17's index and fail every swipe on the level until the local date caught up. The user loses a position, not a word.

The user finishes a resumed session and taps draw more. The finished row is `done`, so the bonus row inserts against a free index. Cited: D16, D17, D18.

## Checks run

All commands below were run from the repository root, on a machine with Xcode installed, which the compile gate requires.

- `swift test --package-path LaoshuKit` — passed, 193 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Laoshu -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — BUILD SUCCEEDED.
- `python3 docs/measure.py > /tmp/m.md && diff /tmp/m.md docs/measurements.md` — empty diff.
- `python3 docs/check_glosses.py` — `5400 glosses read, 5400 words expected, 0 problem(s)`.
- `swift run --package-path LaoshuKit laoshu-build-db --checksum data/laoshu.sqlite` — `5ecdd46167b033a7b6d235890148c3aa74726d5faaa9c576019397ba1e67b9a9`, unchanged from the checkpoint 6 record.
- `grep -rn 'import GRDB' Laoshu/` — empty.
- `grep -rn 'import AVFoundation' LaoshuKit/Sources/` — empty.
- `grep -rn 'session state lives only in memory' LaoshuKit/` — empty; D32 rewrote it.

Every test named in the frozen plan's acceptance checks is present, by that exact name, and passing among the 193: `testASessionSwipedPartwayComesBackWithTheSameQueueInTheSameOrder`, `testAResumedSessionKeepsEachCardsLeftSwipeCount`, `testAResumedSessionsSummaryCountsTheWholeSessionNotJustThePartAfterResuming`, `testASessionFromAnEarlierBusinessDayIsAbandonedAndAFreshOneDrawn`, `testEnteringAndLeavingWithoutSwipingWritesNoSessionRow`, `testASecondLiveSessionOnTheSameLevelIsRefusedByTheDatabase`, `testASessionOnOneLevelDoesNotDisturbALiveSessionOnAnother`, `testAFinishedSessionIsMarkedDoneAndIsNotResumed`, `testABonusSessionPersistsAndResumesLikeAnyOther`, `testAResumedSessionKeepsTheSettingsItWasDrawnWith`, `testResumeReadsADatabaseWrittenByThePreviousVersion`, `testASwipeWhoseWriteThrowsLeavesTheCardAtTheHeadOfTheQueue`, `testADrawOnANewDayRetiresYesterdaysRowAndWritesNothingElse`, `testALeftSwipedCardResumesAtThePlaceTheLeftSwipePutIt`, `testParkedWordsKeepTheirOrderAcrossAResume`, `testAFutureDatedLiveSessionIsRetiredRatherThanBlockingTheLevel`, `testABonusDrawRetiresALiveSessionOnTheSameLevel`, `testAResumedSessionNamesTheReturnDateTheBatchActuallyHolds`, `testTheSummaryNamesTheReturnDateTheBatchHoldsWhenTheFirstSwipeCrossesMidnight`, `testASessionDrawnBeforeAndFirstSwipedAfterTheDayBoundaryIsResumable`, `testAResumedSessionsDrawMoreButtonShowsTheCurrentSetting`, `testABonusDrawOnAnExhaustedLevelLeavesTheLiveSessionAlone`, `testAResumeWhoseWordsNoLongerResolveAbandonsTheSessionAndDrawsFresh`.

## Not run here

The frozen plan's own flow, in the user's words, "a half-done day is not lost": draw a session, swipe some right and some left, kill the app, reopen it, tap the same level, and find the same cards still to do with the counts that were there. The plan itself says why this is not run here: "There is no UI test target here and checkpoint 1 D10 forbids an automated check depending on a simulator, so this flow is run by hand at step 9 against a seeded database." This task did not run it and does not claim to have.

The plan's five screens (a session part way through; the same level reopened after a kill, with "Picking up where you left off"; the same screen after one swipe, the line gone; the summary of a resumed session showing the full drawn count; a level whose live session was created on an earlier business day, reopened) are likewise read at step 9 of the light factory's chain, by the planning session, on a Mac with Xcode and a booted simulator, after every pebble merges and before the checkpoint is called built. This task took no screenshots and drove no simulator, since there is no UI test target in this repository and checkpoint 1 D10 says no automated check may depend on a simulator.

Route line 9 and route line 13 are out of this task's scope, as the pebble that cut it says, and are not addressed here.

## Defects

Scoped to what the checks run here could show: none. Every command above ran and every named test passed. What these checks cannot show — the resumed flow itself, the "Picking up where you left off" line's appearance and disappearance, and the summary and allowance-spent screens as drawn on a device — is unread by this task; step 9's screen read is where a defect in any of those would surface, and this record makes no claim about them either way.
