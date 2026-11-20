<<<<<<< HEAD
# cliphub
=======
# Clipboard Hub

A unified Omarchy Quattro shell plugin: clipboard history and emoji search in a single overlay, with a single bar button.

Clipboard history supports pinned items, per-item delete, clear-all that preserves pins, and small image previews. The emoji tab searches and inserts emoji. Both views use Nerd Font icons and a live search box.

## Features

- One bar button opens the Clipboard tab; switch to Emoji with the icon tab inside the menu
- Clipboard: pinned section at the top, pin/unpin, copy, delete, and `Clear all` (unpinned only)
- Image clipboard entries are stored and previewed as thumbnails
- Click any clipboard row to copy that text; `Enter` pastes, `Shift+Enter` copies only
- Emoji search with keyboard navigation and insertion
- Compact, theme-aware overlay; no changes to `/usr/share/omarchy/`

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
- **Mouse:** click a clipboard row to copy its text; use the row icons to copy, pin/unpin, or delete
- **Keyboard:** `Tab` switches tabs, `Esc` clears the search or closes, `Del` deletes the selected entry, `Shift+Del` clears unpinned entries, `Ctrl+P` pins/unpins, arrows navigate

## State

The plugin stores its own state outside the repository:

- `~/.local/state/omarchy/clipboard-hub/history.json`
- `~/.local/state/omarchy/clipboard-hub/images/`

The state directory name is intentionally stable and is not derived from the plugin id, so renaming or reinstalling the plugin preserves your history.

## Remove

```bash
omarchy plugin remove adii9669.clipboard-hub --yes
```

This removes the plugin checkout and unloads it from the shell. Your clipboard history under `~/.local/state/omarchy/clipboard-hub/` is left intact; delete it manually if you want a clean slate. Remove the `{ "id": "adii9669.clipboard-hub" }` entry from `bar.layout.right` in `~/.config/omarchy/shell.json` if you placed it there yourself.

## License

MIT — see [LICENSE](LICENSE).
>>>>>>> 14f5c87 (Add Clipboard Hub plugin for Omarchy Quattro)
