"""Build CardPilot's AltStore Classic / SideStore source from a published IPA."""

import argparse
from datetime import datetime
import hashlib
import html
import json
from pathlib import Path
import plistlib
import re
import shutil
from urllib.parse import quote, urlsplit
import zipfile


BUNDLE_ID = "com.maxduke.CardPilot"
IPA_NAME = "CardPilot-unsigned.ipa"
TAG_PATTERN = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
APP_ROOT = "Payload/CardPilot.app/"
PROJECT_ROOT = Path(__file__).resolve().parents[1]


def release_assets(release, repository):
    tag = release["tag_name"]
    if not TAG_PATTERN.fullmatch(tag):
        raise ValueError("A stable vMAJOR.MINOR.PATCH tag is required")
    expected = {IPA_NAME, IPA_NAME + ".sha256"}
    assets = [asset for asset in release.get("assets", []) if asset["name"] in expected]
    if len(assets) != 2 or {asset["name"] for asset in assets} != expected:
        raise ValueError("A release must have exactly one IPA and its checksum")
    result = {asset["name"]: asset for asset in assets}
    for name, asset in result.items():
        expected_url = f"https://github.com/{repository}/releases/download/{tag}/{name}"
        if asset.get("browser_download_url") != expected_url or asset.get("state") != "uploaded":
            raise ValueError("Source downloads must use uploaded assets at the exact release tag")
        if type(asset.get("size")) is not int or asset["size"] <= 0:
            raise ValueError("Release asset sizes must be positive byte counts")
    return result


def select_release(releases, repository):
    """An old tag being rebuilt must never move the source back a version."""
    candidates = []
    for release in releases:
        match = TAG_PATTERN.fullmatch(release.get("tag_name", ""))
        if not match or release.get("draft") or release.get("prerelease") or not release.get("published_at"):
            continue
        names = {asset["name"] for asset in release.get("assets", [])}
        if {IPA_NAME, IPA_NAME + ".sha256"} <= names:
            candidates.append((tuple(map(int, match.groups())), release))
    if not candidates:
        raise ValueError("No published stable release has an IPA and checksum")
    release = max(candidates, key=lambda item: item[0])[1]
    release_assets(release, repository)
    return release


