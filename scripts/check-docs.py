#!/usr/bin/env python3
"""Every document under docs/ is reachable from the entry files, and every pointer resolves.

A document nobody points at is a document no agent opens: it goes stale unnoticed and the
next session writes a second copy of it. This walks the pointer graph from AGENTS.md,
CLAUDE.md and README.md and reports what it never reaches, plus any pointer naming a file
that is not there.

    scripts/check-docs.py                prove every document is reachable
    scripts/check-docs.py --self-test    prove the check catches a stray document, then check the tree
    scripts/check-docs.py --root DIR     check another tree (used by the self-test)

A pointer is the file's path (`docs/RUNBOOK.md`) or its bare name, written anywhere in a
document already reached. Naming a directory (`docs/reference/`) reaches everything inside
it, which is how a bulk reference folder earns one pointer instead of thirty.
"""

import argparse
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT_FILES = ("AGENTS.md", "CLAUDE.md", "README.md")
# Plans are working state with their own lifecycle: active/ then completed/, named by date.
SKIP_DIRS = {"plans"}
PATH_RE = re.compile(r"docs/[A-Za-z0-9_][A-Za-z0-9_./*-]*")
PLACEHOLDER = re.compile(r"[<>*]|YYYY|NN|NAME|\.\.\.")


def candidates(root):
    docs = root / "docs"
    if not docs.is_dir():
        return []
    out = []
    for p in sorted(docs.rglob("*")):
        if not p.is_file() or p.name.startswith("."):
            continue
        rel = p.relative_to(root)
        if SKIP_DIRS & set(rel.parts):
            continue
        out.append(rel)
    return out


def mentions(text, rel):
    """Is this file named in the text, by full path, by bare name, or by a parent directory?"""
    if str(rel) in text:
        return True
    # A folder pointer reaches everything inside it, but "docs/" alone reaches nothing.
    for parent in rel.parents:
        if len(parent.parts) > 1 and f"{parent}/" in text:
            return True
    # A bare name is a real pointer, except for names the entry files say constantly.
    return rel.name not in ROOT_FILES and rel.name in text


def reachable(root, files):
    texts = {}
    frontier = []
    for name in ROOT_FILES:
        p = root / name
        if p.is_file():
            frontier.append(read(p))
    found = set()
    while frontier:
        text = frontier.pop()
        for rel in files:
            if rel in found or not mentions(text, rel):
                continue
            found.add(rel)
            body = read(root / rel)
            texts[rel] = body
            frontier.append(body)
    return found, texts


def read(path):
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def dangling(root, texts, real):
    # A name with a space in it reads as a shorter path than it is, so a prefix of a real
    # file counts as resolved.
    prefixes = tuple(str(r) for r in real if " " in str(r))
    out = []
    for source, text in texts.items():
        for hit in PATH_RE.findall(text):
            ref = hit.rstrip(" .,;:)`'\"")
            # A folder is made when it is first used, so a folder pointer is never dangling.
            if ref.endswith("/") or PLACEHOLDER.search(ref) or (root / ref).exists():
                continue
            if any(p.startswith(ref) for p in prefixes):
                continue
            out.append((source, ref))
    return sorted(set(out))


def check(root):
    root = pathlib.Path(root).resolve()
    files = candidates(root)
    entries = [n for n in ROOT_FILES if (root / n).is_file()]
    found, texts = reachable(root, files)
    for name in entries:
        texts[pathlib.Path(name)] = read(root / name)
    problems = 0

    orphans = [f for f in files if f not in found]
    if orphans:
        problems += len(orphans)
        print(f"{len(orphans)} document(s) under docs/ that nothing points at:")
        for rel in orphans:
            print(f"  {rel}")
        print(f"  Fix: name each one in {entries[0] if entries else 'AGENTS.md'} or in a document"
              " it already reaches, saying when to read it. If it has no reader, move it under a"
              " folder that does, or take it out of docs/.")

    bad = dangling(root, texts, files)
    if bad:
        problems += len(bad)
        print(f"{len(bad)} pointer(s) to a file that is not there:")
        for source, ref in bad:
            print(f"  {source} -> {ref}")
        print("  Fix: correct the path, or restore the file it names.")

    if not problems:
        print(f"docs: {len(files)} file(s), all reachable, all pointers resolve")
    return 1 if problems else 0


def self_test():
    """Plant one orphan and one broken pointer, and assert exactly those are caught."""
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        (root / "docs" / "reference").mkdir(parents=True)
        (root / "docs" / "plans" / "active").mkdir(parents=True)
        (root / "AGENTS.md").write_text(
            "Read docs/ARCHITECTURE.md first. Bulk material lives in docs/reference/.\n"
            "The runbook is docs/RUNBOOK_gone.md. Plans go in docs/plans/active/, "
            "payer files are docs/PAYER_*.md. Ask docs/Questions for tara.rtf.\n"
        )
        (root / "docs" / "ARCHITECTURE.md").write_text("Layers. See NOTES.md for the invariants.\n")
        (root / "docs" / "NOTES.md").write_text("Invariants.\n")
        (root / "docs" / "orphan.md").write_text("Nobody points here.\n")
        (root / "docs" / "Questions for tara.rtf").write_text("spaces in the name\n")
        (root / "docs" / "reference" / "dump.txt").write_text("bulk\n")
        (root / "docs" / "plans" / "active" / "2026-01-01-thing.md").write_text("plan\n")

        out = subprocess.run([sys.executable, __file__, "--root", str(root)],
                             capture_output=True, text=True)
        assert out.returncode == 1, out.stdout
        assert "docs/orphan.md" in out.stdout, out.stdout
        assert "docs/RUNBOOK_gone.md" in out.stdout, out.stdout
        for reached in ("ARCHITECTURE.md", "NOTES.md", "dump.txt", "2026-01-01-thing.md"):
            assert f"  docs/{reached}" not in out.stdout, f"{reached} wrongly reported\n{out.stdout}"
        assert "reference/dump.txt" not in out.stdout, out.stdout
        assert "plans/active" not in out.stdout, out.stdout
        assert "docs/Questions" not in out.stdout, out.stdout

        (root / "docs" / "orphan.md").unlink()
        (root / "docs" / "RUNBOOK_gone.md").write_text("runbook\n")
        clean = subprocess.run([sys.executable, __file__, "--root", str(root)],
                               capture_output=True, text=True)
        assert clean.returncode == 0, clean.stdout
    print("check-docs self-test passed: orphan caught, broken pointer caught, clean tree passes")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=".", help="repository root to check")
    ap.add_argument("--self-test", action="store_true",
                    help="prove the check catches what it claims, then check the tree")
    args = ap.parse_args()
    if args.self_test and self_test() != 0:
        return 1
    return check(args.root)


if __name__ == "__main__":
    sys.exit(main())
