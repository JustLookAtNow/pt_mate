import json
import os
import re
import urllib.request
from datetime import datetime
from typing import Any, Dict, List, Optional, TypedDict


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
    developer_name: str
    subtitle: str
    localized_description: str
    category: str
    screenshot_count: int
    caption: str
    tint_colour: str
    image_url: str


def load_config(config_path: str) -> AppConfig:
    with open(config_path, "r", encoding="utf-8") as config_file:
        return json.load(config_file)


def fetch_releases(repo_url: str) -> List[GitHubRelease]:
    api_url = f"https://api.github.com/repos/{repo_url}/releases"
    headers = {"Accept": "application/vnd.github+json"}
    
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
        
    req = urllib.request.Request(api_url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            if response.status != 200:
                raise Exception(f"GitHub API returned status code {response.status}")
            releases: List[GitHubRelease] = json.loads(response.read().decode())
    except urllib.error.HTTPError as e:
        raise Exception(f"GitHub API error ({e.code}): {e.read().decode()}")
    except Exception as e:
        raise Exception(f"Failed to fetch releases: {e}")
    
    valid_releases = [
        release
        for release in releases
        if not release.get("draft", False) and not release.get("prerelease", False)
    ]
    return sorted(valid_releases, key=lambda item: item["published_at"], reverse=True)


def format_description(description: str) -> str:
    if not description:
        return ""
    # Basic HTML strip
    formatted = re.sub(r"<[^<]+?>", "", description)
    # Basic Markdown title strip
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
    match = re.search(r"(\d+(\.\d+)*)", cleaned)
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
        print("Warning: No version entries with .ipa files found.")

    latest_release = None
    latest_download_url = None
    latest_size = None
    for release in releases:
        latest_download_url, latest_size = find_download_url_and_size(release)
        if latest_download_url:
            latest_release = release
            break

    repo_url = config["repo_url"]
    branch = os.environ.get("GITHUB_REF_NAME", "master")
    raw_base_url = f"https://raw.githubusercontent.com/{repo_url}/refs/heads/{branch}"

    apps = []
    if latest_release and latest_download_url:
        latest_version = normalize_version(latest_release["tag_name"])
        latest_description = format_description(latest_release.get("body", ""))
        apps.append(
            {
                "beta": False,
                "name": config["app_name"],
                "bundleIdentifier": config["app_id"],
                "developerName": config["developer_name"],
                "subtitle": config["subtitle"],
                "version": latest_version,
                "versionDate": latest_release["published_at"],
                "versionDescription": latest_description,
                "downloadURL": latest_download_url,
                "localizedDescription": config["localized_description"],
                "iconURL": f"{raw_base_url}/mt.png",
                "tintColor": config["tint_colour"],
                "category": config["category"],
                "size": latest_size or 0,
                "screenshotURLs": [
                    f"{raw_base_url}/screenshots/{i + 1}.png"
                    for i in range(config["screenshot_count"])
                ],
                "versions": version_entries,
                "appPermissions": {
                    "entitlements": [],
                    "privacy": {}
                }
            }
        )

    news = []
    if latest_release:
        latest_version = normalize_version(latest_release["tag_name"])
        news.append(
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
        )

    return {
        "name": config["app_name"],
        "identifier": config["source_id"],
        "sourceURL": f"{raw_base_url}/altsource/AltSource.json",
        "headerURL": f"{raw_base_url}/screenshots/1.png",
        "website": f"https://github.com/{repo_url}",
        "iconURL": f"{raw_base_url}/mt.png",
        "subtitle": config["subtitle"],
        "description": (
            f"This is the official source for {config['app_name']}.\n\n"
            "For full details, check the GitHub repository:\n"
            f"https://github.com/{repo_url}"
        ),
        "tintColor": config["tint_colour"],
        "apps": apps,
        "news": news
    }


def main() -> None:
    config = load_config("altsource/config.json")
    try:
        releases = fetch_releases(config["repo_url"])
        source_data = build_source_data(config, releases)

        with open(config["json_file"], "w", encoding="utf-8") as output_file:
            json.dump(source_data, output_file, indent=2, ensure_ascii=False)
            output_file.write("\n")

        print("Successfully updated altsource/AltSource.json.")
    except Exception as e:
        print(f"Error updating altsource: {e}")


if __name__ == "__main__":
    main()
