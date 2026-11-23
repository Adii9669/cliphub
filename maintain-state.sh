#!/bin/bash

# Shared state location, owner-only permissions, and image garbage collection
# for Clipboard Hub. Called at startup and after every history write.
#
# Safety rules:
#  * Never delete images unless history.json is readable and a valid array.
#  * Keep files created inside the grace window. capture.sh writes the image
#    before emitting its JSON entry, so a concurrent capture can be staged on
#    disk while its history entry is still in flight.
#  * Only one GC process may run at a time.

set -o pipefail

STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
STATE_DIR="$STATE_HOME/omarchy/clipboard-hub"
IMAGE_DIR="$STATE_DIR/images"
OPEN_DIR="$STATE_DIR/open"
HISTORY="$STATE_DIR/history.json"
LOCK_DIR="$STATE_DIR/.gc.lock"

# A short grace for post-save runs protects concurrently staged captures while
# still removing older deleted images immediately. Startup uses a wider window.
if [[ ${1:-} == "--now" ]]; then
  grace=${CLIPBOARD_HUB_GC_GRACE_SECONDS:-5}
else
  grace=${CLIPBOARD_HUB_GC_GRACE_SECONDS:-30}
fi

mkdir -p "$IMAGE_DIR" "$OPEN_DIR" 2>/dev/null || exit 0
chmod 700 "$STATE_DIR" "$IMAGE_DIR" "$OPEN_DIR" 2>/dev/null || true

# Several saves can land back to back; serialize the collectors.
mkdir "$LOCK_DIR" 2>/dev/null || exit 0
ref=
cleanup() {
  [[ -n $ref ]] && rm -f -- "$ref"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# A reference file gives sub-minute precision and lets us keep anything
# created after this maintenance run started.
ref=$(mktemp --tmpdir="$STATE_DIR" gc.XXXXXX) || exit 0
chmod 600 "$ref" 2>/dev/null || true
touch -d "-$grace seconds" "$ref" 2>/dev/null || touch "$ref"

# Without a valid history file we have no authoritative list of live images.
# Refuse to guess: keeping orphans is safe, deleting them is not.
if [[ ! -r $HISTORY ]]; then
  exit 0
fi
chmod 600 "$HISTORY" 2>/dev/null || true
if ! jq -e 'type == "array"' "$HISTORY" >/dev/null 2>&1; then
  # Keep one copy for manual recovery before a later capture replaces it.
  if [[ ! -e $HISTORY.invalid ]]; then
    cp -p -- "$HISTORY" "$HISTORY.invalid" 2>/dev/null || true
    chmod 600 "$HISTORY.invalid" 2>/dev/null || true
  fi
  exit 0
fi
if ! refs=$(jq -r '.. | objects | .path? // empty' "$HISTORY" 2>/dev/null | sort -u); then
  exit 0
fi

while IFS= read -r -d '' file; do
  if ! printf '%s\n' "$refs" | grep -Fqx -- "$file"; then
    rm -f -- "$file"
  fi
done < <(find "$IMAGE_DIR" -maxdepth 1 -type f ! -name '.clipboard-tmp.*' ! -newer "$ref" -print0 2>/dev/null)

# Backstop for editor temp files whose owning process was killed before its
# own cleanup trap could run.
find "$OPEN_DIR" -maxdepth 1 -type f -mmin +1440 -delete 2>/dev/null || true

# Fix permissions on files created by earlier versions too.
chmod -R go-rwx "$STATE_DIR" 2>/dev/null || true
