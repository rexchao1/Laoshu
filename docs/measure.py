#!/usr/bin/env python3
"""Regenerate docs/measurements.md from data/hsk_word_list.tsv.

Every measured decision in the checkpoint PRDs cites this file's output.
Run from the repository root:

    python3 docs/measure.py > docs/measurements.md
"""
import re
import sys
import csv
from collections import Counter, defaultdict

SOURCE = 'data/hsk_word_list.tsv'
GLOSSES = 'data/glosses.tsv'
LEVELS = ('1', '2', '3', '4', '5', '6')
MAX_GLOSS_LENGTH = 40

# The same mechanical signals docs/check_glosses.py bans in a written gloss,
# checked here against the cleaned CC-CEDICT definition instead: a word whose
# cleaned definition still carries one is a word the generation pass could not
# have glossed by copying that definition, and needed to write by hand. See
# checkpoint 8 decisions D2 and D5.
SIGNALS = (
    ('bracketed pinyin', re.compile(r'\[[^\]]*\]')),
    ('hanzi', re.compile(r'[㐀-鿿豈-﫿]')),
    ('surname', re.compile(r'surname\s+[A-Z]')),
    ('(bound form)', re.compile(r'\(bound form\)', re.I)),
    ('variant of', re.compile(r'variant of', re.I)),
    ('trailing ellipsis', re.compile(r'\.\.\.\s*$')),
)


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
    """Drop a source-side disambiguation suffix. See checkpoint 1 decision D9."""
    return re.sub(r'\d+$', '', word)


def collapse(rows):
    """One row per word_index, at the word's lowest level. See checkpoint 1 decision D15.

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


def load_glosses(built):
    rows = list(csv.DictReader(open(GLOSSES), delimiter='\t'))
    by_index = {int(r['word_index']): r['gloss'] for r in rows}
    missing = built - set(by_index)
    assert not missing, f'{len(missing)} built words have no gloss row'
    return by_index


def own_hanzi(word, definition):
    """Does the cleaned definition repeat one of the word's own hanzi? See checkpoint 8 decision D5."""
    return any(ch in definition for ch in strip_suffix(word))


