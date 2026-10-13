"""Plain-language summary of Feather commits Accretion doesn't have yet, for the Feather updates
workflow (job summary and pull request body). Sends only Feather's public commit messages and the
list of changed files to an OpenRouter model; prints Markdown. Without OPENROUTER_API_KEY, prints
nothing (the workflow then shows the plain commit list only).

Usage: python3 .github/scripts/upstream_summary.py   (in a checkout with an `upstream` remote fetched)
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

MODEL = os.environ.get("SUMMARY_MODEL", "google/gemini-2.5-flash")
PROMPT = """You summarise upstream changes for the maintainer of Accretion, a fork of the Feather iOS
sideloading app (GPL-3.0). Given Feather's new commit messages and the files they change, write a short
Markdown summary: what changed for users, what changed technically, and which areas Accretion has
customised and may conflict (Accretion marks its code with `// Accretion:` and keeps its own screens under
Feather/Views/Accretion, its own backend under Feather/Backend/{Account,Core,Store,Server}). End with one
line: "Merge effort: low / medium / high" and why. Under 200 words, plain words, no speculation."""


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def main():
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not key:
        return 0
    log = git("log", "--no-merges", "--format=- %s%n%b", "HEAD..upstream/main")[:20000]
    files = git("diff", "--stat=200", "HEAD...upstream/main")[-8000:]
    body = {
        "model": MODEL,
        "max_tokens": 700,
        "messages": [
            {"role": "system", "content": PROMPT},
            {"role": "user", "content": f"Commits:\n{log}\n\nChanged files:\n{files}"},
        ],
    }
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps(body).encode(),
        method="POST",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            text = json.loads(r.read())["choices"][0]["message"]["content"].strip()
    except urllib.error.HTTPError as e:
        print(f"_AI summary unavailable ({e.code})._")
        return 0
    print(f"#### Summary\n\n{text}\n\n_Summary by `{MODEL}` via OpenRouter; check the commits before merging._")
    return 0


if __name__ == "__main__":
    sys.exit(main())
