#!/usr/bin/env bash
# Apply only the reviewed local changes to the pinned Impactor checkout.
set -euo pipefail
cd "$(dirname "$0")"
for patch in omnisette-remote-v3.patch anisette-mac-auth.patch; do
    if ! git -C Impactor apply --reverse --check "../patches/$patch" 2>/dev/null; then
        git -C Impactor apply "../patches/$patch"
    fi
done
