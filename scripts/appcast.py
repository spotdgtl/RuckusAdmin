#!/usr/bin/env python3
"""Insert a release into a Sparkle appcast (creating the file if needed).

Used by scripts/release.sh. Keeps earlier items so Sparkle can show what changed since the
installed version; an item with the same build number is replaced.
"""
import argparse
import datetime
import email.utils
import html
import os
import re
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def sparkle(tag):
    return f"{{{SPARKLE}}}{tag}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--version", required=True, help="CFBundleVersion (build number)")
    parser.add_argument("--short-version", required=True, help="CFBundleShortVersionString")
    parser.add_argument("--url", required=True, help="download URL of the zip")
    parser.add_argument("--signature", required=True, help='output of sign_update: sparkle:edSignature="…" length="…"')
    parser.add_argument("--notes", default="")
    parser.add_argument("--release-page", default="")
    parser.add_argument("--minimum-system-version", default="15.0")
    parser.add_argument("--title", default="Ruckus Admin")
    parser.add_argument("--keep", type=int, default=10, help="how many items to keep")
    args = parser.parse_args()

    match = re.search(r'edSignature="([^"]+)"\s+length="(\d+)"', args.signature)
    if not match:
        raise SystemExit(f"unexpected sign_update output: {args.signature!r}")
    ed_signature, length = match.group(1), match.group(2)

    if os.path.exists(args.path):
        tree = ET.parse(args.path)
        rss = tree.getroot()
        channel = rss.find("channel")
    else:
        rss = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = args.title
        ET.SubElement(channel, "description").text = f"Updates for {args.title}"
        if args.release_page:
            ET.SubElement(channel, "link").text = args.release_page.split("/releases/")[0]

    for item in list(channel.findall("item")):
        version = item.find(sparkle("version"))
        if version is not None and version.text == args.version:
            channel.remove(item)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.short_version}"
    ET.SubElement(item, "pubDate").text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
    if args.release_page:
        ET.SubElement(item, "link").text = args.release_page
    ET.SubElement(item, sparkle("version")).text = args.version
    ET.SubElement(item, sparkle("shortVersionString")).text = args.short_version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = args.minimum_system_version
    if args.notes:
        paragraphs = [p.strip() for p in args.notes.split("\n\n") if p.strip()]
        body = "".join("<p>" + "<br>".join(html.escape(line) for line in p.splitlines()) + "</p>" for p in paragraphs)
        ET.SubElement(item, "description").text = body
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        "length": length,
        "type": "application/octet-stream",
        sparkle("edSignature"): ed_signature,
    })

    children = list(channel)
    first_item = next((i for i, child in enumerate(children) if child.tag == "item"), len(children))
    channel.insert(first_item, item)
    for extra in channel.findall("item")[args.keep:]:
        channel.remove(extra)

    ET.indent(rss)
    ET.ElementTree(rss).write(args.path, encoding="utf-8", xml_declaration=True)
    print(f"{args.path}: added {args.short_version} ({args.version})")


if __name__ == "__main__":
    main()
