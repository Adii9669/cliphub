#!/bin/bash

# Copy one exact text entry from Clipboard Hub and optionally trigger paste.
#
# The selected text is passed over stdin and terminated by a NUL byte, so the
# action is bound to the item the user clicked rather than to a mutable index
# in history.json. No clipboard content is re-read from disk here.
#
# Usage: paste-text.sh [--shift-insert] [--copy-only] < text-with-NUL-terminator

set -euo pipefail

use_shift_insert=false
copy_only=false

while (( $# > 0 )); do
  case "$1" in
    --shift-insert)
      use_shift_insert=true
      shift
      ;;
    --copy-only)
      copy_only=true
      shift
      ;;
    *)
      echo "Usage: paste-text.sh [--shift-insert] [--copy-only]" >&2
      exit 1
      ;;
  esac
done

# QML writes the selected entry followed by a single NUL delimiter.
IFS= read -r -d '' text || exit 1
[[ -n $text ]] || exit 1

printf '%s' "$text" | wl-copy

if [[ $copy_only == true ]]; then
  exit 0
fi

sleep 0.15
if [[ $use_shift_insert == true ]]; then
  wtype -M shift -k Insert -m shift 2>/dev/null || true
fi
