#!/usr/bin/env python3
"""Validate data/glosses.tsv against the gloss rules. See checkpoint 8 decisions D2, D5a, D6c.

The Swift validator in CatalogueBuilder applies the same rules at build time.
This script exists so the file can be checked at the moment it is written,
before any Swift runs. It reads no database.

Run from the repository root:

    python3 docs/check_glosses.py
"""
import re
import sys
import csv

WORDS = 'data/hsk_word_list.tsv'
GLOSSES = 'data/glosses.tsv'
LEVELS = ('1', '2', '3', '4', '5', '6')
MAX_LENGTH = 40

# D5a: patterns, not bare words. `surname` is a real meaning for 姓 and is
# banned only in CC-CEDICT's tag form, where a capitalised name follows it.
BANNED = [
    ('hanzi', re.compile(r'[㐀-鿿豈-﫿]')),
    ('bracketed pinyin', re.compile(r'\[[^\]]*\]')),
    ('variant of', re.compile(r'variant of', re.I)),
    ('abbr. for', re.compile(r'abbr\. for', re.I)),
    ('(bound form)', re.compile(r'\(bound form\)', re.I)),
    ('surname tag', re.compile(r'surname\s+[A-Z]')),
    ('trailing ellipsis', re.compile(r'\.\.\.\s*$')),
]


def built_word_indexes():
    """The words the catalogue ships, by checkpoint 1 decisions D2 and D15."""
    rows = list(csv.DictReader(open(WORDS), delimiter='\t'))
    return {int(r['word_index']) for r in rows if r['level'] in LEVELS}


def main():
    expected = built_word_indexes()
    problems = []
    seen = {}

    with open(GLOSSES) as f:
        header = f.readline().rstrip('\n').split('\t')
        if header != ['word_index', 'gloss']:
            print(f'{GLOSSES}:1: header is {header}, expected word_index and gloss')
            return 1
        for lineno, line in enumerate(f, start=2):
            fields = line.rstrip('\n').split('\t')
            if len(fields) != 2:
                problems.append(f'line {lineno}: {len(fields)} fields, expected 2')
                continue
            raw_index, gloss = fields
            try:
                index = int(raw_index)
            except ValueError:
                problems.append(f'line {lineno}: word_index {raw_index!r} is not a number')
                continue
            if index in seen:
                problems.append(f'word_index {index}: repeated, lines {seen[index]} and {lineno}')
                continue
            seen[index] = lineno
            if index not in expected:
                problems.append(f'word_index {index}: not in the built word set')
            if not gloss.strip():
                problems.append(f'word_index {index}: empty gloss')
                continue
            if gloss != gloss.strip():
                problems.append(f'word_index {index}: leading or trailing whitespace')
            if len(gloss) > MAX_LENGTH:
                problems.append(f'word_index {index}: {len(gloss)} characters, over {MAX_LENGTH}: {gloss!r}')
            for name, pattern in BANNED:
                if pattern.search(gloss):
                    problems.append(f'word_index {index}: banned {name}: {gloss!r}')

    for index in sorted(expected - set(seen)):
        problems.append(f'word_index {index}: no gloss row')

    for p in problems:
        print(p)
    print(f'{len(seen)} glosses read, {len(expected)} words expected, {len(problems)} problem(s)')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
