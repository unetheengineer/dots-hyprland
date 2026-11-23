pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Etkileşimli klavye: seçili değiştirici tuşlarla hangi kısayolların olduğunu tuşların üstünde gösterir.
 * Dolu tuş = o birleşimde kısayol var, renk kategoriyi gösterir; köşedeki nokta = tuş başka birleşimde kullanılıyor.
 */
Item {
    id: root

    property var binds: []            // süzülmüş kısayollar
    property var categories: []       // renk sırası
    property var mods: []
    property string selected: ""      // seçili tuş (küçük harf)
    signal keyClicked(string keyId, string display)
    signal modToggled(string mod)

    readonly property real gap: 4
    readonly property real unit: Math.max(26, Math.min(76, width / 15.2))
    readonly property real xOff: (width - 15 * unit) / 2
    implicitHeight: unit * 6.5

    readonly property var rows: [
        [["Escape", "Esc", 1], ["F1", "F1", 1], ["F2", "F2", 1], ["F3", "F3", 1], ["F4", "F4", 1], ["F5", "F5", 1], ["F6", "F6", 1], ["F7", "F7", 1], ["F8", "F8", 1], ["F9", "F9", 1], ["F10", "F10", 1], ["F11", "F11", 1], ["F12", "F12", 1], ["Print", "Prt", 1], ["Delete", "Del", 1]],
        [["grave", "`", 1], ["1", "1", 1], ["2", "2", 1], ["3", "3", 1], ["4", "4", 1], ["5", "5", 1], ["6", "6", 1], ["7", "7", 1], ["8", "8", 1], ["9", "9", 1], ["0", "0", 1], ["minus", "-", 1], ["equal", "=", 1], ["BackSpace", "⌫", 2], ["Home", "Home", 1]],
        [["Tab", "Tab", 1.5], ["Q", "Q", 1], ["W", "W", 1], ["E", "E", 1], ["R", "R", 1], ["T", "T", 1], ["Y", "Y", 1], ["U", "U", 1], ["I", "I", 1], ["O", "O", 1], ["P", "P", 1], ["bracketleft", "[", 1], ["bracketright", "]", 1], ["backslash", "\\", 1.5], ["Prior", "PgUp", 1]],
        [["caps", "Caps", 1.75], ["A", "A", 1], ["S", "S", 1], ["D", "D", 1], ["F", "F", 1], ["G", "G", 1], ["H", "H", 1], ["J", "J", 1], ["K", "K", 1], ["L", "L", 1], ["semicolon", ";", 1], ["apostrophe", "'", 1], ["Return", "Enter", 2.25], ["Next", "PgDn", 1]],
        [["mod:SHIFT", "Shift", 2.25], ["Z", "Z", 1], ["X", "X", 1], ["C", "C", 1], ["V", "V", 1], ["B", "B", 1], ["N", "N", 1], ["M", "M", 1], ["comma", ",", 1], ["period", ".", 1], ["slash", "/", 1], ["mod:SHIFT", "Shift", 1.75], ["Up", "↑", 1], ["End", "End", 1]],
        [["mod:CONTROL", "Ctrl", 1.25], ["mod:SUPER", "Super", 1.25], ["mod:ALT", "Alt", 1.25], ["space", "Space", 6.25], ["mod:ALT", "Alt", 1], ["Menu", "Menu", 1], ["Left", "←", 1], ["Down", "↓", 1], ["Right", "→", 1], ["Insert", "Ins", 1]]
    ]
    readonly property var keys: {
        const out = [];
        for (let r = 0; r < rows.length; r++) {
            let x = 0;
            for (const k of rows[r]) { out.push({ id: k[0], legend: k[1], w: k[2], x: x, row: r }); x += k[2]; }
        }
        return out;
    }

    readonly property string combo: mods.slice().sort().join("+")
    // "mods|tuş" -> o birleşimdeki kısayollar
    readonly property var table: {
        const t = {};
        for (const b of binds) {
            if (b.disabled) continue;
            const k = KeybindsStore.norm(b.keys);
            (t[k] = t[k] ?? []).push(b);
        }
        return t;
    }
    readonly property var otherKeys: {
        const s = {};
        for (const b of binds) if (!b.disabled) s[KeybindsStore.aliasKey(KeybindsStore.parse(b.keys).key)] = true;
        return s;
    }
    function at(keyId) { return table[combo + "|" + keyId.toLowerCase()] ?? []; }

    // tuş -> { birleşim: [kısayollar] }; üzerine gelince "başka hangi birleşimlerde var" göstermek için
    readonly property var byKey: {
        const t = {};
        for (const b of binds) {
            if (b.disabled) continue;
            const p = KeybindsStore.parse(b.keys);
            const k = KeybindsStore.aliasKey(p.key), c = p.mods.slice().sort().join("+");
            t[k] = t[k] ?? {};
            (t[k][c] = t[k][c] ?? []).push(b);
        }
        return t;
    }
    function modsName(combo) {
        if (combo === "") return Translation.tr("no modifier");
        const ids = combo.split("+");
        return KeybindsStore.modOrder.filter(m => ids.includes(m)).map(m => m === "CONTROL" ? "Ctrl" : m.charAt(0) + m.slice(1).toLowerCase()).join(" + ");
    }
    function tipFor(keyId) {
        const k = keyId.toLowerCase(), here = at(keyId), all = byKey[k] ?? {};
        const others = Object.keys(all).filter(c => c !== combo);
        if (here.length === 0 && others.length === 0) return "";
        const lines = [];
        if (here.length === 0) lines.push(Translation.tr("Not assigned with the selected modifiers"));
        else if (here.length === 1) lines.push(here[0].label);
        else {
            lines.push(Translation.tr("%1 shortcuts share this key combination").replace("%1", here.length));
            here.forEach(h => lines.push("•  " + h.label));
        }
        if (others.length > 0) {
            const shown = others.slice(0, 5).map(c => modsName(c) + (all[c].length > 1 ? " ×" + all[c].length : ""));
            lines.push(Translation.tr("Also with:") + " " + shown.join(", ") + (others.length > 5 ? "  +" + (others.length - 5) : ""));
        }
        return lines.join("\n");
    }

    readonly property var palette: [
        { bg: Appearance.m3colors.m3primaryContainer, fg: Appearance.m3colors.m3onPrimaryContainer },
        { bg: Appearance.m3colors.m3secondaryContainer, fg: Appearance.m3colors.m3onSecondaryContainer },
        { bg: Appearance.m3colors.m3tertiaryContainer, fg: Appearance.m3colors.m3onTertiaryContainer },
        { bg: Appearance.m3colors.m3primary, fg: Appearance.m3colors.m3onPrimary },
        { bg: Appearance.m3colors.m3secondary, fg: Appearance.m3colors.m3onSecondary },
        { bg: Appearance.m3colors.m3tertiary, fg: Appearance.m3colors.m3onTertiary }
    ]
    function paletteFor(cat) { return palette[Math.max(0, categories.indexOf(cat)) % palette.length]; }

    Repeater {
        model: root.keys
        Item {
            id: cap
            required property var modelData
            readonly property bool isMod: modelData.id.startsWith("mod:")
            readonly property string modName: isMod ? modelData.id.slice(4) : ""
            readonly property var hits: isMod ? [] : root.at(modelData.id)
            readonly property bool lit: hits.length > 0
            readonly property bool active: isMod && root.mods.includes(modName)
            readonly property bool sel: !isMod && root.selected === modelData.id.toLowerCase()
            readonly property bool clash: hits.some(h => h.clash)
            readonly property bool other: !isMod && !lit && !!root.otherKeys[modelData.id.toLowerCase()]
            readonly property var pal: lit ? root.paletteFor(hits[0].category) : null
            readonly property string tip: isMod ? "" : root.tipFor(modelData.id)

            x: root.xOff + modelData.x * root.unit
            y: modelData.row * root.unit + (modelData.row > 0 ? root.unit * 0.4 : 0)
            width: modelData.w * root.unit - root.gap
            height: root.unit - root.gap

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: cap.active ? Appearance.colors.colPrimary
                     : cap.lit ? cap.pal.bg
                     : cma.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                border.width: cap.sel ? 2 : 1
                border.color: cap.sel ? Appearance.colors.colOnLayer1
                            : cap.clash ? Appearance.m3colors.m3error
                            : Appearance.colors.colLayer0Border
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                StyledText {
                    anchors.centerIn: parent
                    text: cap.modelData.legend
                    font.pixelSize: Math.max(10, root.unit * 0.26)
                    font.weight: cap.lit || cap.active ? Font.Bold : Font.Normal
                    color: cap.active ? Appearance.m3colors.m3onPrimary
                         : cap.lit ? cap.pal.fg
                         : cap.isMod ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive
                }
                // başka birleşimde kullanılıyor
                Rectangle {
                    visible: cap.other
                    x: parent.width - 10; y: 5
                    width: 5; height: 5; radius: 3
                    color: Appearance.colors.colOnLayer1Inactive
                }
                // aynı tuşta birden çok kısayol
                Rectangle {
                    visible: cap.hits.length > 1
                    x: 5; y: 5
                    width: 6; height: 6; radius: 3
                    color: cap.clash ? Appearance.m3colors.m3error : cap.pal ? cap.pal.fg : "transparent"
                }
            }
            StyledToolTip {
                extraVisibleCondition: cma.containsMouse && cap.tip !== ""
                text: cap.tip
            }
            MouseArea {
                id: cma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (cap.isMod) {
                        root.modToggled(cap.modName);
                    } else {
                        root.keyClicked(cap.modelData.id, cap.modelData.legend);
                    }
                }
            }
        }
    }
}
