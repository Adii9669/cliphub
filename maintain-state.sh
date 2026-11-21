#!/bin/bash

# Shared state location, owner-only permissions, and image garbage collection
# for Clipboard Hub. Called at startup and after every history write.
#
# Images newer than the grace window are kept even if no history entry refers
# to them yet, so a just-captured screenshot cannot be deleted before its
# entry is saved.

set -o pipefail

STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
STATE_DIR="$STATE_HOME/omarchy/clipboard-hub"
IMAGE_DIR="$STATE_DIR/images"
HISTORY="$STATE_DIR/history.json"

if [[ ${1:-} == "--now" ]]; then
  grace=0
else
  grace=${CLIPBOARD_HUB_GC_GRACE_SECONDS:-30}
fi

mkdir -p "$IMAGE_DIR" "$STATE_DIR/open" 2>/dev/null || exit 0
chmod 700 "$STATE_DIR" "$IMAGE_DIR" "$STATE_DIR/open" 2>/dev/null || true

# A reference file gives sub-minute precision and lets us keep anything
# created after this maintenance run started.
ref=$(mktemp --tmpdir="$STATE_DIR" gc.XXXXXX) || exit 0
chmod 600 "$ref" 2>/dev/null || true
touch -d "-$grace seconds" "$ref" 2>/dev/null || touch "$ref"

refs=""
if [[ -r $HISTORY ]]; then
  chmod 600 "$HISTORY" 2>/dev/null || true
  refs=$(jq -r '.. | objects | .path? // empty' "$HISTORY" 2>/dev/null | sort -u)
fi

while IFS= read -r -d '' file; do
  if ! printf '%s\n' "$refs" | grep -Fqx -- "$file"; then
    rm -f -- "$file"
  fi
done < <(find "$IMAGE_DIR" -maxdepth 1 -type f ! -newer "$ref" -print0 2>/dev/null)

rm -f -- "$ref"

# Fix permissions on files created by earlier versions too.
chmod -R go-rwx "$STATE_DIR" 2>/dev/null || true
