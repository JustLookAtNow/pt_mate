import re
import subprocess
import sys
from pathlib import Path


RELEASE_PREFIX = "# release:"


def run_git_command(args):
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def get_target_version():
    if len(sys.argv) > 1 and sys.argv[1].strip():
        return sys.argv[1].strip()

    pubspec = Path("pubspec.yaml")
    if not pubspec.exists():
        return ""

    content = pubspec.read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([^\s#]+)", content, re.MULTILINE)
    if not match:
        return ""
    return match.group(1)


def parse_release_version(subject_line):
    line = subject_line.strip()
    if not line.startswith(RELEASE_PREFIX):
        return None
    version = line[len(RELEASE_PREFIX):].strip()
    return version or None


def is_beta_version(version):
    base = version.split("+", 1)[0].lower()
    return "beta" in base


def is_release_commit_message(commit_message):
    first_line = commit_message.splitlines()[0].strip() if commit_message else ""
    return parse_release_version(first_line) is not None


def find_release_boundary(target_version):
    releases_raw = run_git_command(["log", "--format=%H%x1f%s"])
    if not releases_raw:
        return None, "Warning: git log returned no commits. Fetching all commits."

    release_entries = []
    for line in releases_raw.splitlines():
        if "\x1f" not in line:
            continue
        commit_hash, subject = line.split("\x1f", 1)
        release_version = parse_release_version(subject)
        if release_version:
            release_entries.append((commit_hash, release_version))

    if not release_entries:
        return None, "Warning: No previous release commit found. Fetching all commits."

    if is_beta_version(target_version):
        commit_hash, release_version = release_entries[0]
        message = (
            f"Beta release detected ({target_version}). "
            f"Collecting commits since last release {release_version}."
        )
        return commit_hash, message

    for commit_hash, release_version in release_entries:
        if not is_beta_version(release_version):
            message = (
                f"Stable release detected ({target_version}). "
                f"Collecting commits since last stable release {release_version}."
            )
            return commit_hash, message

    message = (
        f"Stable release detected ({target_version}), but no previous stable release commit found. "
        "Fetching all commits."
    )
    return None, message


def main():
    target_version = get_target_version()
    if not target_version:
        print("Warning: Could not determine target version. Treating as stable release.")
        target_version = "0.0.0"

    boundary_commit, boundary_message = find_release_boundary(target_version)
    print(boundary_message)

    range_str = f"{boundary_commit}..HEAD" if boundary_commit else "HEAD"
    commits_raw = run_git_command(["log", range_str, "--format=%B%x1e"])

    if not commits_raw:
        print("No new commits found in selected range.")
        return

    commits = [c.strip() for c in commits_raw.split("\x1e") if c.strip()]
    commits = [c for c in commits if not is_release_commit_message(c)]

    if not commits:
        print("No user-facing commits found in selected range.")
        return

    print(f"Found {len(commits)} commits for release notes.")
    print("-" * 20)
    for i, commit in enumerate(commits, 1):
        print(f"Commit {i}:")
        print(commit)
        print("-" * 10)


if __name__ == "__main__":
    main()
