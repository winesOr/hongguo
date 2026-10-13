import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
pubspec_path = root / 'pubspec.yaml'

def get_current_version():
    content = pubspec_path.read_text(encoding='utf-8')
    m = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)', content, re.MULTILINE)
    if not m:
        raise ValueError("Cannot parse version from pubspec.yaml")
    return m.group(1), int(m.group(2))

def bump_version():
    content = pubspec_path.read_text(encoding='utf-8')
    m = re.search(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', content, re.MULTILINE)
    if not m:
        raise ValueError("Cannot parse version from pubspec.yaml")
    major, minor, patch, build = map(int, m.groups())
    new_patch = patch + 1
    new_build = build + 1
    new_version_str = f"{major}.{minor}.{new_patch}+{new_build}"
    new_content = re.sub(
        r'^version:\s*[\w.+-]+',
        f'version: {new_version_str}',
        content,
        count=1,
        flags=re.MULTILINE
    )
    pubspec_path.write_text(new_content, encoding='utf-8')
    return new_version_str

if __name__ == '__main__':
    if '--get' in sys.argv:
        v, b = get_current_version()
        print(f"{v}+{b}")
    else:
        new_v = bump_version()
        print(new_v)
