pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    anchors.fill: parent

    property string mode: "edit"
    property string originalCombo: ""
    property string originalCategory: ""
    property string originalDescription: ""
    property string source: "default"
    property string presetCategory: ""

    property string inputCombo: ""
    property string inputCategory: ""
    property string inputDescription: ""
    property string inputCommand: ""

    readonly property string normalizedCombo: KeybindsEditor.normalizeCombo(inputCombo) ?? ""
    readonly property var conflict: normalizedCombo
        ? KeybindsEditor.detectConflict(normalizedCombo, root.mode === "edit" ? root.originalCombo : "")
        : null
    readonly property bool comboInvalid: inputCombo.length > 0 && !normalizedCombo
    readonly property bool descFilled: inputDescription.length > 0
    readonly property bool commandRequired: root.mode !== "add" || inputCommand.length > 0
    readonly property bool hasChanges: root.mode === "add"
        || normalizedCombo !== KeybindsEditor.normalizeCombo(originalCombo)
        || inputCategory.trim() !== originalCategory
        || inputDescription.trim() !== originalDescription
    readonly property bool canSave:
        !!normalizedCombo && !conflict && descFilled && commandRequired && hasChanges

    signal canceled()
    signal saved(var payload)

    function open(opts) {
        root.mode = opts.mode || "edit";
        root.originalCombo = opts.combo || "";
        root.originalCategory = opts.category || "";
        root.originalDescription = opts.description || "";
        root.source = opts.source || "default";
        root.presetCategory = opts.presetCategory || "";

        root.inputCombo = root.originalCombo;
        root.inputCategory = root.originalCategory || root.presetCategory;
        root.inputDescription = root.originalDescription;
        root.inputCommand = "";

        if (HyprlandKeybinds.keybindCategories.length === 0 && root.mode === "add") {
            console.warn("[KeybindEditDialog] Categories not loaded yet, refusing to open in add mode");
            root.canceled();
            return;
        }

        const cats = HyprlandKeybinds.keybindCategories;
        const idx = cats.indexOf(root.inputCategory);
        if (idx >= 0) {
            newCategoryField.text = "";
            categoryField.currentIndex = idx;
        } else if (root.inputCategory.length > 0) {
            newCategoryField.text = root.inputCategory;
            categoryField.currentIndex = 0;
        } else {
            newCategoryField.text = "";
            categoryField.currentIndex = 0;
            if (cats.length > 0) root.inputCategory = cats[0];
        }

        root.visible = true;
        comboField.forceActiveFocus();
    }

    visible: false

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        MouseArea {
            anchors.fill: parent
            preventStealing: true
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 480
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        implicitHeight: cardCol.implicitHeight + 32

        ColumnLayout {
            id: cardCol
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                margins: 20
            }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: root.mode === "edit" ? Translation.tr("Edit keybind") : Translation.tr("Add keybind")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
                Rectangle {
                    width: 28; height: 28; radius: Appearance.rounding.full
                    color: closeArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"; iconSize: 20
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.canceled()
                    }
                }
            }

            StyledText {
                text: Translation.tr("Combination")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurfaceVariant
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainer
                border.width: 1
                border.color: root.comboInvalid || root.conflict
                    ? Appearance.m3colors.m3error
                    : Appearance.colors.colOutlineVariant
                StyledTextInput {
                    id: comboField
                    anchors.fill: parent
                    anchors.margins: 10
                    text: root.inputCombo
                    onTextChanged: root.inputCombo = text
                    font.family: "monospace"
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) { root.canceled(); event.accepted = true; }
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.canSave) root._emitSave();
                            event.accepted = true;
                        }
                    }
                    onFocusChanged: {
                        if (!focus) {
                            const n = KeybindsEditor.normalizeCombo(text);
                            if (n) text = n;
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: !!root.conflict || root.comboInvalid
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
                text: root.conflict
                    ? Translation.tr("⚠ Conflict with: ") + root.conflict.description
                    : Translation.tr("⚠ Invalid combination")
            }

            StyledText {
                text: Translation.tr("Category")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurfaceVariant
            }
            StyledComboBox {
                id: categoryField
                Layout.fillWidth: true
                editable: false
                model: HyprlandKeybinds.keybindCategories
                onCurrentTextChanged: {
                    if (!root.visible) return;
                    if (newCategoryField.text.trim().length === 0) {
                        root.inputCategory = currentText;
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainer
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                StyledTextInput {
                    id: newCategoryField
                    anchors.fill: parent
                    anchors.margins: 10
                    onTextChanged: {
                        if (!root.visible) return;
                        const t = text.trim();
                        if (t.length > 0) root.inputCategory = t;
                        else root.inputCategory = categoryField.currentText;
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    visible: newCategoryField.text.length === 0
                    text: Translation.tr("Or type a new category")
                    color: Appearance.m3colors.m3onSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            StyledText {
                text: Translation.tr("Description")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurfaceVariant
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainer
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                StyledTextInput {
                    id: descField
                    anchors.fill: parent
                    anchors.margins: 10
                    text: root.inputDescription
                    onTextChanged: root.inputDescription = text
                }
            }

            StyledText {
                visible: root.mode === "add"
                text: Translation.tr("Command")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurfaceVariant
            }
            Rectangle {
                visible: root.mode === "add"
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainer
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                StyledTextInput {
                    id: commandField
                    anchors.fill: parent
                    anchors.margins: 10
                    font.family: "monospace"
                    text: root.inputCommand
                    onTextChanged: root.inputCommand = text
                }
            }

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3onSurfaceVariant
                text: root.mode === "edit"
                    ? Translation.tr("Source: ") + (root.source === "custom" ? "custom/keybinds.lua" : "hyprland/keybinds.lua")
                    : Translation.tr("Source: ") + "custom/keybinds.lua (new)"
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                Item { Layout.fillWidth: true }
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.canceled()
                }
                DialogButton {
                    buttonText: Translation.tr("Save")
                    enabled: root.canSave
                    onClicked: {
                        if (!root.canSave) return;
                        root._emitSave();
                    }
                }
            }
        }
    }

    function _emitSave() {
        const payload = {
            mode: root.mode,
            source: root.source,
            originalCombo: root.originalCombo,
            combo: root.normalizedCombo,
            category: root.inputCategory.trim() || "Misc",
            description: root.inputDescription.trim(),
        };
        if (root.mode === "add") payload.command = root.inputCommand;
        root.saved(payload);
    }
}
