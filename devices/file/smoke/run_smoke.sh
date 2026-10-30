#!/bin/sh
# Smoke test for legder on a file: every phase is a separate process,
# so what the next phase reads came from the file, not from memory.
#
#   ./run_smoke.sh            uses a temporary file, removed afterwards
#   ./run_smoke.sh PATH       uses PATH (must not exist), and keeps it
#
# Run from this directory after `alr build`.

set -eu

BIN=./bin/file_smoke
[ -x "$BIN" ] || { echo "build first: alr build"; exit 1; }

if [ $# -ge 1 ]; then
    DB=$1
    KEEP=1
    [ ! -e "$DB" ] || { echo "$DB exists; pick a new path"; exit 1; }
else
    DIR=$(mktemp -d)
    DB=$DIR/legder.db
    KEEP=0
    trap 'rm -rf "$DIR"' EXIT
fi

"$BIN" write          "$DB"
"$BIN" check          "$DB"
"$BIN" check          "$DB"     # reading twice changes nothing
"$BIN" extend         "$DB"
"$BIN" check-extended "$DB"

SIZE=$(wc -c < "$DB" | tr -d ' ')
echo "file holds $SIZE bytes = $((SIZE / 512)) blocks (8 records expected)"
[ "$SIZE" -eq $((8 * 512)) ] || { echo "SMOKE FAILED: unexpected file size"; exit 1; }

[ "$KEEP" -eq 1 ] && echo "database kept at $DB"
echo "smoke ok"
