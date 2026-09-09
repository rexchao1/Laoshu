# Checkpoint 10 decisions: Spread the backlog

A study session on a level no longer draws every batch that has come due there, only the three oldest. A user who studies daily never notices: a steady-state day is due at most two batches, yesterday's new one at its first look and one from eight days ago at its second. A user who has been away for a while does notice, in a good way — checkpoint 2 D8 named the case a week's absence produces, seven batches and 56 words landing in one session on top of the day's eight new ones, and left pacing it to a route line of its own. This checkpoint is that line, built as the simple cap the user chose over an adaptive scheduler when asked which way to take it on 2026-09-09: a session draws at most three due batches, oldest due first, and whatever is left over is not touched in any way, so it stays exactly as due as it was and the next session picks up where this one left off.

One line per decision: what was decided, and why.

D1. The cap applies to `SessionEngine.startSession(level:)` only, at `LaoshuKit/Sources/LaoshuKit/SessionEngine.swift`, as a new `maxDueBatchesPerSession = 3` constant. `BatchStore.dueBatches(level:today:)` already orders its result by `next_look_on` ascending, so `.prefix(3)` is "the three oldest" with no extra sort. The batches past the cap are simply excluded from `dueBatchIDs`: nothing calls `recordLook` on them, so `next_look_on` and `look_number` are untouched and `dueBatches` returns them again, unchanged, the next time anything asks. Cited: checkpoint 2 D8, "Pacing that return is a route line of its own, built next, rather than work folded in here"; the review answer of 2026-09-09 choosing "simple cap: only ever draw N due batches per session, carry the rest over" over an adaptive scheduler.

D2. Three, not some other number, because it is the smallest cap that never touches a steady-state day. `Batch.lookTaken` puts a batch's second look seven days after the first was actually taken, and `BatchScheduler.createBatch` puts the first look the day after the batch was created, so a user studying every day is due at most two batches on any given day — one entering its first look, one entering its second — before this cap ever applies. A cap of three leaves that case untouched and only bites once a third batch is overdue at the same time, which only happens after a missed day or more. Cited: the same review answer, which left the exact number to be picked rather than naming one; `LaoshuKit/Sources/LaoshuKit/Batch.swift`'s `lookTaken` and `BatchScheduler.createBatch`.

D3. `LevelSummary.waitingCount` and `LevelProgress.waitingCount`, shown on the level list and the progress screen, are not capped and keep counting every word behind a due batch, capped batches included. They are informational reads that write nothing and schedule nothing, unlike a session's draw; capping what they report would make the level list say fewer words are waiting than a session actually holds once the backlog clears down to three batches or fewer. Cited: `LaoshuKit/Sources/LaoshuKit/SessionEngine.swift`'s `levelSummaries()` and `LaoshuKit/Sources/LaoshuKit/ProgressStore.swift`'s `progress()`, both pure reads over the same `batch` rows a capped draw leaves untouched.

D4. No new schema, no new setting, no new dependency. The cap is a constant in `SessionEngine`, not a preference row — the review answer asked for a simple cap, not a tunable one, and a wrong constant is one line to change later. Cited: checkpoint 2 D23's "no new package dependency" as the pattern this follows for scope; the review answer of 2026-09-09.

## Failure modes

A user away long enough to backlog more than three batches on a level sees the same words for several sessions in a row before the level's due queue clears, rather than one very large session. This is the point of the cap, not a defect in it, but it does mean the newest-due batches in a long backlog wait longest — the ordering is strictly oldest-first, so a batch overdue by three weeks is drawn before one overdue by three days regardless of which the user might rather see first.

The level list's waiting count (D3) can read higher than what today's session actually offers, once a backlog exceeds the cap. Nothing here explains that gap on screen; the number is honest about the backlog, not about what one session will draw from it.

## Checks run

- `swift test --package-path LaoshuKit --filter SessionEngineTests` — passed, including a new test creating five due batches with distinct due dates and asserting the session draws only the three oldest by word (six words, indices 1-6) while the two others are left due, unadvanced, at `look_number == 0`.
- `scripts/check` — all six checks pass.

## Not run here

The user runs this on the phone: leave the app long enough (or move the simulator's clock) for a level to backlog four or more due batches, open that level, and confirm the session offers roughly half the backlog rather than all of it, with the rest still waiting afterward.
