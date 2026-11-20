#!/bin/bash

# Copy a text entry from Clipboard Hub history and optionally trigger paste.
# Usage: paste-text.sh [--shift-insert] [--copy-only] --history-index <index>

set -euo pipefail

use_shift_insert=false
copy_only=false
history_index=""

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
    --history-index)
      history_index="${2:-}"
      shift 2
      ;;
    *)
      echo "Usage: paste-text.sh [--shift-insert] [--copy-only] --history-index <index>" >&2
      exit 1
      ;;
  esac
done

[[ $history_index =~ ^[0-9]+$ ]] || exit 1

history_path="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/clipboard-hub/history.json"
[[ -r $history_path ]] || exit 1

jq -e --argjson index "$history_index" '.[$index].type == "text" and (.[$index].text | type == "string")' "$history_path" >/dev/null || exit 1
jq -j --argjson index "$history_index" '.[$index].text' "$history_path" | wl-copy

if [[ $copy_only == true ]]; then
  exit 0
fi

sleep 0.15
if [[ $use_shift_insert == true ]]; then
  wtype -M shift -k Insert -m shift 2>/dev/null || true
fi
