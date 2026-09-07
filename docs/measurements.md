# Laoshu measurements

Derived from `data/hsk_word_list.tsv`. Regenerate with `python3 docs/measure.py > docs/measurements.md`.

## Rows, words, and the collapse

- Rows in source: 11105
- Rows at levels 1-6: 5483
- `word_index` values appearing more than once: 81, accounting for 83 extra rows
- Distinct words after collapsing to the lowest level: **5400**

Duplicate groups differing in a field the app displays:

| field | groups differing |
| --- | --- |
| `word` | 0 |
| `pinyin` | 0 |
| `definition_cc-cedict` | 0 |
| `traditional_cc-cedict` | 0 |

They differ only in `part_of_speech`, which the app never shows, so collapsing loses nothing on screen. This script asserts it rather than asserting it in prose.

## Words per level, against the published HSK 3.0 standard

| level | words | cumulative | official cumulative |
| --- | --- | --- | --- |
| 1 | 300 | 300 | 300 |
| 2 | 200 | 500 | 500 |
| 3 | 500 | 1000 | 1000 |
| 4 | 1000 | 2000 | 2000 |
| 5 | 1600 | 3600 | 3600 |
| 6 | 1800 | 5400 | 5400 |

An exact match at every level, asserted by this script. Levels 7-9 are one undifferentiated bucket of 5622 words and are filtered out.

## `word_index` blocks

| level | lowest | highest |
| --- | --- | --- |
| 1 | 1 | 300 |
| 2 | 301 | 500 |
| 3 | 501 | 1000 |
| 4 | 1001 | 2000 |
| 5 | 2001 | 3600 |
| 6 | 3601 | 5400 |

Each level owns a contiguous block of `word_index`, asserted by this script. Within a block the order is pinyin dictionary order, syllable first and then tone, matching `pinyin_numbered`: `word_index` 3 to 6 are 爸爸 bàba, 吧 ba, 白天 báitiān, 百 bǎi, which a plain alphabetical sort would not produce. After the collapse every word sits in its own level's block, so no word carried up from a lower level leads a level.

## Definition cleanup rule

| | median | p90 | max |
| --- | --- | --- | --- |
| raw | 39 | 109 | 545 |
| cleaned | 22 | 45 | 90 |

Rows cleaning to empty across all 5400 shipped words: **0**

## Pinyin collisions on exact toned pinyin

| level range | words | sharing pinyin with another | share |
| --- | --- | --- | --- |
| 1-1 | 300 | 16 | 5.3% |
| 1-3 | 1000 | 103 | 10.3% |
| 1-6 | 5400 | 708 | 13.1% |

The worst single form is `shì`: 是 (to be), 事 (matter), 市 (market; city), 室 (room), 试 (to test).

## Source-side disambiguation suffixes

61 shipped words carry a trailing digit, e.g. 本1, 点1, 和1, 会1, 两1, 喂1, 别1, 打1, 等1, 点2. Stripped at build time; a zh-CN voice otherwise pronounces the digit.

## Speech synthesis: hanzi versus pinyin

Hand-recorded on 2026-09-07, not derived from the source file by this script. macOS voice Tingting, the same speech stack as iOS `AVSpeechSynthesizer`:

| input | rendered duration |
| --- | --- |
| 学习汉语很有意思 | 1.85s |
| xuéxí hànyǔ hěn yǒu yìsi | 6.48s |

The pinyin form is spelled out letter by letter, so the synthesizer must be fed hanzi.
