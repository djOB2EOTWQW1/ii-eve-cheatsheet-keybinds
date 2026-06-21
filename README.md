# ii-eve Cheatsheet Keybinds

Editable keybinds tab for the cheatsheet on the [ii-eve](https://github.com/djOB2EOTWQW1/ii-eve) and [ii-vynx](https://github.com/vaguesyntax/ii-vynx) Quickshell shells, via the `cheatsheet` contribution point.

Self-contained: bundles its own `HyprlandKeybinds` / `KeybindsEditor` / `CheatsheetSearch` services and the `keybind_edit.py` helper (stdlib only, no venv), so it works on either shell.

## Features
- Keybinds parsed from `hyprctl binds`, grouped into searchable category cards.
- Fuzzy filter (`/` to focus the search field).
- Edit mode: add, edit, and delete keybinds. Changes are written to your custom keybinds config and applied with `hyprctl reload`; a failed reload rolls back automatically.
- Conflict detection when assigning a combination.
- Reorder categories (persisted in the extension config).

## Install
Extensions settings → paste this directory's path (local) or the repo URL → Install → enable. The **Keybinds** tab appears in the cheatsheet (Super+/ or your configured shortcut).

## Credits

**[asteriau](https://github.com/asteriau/dotfiles)** Borrowed the searchable keybind cheatsheet (live filter + empty state) and the `CheatsheetSearch` session-scoped query singleton.


## License
GPL-3.0 — derived from the GPL-3.0 licensed ii-eve / dots-hyprland code.
