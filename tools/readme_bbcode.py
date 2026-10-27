#!/usr/bin/env python3
"""Turns the player part of README.md into BBCode for LotroInterface.

Reads README.md up to the marker comment that ends the description and
writes dist/lotrointerface.txt. The Screenshots section, image lines and
HTML comments are left out; screenshots go into the LotroInterface gallery.

Usage: python3 -I tools/readme_bbcode.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
DIST = ROOT / "dist"
MARKER = "<!-- end of LotroInterface description -->"
HEADING_SIZES = {1: 5, 2: 4, 3: 3}


def inline(text):
    text = re.sub(r"`([^`]+)`", r"[font=Courier New]\1[/font]", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"[b]\1[/b]", text)
    text = re.sub(r"\*([^*]+)\*", r"[i]\1[/i]", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"[url=\2]\1[/url]", text)
    return text


def blocks(lines):
    """Groups lines into paragraphs, lists, code blocks and headings."""
    block = []
    code = None
    for line in lines:
        if code is not None:
            if line.startswith("```"):
                yield "code", code
                code = None
            else:
                code.append(line)
        elif line.startswith("```"):
            if block:
                yield "text", block
                block = []
            code = []
        elif line.startswith("#"):
            if block:
                yield "text", block
                block = []
            yield "heading", [line]
        elif not line.strip():
            if block:
                yield "text", block
                block = []
        else:
            block.append(line)
    if block:
        yield "text", block


def convert(markdown):
    markdown = re.sub(r"<!--.*?-->", "", markdown, flags=re.S)
    markdown = re.sub(r"^## Screenshots\n.*?(?=^## )", "", markdown, flags=re.S | re.M)
    lines = [l for l in markdown.splitlines() if not l.lstrip().startswith("![")]
    out = []
    for kind, block in blocks(lines):
        if kind == "code":
            out.append("[code]\n" + "\n".join(block) + "\n[/code]")
        elif kind == "heading":
            level = len(block[0]) - len(block[0].lstrip("#"))
            title = inline(block[0].lstrip("#").strip())
            out.append(f"[size={HEADING_SIZES.get(level, 3)}][b]{title}[/b][/size]")
        elif block[0].startswith("- "):
            items = []
            for line in block:
                if line.startswith("- "):
                    items.append(line[2:].strip())
                else:
                    items[-1] += " " + line.strip()
            out.append("[list]\n" + "\n".join(f"[*]{inline(i)}" for i in items) + "\n[/list]")
        else:
            out.append(inline(" ".join(l.strip() for l in block)))
    return "\n\n".join(out) + "\n"


def main():
    text = README.read_text(encoding="utf-8")
    if MARKER not in text:
        print(f"Marker fehlt in README.md: {MARKER}")
        return 1
    bbcode = convert(text.split(MARKER)[0])
    DIST.mkdir(exist_ok=True)
    target = DIST / "lotrointerface.txt"
    target.write_text(bbcode, encoding="utf-8")
    print(f"{target} ({len(bbcode)} Zeichen)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
