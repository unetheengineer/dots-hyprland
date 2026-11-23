pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Kısayol görünümü ve düzenleyicisi (Super+/). Listeyi hyprland/keybind-layer.lua'nın yazdığı manifest besler;
 * değişiklikler KeybindsStore üzerinden custom/keybind-overrides.lua'ya yazılıp Hyprland yeniden yüklenir.
 */
Scope {
    id: root
    property alias open: loader.active

    Loader {
        id: loader
        active: false

        sourceComponent: PanelWindow {
            id: win
            visible: loader.active

            anchors { top: true; bottom: true; left: true; right: true }
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:keybinds"
            color: "transparent"
            mask: Region { item: bg }

            function hide() { loader.active = false; }

            Component.onCompleted: GlobalFocusGrab.addDismissable(win)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { win.hide(); }
            }

            // --- durum ---
            property string query: ""
            property string category: ""      // "", kategori adı, "@clash", "@changed"
            property string view: "keyboard"      // "list" | "keyboard"
            property var mods: ["SUPER"]      // klavye görünümü
            property string selKey: ""
            property string selKeyName: ""
            property string selectedId: ""

            readonly property real margin: Appearance.sizes.elevationMargin
            readonly property real maxW: (win.screen?.width ?? 1600) - margin * 2 - 24
            readonly property real maxH: (win.screen?.height ?? 900) - margin * 2 - 24
            readonly property bool compact: bg.width < 900
            readonly property bool kbMode: view === "keyboard" && !compact
            readonly property bool editorOpen: editor.creating || selectedId !== ""
            readonly property real editorW: compact ? bg.width - 24 : 380

            readonly property var filtered: {
                const q = query.trim().toLowerCase();
                return KeybindsStore.binds.filter(b => {
                    if (b.internal && q === "") return false;   // end-4'ün iç tuşları (çalışma alanı numarası kaplaması)
                    if (category === "@clash" && !b.clash) return false;
                    if (category === "@changed" && !(b.custom || b.remapped || b.disabled || b.renamed)) return false;
                    if (category !== "" && category[0] !== "@" && b.category !== category) return false;
                    if (q === "") return true;
                    return [b.label, b.keys, b.category, b.command, b.src].some(v => String(v ?? "").toLowerCase().includes(q));
                });
            }
            readonly property var groups: {
                const order = KeybindsStore.categories;
                return order.map(c => ({ name: c, items: filtered.filter(b => b.category === c) })).filter(g => g.items.length > 0);
            }
            // klavye görünümü: seçili birleşimdeki kısayollar
            readonly property var comboBinds: filtered.filter(b => {
                const p = KeybindsStore.parse(b.keys);
                if (b.disabled) return false;
                if (p.mods.slice().sort().join("+") !== mods.slice().sort().join("+")) return false;
                return selKey === "" || KeybindsStore.aliasKey(p.key) === selKey;
            })

            function select(id) { editor.draft = null; selectedId = id; }
            function startDraft(keys) {
                selectedId = "";
                editor.draft = { keys: keys, label: "", command: "", action: "exec", flags: {} };
            }
            function closeEditor() { selectedId = ""; editor.draft = null; editor.recording = false; }

            Item {
                id: bg
                anchors.centerIn: parent
                width: Math.min(win.maxW, 1500)
                height: Math.min(win.maxH, 900)
                focus: true

                Keys.onPressed: e => {
                    if (e.key !== Qt.Key_Escape) return;
                    if (editor.recording) editor.recording = false;
                    else if (win.editorOpen) win.closeEditor();
                    else if (win.query !== "") win.query = "";
                    else win.hide();
                    e.accepted = true;
                }

                StyledRectangularShadow { target: panel }
                Rectangle {
                    id: panel
                    anchors.fill: parent
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    radius: Appearance.rounding.windowRounding
                }

                // ---- ana sütun ----
                ColumnLayout {
                    id: main
                    anchors {
                        fill: parent
                        margins: 20
                        rightMargin: 20 + (win.editorOpen && !win.compact ? win.editorW + 16 : 0)
                    }
                    spacing: 12
                    visible: !(win.editorOpen && win.compact)

                    // üst çubuk
                    Flow {
                        id: header
                        Layout.fillWidth: true
                        spacing: 10

                        StyledText {
                            id: title
                            height: 40
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Keybinds")
                            font.pixelSize: Appearance.font.pixelSize.title
                            color: Appearance.colors.colOnLayer0
                        }
                        MaterialTextField {
                            id: search
                            width: win.compact ? header.width : Math.max(220, header.width - title.width - toggles.width - actions.width - 3 * header.spacing)
                            height: 40
                            placeholderText: Translation.tr("Search shortcuts…")
                            text: win.query
                            onTextChanged: win.query = text
                            Component.onCompleted: forceActiveFocus()
                        }
                        Row {
                            id: toggles
                            spacing: 4
                            visible: !win.compact
                            Repeater {
                                model: [{ v: "list", icon: "view_agenda", tip: Translation.tr("List") }, { v: "keyboard", icon: "keyboard", tip: Translation.tr("Keyboard") }]
                                RippleButton {
                                    required property var modelData
                                    implicitWidth: 40; implicitHeight: 40
                                    buttonRadius: Appearance.rounding.full
                                    toggled: win.view === modelData.v
                                    onClicked: win.view = modelData.v
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.icon
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: parent.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                    }
                                    StyledToolTip { text: modelData.tip }
                                }
                            }
                        }
                        Row {
                            id: actions
                            spacing: 4
                            StyledText {
                                visible: KeybindsStore.applying
                                height: 40
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Applying…")
                                color: Appearance.colors.colOnLayer1Inactive
                                rightPadding: 8
                            }
                            RippleButton {
                                implicitWidth: 40; implicitHeight: 40
                                buttonRadius: Appearance.rounding.full
                                onClicked: win.startDraft("")
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "add"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledToolTip { text: Translation.tr("New shortcut") }
                            }
                            RippleButton {
                                implicitWidth: 40; implicitHeight: 40
                                buttonRadius: Appearance.rounding.full
                                onClicked: win.hide()
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "close"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }

                    // kategori süzgeci
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: {
                                const m = [{ v: "", t: Translation.tr("All") }];
                                KeybindsStore.categories.forEach(c => m.push({ v: c, t: Translation.tr(c) }));
                                if (KeybindsStore.clashCount > 0) m.push({ v: "@clash", t: Translation.tr("Conflicts") + " " + KeybindsStore.clashCount, warn: true });
                                if (KeybindsStore.changedCount > 0) m.push({ v: "@changed", t: Translation.tr("Modified") + " " + KeybindsStore.changedCount });
                                return m;
                            }
                            RippleButton {
                                required property var modelData
                                implicitHeight: 32
                                implicitWidth: chipText.implicitWidth + 24
                                buttonRadius: Appearance.rounding.full
                                toggled: win.category === modelData.v
                                colBackground: Appearance.colors.colLayer1
                                onClicked: win.category = modelData.v
                                contentItem: StyledText {
                                    id: chipText
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.t
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: parent.toggled ? Appearance.m3colors.m3onPrimary : (modelData.warn ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1)
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: KeybindsStore.manifest.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("No shortcuts found yet. Reload the Hyprland config so the keybind layer can list them.")
                        color: Appearance.colors.colOnLayer1Inactive
                    }

                    // ---- liste görünümü ----
                    StyledFlickable {
                        id: listView
                        visible: !win.kbMode
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentHeight: listCol.implicitHeight

                        readonly property real spacing: 10
                        readonly property int cols: Math.max(1, Math.min(4, Math.floor((width + spacing) / (300 + spacing))))
                        readonly property real cardW: (width - (cols - 1) * spacing) / cols

                        ColumnLayout {
                            id: listCol
                            width: listView.width
                            spacing: 16
                            Repeater {
                                model: win.groups
                                ColumnLayout {
                                    id: grp
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    StyledText {
                                        text: Translation.tr(grp.modelData.name) + "  ·  " + grp.modelData.items.length
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: listView.spacing
                                        Repeater {
                                            model: grp.modelData.items
                                            BindCard {
                                                required property var modelData
                                                bind: modelData
                                                width: listView.cardW
                                                selected: win.selectedId === modelData.id
                                                onClicked: win.select(modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- klavye görünümü ----
                    StyledFlickable {
                        id: kbView
                        visible: win.kbMode
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentHeight: kbCol.implicitHeight

                        ColumnLayout {
                            id: kbCol
                            width: kbView.width
                            spacing: 14

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: Translation.tr("Pick modifier keys to see what each key does with them. Hover a key to see its other combinations: a dot in the top-right corner means it is also used with other modifiers, a dot in the top-left means several shortcuts share it.")
                                color: Appearance.colors.colOnLayer1Inactive
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            KeyboardView {
                                Layout.fillWidth: true
                                binds: win.filtered
                                categories: KeybindsStore.categories
                                mods: win.mods
                                selected: win.selKey
                                onModToggled: m => win.mods = win.mods.includes(m) ? win.mods.filter(x => x !== m) : win.mods.concat([m])
                                onKeyClicked: (id, legend) => {
                                    if (win.selKey === id.toLowerCase()) { win.selKey = ""; win.selKeyName = ""; return; }
                                    win.selKey = id.toLowerCase(); win.selKeyName = id;
                                    if (win.comboBinds.length === 1) win.select(win.comboBinds[0].id);
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const k = KeybindsStore.compose(win.mods, win.selKeyName);
                                        return (k === "" ? Translation.tr("Single keys") : k) + "  ·  " + win.comboBinds.length;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer1Inactive
                                }
                                RippleButton {
                                    implicitHeight: 32
                                    implicitWidth: addHere.implicitWidth + 24
                                    buttonRadius: Appearance.rounding.full
                                    visible: win.selKey !== ""
                                    onClicked: win.startDraft(KeybindsStore.compose(win.mods, win.selKeyName))
                                    contentItem: StyledText {
                                        id: addHere
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        text: Translation.tr("Add shortcut here")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 10
                                readonly property int cols: Math.max(1, Math.min(4, Math.floor((width + spacing) / (300 + spacing))))
                                Repeater {
                                    model: win.comboBinds
                                    BindCard {
                                        required property var modelData
                                        bind: modelData
                                        showCategory: true
                                        width: (kbCol.width - (parent.cols - 1) * parent.spacing) / parent.cols
                                        selected: win.selectedId === modelData.id
                                        onClicked: win.select(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- düzenleyici ----
                BindEditor {
                    id: editor
                    visible: win.editorOpen
                    anchors {
                        top: parent.top; bottom: parent.bottom; right: parent.right
                        margins: 12
                    }
                    width: win.editorW
                    bind: win.selectedId === "" ? null : KeybindsStore.bindById(win.selectedId)
                    onClosed: win.closeEditor()
                }
            }
        }
    }

    IpcHandler {
        target: "keybinds"
        function toggle(): void { loader.active = !loader.active; }
        function close(): void { loader.active = false; }
        function open(): void { loader.active = true; }
    }

    GlobalShortcut {
        name: "keybindsToggle"
        description: "Toggles the keybinds viewer and editor"
        onPressed: loader.active = !loader.active
    }
}
