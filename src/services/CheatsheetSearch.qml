pragma Singleton

import Quickshell

// Session-scoped query for the keybind cheatsheet — the filter should survive closing and
// reopening the cheatsheet within a session, but reset whenever the quickshell process restarts.
// Bundled so the extension is self-contained on shells (ii-vynx) that lack this singleton.
Singleton {
    id: root
    property string query: ""
}
