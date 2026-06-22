pragma ComponentBehavior: Bound

import "services"
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property string categoryName
    property var cheatsheet: null
    readonly property bool isCategorized: categoryName?.length > 0

    readonly property var _baseBinds: root.isCategorized
        ? HyprlandKeybinds.keybinds.filter(b => b.description?.length > 0 && b.description.substring(0, b.description.indexOf(":")) === root.categoryName)
        : HyprlandKeybinds.keybinds.filter(b => b.description?.length > 0 && b.description.indexOf(":") === -1)
    readonly property var _filteredBinds: root.cheatsheet
        ? root._baseBinds.filter(b => root.cheatsheet.bindMatches(b, root.categoryName))
        : root._baseBinds
    readonly property bool _hasMatches: root._filteredBinds.length > 0

    // Keep the card in layout while the opacity animation drains, so survivors only repack
    // after non-matching cards finish fading out. Flow drops the card once it's fully invisible.
    visible: _hasMatches || opacity > 0
    opacity: _hasMatches ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    color: Appearance.colors.colSurfaceContainer
    radius: Appearance.rounding.large
    implicitWidth: cardColumn.implicitWidth + 28
    implicitHeight: cardColumn.implicitHeight + 24

    // Excellent symbol explanation and source:
    // http://xahlee.info/comp/unicode_computing_symbols.html
    // https://www.nerdfonts.com/cheat-sheet
    property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
    })
    property var functionSymbolMap: ({
        "F1":  "󱊫", "F2":  "󱊬", "F3":  "󱊭", "F4":  "󱊮",
        "F5":  "󱊯", "F6":  "󱊰", "F7":  "󱊱", "F8":  "󱊲",
        "F9":  "󱊳", "F10": "󱊴", "F11": "󱊵", "F12": "󱊶",
    })
    property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
        "Scroll ↑/↓": "󱕒",
        "Page_↑/↓": "⇞/⇟",
    })

    property var keyBlacklist: ["SUPER_L", "SUPER_R"]
    property var keySubstitutions: Object.assign({
            "Super": "",
            "Mouse_up": "Scroll ↑",
            "Mouse_down": "Scroll ↓",
            "Mouse:272": "LMB",
            "Mouse:273": "RMB",
            "Mouse:275": "MouseBack",
            "Slash": "/",
            "Hash": "#",
            "Return": "Enter",
        },
        !!Config.options?.cheatsheet?.superKey ? { "Super": Config.options.cheatsheet.superKey } : {},
        Config.options?.cheatsheet?.useMacSymbol ? macSymbolMap : {},
        Config.options?.cheatsheet?.useFnSymbol ? functionSymbolMap : {},
        Config.options?.cheatsheet?.useMouseSymbol ? mouseSymbolMap : {},
    )

    readonly property var categoryIcons: ({
        "Window": "select_window",
        "App": "apps",
        "Apps": "apps",
        "Application": "apps",
        "Utilities": "build",
        "Utility": "build",
        "Shell": "desktop_windows",
        "Screenshot": "screenshot_monitor",
        "Workspace": "view_carousel",
        "Workspaces": "view_carousel",
        "Monitor": "tv",
        "Monitors": "tv",
        "Media": "music_note",
        "Volume": "volume_up",
        "Audio": "volume_up",
        "Backlight": "light_mode",
        "Brightness": "light_mode",
        "Power": "power_settings_new",
        "Session": "power_settings_new",
        "System": "settings",
    })
    readonly property string categoryIcon: root.categoryIcons[root.categoryName] ?? "keyboard"

    readonly property bool editMode: root.cheatsheet?.editMode ?? false

    function comboFor(bind) {
        const tokens = root.modMaskToStringList(bind.modmask)
            .map(m => m.toUpperCase());
        const key = bind.key;
        const lk = key.toLowerCase();
        const table = ({
            "space": "Space", "minus": "Minus", "equal": "Equal", "slash": "Slash",
            "period": "Period", "semicolon": "Semicolon", "apostrophe": "Apostrophe",
            "bracketleft": "BracketLeft", "bracketright": "BracketRight",
            "backslash": "Backslash", "return": "Return", "backspace": "BackSpace",
            "tab": "Tab", "escape": "Escape", "delete": "Delete", "print": "Print",
        });
        let luaKey = table[lk];
        if (!luaKey) {
            if (/^mouse[:_]/.test(lk)) luaKey = lk;
            else luaKey = key.length ? key[0].toUpperCase() + key.slice(1).toLowerCase() : key;
        }
        return [...tokens, luaKey].join(" + ");
    }

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

    // Width of the widest pill — combo column shares it so action labels align.
    // Grow-only; filtering shouldn't collapse the column.
    property int maxComboWidth: 0

    ColumnLayout {
        id: cardColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: root.categoryIcon
                iconSize: Appearance.font.pixelSize.huge
                fill: 1
                color: Appearance.m3colors.m3primary
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.title
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
                text: root.isCategorized ? root.categoryName : Translation.tr("Uncategorized")
            }

            Row {
                visible: root.editMode && root.isCategorized
                spacing: 2
                Rectangle {
                    width: 24; height: 24; radius: Appearance.rounding.full
                    color: upArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_upward"; iconSize: 16
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    MouseArea {
                        id: upArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cheatsheet?.moveCategory(root.categoryName, -1)
                    }
                }
                Rectangle {
                    width: 24; height: 24; radius: Appearance.rounding.full
                    color: downArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_downward"; iconSize: 16
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    MouseArea {
                        id: downArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cheatsheet?.moveCategory(root.categoryName, 1)
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 4 }

        Column {
            spacing: 4
            Repeater {
                model: root._filteredBinds
                delegate: BindLine {
                    required property var modelData
                    keyData: modelData
                }
            }

            KeybindAddNewLine {
                visible: root.editMode
                onClicked: root.cheatsheet?.requestAdd(root.categoryName)
            }
        }
    }

    component BindLine: Row {
        id: bindLine
        required property var keyData
        spacing: 10
        opacity: root.editMode && !bindLine.isEditable ? 0.45 : 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        readonly property var modTokens: root.modMaskToStringList(bindLine.keyData.modmask)
            .map(m => root.keySubstitutions[m] ?? m)
            .filter(m => m.length > 0)
        readonly property bool keyShown: !root.keyBlacklist.includes(bindLine.keyData.key)
        readonly property string keyToken: {
            const raw = bindLine.keyData.key;
            const titled = StringUtils.toTitleCase(raw);
            return root.keySubstitutions[raw] ?? root.keySubstitutions[titled] ?? titled;
        }
        readonly property var parts: bindLine.keyShown ? [...bindLine.modTokens, bindLine.keyToken] : bindLine.modTokens
        readonly property string comboString: root.comboFor(bindLine.keyData)
        // Editable only when the combo is found in a config file AND it round-trips through the
        // editor's normalizer. Combos with mods the editor doesn't model (Caps/Mod2/Mod3/Mod5)
        // can't be normalized, so the edit dialog could never save them — dim them instead.
        readonly property bool isEditable: KeybindsEditor.findSourceFor(bindLine.comboString) !== "generated"
            && KeybindsEditor.normalizeCombo(bindLine.comboString) !== null

        Item {
            id: comboSlot
            implicitWidth: Math.max(pill.implicitWidth, root.maxComboWidth)
            implicitHeight: pill.implicitHeight
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: pill
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: Appearance.colors.colSecondaryContainer
                radius: Appearance.rounding.full
                implicitWidth: pillRow.implicitWidth + 18
                implicitHeight: pillRow.implicitHeight + 6
                visible: bindLine.parts.length > 0
                onImplicitWidthChanged: root.maxComboWidth = Math.max(root.maxComboWidth, implicitWidth)
                Component.onCompleted: root.maxComboWidth = Math.max(root.maxComboWidth, implicitWidth)

                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: bindLine.parts
                        delegate: Row {
                            id: tokenRow
                            required property int index
                            required property var modelData
                            readonly property bool isTrigger: bindLine.keyShown && index === bindLine.parts.length - 1
                            spacing: 4
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: tokenRow.index > 0
                                font.pixelSize: Config.options?.cheatsheet?.fontSize?.key || Appearance.font.pixelSize.smaller
                                color: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.4)
                                text: "+"
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: Config.options?.cheatsheet?.fontSize?.key || Appearance.font.pixelSize.smaller
                                font.weight: tokenRow.isTrigger ? Font.DemiBold : Font.Medium
                                color: tokenRow.isTrigger
                                    ? Appearance.colors.colOnSecondaryContainer
                                    : ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.25)
                                text: tokenRow.modelData
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Config.options?.cheatsheet?.fontSize?.comment || Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer0
            text: {
                if (!root.categoryName) return bindLine.keyData.description;
                const regex = new RegExp("\\s*" + root.categoryName + "\\s*:\\s*");
                return bindLine.keyData.description.replace(regex, "");
            }
        }

        Row {
            id: editIcons
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            visible: root.editMode && bindLine.isEditable
            opacity: visible ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Rectangle {
                width: 28; height: 28; radius: Appearance.rounding.full
                color: editArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"; iconSize: 18
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
                MouseArea {
                    id: editArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cheatsheet?.requestEdit(bindLine.keyData, bindLine.comboString, root.categoryName)
                }
            }
            Rectangle {
                width: 28; height: 28; radius: Appearance.rounding.full
                color: deleteArea.containsMouse ? Appearance.colors.colErrorContainer : "transparent"
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"; iconSize: 18
                    color: deleteArea.containsMouse
                        ? Appearance.m3colors.m3onErrorContainer
                        : Appearance.m3colors.m3onSurfaceVariant
                }
                MouseArea {
                    id: deleteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cheatsheet?.requestDelete(bindLine.keyData, bindLine.comboString)
                }
            }
        }
    }
}
