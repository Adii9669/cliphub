#!/bin/bash

# Insert an emoji into the focused application using the standard Ctrl+V paste.
# Unlike omarchy-menu-emoji-insert this keeps ownership of the clipboard and
# uses the shortcut browsers understand.

set -euo pipefail

emoji="${1:-}"
[[ -n $emoji ]] || exit 0

# Forks into the background and keeps serving the selection until replaced.
# No --sensitive and no kill, so slow clients (browsers) can still read it.
printf '%s' "$emoji" | wl-copy --type text/plain

# Let the compositor and the target app register the new clipboard owner.
sleep 0.2

if command -v wtype >/dev/null 2>&1; then
  wtype -M ctrl -k v -m ctrl 2>/dev/null || true
fi
