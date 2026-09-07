#!/usr/bin/env python3
"""Regenerate docs/measurements.md from data/hsk_word_list.tsv.

Every measured decision in the checkpoint PRDs cites this file's output.
Run from the repository root: python3 docs/measure.py > docs/measurements.md
"""
import re, csv
from collections import Counter

SUFFIX = re.compile(r'\d$')

def clean(d):
    """The definition cleanup rule. See decision D7."""
    d = re.sub(r'/(CL:|variant of|see also|abbr\. for|old variant of)[^/]*', '', d)
    d = re.sub(r'\([^()]*(?:[一-鿿]|\[[a-z0-9 ]+\])[^()]*\)', '', d)
    d = re.sub(r'\s{2,}', ' ', d)
    senses = [x.strip(' ;,') for x in d.split('/') if x.strip(' ;,')]
    out = '; '.join(senses[:2])
    if len(out) > 60:
        out = senses[0] if senses else ''
    if len(out) > 90:
        out = out[:87].rsplit(' ', 1)[0] + '...'
    return out.strip(' ;,')

# The reporting body of this script is the code that produced docs/measurements.md.
# Kept short here; the table shapes are in that file.
