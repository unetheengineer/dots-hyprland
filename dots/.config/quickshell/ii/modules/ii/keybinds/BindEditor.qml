pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Kısayol düzenleyici. Var olan kısayolda değişiklik anında uygulanır; yeni kısayol (draft) "Add" ile eklenir.
Rectangle {
    id: root

    property var bind: null          // var olan kısayol (KeybindsStore.binds öğesi)
    property var draft: null         // yeni kısayol taslağı
    signal closed()

    readonly property bool creating: draft !== null
    readonly property bool isCustom: creating || (bind?.custom ?? false)
    readonly property string curKeys: creating ? (draft.keys ?? "") : (bind?.keys ?? "")
    readonly property var parsed: KeybindsStore.parse(curKeys)
    property bool recording: false

    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    function applyKeys(k) {
        if (creating) draft = Object.assign({}, draft, { keys: k });
        else if (bind) KeybindsStore.setKeys(bind.id, k);
    }
    function toggleMod(m) {
        const mods = parsed.mods.includes(m) ? parsed.mods.filter(x => x !== m) : parsed.mods.concat([m]);
        applyKeys(KeybindsStore.compose(mods, parsed.key));
    }
    function setPatch(patch) {
        if (creating) draft = Object.assign({}, draft, patch);
        else if (bind) KeybindsStore.updateCustom(bind.id, patch);
    }
    function setFlag(name, on) {
        const f = Object.assign({}, creating ? draft.flags : bind.flagMap);
        if (on) f[name] = true; else delete f[name];
        setPatch({ flags: f });
    }

    function keyName(e) {
        const k = e.key;
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k);
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F24) return "F" + (k - Qt.Key_F1 + 1);
        const m = {};
        m[Qt.Key_Space] = "SPACE"; m[Qt.Key_Return] = "Return"; m[Qt.Key_Enter] = "Return"; m[Qt.Key_Tab] = "Tab"; m[Qt.Key_Backtab] = "Tab";
        m[Qt.Key_Backspace] = "BackSpace"; m[Qt.Key_Delete] = "Delete"; m[Qt.Key_Insert] = "Insert"; m[Qt.Key_Home] = "Home"; m[Qt.Key_End] = "End";
        m[Qt.Key_PageUp] = "Prior"; m[Qt.Key_PageDown] = "Next"; m[Qt.Key_Left] = "Left"; m[Qt.Key_Right] = "Right"; m[Qt.Key_Up] = "Up"; m[Qt.Key_Down] = "Down";
        m[Qt.Key_Comma] = "comma"; m[Qt.Key_Period] = "period"; m[Qt.Key_Minus] = "minus"; m[Qt.Key_Equal] = "equal"; m[Qt.Key_Slash] = "slash";
        m[Qt.Key_Backslash] = "backslash"; m[Qt.Key_Semicolon] = "semicolon"; m[Qt.Key_Apostrophe] = "apostrophe"; m[Qt.Key_BracketLeft] = "bracketleft";
        m[Qt.Key_BracketRight] = "bracketright"; m[Qt.Key_QuoteLeft] = "grave"; m[Qt.Key_Print] = "Print";
        return m[k] ?? "";
    }

    // Değiştiricisiz tuşa atama oturumu bozabilir: yalnızca medya tuşları ve Print serbest
    readonly property bool keysValid: {
        const k = parsed.key.toLowerCase();
        return k !== "" && (parsed.mods.length > 0 || k.startsWith("xf86") || k === "print");
    }

    StyledFlickable {
        anchors.fill: parent
        anchors.margins: 16
        contentHeight: col.implicitHeight
        clip: true

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: root.creating ? Translation.tr("New shortcut") : Translation.tr("Edit shortcut")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                RippleButton {
                    implicitWidth: 34; implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.closed()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            // Ad
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText { text: Translation.tr("Name"); color: Appearance.colors.colOnLayer1Inactive; font.pixelSize: Appearance.font.pixelSize.smaller }
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("What does it do?")
                    text: root.creating ? (root.draft.label ?? "") : (root.bind?.label ?? "")
                    onTextEdited: if (root.creating) root.draft = Object.assign({}, root.draft, { label: text })
                    onEditingFinished: if (!root.creating && root.bind && text !== root.bind.label) KeybindsStore.setLabel(root.bind.id, text)
                }
            }

            // Tuşlar
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                StyledText { text: Translation.tr("Keys"); color: Appearance.colors.colOnLayer1Inactive; font.pixelSize: Appearance.font.pixelSize.smaller }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ m: "SUPER", t: "Super" }, { m: "CONTROL", t: "Ctrl" }, { m: "ALT", t: "Alt" }, { m: "SHIFT", t: "Shift" }]
                        RippleButton {
                            required property var modelData
                            implicitHeight: 36
                            implicitWidth: label.implicitWidth + 28
                            buttonRadius: Appearance.rounding.full
                            toggled: root.parsed.mods.includes(modelData.m)
                            onClicked: root.toggleMod(modelData.m)
                            contentItem: StyledText {
                                id: label
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.t
                                color: parent.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: root.recording ? Translation.tr("Press a key…") : Translation.tr("Main key (e.g. Q, F5, Return)")
                        text: root.parsed.key
                        onEditingFinished: { const v = text.trim(); if (v !== root.parsed.key) root.applyKeys(KeybindsStore.compose(root.parsed.mods, v)); }
                    }
                    RippleButton {
                        implicitHeight: 40
                        implicitWidth: rec.implicitWidth + 24
                        buttonRadius: Appearance.rounding.full
                        toggled: root.recording
                        onClicked: { root.recording = !root.recording; if (root.recording) recorder.forceActiveFocus(); }
                        contentItem: StyledText {
                            id: rec
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: root.recording ? Translation.tr("Listening…") : Translation.tr("Record key")
                            color: parent.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
                StyledText {
                    visible: root.curKeys !== "" && !root.keysValid
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("Pick at least one modifier; a bare key can break typing.")
                    color: Appearance.m3colors.m3error
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                // Dinlerken fare tuşu ve tekerlek bu alana tıklanarak seçilir
                Rectangle {
                    visible: root.recording
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colPrimary
                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Click or scroll here for mouse buttons")
                        color: Appearance.colors.colOnLayer1Inactive
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        onPressed: e => {
                            const b = {}; b[Qt.LeftButton] = 272; b[Qt.RightButton] = 273; b[Qt.MiddleButton] = 274; b[Qt.BackButton] = 275; b[Qt.ForwardButton] = 276;
                            if (b[e.button] === undefined) return;
                            root.applyKeys(KeybindsStore.compose(root.parsed.mods, "mouse:" + b[e.button]));
                            root.recording = false;
                        }
                        onWheel: e => {
                            const n = e.angleDelta.y > 0 ? "mouse_up" : e.angleDelta.y < 0 ? "mouse_down" : e.angleDelta.x > 0 ? "mouse_right" : e.angleDelta.x < 0 ? "mouse_left" : "";
                            if (n === "") return;
                            root.applyKeys(KeybindsStore.compose(root.parsed.mods, n));
                            root.recording = false;
                        }
                    }
                }
                Item {
                    id: recorder
                    width: 0; height: 0
                    Keys.onPressed: e => {
                        if (!root.recording) return;
                        if (e.key === Qt.Key_Escape) { root.recording = false; e.accepted = true; return; }
                        const n = root.keyName(e);
                        if (n === "") return;
                        root.applyKeys(KeybindsStore.compose(root.parsed.mods, n));
                        root.recording = false;
                        e.accepted = true;
                    }
                }
            }

            // Eylem (yalnızca kendi eklediklerimiz)
            ColumnLayout {
                visible: root.isCustom
                Layout.fillWidth: true
                spacing: 6
                StyledText { text: Translation.tr("Action"); color: Appearance.colors.colOnLayer1Inactive; font.pixelSize: Appearance.font.pixelSize.smaller }
                RowLayout {
                    spacing: 6
                    Repeater {
                        model: [{ v: "exec", t: Translation.tr("Run command") }, { v: "global", t: Translation.tr("Shell action") }]
                        RippleButton {
                            required property var modelData
                            implicitHeight: 36
                            implicitWidth: al.implicitWidth + 28
                            buttonRadius: Appearance.rounding.full
                            toggled: (root.creating ? (root.draft.action ?? "exec") : (root.bind?.action ?? "exec")) === modelData.v
                            onClicked: root.setPatch({ action: modelData.v })
                            contentItem: StyledText {
                                id: al
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.t
                                color: parent.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
                MaterialTextField {
                    Layout.fillWidth: true
                    font.family: Appearance.font.family.monospace
                    placeholderText: (root.creating ? root.draft.action : root.bind?.action) === "global" ? "quickshell:overviewToggle" : "kitty -e btop"
                    text: root.creating ? (root.draft.command ?? "") : (root.bind?.command ?? "")
                    onTextEdited: if (root.creating) root.draft = Object.assign({}, root.draft, { command: text })
                    onEditingFinished: if (!root.creating && root.bind && text !== root.bind.command) KeybindsStore.updateCustom(root.bind.id, { command: text })
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ n: "locked", t: Translation.tr("Works when locked") }, { n: "repeating", t: Translation.tr("Repeat when held") }, { n: "release", t: Translation.tr("On key release") }]
                        RippleButton {
                            required property var modelData
                            readonly property var flagsNow: root.creating ? (root.draft.flags ?? {}) : (root.bind?.flagMap ?? {})
                            implicitHeight: 32
                            implicitWidth: fl.implicitWidth + 24
                            buttonRadius: Appearance.rounding.full
                            toggled: flagsNow[modelData.n] === true
                            onClicked: root.setFlag(modelData.n, !toggled)
                            contentItem: StyledText {
                                id: fl
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.t
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: parent.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }

            // Kaynak (varsayılan kısayollar)
            ColumnLayout {
                visible: !root.creating && !root.isCustom && (root.bind?.src ?? "") !== ""
                Layout.fillWidth: true
                spacing: 4
                StyledText { text: Translation.tr("Defined in"); color: Appearance.colors.colOnLayer1Inactive; font.pixelSize: Appearance.font.pixelSize.smaller }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: srcText.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    StyledText {
                        id: srcText
                        anchors { fill: parent; margins: 8 }
                        text: (root.bind?.src ?? "") + "\n" + (root.bind?.file ?? "").split("/").slice(-2).join("/") + ":" + (root.bind?.line ?? 0)
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1Inactive
                        wrapMode: Text.WrapAnywhere
                    }
                }
                RippleButton {
                    implicitHeight: 32
                    implicitWidth: of.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    onClicked: Quickshell.execDetached(["xdg-open", root.bind.file])
                    contentItem: StyledText {
                        id: of
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Open file")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            // Etkin
            RowLayout {
                visible: !root.creating
                Layout.fillWidth: true
                StyledText { Layout.fillWidth: true; text: Translation.tr("Enabled"); color: Appearance.colors.colOnLayer1 }
                StyledSwitch {
                    checked: !(root.bind?.disabled ?? false)
                    onClicked: if (root.bind) KeybindsStore.setDisabled(root.bind.id, !checked)
                }
            }

            // Eylemler
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                RippleButton {
                    visible: root.creating
                    enabled: root.keysValid && (root.draft?.command ?? "") !== ""
                    implicitHeight: 38
                    implicitWidth: ad.implicitWidth + 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: {
                        const d = root.draft;
                        KeybindsStore.add({ label: d.label || d.command, keys: d.keys, action: d.action ?? "exec", command: d.command, flags: d.flags ?? {} });
                        root.draft = null;
                        root.closed();
                    }
                    contentItem: StyledText {
                        id: ad
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Add")
                        color: Appearance.m3colors.m3onPrimary
                    }
                }
                RippleButton {
                    visible: !root.creating && !root.isCustom && ((root.bind?.remapped ?? false) || (root.bind?.renamed ?? false) || (root.bind?.disabled ?? false))
                    implicitHeight: 38
                    implicitWidth: rs.implicitWidth + 32
                    buttonRadius: Appearance.rounding.full
                    onClicked: KeybindsStore.reset(root.bind.id)
                    contentItem: StyledText {
                        id: rs
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Reset to default")
                        color: Appearance.colors.colOnLayer1
                    }
                }
                RippleButton {
                    visible: !root.creating && root.isCustom
                    implicitHeight: 38
                    implicitWidth: dl.implicitWidth + 32
                    buttonRadius: Appearance.rounding.full
                    onClicked: { const id = root.bind.id; root.closed(); KeybindsStore.remove(id); }
                    contentItem: StyledText {
                        id: dl
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Delete")
                        color: Appearance.m3colors.m3error
                    }
                }
            }
        }
    }
}
