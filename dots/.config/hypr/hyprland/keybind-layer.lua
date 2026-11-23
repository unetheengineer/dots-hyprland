-- Kısayol katmanı: hl.bind'ı sarar.
--  1) tanımlanan her kısayolu manifest'e yazar (Keybinds sayfası listeyi buradan okur),
--  2) kullanıcı değişikliklerini uygular (tuş değiştir / kapat / açıklama),
--  3) kullanıcının eklediği kısayolları tanımlar.
-- Değişiklikler custom/keybind-overrides.lua içinde durur; sayfa bu dosyayı üretir.
local home = os.getenv("HOME")
local statePath = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/quickshell/user/keybinds-manifest.json"

local ok, overrides = pcall(require, "custom.keybind-overrides")
if not ok or type(overrides) ~= "table" then overrides = {} end
local changes = overrides.changes or {}
local custom = overrides.custom or {}

local function normalize(keys)
    local parts = {}
    for p in tostring(keys):gmatch("[^+]+") do parts[#parts + 1] = p:match("^%s*(.-)%s*$") end
    local key = table.remove(parts) or ""
    local mods = {}
    for _, m in ipairs(parts) do
        m = m:upper()
        if m == "CTRL" then m = "CONTROL" elseif m == "MOD" then m = "SUPER" end
        mods[#mods + 1] = m
    end
    table.sort(mods)
    return table.concat(mods, "+") .. "|" .. key:lower()
end

local function esc(s)
    return (tostring(s):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
        return " "
    end))
end

-- Kaynak satırı: açıklaması olmayan kısayolların ne yaptığını sayfa buradan çıkarır.
local fileLines = {}
local function sourceLine(path, line)
    if not path or path == "" or line == 0 then return "" end
    if fileLines[path] == nil then
        fileLines[path] = {}
        local f = io.open(path, "r")
        if f then
            for l in f:lines() do fileLines[path][#fileLines[path] + 1] = l end
            f:close()
        end
    end
    local l = (fileLines[path][line] or ""):gsub("^%s+", "")
    -- çok satırlı çağrıda eylem sonraki satırda olur
    if l:match("[,(]%s*$") then l = l .. " " .. (fileLines[path][line + 1] or ""):gsub("^%s+", "") end
    return l:sub(1, 240)
end

local flagNames = { "locked", "repeating", "release", "mouse", "long_press", "ignore_mods", "transparent", "non_consuming" }

local entries, seen, dirty = {}, {}, false

local function write()
    local out = {}
    for _, e in ipairs(entries) do
        local fl = {}
        for _, n in ipairs(flagNames) do if e.flags[n] then fl[#fl + 1] = '"' .. n .. '"' end end
        out[#out + 1] = string.format(
            '{"id":"%s","keys":"%s","newKeys":%s,"disabled":%s,"desc":"%s","src":"%s","file":"%s","line":%d,"custom":%s,"flags":[%s]}',
            esc(e.id), esc(e.keys), e.newKeys and ('"' .. esc(e.newKeys) .. '"') or "null", tostring(e.disabled),
            esc(e.desc or ""), esc(e.src or ""), esc(e.file or ""), e.line or 0, tostring(e.custom == true), table.concat(fl, ","))
    end
    local f = io.open(statePath, "w")
    if f then f:write("[", table.concat(out, ",\n"), "]\n"); f:close() end
end

local rawBind = hl.bind

-- Hata olsa bile kısayol tanımlanmalı: izleme pcall içinde, asıl hl.bind her zaman çağrılır.
local function track(keys, opts, info, extra)
    local n = normalize(keys)
    seen[n] = (seen[n] or 0) + 1
    local id = (extra and extra.id) or (n .. "#" .. seen[n])
    local ch = changes[id] or {}
    local flags = {}
    for _, name in ipairs(flagNames) do if opts[name] then flags[name] = true end end
    local e = {
        id = id, keys = keys, newKeys = ch.keys, disabled = ch.disabled == true,
        desc = ch.description or opts.description, flags = flags,
        file = info and (info.source:sub(1, 1) == "@" and info.source:sub(2) or info.short_src) or "",
        line = info and info.currentline or 0,
        custom = extra ~= nil,
    }
    e.src = extra and "" or sourceLine(e.file, e.line)
    entries[#entries + 1] = e
    dirty = true
    return ch
end

local function bind(keys, dispatcher, opts, info, extra)
    opts = opts or {}
    local ok, ch = pcall(track, keys, opts, info, extra)
    if not ok then return rawBind(keys, dispatcher, opts) end
    if ch.disabled == true then return end
    local o = opts
    if ch.description then
        o = {}
        for k, v in pairs(opts) do o[k] = v end
        o.description = ch.description
    end
    return rawBind(ch.keys or keys, dispatcher, o)
end

-- Sonradan kaldırılan (hl.unbind) kısayollar listede kalmasın.
local rawUnbind = hl.unbind
hl.unbind = function(keys, ...)
    pcall(function()
        local n = normalize(keys)
        for i = #entries, 1, -1 do
            if normalize(entries[i].newKeys or entries[i].keys) == n then table.remove(entries, i); dirty = true end
        end
    end)
    return rawUnbind(keys, ...)
end

hl.bind = function(keys, dispatcher, opts)
    local r = bind(keys, dispatcher, opts, debug.getinfo(2, "Sl"))
    return r
end

-- Kullanıcının eklediği kısayollar
for _, c in ipairs(custom) do
    local dispatcher
    if c.action == "global" then dispatcher = hl.dsp.global(c.command or "")
    else dispatcher = hl.dsp.exec_cmd(c.command or "") end
    local opts = { description = c.label }
    for k, v in pairs(c.flags or {}) do opts[k] = v end
    bind(c.keys or "", dispatcher, opts, nil, { id = c.id })
end

hl.timer(function()
    if dirty then dirty = false; write() end
end, { timeout = 500, type = "repeat" })
