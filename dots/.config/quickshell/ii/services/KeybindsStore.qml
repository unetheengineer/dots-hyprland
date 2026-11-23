pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Kısayol deposu. hyprland/keybind-layer.lua her açılışta manifest yazar (tanımlı tüm kısayollar);
 * kullanıcı değişiklikleri keybinds.json'da durur ve custom/keybind-overrides.lua olarak üretilir.
 * Kaydedince hyprctl reload ile uygulanır.
 */
Singleton {
    id: root

    readonly property string manifestPath: (Quickshell.env("XDG_STATE_HOME") || Directories.home + "/.local/state") + "/quickshell/user/keybinds-manifest.json"
    readonly property string userPath: FileUtils.trimFileProtocol(Directories.shellConfig + "/keybinds.json")
    readonly property string luaPath: FileUtils.trimFileProtocol(Directories.config) + "/hypr/custom/keybind-overrides.lua"

    property var manifest: []
    property var user: ({ changes: {}, custom: [] })
    property bool applying: false

    readonly property var modOrder: ["SUPER", "CONTROL", "ALT", "SHIFT"]

    // "SUPER + SHIFT + Q" -> { mods: [...], key }
    function parse(s) {
        const parts = String(s).split("+").map(x => x.trim()).filter(x => x !== "");
        const key = parts.length ? parts[parts.length - 1] : "";
        const mods = parts.slice(0, -1).map(m => m.toUpperCase()).map(m => m === "CTRL" ? "CONTROL" : m === "MOD" ? "SUPER" : m);
        return { mods: modOrder.filter(m => mods.includes(m)).concat(mods.filter(m => !modOrder.includes(m))), key };
    }
    function compose(mods, key) {
        const ordered = modOrder.filter(m => mods.includes(m)).concat(mods.filter(m => !modOrder.includes(m)));
        return ordered.concat(key === "" ? [] : [key]).join(" + ");
    }
    // Aynı fiziksel tuşun farklı yazımları (code:10 = 1 ...) tek ada iner; çakışma ve klavye eşlemesi buna dayanır.
    function aliasKey(key) {
        const m = /^code:(\d+)$/.exec(key);
        if (!m) return key.toLowerCase();
        const n = parseInt(m[1]);
        if (n >= 10 && n <= 18) return String(n - 9);
        if (n === 19) return "0";
        return key.toLowerCase();
    }
    function norm(keys) { const p = parse(keys); return p.mods.slice().sort().join("+") + "|" + aliasKey(p.key); }
    // Gösterim adı: code:82 -> Num −
    function prettyKey(key) {
        const m = /^code:(\d+)$/.exec(key);
        if (m) {
            const n = parseInt(m[1]);
            const kp = { 79: "7", 80: "8", 81: "9", 82: "−", 83: "4", 84: "5", 85: "6", 86: "+", 87: "1", 88: "2", 89: "3", 90: "0", 91: ".", 63: "*", 106: "/" };
            if (kp[n] !== undefined) return "Num " + kp[n];
            const a = aliasKey(key);
            if (a !== key.toLowerCase()) return a;
        }
        const mouse = { "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click", "mouse:275": "Mouse back", "mouse:276": "Mouse forward",
                        mouse_up: "Scroll up", mouse_down: "Scroll down", mouse_left: "Scroll left", mouse_right: "Scroll right" };
        if (mouse[key] !== undefined) return mouse[key];
        const names = { SUPER_L: "Super", SUPER_R: "Super (R)", BracketLeft: "[", BracketRight: "]", Prior: "PgUp", Next: "PgDn", BackSpace: "⌫", Return: "Enter", SPACE: "Space",
                        Slash: "/", Period: ".", Comma: ",", Semicolon: ";", Apostrophe: "'", Equal: "=", Minus: "-", Backslash: "\\",
                        bracketleft: "[", bracketright: "]", grave: "`" };
        return names[key] ?? key;
    }

    function humanize(s) {
        const t = String(s).replace(/[_-]+/g, " ").replace(/([a-z0-9])([A-Z])/g, "$1 $2").trim().toLowerCase();
        return t.charAt(0).toUpperCase() + t.slice(1);
    }

    // Açıklaması olmayan kısayolun kaynak satırından ad ve kategori çıkar.
    function infer(src) {
        const T = Translation.tr;
        const rules = [
            [/focus\(\{\s*workspace/, "Go to workspace", "Workspace"],
            [/window\.move\(\{\s*workspace/, "Move window to workspace", "Workspace"],
            [/focus\(\{\s*direction/, "Focus window", "Window"],
            [/numpadkey|numberkey/, "Go to workspace", "Workspace"],
            [/zoomfunction/, "Zoom screen", "Screen"],
            [/toggle_special/, "Scratchpad", "Workspace"],
            [/splitratio/, "Resize split", "Window"],
            [/window\.resize/, "Resize window", "Window"],
            [/window\.drag/, "Drag window", "Window"],
            [/searchToggle/, "Toggle search", "Shell"],
            [/window\.close|killactive/, "Close window", "Window"],
        ];
        for (const [re, label, cat] of rules) if (re.test(src)) return { label: T(label), category: cat };
        let m = /global\(\s*"quickshell:([A-Za-z0-9_]+)"/.exec(src);
        if (m) return { label: humanize(m[1]), category: "Shell" };
        m = /exec_cmd\(\s*([^)]*)/.exec(src);
        if (m) {
            const lit = /"([^"]{1,60})/.exec(m[1]);
            const word = lit ? lit[1] : m[1].split(/[ ,.]/)[0];
            return { label: word.replace(/\$[A-Za-z]+\/?/g, "").trim() || humanize(m[1].slice(0, 30)), category: "Commands" };
        }
        m = /dsp\.(window|focus|workspace|layout|group|cursor)\.?([A-Za-z_]*)/.exec(src);
        if (m) {
            const cat = { window: "Window", focus: "Window", workspace: "Workspace", layout: "Window", group: "Window", cursor: "Window" }[m[1]];
            return { label: humanize(m[2] || m[1]), category: cat };
        }
        m = /dsp\.([A-Za-z_.]+)/.exec(src);
        if (m) return { label: humanize(m[1].split(".").pop()), category: "Other" };
        return { label: "", category: "Other" };
    }

    function customOf(id) { return (user.custom ?? []).find(c => c.id === id); }

    readonly property var binds: {
        const out = [];
        const counts = {};
        for (const e of manifest) {
            const ch = user.changes?.[e.id] ?? {};
            const keys = e.newKeys ?? e.keys;
            const c = e.custom ? customOf(e.id) : null;
            let label = e.desc ?? "", category = "";
            const ci = label.indexOf(":");
            if (ci > 0 && ci < 24 && !e.custom) { category = label.slice(0, ci).trim(); label = label.slice(ci + 1).trim(); }
            if (e.custom) category = "Custom";
            if (label === "" || category === "") {
                const g = infer(e.src ?? "");
                if (label === "") label = g.label;
                if (category === "") category = g.category;
            }
            if (label === "") label = keys;
            const b = {
                id: e.id, keys, origKeys: e.keys, disabled: e.disabled === true, custom: e.custom === true,
                label, category, src: e.src ?? "", file: e.file ?? "", line: e.line ?? 0,
                flags: e.flags ?? [], flagMap: c?.flags ?? {}, command: c?.command ?? "", action: c?.action ?? "exec",
                renamed: ch.description !== undefined, remapped: e.newKeys !== null && e.newKeys !== undefined,
                clash: false,
                internal: (e.flags ?? []).includes("ignore_mods") && (e.flags ?? []).includes("transparent"),
            };
            out.push(b);
            if (!b.disabled) { const n = norm(keys); (counts[n] = counts[n] ?? []).push(b); }
        }
        // Çakışma: aynı tuşu kullanan etkin kayıtlardan biri kullanıcı değişikliği/eklemesiyse işaretle
        // (end-4'ün bilerek ikiledikleri çakışma sayılmaz).
        for (const n in counts) {
            const list = counts[n];
            if (list.length > 1 && list.some(b => b.custom || b.remapped)) list.forEach(b => b.clash = true);
        }
        return out;
    }
    readonly property var categories: {
        const seen = [];
        for (const b of binds) if (!seen.includes(b.category)) seen.push(b.category);
        return seen;
    }
    readonly property int clashCount: binds.filter(b => b.clash).length
    readonly property int changedCount: binds.filter(b => b.custom || b.remapped || b.disabled || b.renamed).length

    function bindById(id) { return binds.find(b => b.id === id) ?? null; }

    // --- değişiklikler ---
    function mutate(fn) {
        const u = JSON.parse(JSON.stringify(user));
        u.changes = u.changes ?? {}; u.custom = u.custom ?? [];
        fn(u);
        user = u;
        commit();
    }
    function patchChange(id, patch, origKeys) {
        mutate(u => {
            const c = Object.assign({}, u.changes[id] ?? {}, patch);
            if (c.keys !== undefined && norm(c.keys) === norm(origKeys)) delete c.keys;
            if (c.disabled !== true) delete c.disabled;
            if (c.description === undefined || c.description === "") delete c.description;
            if (Object.keys(c).length === 0) delete u.changes[id]; else u.changes[id] = c;
        });
    }
    function setKeys(id, keys) {
        const b = bindById(id);
        if (!b) return;
        if (b.custom) mutate(u => { const c = u.custom.find(x => x.id === id); if (c) c.keys = keys; });
        else patchChange(id, { keys }, b.origKeys);
    }
    function setDisabled(id, on) {
        const b = bindById(id);
        if (!b) return;
        if (b.custom) mutate(u => { const c = u.custom.find(x => x.id === id); if (c) c.disabled = on; });
        else patchChange(id, { disabled: on }, b.origKeys);
    }
    function setLabel(id, text) {
        const b = bindById(id);
        if (!b) return;
        if (b.custom) mutate(u => { const c = u.custom.find(x => x.id === id); if (c) c.label = text; });
        else patchChange(id, { description: text === "" ? undefined : text }, b.origKeys);
    }
    function updateCustom(id, patch) { mutate(u => { const c = u.custom.find(x => x.id === id); if (c) Object.assign(c, patch); }); }
    function reset(id) { mutate(u => { delete u.changes[id]; }); }
    function remove(id) { mutate(u => { u.custom = u.custom.filter(c => c.id !== id); }); }
    function add(entry) {
        const id = "custom:" + Date.now().toString(36);
        mutate(u => { u.custom.push(Object.assign({ id, action: "exec", flags: {} }, entry)); });
        return id;
    }
    function resetAll() { mutate(u => { u.changes = {}; u.custom = []; }); }

    // --- yazma ---
    function luaStr(s) {
        const clean = String(s).split("").map(c => { const n = c.charCodeAt(0); return n < 32 || n === 0x2028 || n === 0x2029 ? " " : c; }).join("");
        return JSON.stringify(clean);
    }
    function luaText(u) {
        let t = "-- Keybinds sayfası tarafından üretilir; elle düzenleme.\nreturn {\n  changes = {\n";
        for (const id in u.changes) {
            const c = u.changes[id], f = [];
            if (c.keys) f.push("keys = " + luaStr(c.keys));
            if (c.disabled) f.push("disabled = true");
            if (c.description) f.push("description = " + luaStr(c.description));
            t += "    [" + luaStr(id) + "] = { " + f.join(", ") + " },\n";
        }
        t += "  },\n  custom = {\n";
        for (const c of u.custom) {
            if (c.disabled) continue;
            const fl = Object.keys(c.flags ?? {}).filter(k => c.flags[k]).map(k => k + " = true").join(", ");
            t += "    { id = " + luaStr(c.id) + ", keys = " + luaStr(c.keys ?? "") + ", label = " + luaStr(c.label ?? "")
                + ", action = " + luaStr(c.action ?? "exec") + ", command = " + luaStr(c.command ?? "") + ", flags = { " + fl + " } },\n";
        }
        return t + "  },\n}\n";
    }
    function commit() {
        userFile.setText(JSON.stringify(user, null, 2));
        luaFile.setText(luaText(user));
        applying = true;
        reloadTimer.restart();
    }

    Timer {
        id: reloadTimer
        interval: 400
        onTriggered: { Quickshell.execDetached(["hyprctl", "reload"]); settle.restart(); }
    }
    Timer { id: settle; interval: 1500; onTriggered: root.applying = false }

    FileView {
        id: manifestFile
        path: root.manifestPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.manifest = JSON.parse(text()); } catch (e) { console.warn("[KeybindsStore] manifest okunamadı:", e); } }
    }
    FileView {
        id: userFile
        path: root.userPath
        printErrors: false
        onLoaded: { try { root.user = JSON.parse(text()); } catch (e) { console.warn("[KeybindsStore] keybinds.json okunamadı:", e); } }
    }
    FileView {
        id: luaFile
        path: root.luaPath
        printErrors: false
    }
}
