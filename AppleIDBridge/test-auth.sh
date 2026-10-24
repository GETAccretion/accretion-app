#!/usr/bin/env bash
# Offline fixtures only. The filtered tests never provision or authenticate an account.
set -euo pipefail
cd "$(dirname "$0")"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$PWD/target-auth-tests}"
bash apply-patches.sh
cargo test --locked --manifest-path Impactor/Cargo.toml -p plume_core --features tweaks --lib accretion_
cargo test --locked --manifest-path Impactor/Cargo.toml -p omnisette --features remote-anisette-v3 --lib accretion_client_info
cargo test --locked --lib authentication_tests
