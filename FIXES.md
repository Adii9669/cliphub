# Clipboard Hub — Review Findings and Fixes

This document records the issues found during a full review of the plugin, what
each one could cause, and the solution chosen for it. It is kept in the repo as
a learning record so the reasoning survives after the code has moved on.
Applies to v1.0.2.

Scope: the review covered `ClipboardHub.qml`, `ClipboardModel.js`,
`EmojiSearch.js`, `BarWidget.qml`, `capture.sh`, `paste-text.sh`,
`insert-emoji.sh`, `maintain-state.sh`, `manifest.json`, `README.md`, and the
Omarchy shell/keybinding integration.

---

## 1. State and data safety

### 1.1 Garbage collection deleted every image when history was unreadable

**Where:** `maintain-state.sh`

**The issue:** The script collected with:

```bash
refs=""
if [[ -r $HISTORY ]]; then
  refs=$(jq -r '.. | objects | .path? // empty' "$HISTORY" | sort -u)
fi
```

There is no `set -e`, and `jq` failure was ignored. If `history.json` was
corrupt, unreadable, or simply absent, `refs` became an empty string and the
`find … -print0` loop treated **every** image in `images/` as unreferenced.
Because `--now` used a zero-second grace, all of them were deleted.

**What it can cause:** One bad write (or the file being temporarily missing)
permanently destroys every screenshot the user ever saved. This is the worst
class of bug in a clipboard manager: silent, irreversible data loss.

**The fix chosen:** Refuse to guess. GC now runs only when `history.json` is
readable **and** a valid JSON array:

```bash
if [[ ! -r $HISTORY ]]; then exit 0; fi
if ! jq -e 'type == "array"' "$HISTORY" >/dev/null 2>&1; then … exit 0; fi
if ! refs=$(jq -r '…' "$HISTORY" 2>/dev/null | sort -u); then exit 0; fi
```

Keeping orphans is safe; deleting them on bad input is not. We chose
fail-closed. An unreadable file is also copied once to `history.json.invalid`
so a human can recover it later.

**Verification:** corrupt and missing-history tests both keep images; a valid
empty array removes only genuinely old orphans.

---

### 1.2 Cleanup raced the asynchronous history write

**Where:** `ClipboardHub.qml` (`saveHistory`), `maintain-state.sh`

**The issue:** `FileView.setText()` is asynchronous. The old code launched
`maintain-state.sh --now` immediately after queuing the write, so the helper
could read the *previous* `history.json` and keep an image whose entry had just
been deleted.

**What it can cause:** Deleted screenshots stayed on disk until some unrelated
later maintenance run — a privacy leak and a broken promise of the delete
action.

**The fix chosen:** Move cleanup to `FileView.onSaved`, which Quickshell emits
only after the atomic rename completes. `onSaveFailed` deliberately does
nothing, because the old file may be the only remaining record of images that
the unsaved in-memory history just dropped.

**Verification:** A standalone Quickshell probe confirmed `onSaved` observes the
new on-disk content; a helper test confirmed GC against the old snapshot keeps
the image while GC after the save removes it.

---

### 1.3 Zero grace still raced an in-flight capture

**Where:** `maintain-state.sh`, `ClipboardHub.qml:onSaved`

**The issue:** `capture.sh` writes the image file **before** it emits the JSON
entry that puts it in history. With two rapid copies, image B can be on disk
while only entry A has been saved. A `--now` GC with `grace=0` sees B as old and
unreferenced and deletes it; B's save then lands with a dangling path.

**What it can cause:** A screenshot that the user just took disappears from the
history UI or shows a broken thumbnail, even though nothing was deleted by the
user.

**The fix chosen:** Give post-save runs a small non-zero grace (5 seconds by
default) instead of zero. Old deleted images are still removed immediately —
they were captured long ago — but a file staged in the last few seconds is
protected. A single `CLIPBOARD_HUB_GC_GRACE_SECONDS` override covers both the
startup run (30 s) and the post-save run (5 s).

Also added an atomic `mkdir`-based lock (`$STATE_DIR/.gc.lock`) so back-to-back
saves cannot run two collectors concurrently.

**Verification:** A file created seconds ago and an in-progress temp file
survive a `--now` run, while a 10-minute-old orphan is removed.

---

### 1.4 GC deleted files that capture.sh was still writing

**Where:** `capture.sh`, `maintain-state.sh`

