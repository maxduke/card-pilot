import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit
import zipfile


spec = importlib.util.spec_from_file_location("app_source", Path(__file__).parents[1] / "build_app_source.py")
app_source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app_source)


class AppSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.ipa = self.root / "CardPilot-unsigned.ipa"
        self.checksum = self.root / "CardPilot-unsigned.ipa.sha256"
        self.repository = "maxduke/card-pilot"
        self.base_url = "https://maxduke.github.io/card-pilot"
        self.info = {
            "CFBundleIdentifier": "com.maxduke.CardPilot",
            "CFBundleShortVersionString": "0.1.11",
            "CFBundleVersion": "1",
            "MinimumOSVersion": "17.0",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "CFBundleExecutable": "CardPilot",
            "NSFaceIDUsageDescription": "使用面容 ID 解锁 CardPilot。",
        }
        self.release = {
            "tag_name": "v0.1.11", "draft": False, "prerelease": False,
            "published_at": "2026-11-08T10:38:55Z", "assets": [],
        }
        self.write_package()

    def update_assets(self):
        self.release["assets"] = [{
            "name": path.name, "size": path.stat().st_size, "state": "uploaded",
            "digest": "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest(),
            "browser_download_url": f"https://github.com/{self.repository}/releases/download/{self.release['tag_name']}/{path.name}",
        } for path in [self.ipa, self.checksum]]

    def write_package(self, extra=None):
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/CardPilot.app/Info.plist", plistlib.dumps(self.info))
            archive.writestr("Payload/CardPilot.app/CardPilot", b"unsigned-device-executable-fixture")
            for name, value in (extra or {}).items():
                archive.writestr(name, value)
        digest = hashlib.sha256(self.ipa.read_bytes()).hexdigest()
        self.checksum.write_text(digest + "  CardPilot-unsigned.ipa\n")
        self.update_assets()

    def build(self):
        return app_source.build_source(self.release, self.repository, self.ipa, self.checksum, self.base_url)

    def test_source_matches_the_actual_ipa_and_classic_permission_contract(self):
        source = self.build()
        self.assertEqual(source["identifier"], "com.maxduke.CardPilot.source")
        self.assertEqual(len(source["apps"]), 1)
        app = source["apps"][0]
        self.assertEqual(app["bundleIdentifier"], "com.maxduke.CardPilot")
        self.assertEqual(app["appPermissions"], {
            "entitlements": [], "privacy": {"NSFaceIDUsageDescription": "使用面容 ID 解锁 CardPilot。"},
        })
        current = app["versions"][0]
        self.assertEqual((current["version"], current["buildVersion"], current["minOSVersion"]), ("0.1.11", "1", "17.0"))
        self.assertEqual(current["size"], self.ipa.stat().st_size)
        self.assertEqual(current["downloadURL"], "https://github.com/maxduke/card-pilot/releases/download/v0.1.11/CardPilot-unsigned.ipa")
        self.assertNotIn("marketplaceID", app)
        for original, modern in [("version", "version"), ("versionDate", "date"), ("versionDescription", "localizedDescription"),
                                 ("downloadURL", "downloadURL"), ("size", "size")]:
            self.assertEqual(app[original], current[modern])

    def test_numeric_version_order_ignores_drafts_prereleases_and_incomplete_assets(self):
        old = copy.deepcopy(self.release)
        old["tag_name"] = "v0.1.9"
        future = copy.deepcopy(self.release)
        future["tag_name"] = "v0.1.12"
        future["assets"] = future["assets"][:1]
        draft = copy.deepcopy(self.release)
        draft.update(tag_name="v1.0.0", draft=True)
        beta = copy.deepcopy(self.release)
        beta.update(tag_name="v2.0.0", prerelease=True)
        selected = app_source.select_release([draft, beta, future, self.release, old], self.repository)
        self.assertEqual(selected["tag_name"], "v0.1.11")
        # Release order changes when an old tag is rebuilt; selection must not.
        self.assertEqual(app_source.select_release([old, self.release], self.repository), self.release)

    def test_no_incomplete_or_unpublished_release_is_advertised(self):
        for change in [{"assets": []}, {"draft": True}, {"prerelease": True}, {"published_at": None},
                       {"tag_name": "v0.1.12-beta.1"}, {"tag_name": "v00.1.12"}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                app_source.select_release([{**self.release, **change}], self.repository)

    def test_duplicate_or_mutable_asset_urls_are_rejected(self):
        for bad in ["https://example.com/CardPilot.ipa", "https://github.com/maxduke/card-pilot/releases/latest/download/CardPilot-unsigned.ipa"]:
            self.release["assets"][0]["browser_download_url"] = bad
            with self.subTest(url=bad), self.assertRaisesRegex(ValueError, "exact release tag"):
                self.build()
        self.update_assets()
        self.release["assets"].append(copy.deepcopy(self.release["assets"][0]))
        with self.assertRaisesRegex(ValueError, "exactly one"):
            self.build()

    def test_asset_size_and_github_digest_are_verified(self):
        self.release["assets"][0]["size"] += 1
        with self.assertRaisesRegex(ValueError, "byte count"):
            self.build()
        self.update_assets()
        self.release["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ValueError, "match GitHub"):
            self.build()

    def test_published_checksum_must_match_bytes_and_filename(self):
        for content in ["0" * 64 + "  CardPilot-unsigned.ipa\n",
                        hashlib.sha256(self.ipa.read_bytes()).hexdigest() + "  Other.ipa\n"]:
            with self.subTest(content=content):
                self.checksum.write_text(content)
                self.update_assets()
                with self.assertRaisesRegex(ValueError, "published SHA-256"):
                    self.build()

    def test_older_assets_without_api_digest_still_require_the_checksum(self):
        for asset in self.release["assets"]:
            asset["digest"] = None
        self.assertEqual(self.build()["apps"][0]["version"], "0.1.11")
        content = bytearray(self.ipa.read_bytes())
        content[-1] ^= 1
        self.ipa.write_bytes(content)
        with self.assertRaisesRegex(ValueError, "published SHA-256"):
            self.build()

    def test_archive_integrity_is_verified_even_with_matching_hashes(self):
        self.ipa.write_bytes(b"not-a-zip")
        self.checksum.write_text(hashlib.sha256(self.ipa.read_bytes()).hexdigest() + "  CardPilot-unsigned.ipa\n")
        self.update_assets()
        with self.assertRaises(zipfile.BadZipFile):
            self.build()

    def test_wrong_app_version_build_platform_and_minimum_are_rejected(self):
        original = copy.deepcopy(self.info)
        for key, value in [("CFBundleIdentifier", "com.other.App"), ("CFBundleShortVersionString", "0.1.10"),
                           ("CFBundleVersion", ""), ("MinimumOSVersion", ""),
                           ("CFBundleSupportedPlatforms", ["iPhoneSimulator"]), ("CFBundleExecutable", "Missing")]:
            with self.subTest(key=key):
                self.info = {**original, key: value}
                self.write_package()
                with self.assertRaises(ValueError):
                    self.build()

    def test_privacy_is_read_from_the_package_without_guessing(self):
        self.info["NSCameraUsageDescription"] = "扫描信用卡标签。"
        self.write_package()
        self.assertEqual(self.build()["apps"][0]["appPermissions"]["privacy"]["NSCameraUsageDescription"], "扫描信用卡标签。")
        self.info["NSLocationTemporaryUsageDescriptionDictionary"] = {"test": "location"}
        self.write_package()
        with self.assertRaisesRegex(ValueError, "privacy permission format"):
            self.build()

    def test_signed_or_embedded_apps_never_publish_empty_permission_lists(self):
        for name in ["Payload/CardPilot.app/_CodeSignature/CodeResources", "Payload/CardPilot.app/embedded.mobileprovision",
                     "Payload/CardPilot.app/PlugIns/Share.appex/Info.plist", "Payload/Other.app/Info.plist"]:
            with self.subTest(name=name):
                self.write_package({name: b"unsupported"})
                with self.assertRaises(ValueError):
                    self.build()

    def test_http_and_ambiguous_base_urls_are_rejected(self):
        for value in ["http://example.com/source", "https://example.com/source?test=1", "https://example.com/source#fragment"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                app_source.build_source(self.release, self.repository, self.ipa, self.checksum, value)

    def test_generated_site_has_matching_source_and_encoded_add_links(self):
        source = self.build()
        output = self.root / "site"
        app_source.write_site(source, output)
        self.assertEqual(json.loads((output / "source.json").read_text()), source)
        markup = (output / "index.html").read_text()
        self.assertNotIn("{{", markup)
        for scheme in ["sidestore", "altstore"]:
            match = re.search(r'href="(' + scheme + r'://[^\"]+)"', markup)
            self.assertIsNotNone(match)
            self.assertEqual(parse_qs(urlsplit(match[1]).query), {"url": [self.base_url + "/source.json"]})
        self.assertEqual((output / "icon.png").read_bytes()[:8], b"\x89PNG\r\n\x1a\n")


if __name__ == "__main__":
    unittest.main()
