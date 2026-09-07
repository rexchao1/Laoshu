#!/usr/bin/env python3
"""Regenerate docs/measurements.md from data/hsk_word_list.tsv.

Every measured decision in the checkpoint PRDs cites this file's output.
Run from the repository root:

    python3 docs/measure.py > docs/measurements.md
"""
import re
import csv
from collections import Counter, defaultdict

SOURCE = 'data/hsk_word_list.tsv'
LEVELS = ('1', '2', '3', '4', '5', '6')


def clean(definition):
    """The definition cleanup rule. See checkpoint 1 decision D8."""
    d = re.sub(r'/(CL:|variant of|see also|abbr\. for|old variant of)[^/]*', '', definition)
    d = re.sub(r'\([^()]*(?:[一-鿿]|\[[a-z0-9 ]+\])[^()]*\)', '', d)
    d = re.sub(r'\s{2,}', ' ', d)
    senses = [s.strip(' ;,') for s in d.split('/') if s.strip(' ;,')]
    out = '; '.join(senses[:2])
    if len(out) > 60:
        out = senses[0] if senses else ''
    if len(out) > 90:
        out = out[:87].rsplit(' ', 1)[0] + '...'
    return out.strip(' ;,')


def strip_suffix(word):
    """Drop a source-side disambiguation suffix. See decision D9."""
    return re.sub(r'\d+$', '', word)


def collapse(rows):
    """One row per word_index, at the word's lowest level. See decision D15.

    The source relists a word at a higher level when it gains a part of speech.
    Those rows are identical in every field the app shows, so they collapse.
    """
    best = {}
    for r in rows:
        i = int(r['word_index'])
        if i not in best or int(r['level']) < int(best[i]['level']):
            best[i] = r
    return [best[i] for i in sorted(best)]


