import base64
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts"))
from release_metadata import release_version, validate_key
from validate_appcast import validate_appcast


class ReleaseValidationTests(unittest.TestCase):
    def test_release_tag(self):
        self.assertEqual(release_version("v4.6.2"), "4.6.2")
        for tag in ("main", "v4.6.2-beta", "4.6", "v4.6.2\n", "$(command)"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release_version(tag)

    def test_missing_or_malformed_key_rejected_without_disclosing_value(self):
        for key in ("", "invalid secret content", base64.b64encode(b"short").decode()):
            with self.subTest(), self.assertRaises(ValueError) as error:
                validate_key(key, {32}, "Signing key")
            if key:
                self.assertNotIn(key, str(error.exception))
        validate_key(base64.b64encode(bytes(32)).decode(), {32}, "Public key")

    def check_feed(self, *, signature=None, version="42", url=None, length="7", items=1):
        signature = signature if signature is not None else base64.b64encode(bytes(64)).decode()
        url = url if url is not None else "https://github.com/example/app/releases/download/v1.0.0/ArenaMate-update.zip"
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "update.zip"
            archive.write_bytes(b"archive")
            feed = Path(directory) / "appcast.xml"
            item = f'''<item><sparkle:version>{version}</sparkle:version>
              <enclosure url="{url}" length="{length}" sparkle:edSignature="{signature}"/></item>'''
            feed.write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>' + item * items + '</channel></rss>')
            return validate_appcast(feed, archive, "42", "https://github.com/example/app/releases/download/v1.0.0/ArenaMate-update.zip")

    def test_signed_feed_metadata_accepted(self):
        self.assertEqual(len(base64.b64decode(self.check_feed())), 64)

    def test_unsigned_or_malformed_archive_signature_rejected(self):
        for signature in ("", "not-base64", base64.b64encode(bytes(32)).decode()):
            with self.subTest(signature=signature), self.assertRaises(ValueError):
                self.check_feed(signature=signature)

    def test_wrong_build_url_size_or_item_count_rejected(self):
        for values in ({"version": "41"}, {"url": "https://untrusted.example/update.zip"}, {"length": "8"}, {"items": 0}, {"items": 2}):
            with self.subTest(values=values), self.assertRaises(ValueError):
                self.check_feed(**values)


if __name__ == "__main__":
    unittest.main()
