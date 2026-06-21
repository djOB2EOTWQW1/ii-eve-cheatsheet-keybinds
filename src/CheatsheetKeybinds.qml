pragma ComponentBehavior: Bound

import qs.services
import "services"
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    // Injected by the cheatsheet contribution point.
    property string extensionId: ""
    readonly property string _extId: "ii-eve-cheatsheet-keybinds"
    property real padding: 4
    property bool editMode: false
    // ii-eve exposes Config.options.cheatsheet.allowEditing (toggle in Settings); ii-vynx
    // has no such option, so default editing to available there.
    readonly property bool allowEditing: Config.options?.cheatsheet?.allowEditing ?? true
    onEditModeChanged: if (editMode && !root.allowEditing) editMode = false;
    onAllowEditingChanged: if (!root.allowEditing) root.editMode = false;

    // Stable fixed size (like the timetable/periodic cheatsheet pages). Deriving from
    // QsWindow.window.screen inside the SwipeView's render layer oscillates (window goes
    // null intermittently) → binding loop on the SwipeView height → unstable geometry that
    // breaks tab switching and dialog clicks.
    implicitWidth: 1350
    implicitHeight: 700

    readonly property string query: CheatsheetSearch.query
    readonly property string normalizedQuery: query.trim().toLowerCase()

    // Predicates live here so the empty-state counter and the cards filter through one source.
    function modMaskToStringList(modMask) {
        var list = [];
        if (modMask & (1 << 2)) list.push("Ctrl");
        if (modMask & (1 << 6)) list.push("Super");
        if (modMask & (1 << 0)) list.push("Shift");
        if (modMask & (1 << 3)) list.push("Alt");
        if (modMask & (1 << 1)) list.push("Caps");
        if (modMask & (1 << 4)) list.push("Mod2");
        if (modMask & (1 << 5)) list.push("Mod3");
        if (modMask & (1 << 7)) list.push("Mod5");
        return list;
    }
    function categoryOf(bind) {
        const d = bind.description ?? "";
        const i = d.indexOf(":");
        return i === -1 ? "" : d.substring(0, i);
    }
    function bindMatches(bind, categoryName) {
        const q = root.normalizedQuery;
        if (q === "") return true;
        if (categoryName && categoryName.toLowerCase().includes(q)) return true;
        let blob = bind.__searchBlob;
        if (blob === undefined) {
            blob = [...root.modMaskToStringList(bind.modmask), bind.key ?? "", bind.description ?? ""].join(" ").toLowerCase();
            bind.__searchBlob = blob;
        }
        return blob.includes(q);
    }

    function requestEdit(keyData, combo, category) {
        const desc = keyData.description ?? "";
        const idx = desc.indexOf(":");
        const descNoCat = idx >= 0 ? desc.substring(idx + 1).trim() : desc;
        const cat = idx >= 0 ? desc.substring(0, idx).trim() : (category ?? "");
        const source = KeybindsEditor.findSourceFor(combo);
        if (source === "generated") return;
        keybindDialog.open({
            mode: "edit",
            combo: combo,
            category: cat,
            description: descNoCat,
            source: source,
        });
    }

    function requestAdd(category) {
        keybindDialog.open({
            mode: "add",
            presetCategory: category || "Misc",
            source: "custom",
        });
    }

    function requestDelete(_keyData, combo) {
        const source = KeybindsEditor.findSourceFor(combo);
        if (source === "generated") return;
        KeybindsEditor.applyDelete({ source: source, combo: combo });
    }

    Connections {
        target: KeybindsEditor
        function onApplyFinished(operation, result) {
            if (result.ok) {
                keybindDialog.visible = false;
                snackbar.show(operation === "delete" ? Translation.tr("Keybind deleted") : Translation.tr("Keybind saved"));
            } else {
                snackbar.show(Translation.tr("Failed: ") + (result.error || Translation.tr("unknown error")));
            }
        }
    }

    readonly property var orderedCategories: {
        const all = HyprlandKeybinds.keybindCategories;
        // Persisted in extension config so reordering survives on shells (ii-vynx) whose
        // Config has no cheatsheet.categoryOrder.
        const raw = ExtensionManager.getExtensionConfig(root._extId, "categoryOrder", Config.options?.cheatsheet?.categoryOrder ?? "") || "";
        const saved = raw.length > 0 ? raw.split(",") : [];
        const result = [];
        for (const name of saved) {
            if (all.includes(name)) result.push(name);
        }
        for (const name of all) {
            if (!result.includes(name)) result.push(name);
        }
        return result;
    }

    function moveCategory(name, delta) {
        Qt.callLater(() => {
            const current = root.orderedCategories.slice();
            const i = current.indexOf(name);
            if (i < 0) return;
            const j = i + delta;
            if (j < 0 || j >= current.length) return;
            const tmp = current[i];
            current[i] = current[j];
            current[j] = tmp;
            ExtensionManager.setExtensionConfig(root._extId, "categoryOrder", current.join(","));
        });
    }

    readonly property int matchCount: {
        if (root.normalizedQuery === "") return -1;
        let n = 0;
        const binds = HyprlandKeybinds.keybinds;
        for (let i = 0; i < binds.length; i++) {
            const b = binds[i];
            if ((b.description?.length ?? 0) > 0 && root.bindMatches(b, root.categoryOf(b))) n++;
        }
        return n;
    }
    readonly property bool isEmpty: root.matchCount === 0

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (CheatsheetSearch.query.length > 0 || filterField.text.length > 0) {
                CheatsheetSearch.query = "";
                filterField.text = "";
                event.accepted = true;
            }
            return;
        }
        if (event.key === Qt.Key_Slash) {
            filterField.forceActiveFocus();
            event.accepted = true;
            return;
        }
        const t = event.text;
        const blocked = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (t.length === 1 && t.charCodeAt(0) >= 0x20 && !blocked) {
            filterField.forceActiveFocus();
            filterField.text += t;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.rounding.small
        anchors.bottomMargin: 90
        spacing: 14

        Item {
            id: viewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            StyledFlickable {
                id: flickable
                anchors.fill: parent
                contentHeight: height
                contentWidth: flow.implicitWidth
                opacity: root.isEmpty ? 0 : 1
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Flow {
                    id: flow
                    height: flickable.height
                    flow: Flow.TopToBottom
                    spacing: 12
                    move: Transition {
                        NumberAnimation {
                            properties: "x,y"
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                        }
                    }
                    Repeater {
                        model: [...root.orderedCategories, ""]
                        delegate: CheatsheetKeybindsCategory {
                            required property var modelData
                            categoryName: modelData
                            cheatsheet: root
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8
                opacity: root.isEmpty ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "search_off"
                    iconSize: Appearance.font.pixelSize.huge * 1.6
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    color: Appearance.m3colors.m3onSurfaceVariant
                    text: `No keybinds match "${root.query}"`
                }
            }
        }
    }

    Toolbar {
        id: searchToolbar
        z: 5
        colBackground: Appearance.colors.colSecondaryContainer
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20

        ToolbarTextField {
            id: filterField
            placeholderText: focus ? Translation.tr("Search keybinds") : Translation.tr("Hit \"/\" to search")
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            colBackground: Qt.alpha(Appearance.colors.colOnSecondaryContainer, 0.05)
            color: Appearance.colors.colOnSecondaryContainer
            placeholderTextColor: Qt.alpha(Appearance.colors.colOnSecondaryContainer, 0.6)
            Component.onCompleted: text = CheatsheetSearch.query
            onTextChanged: CheatsheetSearch.query = text
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (text.length > 0 || CheatsheetSearch.query.length > 0) {
                        text = "";
                        CheatsheetSearch.query = "";
                        event.accepted = true;
                    }
                    // else: let the event bubble up so cheatsheet can close.
                }
            }
        }

        IconToolbarButton {
            implicitWidth: height
            onClicked: { CheatsheetSearch.query = ""; filterField.text = ""; }
            text: "close"
            colText: Appearance.colors.colOnSecondaryContainer
            StyledToolTip {
                text: Translation.tr("Clear search")
            }
        }

        IconToolbarButton {
            implicitWidth: height
            visible: root.allowEditing
            toggled: root.editMode
            onClicked: root.editMode = !root.editMode
            text: "edit"
            colBackgroundToggled: Appearance.m3colors.m3primary
            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
            colText: root.editMode ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnSecondaryContainer
            StyledToolTip {
                text: root.editMode ? Translation.tr("Exit edit mode") : Translation.tr("Edit keybinds")
            }
        }
    }

    KeybindEditDialog {
        id: keybindDialog
        visible: false
        onCanceled: visible = false
        onSaved: payload => {
            if (payload.mode === "edit") {
                if (payload.combo === payload.originalCombo) {
                    KeybindsEditor.applySetDescription({
                        source: payload.source,
                        combo: payload.combo,
                        description: payload.description,
                        category: payload.category,
                    });
                } else {
                    KeybindsEditor.applyEdit({
                        source: payload.source,
                        oldCombo: payload.originalCombo,
                        newCombo: payload.combo,
                        description: payload.description,
                        category: payload.category,
                    });
                }
            } else {
                KeybindsEditor.applyAdd({
                    combo: payload.combo,
                    command: payload.command,
                    description: payload.description,
                    category: payload.category,
                });
            }
        }
    }

    Rectangle {
        id: snackbar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        radius: Appearance.rounding.small
        color: Appearance.m3colors.m3inverseSurface
        implicitWidth: snackText.implicitWidth + 32
        implicitHeight: snackText.implicitHeight + 20
        opacity: 0
        visible: opacity > 0

        property string message: ""

        function show(msg) {
            snackbar.message = msg;
            snackbar.opacity = 1;
            hideTimer.restart();
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledText {
            id: snackText
            anchors.centerIn: parent
            text: snackbar.message
            color: Appearance.m3colors.m3inverseOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
        }

        Timer {
            id: hideTimer
            interval: 3000
            onTriggered: snackbar.opacity = 0
        }
    }
}
