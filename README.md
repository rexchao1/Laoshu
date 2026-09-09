# Laoshu

A personal iPhone app for learning Chinese vocabulary.

Pick an HSK level and swipe through a graded session of its words, meeting
each day's new words again the next day and again a week after that; or
browse a level's row to look back over everything already met there,
without being tested. Offline, no account, one user.

A gear in the level list's toolbar opens a Settings screen where the day's
new-word count, the study direction (pinyin first or English first), and
whether a card speaks its word aloud when first turned over are all set.

A placement test on first launch, and any time after from the level list's
toolbar, walks up and down the levels and marks the words the user already
knows so they are never taught as new.

A flame in the level list's toolbar shows how many days in a row the user
has studied, in a run that forgives one missed day a week; tapping it opens
a Progress screen showing that streak, how many words are waiting across
all six levels today, and for each level how many words it has learned, has
in progress, and has left.

Every word's English is a short gloss, one plain meaning rather than a
dictionary entry, written and reviewed for learners and held as data at
`data/glosses.tsv` rather than derived from CC-CEDICT at build time.

## Shape

- `LaoshuKit/` is a pure Swift package holding the vocabulary catalogue, the
  scheduler, and the session logic. It builds and tests with `swift test`, no
  Xcode needed.
- `Laoshu/` is the SwiftUI iPhone app, a thin shell over LaoshuKit.
- `data/` is the bundled HSK vocabulary, built into a SQLite file at package time.

`docs/ARCHITECTURE.md` maps the domains and what may depend on what.
`AGENTS.md` is the working guide for anyone, human or agent, changing the code.

## Building and running

Everything routine has a script:

```
scripts/check        kit tests, gloss rules, measurements, database shape (no Xcode)
scripts/test         kit tests alone; scripts/test --filter StreakTests narrows
scripts/build        compile the app for the simulator (Xcode)
scripts/run          build, boot a simulator, install and launch; --reset wipes progress
scripts/screenshot   capture the booted simulator to a PNG
scripts/check-full   scripts/check, then scripts/build
```

The word database at `data/laoshu.sqlite` is generated from the vendored TSV
and committed rather than built on device. After changing `data/*.tsv`:

```
swift run --package-path LaoshuKit laoshu-build-db data/hsk_word_list.tsv data/glosses.tsv data/laoshu.sqlite
swift run --package-path LaoshuKit laoshu-build-db --checksum data/laoshu.sqlite
cp data/laoshu.sqlite Laoshu/laoshu.sqlite
python3 docs/measure.py > docs/measurements.md
```

Decisions behind each checkpoint are recorded in `docs/decisions/`.

## Attribution

Word definitions and pinyin come from [CC-CEDICT](https://cc-cedict.org/),
used under CC BY-SA 4.0. The vocabulary level mapping comes from the official
HSK 3.0 syllabus.
