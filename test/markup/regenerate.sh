#!/usr/bin/env bash
# Refresh the frozen "expected" JSON in every conformance fixture file by
# running each input through dmark, the proxy oracle for e621ng/dtext.
# Hand-edit the `input` and `label` fields in
# `conformance/fixtures/<category>.json`, then run this script and commit.
#
# Pass category names to limit scope:
#   ./test/markup/regenerate.sh             # all
#   ./test/markup/regenerate.sh blocks      # just blocks.json
#
# Dev-only. Deleted in commit 2 once every fixture is frozen and parity
# is confirmed; the conformance tests run standalone after that.

set -euo pipefail

# Resolve the package root regardless of where we were invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PKG_ROOT"

# Ensure the Node bridge has its dmark dependency installed. yarn install
# is a no-op when up to date so this is fast on warm runs.
if [ ! -d "test/markup/_bridge/node_modules/dmark" ]; then
  echo "[regenerate] installing bridge dependencies"
  (cd test/markup/_bridge && yarn install --silent)
fi

exec dart run test/markup/_bridge/regen.dart "$@"
