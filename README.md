# Laoshu

A personal iPhone app for learning Chinese vocabulary.

Pick an HSK level and swipe through a graded session of its words, meeting
each day's eight new words again the next day and again a week after that;
or browse a level's row to look back over everything already met there,
without being tested. Offline, no account, one user.

A placement test on first launch, and any time after from the level list's
toolbar, walks up and down the levels and marks the words the user already
knows so they are never taught as new.

## Shape

- `LaoshuKit/` — a pure Swift package holding the vocabulary catalogue, the
  scheduler, and the session logic. Builds and tests with `swift test`, no
  Xcode needed.
- `Laoshu/` — the SwiftUI iPhone app, a thin shell over LaoshuKit.
- `data/` — the bundled HSK vocabulary, built into a SQLite file at package time.

## Building

`LaoshuKit/` builds and tests standalone, with no Xcode required:

```
swift test --package-path LaoshuKit
```

The word database at `data/laoshu.sqlite` is generated from the vendored TSV
and committed rather than built on device:

```
swift run --package-path LaoshuKit laoshu-build-db data/hsk_word_list.tsv data/laoshu.sqlite
swift run --package-path LaoshuKit laoshu-build-db --checksum data/laoshu.sqlite
```

The database's shape can be checked directly:

```
sqlite3 data/laoshu.sqlite "select level, count(*) from word group by level order by level"
sqlite3 data/laoshu.sqlite "select count(*) from word where definition = '' or definition is null"
sqlite3 data/laoshu.sqlite "select count(*) from word where hanzi glob '*[0-9]'"
sqlite3 data/laoshu.sqlite "select count(*) from (select word_index from word group by word_index having count(*) > 1)"
```

The measurements the decisions cite regenerate and self-check with:

```
python3 docs/measure.py > /tmp/m.md && diff /tmp/m.md docs/measurements.md
```

The iPhone app target needs Xcode, and its compile gate runs on a machine
that has it, not one carrying only the command line tools:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme Laoshu -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Decisions behind each checkpoint are recorded in `docs/decisions/`.

## Attribution

Word definitions and pinyin come from [CC-CEDICT](https://cc-cedict.org/),
used under CC BY-SA 4.0. The vocabulary level mapping comes from the official
HSK 3.0 syllabus.
