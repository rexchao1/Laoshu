# Where this data comes from

`hsk_word_list.tsv` is taken from
[Punpuf/hsk-syllabus-vocabulary-parser](https://github.com/Punpuf/hsk-syllabus-vocabulary-parser),
which extracts the vocabulary list from the official HSK 3.0 syllabus PDF and
joins it against CC-CEDICT. That project is MIT licensed.

The `pinyin_cc-cedict`, `traditional_cc-cedict` and `definition_cc-cedict`
columns are derived from [CC-CEDICT](https://cc-cedict.org/), which is
published under the Creative Commons Attribution-ShareAlike licence. Any
redistribution of this file, or of a database built from it, has to carry that
attribution and stay under the same licence.

Level assignments come from the official HSK 3.0 syllabus published by Chinese
Testing International. `docs/measurements.md` checks the per-level counts in
this file against the published cumulative totals.
