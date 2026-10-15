"""Check build reuse and recover an encrypted cache without publishing anything."""

import argparse
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

# Files that never go into the IPA or change how it is built. A push that only touches these
# doesn't start a build (release.yml paths-ignore, kept equal by a test) and doesn't block reuse.
NOT_BUILD_INPUTS = (
    ".github/*.md",
    ".github/ISSUE_TEMPLATE/**",
    ".github/actions/alert/**",
    ".github/dependabot.yml",
    ".github/tests/**",
    ".github/workflows/screens.yml",
    ".github/workflows/secrets.yml",
    ".github/workflows/ship.yml",
    ".github/workflows/tests.yml",
    ".github/workflows/upstream.yml",
    ".gitleaks.toml",
)


def not_build_input(filename):
    """True for a file in NOT_BUILD_INPUTS (GitHub glob rules: * stays in one folder, ** spans)."""
    for pattern in NOT_BUILD_INPUTS:
        regex = re.escape(pattern).replace(r"\*\*", ".*").replace(r"\*", "[^/]*")
        if re.fullmatch(regex, filename):
            return True
    return False


def git(*arguments):
    return subprocess.check_output(
        ["git", *arguments], text=True, stderr=subprocess.DEVNULL
    )


def configuration_without_version(text):
    lines = text.splitlines()
    versions = [
        line for line in lines if re.match(r"^\s*FEATHER_PROJECT_VERSION\s*=", line)
    ]
    if len(versions) != 1:
        raise ValueError("Expected one project version assignment")
    return [line for line in lines if line not in versions]


def reusable(base, target):
    before = git(
        "rev-parse", "--verify", "--end-of-options", base + "^{commit}"
    ).strip()
    after = git(
        "rev-parse", "--verify", "--end-of-options", target + "^{commit}"
    ).strip()
    changed = git(
        "diff", "--name-only", "--no-renames", before, after, "--"
    ).splitlines()
    for filename in changed:
        if filename in ("app-repo.json", "app-repo-beta.json") or not_build_input(
            filename
        ):
            continue
        if filename != "Feather.xcconfig":
            return False
        old = configuration_without_version(git("show", before + ":Feather.xcconfig"))
        new = configuration_without_version(git("show", after + ":Feather.xcconfig"))
        if old != new:
            return False
    return True


def restore_cache(source, destination, key):
    source, destination = Path(source), Path(destination)
    if not key or not source.is_file():
        return False
    binary = shutil.which("openssl")
    if not binary and os.name == "nt":
        candidate = (
            Path(os.environ.get("ProgramFiles", "C:/Program Files"))
            / "Git/usr/bin/openssl.exe"
        )
        binary = str(candidate) if candidate.is_file() else None
    if not binary:
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as temporary:
        pending = Path(temporary.name)
    try:
        result = subprocess.run(
            [
                binary,
                "enc",
                "-d",
                "-aes-256-cbc",
                "-pbkdf2",
                "-iter",
                "200000",
                "-pass",
                "env:UPLOAD_KEY",
                "-in",
                str(source),
                "-out",
                str(pending),
            ],
            env={**os.environ, "UPLOAD_KEY": key},
            capture_output=True,
            check=False,
        )
        if result.returncode or not zipfile.is_zipfile(pending):
            return False
        with zipfile.ZipFile(pending) as archive:
            if archive.testzip() is not None:
                return False
        pending.replace(destination)
        return True
    except (OSError, zipfile.BadZipFile):
        return False
    finally:
        pending.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("compare", "restore"))
    parser.add_argument("first")
    parser.add_argument("second")
    args = parser.parse_args()
    try:
        ok = (
            reusable(args.first, args.second)
            if args.operation == "compare"
            else restore_cache(
                args.first, args.second, os.environ.get("UPLOAD_KEY", "")
            )
        )
    except (ValueError, subprocess.CalledProcessError):
        ok = False
    if not ok:
        print("A fresh build is required.")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
