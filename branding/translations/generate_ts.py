#!/usr/bin/env python3
"""Builds the Cheburnezia translation files from upstream's.

    generate_ts.py --overrides overrides.json --out-dir DIR --prefix amneziavpn
                   --app-name Cheburnezia --repo owner/name UPSTREAM.ts...

Writes into DIR:
  * a copy of every upstream .ts with the messages from overrides.json rewritten;
  * <prefix>_en.ts holding only those messages, for the English UI.

The app installs a single QTranslator (CoreController::updateTranslator), so the
overrides have to live inside each language's file rather than on top of it.
English has no upstream file: the source strings are the English text, and the
app loads <prefix>_en.qm for English and as the fallback for any language
without a file of its own.

Prints the generated paths, one per line. Warnings go to stderr.
"""

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# "Amnezia" as a whole word, and "AmneziaVPN". AmneziaWG, AmneziaDNS and the
# like are different products and keep their names.
BRAND_RE = re.compile(r"AmneziaVPN|Amnezia(?![A-Za-z])")


def warn(message):
    print(f"warning: {message}", file=sys.stderr)


class Override:
    def __init__(self, entry, placeholders):
        self.context = entry.get("context")
        self.source = entry.get("source")
        self.source_startswith = entry.get("source_startswith")
        if (self.source is None) == (self.source_startswith is None):
            raise ValueError(f"exactly one of source/source_startswith is required: {entry}")
        self.texts = {key: value.format(**placeholders)
                      for key, value in entry.items()
                      if key not in ("context", "source", "source_startswith")}
        self.app = placeholders["app"]
        self.matched_contexts = {}  # context name -> (source, comment) for the English file

    def label(self):
        return self.source if self.source is not None else self.source_startswith + "..."

    def matches(self, context, source):
        if self.context is not None and context != self.context:
            return False
        if self.source is not None:
            return source == self.source
        return source.startswith(self.source_startswith)

    def english(self, source):
        return self.texts.get("en", self.texts.get("all", BRAND_RE.sub(self.app, source)))

    def translate(self, language, source, current):
        if language in self.texts:
            return self.texts[language]
        if "all" in self.texts:
            return self.texts["all"]
        # An explicit English text means the message was reworded, so the old
        # translation no longer says the right thing even with the name swapped.
        if "en" in self.texts:
            return self.texts["en"]
        if current:
            return BRAND_RE.sub(self.app, current)
        return self.english(source)


def load_overrides(path, placeholders):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return [Override(entry, placeholders) for entry in data["messages"]]


def write_ts(root, path, indent=False):
    if indent:
        ET.indent(root, space="    ")
    body = ET.tostring(root, encoding="unicode")
    path.write_text('<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE TS>\n' + body + "\n",
                    encoding="utf-8", newline="\n")


def rewrite_upstream(ts_path, out_path, overrides):
    tree = ET.parse(ts_path)
    root = tree.getroot()
    language = root.get("language", "")

    for context in root.iter("context"):
        context_name = context.findtext("name", "")
        for message in context.iter("message"):
            source = message.findtext("source")
            translation = message.find("translation")
            if source is None or translation is None:
                continue
            # Obsolete and vanished entries are not compiled into the .qm.
            if translation.get("type") not in (None, "unfinished"):
                continue
            if message.get("numerus") == "yes":
                continue
            for override in overrides:
                if override.matches(context_name, source):
                    override.matched_contexts.setdefault(
                        context_name, set()).add((source, message.findtext("comment")))
                    translation.text = override.translate(language, source, translation.text)
                    translation.attrib.pop("type", None)
                    break

    write_ts(root, out_path)


def write_english(out_path, overrides):
    root = ET.Element("TS", {"version": "2.1", "language": "en"})
    contexts = {}
    for override in overrides:
        if not override.matched_contexts:
            warn(f"no upstream message matches override '{override.label()}' "
                 f"(context {override.context or 'any'}); the string was changed or removed upstream")
            continue
        for context_name, messages in sorted(override.matched_contexts.items()):
            if context_name not in contexts:
                contexts[context_name] = ET.SubElement(root, "context")
                ET.SubElement(contexts[context_name], "name").text = context_name
            for source, comment in sorted(messages, key=lambda m: (m[0], m[1] or "")):
                message = ET.SubElement(contexts[context_name], "message")
                ET.SubElement(message, "source").text = source
                if comment is not None:
                    ET.SubElement(message, "comment").text = comment
                ET.SubElement(message, "translation").text = override.english(source)
    write_ts(root, out_path, indent=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--overrides", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--app-name", required=True)
    parser.add_argument("--repo", required=True, help="GitHub owner/name of the fork")
    parser.add_argument("upstream_ts", nargs="+", type=Path)
    args = parser.parse_args()

    placeholders = {"app": args.app_name, "repo_url": f"https://github.com/{args.repo}"}
    overrides = load_overrides(args.overrides, placeholders)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    generated = []
    for ts_path in sorted(args.upstream_ts):
        out_path = args.out_dir / ts_path.name
        rewrite_upstream(ts_path, out_path, overrides)
        generated.append(out_path)

    english = args.out_dir / f"{args.prefix}_en.ts"
    write_english(english, overrides)
    generated.append(english)

    for path in generated:
        print(path.as_posix())


if __name__ == "__main__":
    main()
