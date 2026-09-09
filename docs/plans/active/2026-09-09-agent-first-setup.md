# Agent-first setup for Laoshu

## Goal

A fresh agent session can find the code for a change, make it, and verify it using only this repository's guidance and scripts.

## Context

Laoshu is the pilot for a workflow change across the user's repositories: short instruction files, an architecture map, reliable commands, and boundaries that a check enforces. Before this plan the repository had a README with commands and `docs/decisions/` but no instruction file, no scripts, and no statement of what may import what.

## Constraints

- Keep every existing check and test. `docs/check_glosses.py`, `docs/measure.py`, and `docs/decisions/` stay where they are.
- Behavior of the app does not change in this work.
- No boundary check is added without a fixture that shows it rejecting a forbidden dependency.

## Done when

- `scripts/check` and `scripts/check-full` are green on a clean checkout with the stated dependencies.
- `scripts/run` and `scripts/screenshot` work on the default simulator.
- `AGENTS.md` and `docs/ARCHITECTURE.md` describe the code as it is.
- One boundary from `docs/ARCHITECTURE.md`'s Not yet enforced list has a check, with a fixture proving it rejects a violation and accepts the tree.
- A fresh session, given a small real change, finds the code, makes the change, and verifies it with the scripts.

## Steps

1. Record the state of every existing check. Done 2026-09-09: all green.
2. Add `scripts/`, `AGENTS.md`, `CLAUDE.md`, `docs/ARCHITECTURE.md`. Verify each script end to end.
3. Add the first boundary check (kit imports, app never imports GRDB) with fixtures. Register it in `scripts/check`.
4. Run one real change through the setup in a fresh session and fix whatever confused it.
5. Move this plan to `docs/plans/completed/` with a Result.
