import subprocess
import sys

def run_command(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        return ""
    return result.stdout.strip()

def main():
    # 查找上次 release 的 commit hash
    last_release_commit = run_command('git log --format="%H" --grep="^release:" -n 1')
    
    if not last_release_commit:
        print("Warning: No previous release commit found. Fetching all commits.")
        range_str = "HEAD"
    else:
        range_str = f"{last_release_commit}..HEAD"

    # 获取所有 commit message，包括多行内容
    # 使用自定义分隔符来区分不同的 commit
    separator = "---COMMIT_SEP---"
    log_format = f"%B{separator}"
    commits_raw = run_command(f'git log {range_str} --format="{log_format}"')
    
    if not commits_raw:
        print("No new commits found since last release.")
        return

    commits = [c.strip() for c in commits_raw.split(separator) if c.strip()]
    
    print(f"Found {len(commits)} commits since last release.")
    print("-" * 20)
    for i, commit in enumerate(commits, 1):
        print(f"Commit {i}:")
        print(commit)
        print("-" * 10)

if __name__ == "__main__":
    main()
