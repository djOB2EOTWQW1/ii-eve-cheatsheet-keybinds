#!/usr/bin/env python3
"""Edit ~/.config/hypr/hyprland/keybinds.lua and custom/keybinds.lua from the UI.

Subcommands read JSON spec from stdin and write JSON result to stdout.
On any error, exit code is 1 and stdout is {"ok": false, "error": "..."}.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
DEFAULT_FILE = HOME / ".config/hypr/hyprland/keybinds.lua"
CUSTOM_FILE = HOME / ".config/hypr/custom/keybinds.lua"
BACKUP_DIR = HOME / ".local/state/quickshell/keybinds-backup"
BACKUP_RETAIN_PER_FILE = 20

CUSTOM_HEADER = (
    "-- This file will not be overwritten across dots-hyprland updates.\n"
    "-- Add or override keybinds here. The cheatsheet edit UI writes here.\n"
)


class KeybindError(Exception):
    """Base error for keybind_edit; carries a user-facing message."""


class ValidationError(KeybindError):
    """Bad spec, missing fields, dangerous/empty command, unknown source."""


class FileOpError(KeybindError):
    """Reading/writing/backing up a target file failed."""


class LuaSyntaxError(KeybindError):
    """`luac -p` rejected the rewritten file."""


def fail(msg):
    print(json.dumps({"ok": False, "error": msg}))
    sys.exit(1)


def ok(**fields):
    print(json.dumps({"ok": True, **fields}))
    sys.exit(0)


def source_path(source):
    if source == "default":
        return DEFAULT_FILE
    if source == "custom":
        return CUSTOM_FILE
    raise ValidationError(f"unknown source: {source!r}")


def combo_re(combo):
    # Matches: hl.bind("<combo>", ...
    # The combo is taken literally; escape regex specials in case (e.g. dots).
    return re.compile(r'^(\s*hl\.bind\("' + re.escape(combo) + r'"\s*,)')


def find_lines(path, combo):
    if not path.exists():
        return []
    rx = combo_re(combo)
    out = []
    try:
        text = path.read_text()
    except OSError as e:
        raise FileOpError(f"cannot read {path}: {e}") from e
    for i, line in enumerate(text.splitlines(), start=1):
        if rx.search(line):
            out.append(i)
    return out


DESC_RE = re.compile(r'(description\s*=\s*)"((?:[^"\\]|\\.)*)"')


def rewrite_description(line, full_desc):
    # full_desc is the already-composed "Category: text" string.
    escaped = full_desc.replace('\\', '\\\\').replace('"', '\\"')

    def sub(m):
        return f'{m.group(1)}"{escaped}"'

    return DESC_RE.sub(sub, line, count=1)


# Command-validation patterns. These match the *whole* command string (anchored
# with re.search) and are rejected outright. The intent is to catch typos and
# obvious foot-guns from the edit UI, NOT to be a sandbox — anyone who can edit
# the Lua file directly bypasses this.
_DANGEROUS_PATTERNS = [
    # Empty / whitespace-only is handled separately for a clearer message.
    (re.compile(r':\s*\(\s*\)\s*\{\s*:\s*\|\s*:'), "fork bomb pattern"),
    (re.compile(r'\brm\s+(-[a-zA-Z]*[rR][a-zA-Z]*\s+)?(-[a-zA-Z]*[fF][a-zA-Z]*\s+)?(["\']?)/(\3|\s|$)'), "rm targeting filesystem root"),
    (re.compile(r'\brm\s+.*(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|-rf|-fr|--recursive\s+--force|--force\s+--recursive)\s+(["\']?)(~|\$HOME|\$\{HOME\})'), "rm -rf targeting $HOME"),
    (re.compile(r'\bmkfs(\.[a-zA-Z0-9]+)?\b'), "mkfs invocation"),
    (re.compile(r'\bdd\b[^;&|]*\bof\s*=\s*/dev/'), "dd writing to a device node"),
    (re.compile(r'>\s*/dev/sd[a-z]'), "redirect overwriting a disk device"),
    (re.compile(r'\bchmod\s+(-[a-zA-Z]*R[a-zA-Z]*\s+)?(0?777)\s+(["\']?)/(\3|\s|$)'), "chmod 777 on filesystem root"),
]

_SUBSTITUTION_PATTERNS = [
    (re.compile(r'\$\('), "command substitution `$(...)`"),
    (re.compile(r'`[^`]*`'), "backtick command substitution"),
]


def validate_command(command):
    if command is None or not command.strip():
        raise ValidationError("'command' is empty")
    for rx, label in _SUBSTITUTION_PATTERNS:
        if rx.search(command):
            raise ValidationError(
                f"command contains {label}; not allowed from the edit UI. "
                f"Edit ~/.config/hypr/custom/keybinds.lua directly if you really need this."
            )
    for rx, label in _DANGEROUS_PATTERNS:
        if rx.search(command):
            raise ValidationError(
                f"command looks dangerous ({label}); refusing. "
                f"Edit ~/.config/hypr/custom/keybinds.lua directly if this is intentional."
            )


def _luac_path():
    for name in ("luac", "luac5.4", "luac5.3"):
        p = shutil.which(name)
        if p:
            return p
    return None


def validate_lua(content):
    """Run `luac -p` on `content`. Silently skip if luac is not installed.

    Note: the project files use stubs like `hl.bind` / `hl.dsp.exec_cmd`. luac
    only parses, it does NOT resolve names, so unresolved globals are fine.
    """
    luac = _luac_path()
    if luac is None:
        return
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".lua", prefix="keybinds-check.", delete=False
    ) as tmp:
        tmp.write(content)
        tmp_path = tmp.name
    try:
        proc = subprocess.run(
            [luac, "-p", tmp_path],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        # Don't block writes on a luac infrastructure failure.
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        sys.stderr.write(f"keybind_edit: luac check skipped: {e}\n")
        return
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    if proc.returncode != 0:
        msg = (proc.stderr or proc.stdout or "").strip().replace(tmp_path, "<content>")
        raise LuaSyntaxError(f"luac -p rejected the rewritten file: {msg}")


def sweep_backups():
    try:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        raise FileOpError(f"cannot create backup dir {BACKUP_DIR}: {e}") from e
    by_stem = {}
    for p in BACKUP_DIR.glob("*.bak"):
        stem = p.name.split(".", 1)[0]
        by_stem.setdefault(stem, []).append(p)
    for stem, paths in by_stem.items():
        paths.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        for old in paths[BACKUP_RETAIN_PER_FILE:]:
            try:
                old.unlink()
            except OSError:
                pass


def backup(path):
    sweep_backups()
    try:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        # Microsecond precision so two backups of the same file within one second don't collide
        # (same filename → the earlier rollback point would be overwritten).
        ts = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        prefix = path.parent.name
        bak = BACKUP_DIR / f"{prefix}-{path.name}.{ts}.bak"
        bak.write_bytes(path.read_bytes())
    except OSError as e:
        raise FileOpError(f"backup of {path} failed: {e}") from e


def atomic_write(path, content):
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".", suffix=".tmp")
    except OSError as e:
        raise FileOpError(f"cannot prepare temp file near {path}: {e}") from e
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.replace(tmp, str(path))
    except OSError as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise FileOpError(f"atomic write to {path} failed: {e}") from e


def write_validated(path, content):
    """Validate Lua, then atomically replace `path`."""
    validate_lua(content)
    atomic_write(path, content)


def require_keys(spec, *keys):
    for k in keys:
        if k not in spec:
            raise ValidationError(f"'{k}' required")


def cmd_find(spec):
    require_keys(spec, "combo")
    combo = spec["combo"]
    custom = find_lines(CUSTOM_FILE, combo)
    default = find_lines(DEFAULT_FILE, combo)
    if custom:
        ok(source="custom", occurrences=len(custom))
    if default:
        ok(source="default", occurrences=len(default))
    ok(source="generated", occurrences=0)


def cmd_edit(spec):
    require_keys(spec, "source", "oldCombo", "newCombo")
    path = source_path(spec["source"])
    if not path.exists():
        raise FileOpError(f"source file does not exist: {path}")
    old_combo = spec["oldCombo"]
    new_combo = spec["newCombo"]
    desc = spec.get("description")
    cat = spec.get("category")

    rx_old = combo_re(old_combo)
    quote_old = f'hl.bind("{old_combo}"'
    quote_new = f'hl.bind("{new_combo}"'

    try:
        lines = path.read_text().splitlines(keepends=True)
    except OSError as e:
        raise FileOpError(f"cannot read {path}: {e}") from e
    changed = []
    for i, line in enumerate(lines):
        if rx_old.search(line):
            new_line = line.replace(quote_old, quote_new, 1)
            if desc is not None and cat is not None and DESC_RE.search(new_line):
                new_line = rewrite_description(new_line, f"{cat}: {desc}")
            lines[i] = new_line
            changed.append(i + 1)

    if not changed:
        raise ValidationError(f"no line matched combo {old_combo!r} in {path}")

    new_content = "".join(lines)
    backup(path)
    write_validated(path, new_content)
    ok(changedLines=changed)


def cmd_delete(spec):
    require_keys(spec, "source", "combo")
    path = source_path(spec["source"])
    if not path.exists():
        raise FileOpError(f"source file does not exist: {path}")
    combo = spec["combo"]
    rx = combo_re(combo)

    try:
        raw = path.read_text().splitlines(keepends=True)
    except OSError as e:
        raise FileOpError(f"cannot read {path}: {e}") from e
    kept = []
    removed = []
    for i, line in enumerate(raw, start=1):
        if rx.search(line):
            removed.append(i)
        else:
            kept.append(line)

    if not removed:
        raise ValidationError(f"no line matched combo {combo!r} in {path}")

    backup(path)
    write_validated(path, "".join(kept))
    ok(removedLines=removed)


def lua_string_literal(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def ensure_custom_exists():
    if CUSTOM_FILE.exists():
        return
    try:
        CUSTOM_FILE.parent.mkdir(parents=True, exist_ok=True)
        CUSTOM_FILE.write_text(CUSTOM_HEADER)
    except OSError as e:
        raise FileOpError(f"cannot create {CUSTOM_FILE}: {e}") from e


def cmd_add(spec):
    require_keys(spec, "combo", "command", "description", "category")
    combo = spec["combo"]
    command = spec["command"]
    if not isinstance(command, str):
        raise ValidationError("'command' must be a string")
    validate_command(command)
    desc = f"{spec['category']}: {spec['description']}"

    ensure_custom_exists()
    # Refuse if combo already present in custom (defaults can be overridden, but custom dups not).
    if find_lines(CUSTOM_FILE, combo):
        raise ValidationError(f"combo {combo!r} already exists in custom/keybinds.lua")

    try:
        text = CUSTOM_FILE.read_text()
    except OSError as e:
        raise FileOpError(f"cannot read {CUSTOM_FILE}: {e}") from e
    if text and not text.endswith("\n"):
        text += "\n"
    line = (
        f"hl.bind({lua_string_literal(combo)}, "
        f"hl.dsp.exec_cmd({lua_string_literal(command)}), "
        f"{{ description = {lua_string_literal(desc)} }})\n"
    )
    new_text = text + line

    # Always back up the pre-add content (even a freshly created header-only file) so a failed
    # reload can be rolled back — otherwise the very first add would leave nothing to restore.
    backup(CUSTOM_FILE)
    write_validated(CUSTOM_FILE, new_text)

    appended_at = len(new_text.splitlines())
    ok(appendedAt=appended_at)


# Matches the final options block: `, { ... }` immediately before the closing `)`.
# Captures the inner content so we can append a description key.
OPTIONS_BLOCK_RE = re.compile(r',\s*\{([^{}]*)\}\s*\)\s*$')


def inject_description(line, full_desc):
    # If the line already has a description anywhere, just replace it.
    if DESC_RE.search(line):
        return rewrite_description(line, full_desc)

    stripped = line.rstrip("\n")
    suffix = "\n" if line.endswith("\n") else ""
    escaped = full_desc.replace('\\', '\\\\').replace('"', '\\"')

    # Case 1: line has an existing { ... } options block at the end → inject inside it.
    m = OPTIONS_BLOCK_RE.search(stripped)
    if m:
        inner = m.group(1).strip()
        if inner:
            new_inner = f'{inner}, description = "{escaped}"'
        else:
            new_inner = f'description = "{escaped}"'
        new_block = ', { ' + new_inner + ' })'
        return stripped[:m.start()] + new_block + suffix

    # Case 2: line ends with `)` but no options block → add a fresh block.
    if not stripped.endswith(")"):
        return None
    # If the line has braces we couldn't parse as a simple options block (e.g. a nested table),
    # refuse rather than appending a second `{ ... }` and silently producing a broken bind.
    if "{" in stripped or "}" in stripped:
        return None
    insertion = f', {{ description = "{escaped}" }}'
    return stripped[:-1] + insertion + ")" + suffix


def cmd_set_description(spec):
    require_keys(spec, "source", "combo", "description", "category")
    path = source_path(spec["source"])
    if not path.exists():
        raise FileOpError(f"source file does not exist: {path}")
    combo = spec["combo"]
    full_desc = f"{spec['category']}: {spec['description']}"

    rx = combo_re(combo)
    try:
        lines = path.read_text().splitlines(keepends=True)
    except OSError as e:
        raise FileOpError(f"cannot read {path}: {e}") from e
    changed = 0
    for i, line in enumerate(lines):
        if rx.search(line):
            new_line = inject_description(line, full_desc)
            if new_line is None:
                raise ValidationError(f"cannot edit multi-line hl.bind on line {i + 1}")
            if new_line != line:
                lines[i] = new_line
                changed += 1

    if changed == 0:
        raise ValidationError(f"no editable line matched combo {combo!r} in {path}")

    backup(path)
    write_validated(path, "".join(lines))
    ok(changedLines=changed)


def cmd_rollback(spec):
    require_keys(spec, "filename")
    target = HOME / spec["filename"]
    prefix = target.parent.name
    candidates = sorted(BACKUP_DIR.glob(f"{prefix}-{target.name}.*.bak"),
                        key=lambda p: p.stat().st_mtime, reverse=True)
    if not candidates:
        raise FileOpError("no backup available")
    try:
        restored = candidates[0].read_text()
    except OSError as e:
        raise FileOpError(f"cannot read backup {candidates[0]}: {e}") from e
    # Rollback content comes from our own previous backup; if it doesn't parse,
    # something is seriously wrong — surface it rather than silently restoring.
    validate_lua(restored)
    atomic_write(target, restored)
    ok(restoredFrom=str(candidates[0]))


SUBCOMMANDS = {
    "find": cmd_find,
    "edit": cmd_edit,
    "delete": cmd_delete,
    "add": cmd_add,
    "set-description": cmd_set_description,
    "rollback": cmd_rollback,
}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in SUBCOMMANDS:
        fail(f"usage: keybind_edit.py <{'|'.join(SUBCOMMANDS)}>  (JSON on stdin)")
    try:
        raw = sys.stdin.read()
    except OSError as e:
        fail(f"cannot read stdin: {e}")
    try:
        spec = json.loads(raw or "{}")
    except json.JSONDecodeError as e:
        fail(f"bad JSON on stdin: {e}")
    if not isinstance(spec, dict):
        fail("stdin JSON must be an object")
    try:
        SUBCOMMANDS[sys.argv[1]](spec)
    except ValidationError as e:
        fail(str(e))
    except LuaSyntaxError as e:
        fail(str(e))
    except FileOpError as e:
        fail(str(e))
    except KeybindError as e:
        fail(str(e))
    except OSError as e:
        fail(f"OS error: {e}")
    except Exception as e:
        fail(f"{type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
