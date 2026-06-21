pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property string _configDir: FileUtils.trimFileProtocol(Directories.config).replace(/\/+$/, "")
    // Bundled script, resolved relative to this file (not the host shell's scripts dir).
    readonly property string scriptPath: FileUtils.trimFileProtocol(Qt.resolvedUrl("../scripts/keybinds/keybind_edit.py"))
    readonly property string defaultFile: _configDir + "/hypr/hyprland/keybinds.lua"
    readonly property string customFile: _configDir + "/hypr/custom/keybinds.lua"

    property string _defaultText: ""
    property string _customText: ""

    property int mutationTick: 0

    readonly property var modOrder: ["CTRL", "SUPER", "SHIFT", "ALT"]
    readonly property var modAliases: ({
        "CTRL": "CTRL", "CONTROL": "CTRL",
        "SUPER": "SUPER", "MOD4": "SUPER", "META": "SUPER", "WIN": "SUPER", "LOGO": "SUPER",
        "SHIFT": "SHIFT",
        "ALT": "ALT", "MOD1": "ALT",
    })
    readonly property var keyHyprctlToLua: ({
        "space": "Space",
        "minus": "Minus",
        "equal": "Equal",
        "slash": "Slash",
        "period": "Period",
        "semicolon": "Semicolon",
        "apostrophe": "Apostrophe",
        "bracketleft": "BracketLeft",
        "bracketright": "BracketRight",
        "backslash": "Backslash",
        "return": "Return",
        "backspace": "BackSpace",
        "tab": "Tab",
        "escape": "Escape",
        "delete": "Delete",
        "print": "Print",
    })

    FileView {
        path: root.defaultFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._defaultText = text()
    }

    FileView {
        path: root.customFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._customText = text()
    }

    function _titleCase(s) {
        if (!s.length) return s;
        return s[0].toUpperCase() + s.slice(1).toLowerCase();
    }

    function parseCombo(input) {
        if (!input) return { ok: false, error: "Enter a key combination" };
        const tokens = input.trim().split(/[+\s]+/).filter(t => t.length > 0);
        if (tokens.length === 0) return { ok: false, error: "Enter a key combination" };
        const mods = [];
        let key = null;
        for (const tok of tokens) {
            const upper = tok.toUpperCase();
            if (root.modAliases[upper] !== undefined) {
                const canon = root.modAliases[upper];
                if (!mods.includes(canon)) mods.push(canon);
            } else {
                if (key !== null) {
                    return { ok: false, error: "Only one non-modifier key allowed" };
                }
                if (/^code:\d+$/i.test(tok)) key = tok.toLowerCase();
                else if (/^XF86/i.test(tok)) key = "XF86" + tok.substring(4);
                else if (/^mouse[:_]/i.test(tok)) key = tok.toLowerCase();
                else key = root._titleCase(tok);
            }
        }
        if (key === null) return { ok: false, error: "Need at least one non-modifier key" };
        mods.sort((a, b) => root.modOrder.indexOf(a) - root.modOrder.indexOf(b));
        return { ok: true, mods: mods, key: key };
    }

    function normalizeCombo(input) {
        const r = root.parseCombo(input);
        if (!r.ok) return null;
        return [...r.mods, r.key].join(" + ");
    }

    function _hasLiteral(text, combo) {
        if (!text) return false;
        return text.indexOf('hl.bind("' + combo + '"') !== -1;
    }

    function findSourceFor(combo) {
        if (root._hasLiteral(root._customText, combo)) return "custom";
        if (root._hasLiteral(root._defaultText, combo)) return "default";
        return "generated";
    }

    readonly property var modBitTable: ({
        "CTRL": 1 << 2,
        "SUPER": 1 << 6,
        "SHIFT": 1 << 0,
        "ALT": 1 << 3,
    })

    function _modsToMask(mods) {
        let m = 0;
        for (const mod of mods) m |= (root.modBitTable[mod] || 0);
        return m;
    }

    function _keysEqual(parsedKey, hyprctlKey) {
        if (!parsedKey || !hyprctlKey) return false;
        if (parsedKey === hyprctlKey) return true;
        if (parsedKey.toLowerCase() === hyprctlKey.toLowerCase()) return true;
        const mapped = root.keyHyprctlToLua[hyprctlKey.toLowerCase()];
        if (mapped && mapped === parsedKey) return true;
        return false;
    }

    function detectConflict(newCombo, excludeCombo) {
        const parsed = root.parseCombo(newCombo);
        if (!parsed.ok) return null;
        const targetMask = root._modsToMask(parsed.mods);
        const excludeNorm = excludeCombo ? root.normalizeCombo(excludeCombo) : null;
        const binds = HyprlandKeybinds.keybinds;
        for (let i = 0; i < binds.length; i++) {
            const b = binds[i];
            if (b.modmask !== targetMask) continue;
            if (!root._keysEqual(parsed.key, b.key)) continue;
            const otherCombo = root._bindToCombo(b);
            if (excludeNorm && otherCombo === excludeNorm) continue;
            return { description: b.description || "(no description)", combo: otherCombo };
        }
        return null;
    }

    function _bindToCombo(bind) {
        const mods = [];
        const m = bind.modmask;
        if (m & (1 << 2)) mods.push("CTRL");
        if (m & (1 << 6)) mods.push("SUPER");
        if (m & (1 << 0)) mods.push("SHIFT");
        if (m & (1 << 3)) mods.push("ALT");
        const lk = (bind.key || "").toLowerCase();
        let k = root.keyHyprctlToLua[lk];
        if (!k) k = /^mouse[:_]/.test(lk) ? lk : root._titleCase(bind.key);
        return [...mods, k].join(" + ");
    }

    signal applyFinished(string operation, var result)

    property string _pendingOp: ""
    property string _pendingSubcommand: ""
    property string _pendingJson: ""
    property string _pendingSourceFile: ""

    Process {
        id: editor
        command: ["python3", root.scriptPath, root._pendingSubcommand]
        stdinEnabled: true
        running: false
        stdout: StdioCollector {
            id: editorStdout
            onStreamFinished: {
                let result;
                const raw = editorStdout.text;
                try {
                    result = JSON.parse(raw || "{}");
                } catch (e) {
                    result = { ok: false, error: "bad JSON from script: " + raw };
                }
                if (!result || typeof result.ok !== "boolean") {
                    result = { ok: false, error: "empty or malformed script output: " + (raw || "<empty>") };
                }
                if (result.ok) {
                    root.mutationTick++;
                    root._awaitingReload = true;
                    Quickshell.execDetached(["hyprctl", "reload"]);
                    reloadTimeout.restart();
                }
                root.applyFinished(root._pendingOp, result);
            }
        }
        onRunningChanged: {
            if (editor.running) {
                editor.write(root._pendingJson);
                editor.stdinEnabled = false;
            }
        }
    }

    property bool _awaitingReload: false

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root._awaitingReload && event.name === "configreloaded") {
                root._awaitingReload = false;
                reloadTimeout.stop();
            }
        }
    }

    Timer {
        id: reloadTimeout
        interval: 2500
        onTriggered: {
            if (!root._awaitingReload) return;
            root._awaitingReload = false;
            root._rollback();
        }
    }

    function _rollback() {
        if (!root._pendingSourceFile) return;
        rollbackProc.stdinEnabled = true;
        rollbackProc.running = true;
    }

    Process {
        id: rollbackProc
        command: ["python3", root.scriptPath, "rollback"]
        stdinEnabled: true
        running: false
        stdout: StdioCollector {
            id: rollbackStdout
            onStreamFinished: {
                let rb;
                const raw = rollbackStdout.text;
                try {
                    rb = JSON.parse(raw || "{}");
                } catch (e) {
                    rb = { ok: false, error: "rollback: bad JSON from script: " + raw };
                }
                if (!rb || typeof rb.ok !== "boolean") {
                    rb = { ok: false, error: "rollback: empty or malformed script output: " + (raw || "<empty>") };
                }
                if (rb.ok) {
                    Quickshell.execDetached(["hyprctl", "reload"]);
                    root.applyFinished("rollback", { ok: false, error: "Reload failed, restored backup" });
                } else {
                    root.applyFinished("rollback", { ok: false, error: "Reload failed AND rollback failed: " + (rb.error || "unknown") });
                }
            }
        }
        onRunningChanged: {
            if (rollbackProc.running) {
                rollbackProc.write(JSON.stringify({ filename: root._pendingSourceFile }));
                rollbackProc.stdinEnabled = false;
            }
        }
    }

    function _runScript(op, subcommand, spec) {
        if (editor.running || rollbackProc.running || root._awaitingReload) {
            root.applyFinished(op, { ok: false, error: "Another operation is in progress, please wait" });
            return;
        }
        root._pendingOp = op;
        root._pendingSubcommand = subcommand;
        root._pendingJson = JSON.stringify(spec);
        if (spec.source === "custom" || op === "add") {
            root._pendingSourceFile = ".config/hypr/custom/keybinds.lua";
        } else {
            root._pendingSourceFile = ".config/hypr/hyprland/keybinds.lua";
        }
        editor.stdinEnabled = true;
        editor.running = true;
    }

    function applyEdit(spec) { root._runScript("edit", "edit", spec); }
    function applyDelete(spec) { root._runScript("delete", "delete", spec); }
    function applyAdd(spec) { root._runScript("add", "add", spec); }
    function applySetDescription(spec) { root._runScript("set-description", "set-description", spec); }
}