def stats(values):
    v = sorted(values)
    return v[len(v) // 2], v[int(len(v) * 0.9)], v[-1]


def main():
    all_rows = list(csv.DictReader(open(SOURCE), delimiter='\t'))
    kept = [r for r in all_rows if r['level'] in LEVELS]
    words = collapse(kept)

    out = print
    out('# Laoshu measurements')
    out('')
    out(f'Derived from `{SOURCE}`. Regenerate with `python3 docs/measure.py > docs/measurements.md`.')
    out('')

    out('## Rows, words, and the collapse')
    out('')
    dup = {i: n for i, n in Counter(int(r['word_index']) for r in kept).items() if n > 1}
    out(f'- Rows in source: {len(all_rows)}')
    out(f'- Rows at levels 1-6: {len(kept)}')
    out(f'- `word_index` values appearing more than once: {len(dup)}, accounting for '
        f'{sum(n - 1 for n in dup.values())} extra rows')
    out(f'- Distinct words after collapsing to the lowest level: **{len(words)}**')
    out('')
    fields = ('word', 'pinyin', 'definition_cc-cedict', 'traditional_cc-cedict')
    groups = defaultdict(list)
    for r in kept:
        groups[r['word_index']].append(r)
    differing = {f: sum(1 for i in dup if len({g[f] for g in groups[str(i)]}) > 1) for f in fields}
    out('Duplicate groups differing in a field the app displays:')
    out('')
    out('| field | groups differing |')
    out('| --- | --- |')
    for f in fields:
        out(f'| `{f}` | {differing[f]} |')
    out('')
    assert all(v == 0 for v in differing.values()), (
        'a duplicate group differs in a field the app displays; the collapse rule is unsafe')
    out('They differ only in `part_of_speech`, which the app never shows, so collapsing loses '
        'nothing on screen. This script asserts it rather than asserting it in prose.')
    out('')

    out('## Words per level, against the published HSK 3.0 standard')
    out('')
    out('| level | words | cumulative | official cumulative |')
    out('| --- | --- | --- | --- |')
    official = {1: 300, 2: 500, 3: 1000, 4: 2000, 5: 3600, 6: 5400}
    counts = Counter(int(r['level']) for r in words)
    cum = 0
    for lvl in range(1, 7):
        cum += counts[lvl]
        out(f'| {lvl} | {counts[lvl]} | {cum} | {official[lvl]} |')
    out('')
    assert all(counts[l] for l in range(1, 7)), 'a level came out empty'
    running = 0
    for lvl in range(1, 7):
        running += counts[lvl]
        assert running == official[lvl], (
            f'level {lvl} cumulative {running} does not match the published standard {official[lvl]}')
    out(f'An exact match at every level, asserted by this script. Levels 7-9 are one '
        f'undifferentiated bucket of {sum(1 for r in all_rows if r["level"] == "7-9")} words '
        f'and are filtered out.')
    out('')

    out('## `word_index` blocks')
    out('')
    out('| level | lowest | highest |')
    out('| --- | --- | --- |')
    for lvl in range(1, 7):
        idx = [int(r['word_index']) for r in words if int(r['level']) == lvl]
        out(f'| {lvl} | {min(idx)} | {max(idx)} |')
    out('')
    for lvl in range(1, 7):
        idx = sorted(int(r['word_index']) for r in words if int(r['level']) == lvl)
        assert idx == list(range(idx[0], idx[-1] + 1)), f'level {lvl} block is not contiguous'
    out('Each level owns a contiguous block of `word_index`, asserted by this script. Within a '
        'block the order is pinyin dictionary order, syllable first and then tone, matching '
        '`pinyin_numbered`: `word_index` 3 to 6 are 爸爸 bàba, 吧 ba, 白天 báitiān, 百 bǎi, which '
        'a plain alphabetical sort would not produce. After the collapse every word sits in its '
        'own level\'s block, so no word carried up from a lower level leads a level.')
    out('')

    out('## Definition cleanup rule')
    out('')
    raw = stats([len(r['definition_cc-cedict']) for r in words])
    cl = [clean(r['definition_cc-cedict']) for r in words]
    out('| | median | p90 | max |')
    out('| --- | --- | --- | --- |')
    out(f'| raw | {raw[0]} | {raw[1]} | {raw[2]} |')
    c = stats([len(x) for x in cl])
    out(f'| cleaned | {c[0]} | {c[1]} | {c[2]} |')
    empty = [w['word_index'] for w, x in zip(words, cl) if not x]
    out('')
    out(f'Rows cleaning to empty across all {len(words)} shipped words: **{len(empty)}**'
        + (f' (`word_index` {", ".join(empty[:20])})' if empty else ''))
    out('')

    out('## Pinyin collisions on exact toned pinyin')
    out('')
    out('| level range | words | sharing pinyin with another | share |')
    out('| --- | --- | --- | --- |')
    for n in (1, 3, 6):
        sub = [r for r in words if int(r['level']) <= n]
        c2 = Counter(r['pinyin'].lower() for r in sub)
        amb = sum(v for v in c2.values() if v > 1)
        out(f'| 1-{n} | {len(sub)} | {amb} | {100 * amb / len(sub):.1f}% |')
    out('')
    out('The worst single form is `shì`: 是 (to be), 事 (matter), 市 (market; city), 室 (room), 试 (to test).')
    out('')

    out('## Source-side disambiguation suffixes')
    out('')
    suf = [r['word'] for r in words if re.search(r'\d$', r['word'])]
    out(f'{len(suf)} shipped words carry a trailing digit, e.g. {", ".join(suf[:10])}. '
        'Stripped at build time; a zh-CN voice otherwise pronounces the digit.')
    out('')

    out('## Speech synthesis: hanzi versus pinyin')
    out('')
    out('Hand-recorded on 2026-09-07, not derived from the source file by this script. macOS '
        'voice Tingting, the same speech stack as iOS `AVSpeechSynthesizer`:')
    out('')
    out('| input | rendered duration |')
    out('| --- | --- |')
    out('| 学习汉语很有意思 | 1.85s |')
    out('| xuéxí hànyǔ hěn yǒu yìsi | 6.48s |')
    out('')
    out('The pinyin form is spelled out letter by letter, so the synthesizer must be fed hanzi.')


if __name__ == '__main__':
    main()