**The issue:** Staged files were named `clipboard.XXXXXX` **inside** `images/`,
and the GC `find` matched every regular file there. A GC run could unlink a
temp file while `read_copy` still held its descriptor; the following
`wc -c` / `sha256sum` / `mv` by path then failed, and the emitted JSON could
point at `images/.png` with an empty hash.

**What it can cause:** Corrupt history entries and intermittent capture
failures that look random because they depend on timing.

**The fix chosen:** Stage files with a distinct `.clipboard-tmp.XXXXXX` prefix
and exclude that prefix in the GC `find`. The capture script's own `EXIT` trap
already removes temps on normal exit and on rejection.

---

### 1.5 A transient read failure emptied the whole history

**Where:** `ClipboardHub.qml` (`FileView.onLoadFailed`)

**The issue:** `onLoadFailed: root.loadHistory("[]")` replaced in-memory history
with an empty array on *any* read error — including a transient permission or
rotation problem. The next capture then wrote that empty array over the real
file.

**What it can cause:** A momentary filesystem hiccup becomes permanent loss of
the entire clipboard history.

**The fix chosen:** Keep the last good in-memory history on load failure. On a
genuine first run the array is already `[]`, so behaviour is unchanged. Failed
saves already skip GC (see 1.2).

**Rule of thumb:** never persist a state you adopted only because you failed to
read the authoritative one.

---

## 2. Capture correctness and privacy

### 2.1 Timed-out clipboard reads were saved as truncated entries

**Where:** `capture.sh:read_copy`

**The issue:**

```bash
timeout 2s "$@" | head -c "$((cap + 1))" >"$tmp" || true
```

`|| true` swallowed the timeout's exit code. If a clipboard owner stalled, the
partial bytes already written to `$tmp` passed the non-empty and size checks.

**What it can cause:** A half-copied password, token, or message is stored
permanently in history and shown in the UI as if it were complete.

**The fix chosen:** Respect `pipefail` and reject a failing pipeline:

```bash
if ! timeout 2s "$@" 2>/dev/null | head -c "$((cap + 1))" >"$tmp"; then
  return 1
fi
```

Oversized payloads are still rejected by the existing `wc -c <= cap` check.

**Verification:** A producer that writes `PARTIAL`, sleeps 3 s, then writes
`REST` now produces no history entry at all.

---

### 2.2 Sensitive detection had a time-of-check/time-of-use race

**Where:** `capture.sh`

**The issue:** Every capture opened a second `wl-paste --list-types` connection
to look for `x-kde-passwordManagerHint`. In watch mode, the payload arrives on
stdin from a different connection, so the clipboard could change between the
probe and the read.

**What it can cause:** A password copied by a manager that advertises only the
hint (and no `--sensitive` flag) could be recorded if the two connections
observed different selections.

**The fix chosen:** In watch mode, trust `CLIPBOARD_STATE`, which
`wl-paste --watch` sets from the very selection whose data is on stdin. Skip any
state other than `data` (or unset, for older clients). Only snapshot mode,
which has no such environment, still probes `--list-types`.

**Verification:** `CLIPBOARD_STATE=sensitive` and `nil` are skipped; the hint is
still rejected in snapshot mode; normal watch captures still work.

---

### 2.3 The total-image cap double-counted the staged file

**Where:** `capture.sh:emit_image`

**The issue:** `du -sb "$IMAGE_DIR"` already includes the just-created temp
file, but the code added `size` to that total again.

**What it can cause:** Images were rejected roughly 10 MiB earlier than the
documented 100 MiB limit — a confusing, invisible cap.

**The fix chosen:** Compare the directory total directly. The temp becomes the
stored image via `mv`, so the final usage really is what `du` reports.

---

### 2.4 Failed hashing or moving still emitted a history entry

**Where:** `capture.sh:emit_image`

**The issue:** With no error checking, a failed `sha256sum` produced `hash=""`
and a failed `mv` left the destination missing, but the script still printed a
JSON entry pointing at `images/.png`.

**What it can cause:** Broken thumbnails and dangling paths that survive every
later GC pass.

**The fix chosen:** Check both operations and return without emitting anything
if either fails; reject an empty hash explicitly.

---

## 3. Performance and memory

### 3.1 Full clipboard text was copied into the UI model on every keystroke

**Where:** `ClipboardModel.js:buildRow`, `ClipboardHub.qml:rebuildClipboardDisplay`

