# Clipboard Hub

A unified Omarchy Quattro shell plugin: clipboard history and emoji search in a single overlay, with a single bar button.

Clipboard history supports pinned items, per-item delete, clear-all that preserves pins, and small image previews. The emoji tab searches and inserts emoji. Both views use Nerd Font icons and a live search box.

## Features

- One bar button opens the Clipboard tab; switch to Emoji with the icon tab inside the menu
- Clipboard: pinned section at the top, pin/unpin, copy, delete, and `Clear all` (unpinned only)
- Image clipboard entries are stored and previewed as thumbnails
- Click any clipboard row to paste that text; `Shift+Enter` copies only
- Emoji search with keyboard navigation and insertion via standard `Ctrl+V` (works in browsers and terminals)
- Compact, theme-aware overlay; no changes to `/usr/share/omarchy/`
- Responsive: the card shrinks to fit the screen, with a narrow-screen layout below ~560px

## Responsive behavior

- The card is capped at 680×460 and otherwise sized to the screen minus the shell's outer gaps, so it never overflows the display.
- Wide screens keep the 68% list / 32% detail split.
- Below ~560px, the list uses the full width, the detail pane becomes a toggleable full-width view (eye/back icon in the header), "Clear all" becomes a trash icon, and thumbnails/action buttons shrink slightly.
- Emoji cells scale between 44px and 68px based on available width; the keyboard column count is derived from the actual grid, so arrow navigation stays correct at any size.
- Short screens simply show fewer rows; both lists scroll.

## Requirements

- Omarchy Quattro shell (Quickshell) with plugin support
- `wl-clipboard` (`wl-paste`, `wl-copy`), `jq`, `perl` (with `Encode` and `JSON::PP`), `coreutils`, `bash`
- Optional: `wtype` for synthetic paste, `omarchy-launch-editor` for the "open in editor" action
- A Nerd Font (JetBrains Mono Nerd Font is used for the icons)

## Install

From a checkout of this repository:

```bash
omarchy plugin add https://github.com/Adii9669/cliphub.git --enable --yes
```

To add the bar button without `--enable`, place the widget manually in `~/.config/omarchy/shell.json` under `bar.layout.right`:

```json
{ "id": "adii9669.clipboard-hub" }
```

The plugin can also be summoned directly:

```bash
omarchy-shell shell toggle adii9669.clipboard-hub '{"tab":"clipboard"}'
omarchy-shell shell toggle adii9669.clipboard-hub '{"tab":"emoji"}'
```

## Usage

- **Bar button:** clipboard icon — opens the Clipboard tab
- **Tabs:** clipboard icon and emoji icon in the menu header
- **Mouse:** click a clipboard row to paste its text; use the row icons to copy, pin/unpin, or delete
- **Keyboard:** `Tab` switches tabs, `Esc` clears the search or closes, `Del` deletes the selected entry, `Shift+Del` clears unpinned entries, `Ctrl+P` pins/unpins, arrows navigate

## State and privacy

The plugin stores its own state outside the repository, under `$XDG_STATE_HOME/omarchy/clipboard-hub` when `XDG_STATE_HOME` is set, otherwise `~/.local/state/omarchy/clipboard-hub`:

- `history.json` — text history and image entry metadata
- `images/` — captured screenshots
- `open/` — temporary files for the "open in editor" action

The state directory name is intentionally stable and is not derived from the plugin id, so renaming or reinstalling the plugin preserves your history. All plugin state directories are set to `700` and files to `600`; existing state is tightened on startup and after every write.

Paste and copy actions are bound to the exact selected item, not to a list index, so a new copy arriving mid-click cannot make the plugin paste the wrong entry.

Capture limits are enforced before storage:

- text entries: 1 MiB each
- images: 10 MiB each
- total image storage: 100 MiB

Deleting an entry or clearing unpinned entries removes plugin-owned image files that are no longer referenced by any remaining entry.

## Remove

```bash
omarchy plugin remove adii9669.clipboard-hub --yes
```

This removes the plugin checkout and unloads it from the shell. Your clipboard history is left intact; delete the state directory manually if you want a clean slate:

```bash
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/clipboard-hub"
```

Remove the `{ "id": "adii9669.clipboard-hub" }` entry from `bar.layout.right` in `~/.config/omarchy/shell.json` if you placed it there yourself.

## License

MIT — see [LICENSE](LICENSE).
