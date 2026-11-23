#!/bin/bash

# Captures the current clipboard as a JSON entry on stdout. In watch mode,
# wl-paste invokes this with the payload on stdin and the mime as $1. Without
# arguments, it snapshots the current selection itself.

set -o pipefail

STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
STATE_DIR="$STATE_HOME/omarchy/clipboard-hub"
IMAGE_DIR="$STATE_DIR/images"
mkdir -p "$IMAGE_DIR"

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
maintain_script="$plugin_dir/maintain-state.sh"
bash "$maintain_script" >/dev/null 2>&1 || true

# Bound both individual entries and total image storage.
MAX_TEXT_BYTES=$((1024 * 1024))
MAX_IMAGE_BYTES=$((10 * 1024 * 1024))
MAX_IMAGE_TOTAL=$((100 * 1024 * 1024))

# In watch mode wl-paste sets CLIPBOARD_STATE for the payload itself, so a
# second --list-types connection would race a clipboard change. Only probe
# types when we have to snapshot the selection ourselves.
types=""
if [[ ${CLIPBOARD_STATE:-} == "sensitive" ]]; then
  exit 0
elif [[ -z ${1:-} ]]; then
  types=$(timeout 2s wl-paste --list-types 2>/dev/null || true)
  if grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
    exit 0
  fi
elif [[ ${CLIPBOARD_STATE:-data} != "data" ]]; then
  # nil/clear/unknown states carry no payload worth persisting.
  exit 0
fi

tmp=
trap 'rm -f -- "$tmp"' EXIT

# Read at most cap+1 bytes; reject oversized payloads before decoding/storing.
read_copy() {
  local cap=$1
  shift
  # pipefail makes a timeout (124) reject the entry. Without this, a slow or
  # hung clipboard owner silently becomes a truncated permanent history item.
  if ! timeout 2s "$@" 2>/dev/null | head -c "$((cap + 1))" >"$tmp"; then
    return 1
  fi
  [[ -s $tmp ]] || return 1
  (( $(wc -c < "$tmp") <= cap ))
}

image_dir_used() {
  du -sb "$IMAGE_DIR" 2>/dev/null | awk '{print $1}'
}

emit_image() {
  local mime="$1"
  local ext hash file used
  shift

  ext=${mime#image/}
  [[ $ext == jpeg ]] && ext=jpg

  # Distinct prefix: the GC must never unlink a file still being staged.
  tmp=$(mktemp --tmpdir="$IMAGE_DIR" .clipboard-tmp.XXXXXX) || return 0
  read_copy "$MAX_IMAGE_BYTES" "$@" || return 0

  # du already counts the staged temp, which becomes the stored image via mv,
  # so compare the directory total directly instead of adding size again.
  used=$(image_dir_used)
  used=${used:-0}
  if (( used > MAX_IMAGE_TOTAL )); then
    bash "$maintain_script" >/dev/null 2>&1 || true
    used=$(image_dir_used)
    used=${used:-0}
    if (( used > MAX_IMAGE_TOTAL )); then
      rm -f -- "$tmp"
      tmp=
      return 0
    fi
  fi

  if ! hash=$(sha256sum "$tmp" | awk '{print $1}') || [[ -z $hash ]]; then
    return 0
  fi
  file="$IMAGE_DIR/$hash.$ext"
  if [[ -e $file ]]; then
    rm -f -- "$tmp"
    tmp=
  else
    mv -- "$tmp" "$file" || return 0
    tmp=
  fi

  jq -cn --arg mime "$mime" --arg path "$file" --arg captured_at "$(LC_TIME="$(omarchy-language locale 2>/dev/null)" date +'%A %H:%M')" \
    '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}'
}

emit_text() {
  tmp=$(mktemp --tmpdir="$STATE_DIR" .clipboard-tmp.XXXXXX) || return 0
  read_copy "$MAX_TEXT_BYTES" "$@" || return 0

  perl -MEncode=decode,FB_CROAK,LEAVE_SRC -MJSON::PP=encode_json -0777 -e '
    my $raw = <STDIN>;
    exit unless length $raw;

    my $encoding;
    my $heuristic_encoding = 0;
    if ($raw =~ /^(?:\xFF\xFE|\xFE\xFF)/) {
      $encoding = "UTF-16";
    } elsif (length($raw) % 2 == 0 && index($raw, "\0") >= 0) {
      my $units = length($raw) / 2;
      my $nuls = $raw =~ tr/\0/\0/;

      if ($nuls * 4 >= $units * 3) {
        my $even_bytes = $raw;
        $even_bytes =~ s/(.)./$1/sg;
        my $even_nuls = $even_bytes =~ tr/\0/\0/;
        undef $even_bytes;

        my $odd_bytes = $raw;
        $odd_bytes =~ s/.(.)/$1/sg;
        my $odd_nuls = $odd_bytes =~ tr/\0/\0/;
        undef $odd_bytes;

        if ($odd_nuls * 4 >= $units * 3 && $even_nuls * 4 < $units) {
          $encoding = "UTF-16LE";
          $heuristic_encoding = 1;
        } elsif ($even_nuls * 4 >= $units * 3 && $odd_nuls * 4 < $units) {
          $encoding = "UTF-16BE";
          $heuristic_encoding = 1;
        }
      }
    }

    my $text = $encoding ? eval { decode($encoding, $raw, FB_CROAK | LEAVE_SRC) } : undef;
    if ($heuristic_encoding && defined($text) && $text =~ /[\x00-\x08\x0E-\x1A\x1C-\x1F]/) {
      $text = undef;
    }
    $text = decode("UTF-8", $raw) unless defined $text;
    print "{\"type\":\"text\",\"text\":", encode_json($text), "}\n";
  ' <"$tmp"
}

case "${1:-}" in
text) emit_text cat; exit 0 ;;
image/*) emit_image "$1" cat; exit 0 ;;
esac

for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
  if grep -qx "$mime" <<<"$types"; then
    emit_image "$mime" wl-paste --type "$mime"
    exit 0
  fi
done

if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
  emit_text wl-paste --type text --no-newline
fi