def main():
    all_rows = list(csv.DictReader(open(SOURCE), delimiter='\t'))
    kept = [r for r in all_rows if r['level'] in LEVELS]
    words = collapse(kept)
    glosses = load_glosses({int(r['word_index']) for r in words})

    if '--dump-definitions' in sys.argv[1:]:
        for r in sorted(words, key=lambda r: int(r['word_index'])):
            print(f"{r['word_index']}\t{clean(r['definition_cc-cedict'])}")
        return

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
    at_or_under_40 = sum(1 for x in cl if len(x) <= MAX_GLOSS_LENGTH)
    out(f'Cleaned definitions at or under the {MAX_GLOSS_LENGTH}-character gloss limit: '
        f'**{at_or_under_40}** of {len(words)}. Checkpoint 8 decision D2 rests on this number.')
    out('')
    assert at_or_under_40 == 4600, (
        f'cleaned definitions at or under {MAX_GLOSS_LENGTH} characters changed to {at_or_under_40}')

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

    out('## Definition and pinyin collisions by level')
    out('')
    out('A word collides with another when they share a cleaned definition, or when they share '
        'toned pinyin. "Catalogue" counts a collision against any of the 5400 shipped words. '
        '"Level" counts a collision only against other words at the same level, since a session '
        'draws from one level only.')
    out('')
    cleaned = [clean(r['definition_cc-cedict']) for r in words]
    pinyin = [r['pinyin'].lower() for r in words]
    gloss = [glosses[int(r['word_index'])] for r in words]
    levels_of = [int(r['level']) for r in words]
    def_catalogue = Counter(cleaned)
    pin_catalogue = Counter(pinyin)
    gloss_catalogue = Counter(gloss)
    def_by_level = defaultdict(Counter)
    pin_by_level = defaultdict(Counter)
    gloss_by_level = defaultdict(Counter)
    for lvl, d, p, g in zip(levels_of, cleaned, pinyin, gloss):
        def_by_level[lvl][d] += 1
        pin_by_level[lvl][p] += 1
        gloss_by_level[lvl][g] += 1

    out('| level | words | def. collisions (catalogue) | def. share (catalogue) | '
        'def. collisions (level) | def. share (level) | pinyin collisions (catalogue) | '
        'pinyin share (catalogue) | pinyin collisions (level) | pinyin share (level) | '
        'gloss collisions (catalogue) | gloss collisions (level) |')
    out('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')

    def_cat_total = 0
    def_lvl_total = 0
    pin_cat_total = 0
    pin_lvl_total = 0
    gloss_cat_total = 0
    gloss_lvl_total = 0
    for lvl in range(1, 7):
        idx = [i for i, l in enumerate(levels_of) if l == lvl]
        n = len(idx)
        def_cat = sum(1 for i in idx if def_catalogue[cleaned[i]] > 1)
        def_lvl = sum(1 for i in idx if def_by_level[lvl][cleaned[i]] > 1)
        pin_cat = sum(1 for i in idx if pin_catalogue[pinyin[i]] > 1)
        pin_lvl = sum(1 for i in idx if pin_by_level[lvl][pinyin[i]] > 1)
        gloss_cat = sum(1 for i in idx if gloss_catalogue[gloss[i]] > 1)
        gloss_lvl = sum(1 for i in idx if gloss_by_level[lvl][gloss[i]] > 1)
        def_cat_total += def_cat
        def_lvl_total += def_lvl
        pin_cat_total += pin_cat
        pin_lvl_total += pin_lvl
        gloss_cat_total += gloss_cat
        gloss_lvl_total += gloss_lvl
        out(f'| {lvl} | {n} | {def_cat} | {100 * def_cat / n:.1f}% | {def_lvl} | '
            f'{100 * def_lvl / n:.1f}% | {pin_cat} | {100 * pin_cat / n:.1f}% | {pin_lvl} | '
            f'{100 * pin_lvl / n:.1f}% | {gloss_cat} | {gloss_lvl} |')
    n = len(words)
    out(f'| all | {n} | {def_cat_total} | {100 * def_cat_total / n:.1f}% | {def_lvl_total} | '
        f'{100 * def_lvl_total / n:.1f}% | {pin_cat_total} | {100 * pin_cat_total / n:.1f}% | '
        f'{pin_lvl_total} | {100 * pin_lvl_total / n:.1f}% | {gloss_cat_total} | {gloss_lvl_total} |')
    out('')
    assert def_cat_total == 274, f'catalogue-wide definition collisions changed to {def_cat_total}'
    assert pin_cat_total == 708, f'catalogue-wide pinyin collisions changed to {pin_cat_total}'
    assert def_lvl_total == 89, f'within-level definition collisions changed to {def_lvl_total}'
    assert pin_lvl_total == 229, f'within-level pinyin collisions changed to {pin_lvl_total}'
    assert gloss_cat_total == 511, f'catalogue-wide gloss collisions changed to {gloss_cat_total}'
    assert gloss_lvl_total == 162, f'within-level gloss collisions changed to {gloss_lvl_total}'
    out('The all-levels row sums the per-level counts: 274 definition collisions and 708 pinyin '
        'collisions counted catalogue-wide, 89 and 229 counted inside the level. Inside a level, '
        'a cleaned definition is shared with another word 1.6% of the time and toned pinyin 4.2%. '
        'Checkpoint 11 decisions D9, D9a and D10 rest on these four numbers. The gloss columns '
        f'recount the same catalogue against `data/glosses.tsv` instead of the cleaned definition: '
        f'{gloss_cat_total} words share a gloss with another word catalogue-wide, {gloss_lvl_total} '
        'inside their own level. Checkpoint 8 decision D4b rests on these two numbers.')
    out('')

    out('## Source-side disambiguation suffixes')
    out('')
    suf = [r['word'] for r in words if re.search(r'\d$', r['word'])]
    out(f'{len(suf)} shipped words carry a trailing digit, e.g. {", ".join(suf[:10])}. '
        'Stripped at build time; a zh-CN voice otherwise pronounces the digit.')
    out('')

    out('## Gloss source signals')
    out('')
    out('A word is flagged when its cleaned CC-CEDICT definition still carries a signal a rule '
        'can check mechanically: bracketed pinyin, a hanzi character, a bare "surname" tag, a '
        '"(bound form)" tag, a "variant of" tag, a definition `clean()` truncated with a trailing '
        '"...", or the word\'s own hanzi repeated back in its definition. None of these can be '
        'trusted to a rule, which is why checkpoint 8 decision D5 has every gloss written by a '
        'model pass instead of falling back to the cleaned definition.')
    out('')
    signal_hits = {name: [] for name, _ in SIGNALS}
    signal_hits['own hanzi'] = []
    flagged = [False] * len(words)
    flagged_by_level = defaultdict(int)
    for i, (r, d) in enumerate(zip(words, cleaned)):
        hit = False
        for name, pattern in SIGNALS:
            if pattern.search(d):
                signal_hits[name].append(i)
                hit = True
        if own_hanzi(r['word'], d):
            signal_hits['own hanzi'].append(i)
            hit = True
        flagged[i] = hit
        if hit:
            flagged_by_level[int(r['level'])] += 1

    out('| level | words | flagged by any signal | share |')
    out('| --- | --- | --- | --- |')
    for lvl in range(1, 7):
        n = counts[lvl]
        out(f'| {lvl} | {n} | {flagged_by_level[lvl]} | {100 * flagged_by_level[lvl] / n:.1f}% |')
    total_flagged = sum(flagged)
    out(f'| all | {len(words)} | {total_flagged} | {100 * total_flagged / len(words):.1f}% |')
    out('')
    signal_counts = {name: len(hits) for name, hits in signal_hits.items()}
    out('| signal | words |')
    out('| --- | --- |')
    for name, _ in SIGNALS:
        out(f'| {name} | {signal_counts[name]} |')
    out(f'| own hanzi | {signal_counts["own hanzi"]} |')
    out('')
    assert total_flagged == 214, f'words flagged by any signal changed to {total_flagged}'
    assert signal_counts['bracketed pinyin'] == 83, (
        f'bracketed pinyin signal changed to {signal_counts["bracketed pinyin"]}')
    assert signal_counts['hanzi'] == 73, f'hanzi signal changed to {signal_counts["hanzi"]}'
    assert signal_counts['surname'] == 61, f'surname signal changed to {signal_counts["surname"]}'
    assert signal_counts['(bound form)'] == 45, (
        f'(bound form) signal changed to {signal_counts["(bound form)"]}')
    assert signal_counts['variant of'] == 37, (
        f'variant of signal changed to {signal_counts["variant of"]}')
    assert signal_counts['trailing ellipsis'] == 32, (
        f'trailing ellipsis signal changed to {signal_counts["trailing ellipsis"]}')
    assert signal_counts['own hanzi'] == 59, f'own hanzi signal changed to {signal_counts["own hanzi"]}'
    out(f'{total_flagged} of {len(words)} words are flagged by at least one signal, '
        f'{flagged_by_level[1]} of them at level 1. Checkpoint 8 decision D5 rests on these eight '
        'numbers: the total and each of the seven signals above.')
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
