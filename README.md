# Laoshu

A personal iPhone app for learning Chinese vocabulary.

Pick an HSK level, swipe through its words, and see each word again on the day
you are about to forget it. Offline, no account, one user.

## Shape

- `LaoshuKit/` — a pure Swift package holding the vocabulary catalogue, the
  scheduler, and the session logic. Builds and tests with `swift test`, no
  Xcode needed.
- `Laoshu/` — the SwiftUI iPhone app, a thin shell over LaoshuKit.
- `data/` — the bundled HSK vocabulary, built into a SQLite file at package time.

## Attribution

Word definitions and pinyin come from [CC-CEDICT](https://cc-cedict.org/),
used under CC BY-SA 4.0. The vocabulary level mapping comes from the official
HSK 3.0 syllabus.
