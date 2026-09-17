#!/usr/bin/env python3
"""Insert or replace one item in a Sparkle appcast feed (ADR-0080 §3).

Sparkle's generate_appcast requires every referenced archive on disk and
moves old update files aside, so it cannot maintain a feed on a fresh CI
runner. This script merges a single <item> into an existing feed (or
creates the feed) using only the Python 3 standard library.

Usage:
  scripts/release-appcast-merge.py --feed PATH --version V --build-number N \
      --download-url URL --dmg PATH --signature SIG --notes-file PATH \
      [--title TITLE] [--max-items N]
"""

import argparse
import os
import sys
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime

MIN_SYSTEM_VERSION = "14.0"
NOTES_MARKER = "@@BREV_RELEASE_NOTES@@"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"

ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)


def q(ns, tag):
    return "{%s}%s" % (ns, tag)


def new_feed(title):
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = title
    ET.SubElement(channel, "link").text = "https://henrikogaard.github.io/brev/"
    ET.SubElement(channel, "description").text = "Brev update feed"
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(rss)


def item_sort_key(item):
    version_el = item.find(q(SPARKLE_NS, "version"))
    try:
        return int((version_el.text or "0").strip())
    except ValueError:
        return 0


def item_version(item):
    for tag in (q(SPARKLE_NS, "version"), q(SPARKLE_NS, "shortVersionString")):
        el = item.find(tag)
        if el is not None and (el.text or "").strip():
            return el.text.strip()
    title_el = item.find("title")
    return (title_el.text or "").strip() if title_el is not None else ""


def build_item(args, notes_text, pubdate):
    item = ET.Element("item")
    ET.SubElement(item, "title").text = args.version
    ET.SubElement(item, "pubDate").text = pubdate
    ET.SubElement(item, q(SPARKLE_NS, "version")).text = args.build_number
    ET.SubElement(item, q(SPARKLE_NS, "shortVersionString")).text = args.version
    ET.SubElement(item, q(SPARKLE_NS, "minimumSystemVersion")).text = MIN_SYSTEM_VERSION
    desc = ET.SubElement(item, "description")
    # Plain-text notes inside a <pre> in CDATA. ElementTree has no CDATA
    # support, so a marker is embedded and serialize() rewrites it.
    desc.text = NOTES_MARKER + notes_text
    ET.SubElement(item, "enclosure", {
        "url": args.download_url,
        "length": str(os.path.getsize(args.dmg)),
        "type": "application/octet-stream",
        q(SPARKLE_NS, "edSignature"): args.signature,
    })
    return item


def serialize(tree, path):
    """Write the feed, restoring CDATA markers that ElementTree escapes."""
    raw = ET.tostring(tree.getroot(), encoding="unicode")
    # ElementTree has no CDATA support; rewrite the marked item description
    # bodies into CDATA-wrapped <pre> notes. The inner text is already
    # XML/HTML-escaped by the serializer.
    raw = re.sub(
        r"<description>%s(.*?)</description>" % re.escape(NOTES_MARKER),
        r"<description><![CDATA[<pre>\1</pre>]]></description>",
        raw,
        flags=re.S,
    )
    xml = '<?xml version="1.0" encoding="utf-8"?>\n' + raw + "\n"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(xml)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feed", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--dmg", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--notes-file", required=True)
    parser.add_argument("--title", default="Brev changelog")
    parser.add_argument("--max-items", type=int, default=0,
                        help="keep at most N items, newest first (0 = keep all)")
    args = parser.parse_args()

    for path_arg in (args.dmg, args.notes_file):
        if not os.path.isfile(path_arg):
            print("release-appcast-merge: missing file: %s" % path_arg, file=sys.stderr)
            return 1

    with open(args.notes_file, encoding="utf-8") as fh:
        notes_text = fh.read().strip()

    if os.path.isfile(args.feed):
        tree = ET.parse(args.feed)
        channel = tree.getroot().find("channel")
        if channel is None:
            print("release-appcast-merge: %s has no <channel>" % args.feed,
                  file=sys.stderr)
            return 1
    else:
        os.makedirs(os.path.dirname(os.path.abspath(args.feed)) or ".",
                    exist_ok=True)
        tree = new_feed(args.title)
        channel = tree.getroot().find("channel")

    pubdate = format_datetime(datetime.now(timezone.utc), usegmt=True)
    new_item = build_item(args, notes_text, pubdate)

    items = channel.findall("item")
    # Idempotent: replace an existing item for the same version or build.
    kept = [
        item for item in items
        if item_version(item) not in (args.version, args.build_number)
    ]
    kept.insert(0, new_item)

    if args.max_items > 0:
        kept = kept[: args.max_items]

    for item in items:
        channel.remove(item)
    for item in kept:
        channel.append(item)

    serialize(tree, args.feed)
    print("release-appcast-merge: %s now has %d item(s)"
          % (args.feed, len(kept)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
