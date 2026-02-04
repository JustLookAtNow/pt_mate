import yaml
import sys
import re
import os

def bump_version(current_version, new_version=None):
    if new_version:
        return new_version
    
    # 简单的语义化版本自增逻辑 (major.minor.patch+build)
    # Flutter 格式通常是 1.0.0+1
    base_part = current_version.split('+')[0]
    parts = base_part.split('.')
    while len(parts) < 3:
        parts.append('0')
    
    parts[-1] = str(int(parts[-1]) + 1)
    new_base = '.'.join(parts)
    
    # 如果有 build number，也尝试增加它
    if '+' in current_version:
        build_num = current_version.split('+')[1]
        try:
            new_build = str(int(build_num) + 1)
            return f"{new_base}+{new_build}"
        except ValueError:
            return new_base
    
    return new_base

def main():
    pubspec_path = 'pubspec.yaml'
    if not os.path.exists(pubspec_path):
        print(f"Error: {pubspec_path} not found.")
        sys.exit(1)

    target_version = sys.argv[1] if len(sys.argv) > 1 else None

    # 我们使用正则替换以保持 yaml 文件的原始格式和注释
    with open(pubspec_path, 'r', encoding='utf-8') as f:
        content = f.read()

    version_match = re.search(r'^version:\s*([^\s#]+)', content, re.MULTILINE)
    if not version_match:
        print("Error: Could not find version in pubspec.yaml")
        sys.exit(1)

    current_version = version_match.group(1)
    new_version = bump_version(current_version, target_version)

    print(f"Bumping version from {current_version} to {new_version}")

    new_content = re.sub(r'^version:\s*[^\s#]+', f'version: {new_version}', content, flags=re.MULTILINE)

    with open(pubspec_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    print(f"Successfully updated version to {new_version}")
    # 输出给后续流程使用
    print(f"NEW_VERSION={new_version}")

if __name__ == "__main__":
    main()
