import json
import re
from datetime import datetime
from typing import Any, Dict, List, Optional, TypedDict

import requests


class ReleaseAsset(TypedDict):
    browser_download_url: str
    name: str
    size: int


class GitHubRelease(TypedDict):
    tag_name: str
    published_at: str
    body: str
    draft: bool
    prerelease: bool
    assets: List[ReleaseAsset]


class VersionEntry(TypedDict):
    version: str
    date: str
    localizedDescription: str
    downloadURL: Optional[str]
    size: Optional[int]


class AppConfig(TypedDict):
    repo_url: str
    json_file: str
    source_id: str
    app_id: str
    app_name: str
    caption: str
    tint_colour: str
    image_url: str


def load_config(config_path: str) -> AppConfig:
    with open(config_path, "r", encoding="utf-8") as config_file:
        return json.load(config_file)


def fetch_releases(repo_url: str) -> List[GitHubRelease]:
    api_url = f"https://api.github.com/repos/{repo_url}/releases"
    headers = {"Accept": "application/vnd.github+json"}
    response = requests.get(api_url, headers=headers, timeout=30)
    response.raise_for_status()
    releases: List[GitHubRelease] = response.json()
    valid_releases = [
        release
        for release in releases
        if not release.get("draft", False) and not release.get("prerelease", False)
    ]
    return sorted(valid_releases, key=lambda item: item["published_at"], reverse=True)


def format_description(description: str) -> str:
    formatted = re.sub(r"<[^<]+?>", "", description)
    formatted = re.sub(r"#{1,6}\s?", "", formatted)
    return formatted.strip()


def find_download_url_and_size(
    release: GitHubRelease,
) -> tuple[Optional[str], Optional[int]]:
    for asset in release["assets"]:
        if asset["name"].endswith(".ipa"):
            return asset["browser_download_url"], asset["size"]
    return None, None


def normalize_version(version: str) -> str:
    cleaned = version.lstrip("v")
    match = re.search(r"(\d+\.\d+\.\d+)", cleaned)
    if match:
        return match.group(1)
    return cleaned


def build_version_entries(releases: List[GitHubRelease]) -> List[VersionEntry]:
    entries: List[VersionEntry] = []
    seen_versions = set()

    for release in releases:
        download_url, size = find_download_url_and_size(release)
        if not download_url:
            continue

        version = normalize_version(release["tag_name"])
        if version in seen_versions:
            continue

        seen_versions.add(version)
        entries.append(
            {
                "version": version,
                "date": release["published_at"],
                "localizedDescription": format_description(release.get("body", "")),
                "downloadURL": download_url,
                "size": size,
            }
        )

    return entries


def build_source_data(
    config: AppConfig,
    releases: List[GitHubRelease],
) -> Dict[str, Any]:
    version_entries = build_version_entries(releases)
    if not version_entries:
        raise ValueError("No iOS IPA asset found in non-prerelease releases.")

    latest_release = None
    latest_download_url = None
    latest_size = None
    for release in releases:
        latest_download_url, latest_size = find_download_url_and_size(release)
        if latest_download_url:
            latest_release = release
            break

    if latest_release is None or latest_download_url is None:
        raise ValueError("No release with a matching iOS IPA asset was found.")

    latest_version = normalize_version(latest_release["tag_name"])
    latest_description = format_description(latest_release.get("body", ""))
    repo_url = config["repo_url"]
    raw_base_url = f"https://raw.githubusercontent.com/{repo_url}/refs/heads/master"

    return {
        "name": config["app_name"],
        "identifier": config["source_id"],
        "sourceURL": f"{raw_base_url}/altsource/AltSource.json",
        "headerURL": f"{raw_base_url}/screenshots/1.png",
        "website": f"https://github.com/{repo_url}",
        "iconURL": f"{raw_base_url}/mt.png",
        "subtitle": "PT private tracker companion",
        "description": (
            "This is the official source for PT Mate.\n\n"
            "For full details, check the GitHub repository:\n"
            f"https://github.com/{repo_url}"
        ),
        "tintColor": config["tint_colour"],
        "apps": [
            {
                "beta": False,
                "name": config["app_name"],
                "bundleIdentifier": config["app_id"],
                "developerName": "JustLookAtNow",
                "subtitle": "PT private tracker companion",
                "version": latest_version,
                "versionDate": latest_release["published_at"],
                "versionDescription": latest_description,
                "downloadURL": latest_download_url,
                "localizedDescription": (
                    "PT Mate is a Flutter-based private tracker client for browsing, "
                    "searching, and managing downloads across multiple PT sites."
                ),
                "iconURL": f"{raw_base_url}/mt.png",
                "tintColor": config["tint_colour"],
                "category": "utilities",
                "size": latest_size or 0,
                "screenshotURLs": [
                    f"{raw_base_url}/screenshots/1.png",
                    f"{raw_base_url}/screenshots/2.png",
                    f"{raw_base_url}/screenshots/3.png",
                ],
                "versions": version_entries,
                "appPermissions": {
                    "entitlements": [],
                    "privacy": {}
                }
            }
        ],
        "news": [
            {
                "appID": config["app_id"],
                "title": (
                    f"{latest_version} - "
                    f"{datetime.strptime(latest_release['published_at'], '%Y-%m-%dT%H:%M:%SZ').strftime('%d %b')}"
                ),
                "identifier": f"release-{latest_version}",
                "caption": config["caption"],
                "date": latest_release["published_at"],
                "tintColor": config["tint_colour"],
                "imageURL": config["image_url"],
                "notify": True,
                "url": (
                    f"https://github.com/{repo_url}/releases/tag/"
                    f"{latest_release['tag_name']}"
                )
            }
        ]
    }


def main() -> None:
    config = load_config("altsource/config.json")
    releases = fetch_releases(config["repo_url"])
    source_data = build_source_data(config, releases)

    with open(config["json_file"], "w", encoding="utf-8") as output_file:
        json.dump(source_data, output_file, indent=2, ensure_ascii=False)
        output_file.write("\n")

    print("Successfully updated altsource/AltSource.json.")


if __name__ == "__main__":
    main()
