pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Tek kısayol kartı: tuşlar, ad, kategori ve durum rozetleri.
RippleButton {
    id: root

    required property var bind
    property bool selected: false
    property bool showCategory: false

    readonly property var tokens: {
        const p = KeybindsStore.parse(bind.keys);
        const tap = p.key === "SUPER_L" || p.key === "SUPER_R";   // "Super" tuşuna basıp bırakma: değiştirici tekrarı gösterilmez
        const names = p.mods.filter(m => !(tap && m === "SUPER")).map(m => m === "CONTROL" ? "Ctrl" : m.charAt(0) + m.slice(1).toLowerCase());
        return names.concat(p.key === "" ? [] : [KeybindsStore.prettyKey(p.key)]);
    }

    implicitHeight: content.implicitHeight + 20
    buttonRadius: Appearance.rounding.normal
    toggled: selected
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    opacity: bind.disabled ? 0.55 : 1

    contentItem: ColumnLayout {
        id: content
        spacing: 6

        Flow {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: root.tokens
                KeyboardKey {
                    required property string modelData
                    key: modelData
                    pixelSize: Appearance.font.pixelSize.small
                    horizontalPadding: 7
                    verticalPadding: 2
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.bind.label
            font.pixelSize: Appearance.font.pixelSize.normal
            font.strikeout: root.bind.disabled
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                visible: root.showCategory
                text: root.bind.category
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1Inactive
                elide: Text.ElideRight
            }
            Item { Layout.fillWidth: true; visible: !root.showCategory }
            Repeater {
                model: [
                    { on: root.bind.clash, icon: "warning", tip: Translation.tr("Conflicts with another shortcut") },
                    { on: root.bind.custom, icon: "add_circle", tip: Translation.tr("Added by you") },
                    { on: root.bind.remapped, icon: "edit", tip: Translation.tr("Key changed") },
                    { on: root.bind.disabled, icon: "block", tip: Translation.tr("Disabled") }
                ].filter(x => x.on)
                MaterialSymbol {
                    required property var modelData
                    text: modelData.icon
                    iconSize: Appearance.font.pixelSize.normal
                    color: modelData.icon === "warning" ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1Inactive
                }
            }
        }
    }
}
