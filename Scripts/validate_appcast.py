"""Check release metadata and return the archive's signature for verification."""
import base64
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def validate_appcast(feed, archive, version, download_url):
    root = ET.parse(feed).getroot()
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Expected exactly one release in the generated feed.")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("The update enclosure is missing.")
    # Sparkle 2 emits these as item elements; accept enclosure attributes too.
    actual_version = item.findtext(SPARKLE + "version") or enclosure.get(SPARKLE + "version")
    if actual_version != version:
        raise ValueError("Feed build version does not match the app build.")
    if enclosure.get("url") != download_url:
        raise ValueError("The archive URL does not match this release.")
    if enclosure.get("length") != str(Path(archive).stat().st_size):
        raise ValueError("The archive length does not match the feed.")
    signature = enclosure.get(SPARKLE + "edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("The update has no valid Ed25519 signature.")
    return signature


if __name__ == "__main__":
    try:
        print(validate_appcast(*sys.argv[1:]))
    except (ValueError, ET.ParseError, OSError) as error:
        raise SystemExit(str(error)) from None