**The issue:** Rows carried an uncapped `pasteText` (up to 1 MiB) for every one
of up to 200 entries. Every filter keystroke cleared and re-appended the whole
`ListModel`.

**What it can cause:** Roughly 200 MiB copied per keystroke plus a second full
copy in `root.history` — shell freezes and large resident memory on any
realistic history.

**The fix chosen:** Keep only capped previews (8 KiB, already used for the
detail pane) in the model. At activation time, resolve the full entry from
`root.history` by its stable id via the new `ClipboardModel.entryById()`.
Paste content is still the exact original text; only the display representation
is bounded.

**Verification:** A 200 KB entry produces a row with `fullText.length <= 8192`
and no `pasteText`, while `entryById()` returns all 200 KB for pasting.

---

### 3.2 The file watcher reloaded on GC noise

**Where:** `ClipboardHub.qml` (`FileView.watchChanges`)

**The issue:** GC creates a reference file, chmods the state tree, and touches
history permissions. With a raw `onFileChanged: reload()`, one save could
trigger several reloads and UI rebuilds.

**What it can cause:** Needless UI churn and extra work proportional to GC
activity.

**The fix chosen:** Debounce `reload()` through a 150 ms `Timer`. Multiple
signals collapse into one content reload.

---

## 4. Correctness bugs

### 4.1 A shared Process could paste the wrong entry

**Where:** `ClipboardHub.qml:runPasteText`, former `pasteProc`

**The issue:** One `Process` object held a single `pendingText` property and was
restarted with `running = false; running = true`. Restarting terminates the
old QProcess but does not immediately destroy it. Two fast activations could
overwrite `pendingText` before the restarted process's `onStarted` wrote it —
or SIGTERM a paste that had already copied text but had not yet sent `Ctrl+V`.

**What it can cause:** The exact wrong-item paste this design was meant to
eliminate, just moved from a mutable index to a mutable payload.

**The fix chosen:** Create a fresh `Process` from a `Component` for each paste,
capture the text as its own `payload` property, and `destroy()` it on exit.
Nothing shared remains between activations.

---

### 4.2 A single `file://` line misclassified text as a file

**Where:** `ClipboardModel.js:filePaths`

**The issue:** `filePaths()` accepted an entry as a file if *any* line began with
`file://`. A log line or URL like `see file:///home/me/notes.txt` made
`buildRow()` set `entryType: "file"`, replaced the detail text with just the
path, and made "open in editor" write the path instead of the copied text.

**What it can cause:** Content is displayed and edited incorrectly; pasting
still worked, which made the bug especially confusing.

**The fix chosen:** Classify as a file only when every non-empty line is a
valid `file://` URI. Mixed content stays text.

---

### 4.3 Pinning left the cursor on a different entry

**Where:** `ClipboardHub.qml:togglePinAtDisplayIndex`

**The issue:** Pinned and recent rows are separate sections. Toggling a pin
reordered the model but left `selectedIndex` untouched.

**What it can cause:** The user unpins or pins an item and the highlight jumps
to a completely different entry; the next `Del` or `Enter` acts on the wrong
one.

**The fix chosen:** Remember the `entryId`, rebuild, find that id in the new
model, and move the cursor to its new index (plus scroll it into view).

---

### 4.4 "Open in editor" leaked temp files forever

**Where:** `ClipboardHub.qml:openClipboardRow`

**The issue:** The command created a temp file under `open/` and then `exec`ed
the editor, so nothing remained to delete the file when the editor closed.

**What it can cause:** Unbounded disk use and a growing archive of clipboard
contents on disk — a direct contradiction of the privacy documentation.

**The fix chosen:** Drop `exec`, install a shell `trap 'rm -f -- "$f"' EXIT`, and
let the editor run as a child. Added a daily TTL sweep of `open/` in
`maintain-state.sh` as a backstop for a killed process.

---

### 4.5 Pinned history was unbounded

**Where:** `ClipboardModel.js:capUnpinned`, `togglePinnedById`

**The issue:** Only unpinned entries had a limit (200). Pinned entries were
never trimmed, and each may hold up to 1 MiB.

**What it can cause:** Unbounded `history.json` growth and the same UI/memory
problems as 3.1, triggered by ordinary pinning.

**The fix chosen:** A 100-entry pinned cap, enforced both in `capUnpinned()` and
in `togglePinnedById()` — because pinning is a write path too. Newest entries
win; total history is bounded at 300.