def verify_asset(path, asset):
    if path.stat().st_size != asset["size"]:
        raise ValueError(f"Asset byte count does not match GitHub: {path.name}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if asset.get("digest") and asset["digest"] != "sha256:" + digest:
        raise ValueError(f"Asset SHA-256 does not match GitHub: {path.name}")
    return digest


def build_source(release, repository, ipa_path, checksum_path, base_url):
    assets = release_assets(release, repository)
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("Only published stable releases belong in this source")
    published = datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
    if published.tzinfo is None:
        raise ValueError("Release publication time must include a time zone")
    base_url = base_url.rstrip("/")
    parsed = urlsplit(base_url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.query or parsed.fragment:
        raise ValueError("The source needs a public HTTPS base URL")

    digest = verify_asset(ipa_path, assets[IPA_NAME])
    verify_asset(checksum_path, assets[IPA_NAME + ".sha256"])
    checksum = re.fullmatch(r"([0-9a-fA-F]{64})[ \t]+\*?CardPilot-unsigned\.ipa[ \t]*\n?", checksum_path.read_text())
    if not checksum or checksum[1].lower() != digest:
        raise ValueError("The IPA does not match its published SHA-256 file")

    with zipfile.ZipFile(ipa_path) as archive:
        if archive.testzip() is not None:
            raise ValueError("IPA ZIP integrity check failed")
        for name in archive.namelist():
            if name not in {"Payload/", APP_ROOT} and not name.startswith(APP_ROOT):
                raise ValueError("Unexpected content outside the CardPilot app bundle")
            if any(part.endswith((".appex", ".app")) for part in Path(name.removeprefix(APP_ROOT)).parts):
                raise ValueError("Embedded apps/extensions need explicit source permission support")
            if "_CodeSignature" in Path(name).parts or name.endswith("embedded.mobileprovision"):
                raise ValueError("This source expects the published unsigned IPA")
        info = plistlib.loads(archive.read(APP_ROOT + "Info.plist"))
        if info.get("CFBundleIdentifier") != BUNDLE_ID:
            raise ValueError("The IPA bundle identifier is not CardPilot")
        version = release["tag_name"][1:]
        if info.get("CFBundleShortVersionString") != version:
            raise ValueError("The IPA version does not match its release tag")
        build = info.get("CFBundleVersion")
        minimum = info.get("MinimumOSVersion")
        if not isinstance(build, str) or not build or not isinstance(minimum, str) or not re.fullmatch(r"\d+(?:\.\d+){1,2}", minimum):
            raise ValueError("The IPA must declare its build and minimum iOS version")
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("The source must point to an iPhoneOS build")
        executable = info.get("CFBundleExecutable", "")
        if not executable or "/" in executable or APP_ROOT + executable not in archive.namelist():
            raise ValueError("The IPA is missing its app executable")
        privacy = {}
        for key, value in info.items():
            if "UsageDescription" in key:
                if not isinstance(value, str) or not value.strip():
                    raise ValueError(f"Unsupported privacy permission format: {key}")
                privacy[key] = value

    release_url = f"https://github.com/{repository}/releases/tag/{release['tag_name']}"
    current = {
        "version": version,
        "buildVersion": build,
        "date": release["published_at"],
        "localizedDescription": f"CardPilot {version} 正式版。\n完整更新说明：{release_url}",
        "downloadURL": assets[IPA_NAME]["browser_download_url"],
        "size": assets[IPA_NAME]["size"],
        "minOSVersion": minimum,
    }
    icon_url = base_url + "/icon.png"
    app = {
        "name": "CardPilot",
        "bundleIdentifier": BUNDLE_ID,
        "developerName": "maxduke",
        "subtitle": "信用卡、账单提醒与促销进度",
        "localizedDescription": "本地优先的 iPhone 信用卡管理工具，统一记录账单日期、还款提醒和促销进度。数据保存在设备本地，只记录卡片末四位。",
        "iconURL": icon_url,
        "tintColor": "#C63E2B",
        "category": "utilities",
        "versions": [current],
        "appPermissions": {"entitlements": [], "privacy": privacy},
        # Older compatible clients still read the original app-level fields.
        "version": current["version"],
        "versionDate": current["date"],
        "versionDescription": current["localizedDescription"],
        "downloadURL": current["downloadURL"],
        "size": current["size"],
    }
    return {
        "name": "CardPilot 软件源",
        "identifier": BUNDLE_ID + ".source",
        "subtitle": "CardPilot 正式版安装与更新",
        "description": "通过 SideStore 或 AltStore Classic 安装和更新 CardPilot。软件源随正式版 IPA 发布自动更新。",
        "iconURL": icon_url,
        "website": base_url + "/",
        "tintColor": app["tintColor"],
        "apps": [app],
        "news": [],
    }


def write_site(source, output):
    base_url = source["website"].rstrip("/")
    current = source["apps"][0]["versions"][0]
    source_url = base_url + "/source.json"
    encoded = quote(source_url, safe="")
    values = {
        "SOURCE_URL": source_url,
        "SIDESTORE_URL": "sidestore://source?url=" + encoded,
        "ALTSTORE_URL": "altstore://source?url=" + encoded,
        "VERSION": current["version"],
        "MINIMUM_IOS": current["minOSVersion"],
        "DOWNLOAD_URL": current["downloadURL"],
    }
    template = (PROJECT_ROOT / "source/index.html").read_text()
    for key, value in values.items():
        template = template.replace("{{" + key + "}}", html.escape(value, quote=True))
    if re.search(r"\{\{[A-Z_]+\}\}", template):
        raise ValueError("The source page has an unresolved template value")
    output.mkdir(parents=True, exist_ok=True)
    (output / "source.json").write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n")
    (output / "index.html").write_text(template)
    shutil.copyfile(PROJECT_ROOT / "CardPilot/Assets.xcassets/AppIcon.appiconset/AppIcon.png", output / "icon.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["select", "build"])
    parser.add_argument("--repository", default="maxduke/card-pilot")
    parser.add_argument("--releases", type=Path)
    parser.add_argument("--release", type=Path)
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--checksum", type=Path)
    parser.add_argument("--base-url")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.command == "select":
        if not args.releases:
            parser.error("select requires --releases")
        selected = select_release(json.loads(args.releases.read_text()), args.repository)
        args.output.write_text(json.dumps(selected, ensure_ascii=False, indent=2) + "\n")
    else:
        if not all([args.release, args.ipa, args.checksum, args.base_url]):
            parser.error("build requires --release, --ipa, --checksum and --base-url")
        source = build_source(json.loads(args.release.read_text()), args.repository, args.ipa, args.checksum, args.base_url)
        write_site(source, args.output)
        print(f"Validated CardPilot {source['apps'][0]['version']}: {source['website']}source.json")


if __name__ == "__main__":
    main()
