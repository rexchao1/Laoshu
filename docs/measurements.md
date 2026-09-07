# Laoshu measurements

All figures derived from `data/hsk_word_list.tsv` at the commit that carries this file.
Regenerate with `python3 docs/measure.py`.

## Words per level, and cumulative against the published HSK 3.0 standard

| level | words | cumulative | official cumulative |
| --- | --- | --- | --- |
| 1 | 300 | 300 | 300 |
| 2 | 204 | 504 | 500 |
| 3 | 507 | 1011 | 1000 |
| 4 | 1019 | 2030 | 2000 |
| 5 | 1638 | 3668 | 3600 |
| 6 | 1815 | 5483 | 5400 |

Levels 7-9 ship as one undifferentiated bucket of 5622 words and are filtered out.
Total rows in source: 11105. Levels 1-6 kept: 5483.

## Definition cleanup rule, over levels 1-6

| | median | p90 | max |
| --- | --- | --- | --- |
| raw | 39 | 112 | 545 |
| cleaned | 22 | 46 | 90 |

Rows cleaning to empty across levels 1-6: **0**

## Pinyin collisions on exact toned pinyin

| level range | words | sharing pinyin with another | share |
| --- | --- | --- | --- |
| 1-1 | 300 | 16 | 5.3% |
| 1-3 | 1011 | 123 | 12.2% |
| 1-6 | 5483 | 830 | 15.1% |

The worst single form is `shì`, covering 是 (to be), 事 (matter), 市 (market; city), 室 (room), 试 (to test).

## Source-side disambiguation suffixes

90 rows carry a trailing digit, e.g. 本1, 点1, 点1, 和1, 会1, 两1, 喂1, 别1, 打1, 等1. Stripped at build time; a zh-CN voice otherwise pronounces the digit.

## Speech synthesis: hanzi versus pinyin

macOS voice Tingting, same speech stack as iOS AVSpeechSynthesizer, 2026-09-07:

| input | rendered duration |
| --- | --- |
| 学习汉语很有意思 | 1.85s |
| xuéxí hànyǔ hěn yǒu yìsi | 6.48s |

The pinyin form is spelled out letter by letter, so the synthesizer must be fed hanzi.