---

### 4.6 IDs and image paths from history.json were trusted verbatim

**Where:** `ClipboardModel.js:normalizeEntry`, `ClipboardHub.qml`

**The issue:** Stored `id` values were accepted as-is, so a duplicated or
tampered file could give two entries the same id and make one delete/pin affect
several. Image `path` values were passed straight to `execDetached`.

**What it can cause:** Wrong-entry mutations and, with a tampered file, an
external command being asked to act on an arbitrary local path. (argv use
prevented shell injection, but not arbitrary file access.)

**The fix chosen:** Always recompute ids from content with `makeId()`. Before
using an image path, require it to start with `root.imageDir + "/"` via
`safeImagePath()`.

---

### 4.7 Helper paths hard-coded `$HOME/.config`

**Where:** `ClipboardHub.qml:pluginDir`, `omarchyPath`

**The issue:** Scripts were located with `Quickshell.env("HOME") + "/.config/…"`
even though state paths respected `XDG_STATE_HOME`. A shell loaded from
`XDG_CONFIG_HOME` would fail to find every helper.

**The fix chosen:** Resolve the plugin directory from `Qt.resolvedUrl(".")`,
strip the `file://` prefix and trailing slash, and URL-decode it. Added a
fallback for an unset `OMARCHY_PATH`.

---

### 4.8 Mouse click copied while the docs said paste

**Where:** `ClipboardHub.qml` row `MouseArea`, `README.md`

**The issue:** Clicking a row called `copyClipboardIndex()` (copy-only), while
keyboard `Enter` pasted and the README promised paste.

**What it can cause:** Inconsistent UX and misleading documentation.

**The fix chosen:** Make click call `activateClipboardIndex()` so mouse and
keyboard behave the same. Copy remains available through the row icon and
`Shift+Enter`.

---

### 4.9 `close()` stole focus after the panel was hidden

**Where:** `ClipboardHub.qml:close`, `cancelClearUnpinned`

**The issue:** `close()` always called `cancelClearUnpinned()`, which scheduled
`filterInput.forceActiveFocus()` with `Qt.callLater` even though the overlay was
closing.

**What it can cause:** A hidden panel tries to grab keyboard focus, potentially
stealing it from the application the user returned to.

**The fix chosen:** Only cancel the dialog when it is actually open, and guard
the deferred focus call with `if (root.opened)`.

---

## 5. Cleanup and documentation

- Removed dead exports/parameters (`referencedImagePaths()`, the unused `tr`
  callback in `buildRow`, unused delegate `required property` roles, the
  redundant emoji `index` role, and the unused `mouseButton` parameter in
  `BarWidget.qml`).
- Added `textFormat: Text.PlainText` to the two remaining hardcoded glyph
  labels for consistency.
- README now states the real terminal paste behaviour, lists all required
  commands (`setpriv`, `pkill`, `omarchy-language`), documents the 200 + 100
  entry caps and the new cleanup guarantees, and links to this file.

---

## Verification performed

- `bash -n` on all four shell scripts.
- `node --check ClipboardModel.js`.
- `omarchy plugin validate .` on the working tree and on a clean clone.
- Corrupt/missing/valid `history.json` GC tests.
- Fresh-file, staged-temp, and old-orphan GC tests; lock-release check.
- Editor-temp TTL sweep test.
- Timed-out read, sensitive-state, nil-state, and password-hint capture tests.
- JS unit checks for URI classification, id recomputation, capped display rows,
  id lookup, pinned cap, and duplicate collapse.
- Standalone Quickshell probes for `onSaved` ordering, `Qt.resolvedUrl(".")`,
  and fresh-`Process` stdin delivery.
- Shell journal check after live plugin reload: no QML errors.

## General lessons

1. **Async writes need completion signals.** Anything depending on new file
   content belongs in `onSaved`, not next to `setText()`.
2. **Cleanup must be fail-closed.** If you cannot prove what is live, delete
   nothing.
3. **Grace windows protect in-flight producers.** A producer writes data before
   it publishes the reference to it; zero grace always has a hole.
4. **Never persist fallback state.** A failed read is not an empty history.
5. **Bound every user-controllable collection**, including pins and temp files.
6. **Data from disk is data, not authority.** Recompute ids; validate paths.
7. **One object per concurrent action.** Shared mutable slots reintroduce the
   races that careful payload plumbing was meant to remove.
