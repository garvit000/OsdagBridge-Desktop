"""Download the pip-only wheels that get bundled into the installer.

openseespy / opsvis are not available as conda packages, so the installer ships
their wheels (``extra_files`` in construct.yaml) and installs them offline in
the post-install step. construct.yaml is the single source of truth: every
``wheels/<file>.whl`` entry for the requested platform is downloaded here with
the exact version encoded in its filename.

Usage (from the repository root, before running ``constructor``):

    python constructor/fetch_wheels.py --platform win
    python constructor/fetch_wheels.py --platform linux
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONSTRUCT_YAML = HERE / "construct.yaml"
WHEEL_DIR = HERE / "wheels"

PIP_PLATFORM = {"win": "win_amd64", "linux": "manylinux2014_x86_64"}
# Must match the python pinned in construct.yaml `specs`.
PYTHON_VERSION = "3.12"

ENTRY_RE = re.compile(r"^\s*-\s*wheels/(?P<file>[^\s:]+\.whl)\s*:.*#\s*\[(?P<sel>\w+)\]")


def wanted_wheels(platform: str) -> list[str]:
    files = []
    for line in CONSTRUCT_YAML.read_text(encoding="utf-8").splitlines():
        m = ENTRY_RE.match(line)
        if m and m.group("sel") == platform:
            files.append(m.group("file"))
    if not files:
        sys.exit(f"No 'wheels/*.whl  # [{platform}]' entries found in {CONSTRUCT_YAML}")
    return files


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=sorted(PIP_PLATFORM), required=True)
    args = parser.parse_args()

    files = wanted_wheels(args.platform)
    # Wheel filename: {name}-{version}-{python}-{abi}-{platform}.whl
    pins = [f"{f.split('-')[0]}=={f.split('-')[1]}" for f in files]
    print("Downloading:", " ".join(pins))

    WHEEL_DIR.mkdir(exist_ok=True)
    subprocess.check_call([
        sys.executable, "-m", "pip", "download",
        "--no-deps", "--only-binary=:all:",
        "--platform", PIP_PLATFORM[args.platform],
        "--python-version", PYTHON_VERSION,
        "--dest", str(WHEEL_DIR),
        *pins,
    ])

    missing = [f for f in files if not (WHEEL_DIR / f).is_file()]
    if missing:
        sys.exit(
            "pip downloaded different files than construct.yaml expects "
            f"(update the filenames there): {missing}"
        )
    print("All wheels present in", WHEEL_DIR)


if __name__ == "__main__":
    main()
