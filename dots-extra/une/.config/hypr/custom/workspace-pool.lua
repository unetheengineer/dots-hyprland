-- Ortak çalışma alanı havuzu: iki monitörde çalışma alanları monitöre bağlı sayılmaz.
-- Gezinme, diğer monitörde görünen dışındaki tüm çalışma alanlarını dolaşır; seçilen çalışma alanı
-- odaktaki monitöre gelir. Çalışma alanı sayısı/numaraları end-4'ün kısayollarına dokunmaz.
local MON1 = "DP-1"      -- birincil monitör
local MON2 = "HDMI-A-1"  -- ikincil monitör

-- Çalışma alanı animasyonu end-4 varsayılanıdır (general.lua); takasta geçici olarak dikey kayar.
local function workspace_anim(style)
    hl.animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "menu_decel", style = style })
end

-- Her iki monitörün etkin çalışma alanlarını takas eder (monitörler üst üste: dikey kayar).
local function swap_monitors()
    workspace_anim("slidevert")
    hl.timer(function() workspace_anim("slide") end, { timeout = 600, type = "oneshot" })
    hl.dispatch(hl.dsp.workspace.swap_monitors({ monitor1 = MON1, monitor2 = MON2 }))
end

-- Komşu çalışma alanı adayı: o monitöre bağlı olanlar ve başka monitörde şu an görünen dışındakiler.
local function in_pool(ws, mon_id)
    if not ws.monitor then return false end
    if ws.monitor.id == mon_id then return true end
    return not (ws.monitor.active_workspace and ws.monitor.active_workspace.id == ws.id)
end

-- Komşu çalışma alanı kimliği (uçlarda sarmaz); create_at_end ise sondan sonra boş bir kimlik döner.
local function neighbor_workspace(mon_id, current, delta, create_at_end)
    local used, target = {}, nil
    for _, ws in ipairs(hl.get_workspaces()) do
        if ws.id and ws.id > 0 then -- kapanmakta olan çalışma alanının kimliği boş gelebilir
            used[ws.id] = true -- bütün monitörlerdeki kimlikler, başkasınınkini çalmayalım
            if in_pool(ws, mon_id) then
                if delta > 0 and ws.id > current then
                    if not target or ws.id < target then target = ws.id end
                elseif delta < 0 and ws.id < current then
                    if not target or ws.id > target then target = ws.id end
                end
            end
        end
    end

    if not target and create_at_end then
        target = current + 1
        while used[target] do target = target + 1 end
    end
    return target
end

-- Animasyonları 150 ms kapatıp işlemi yapar: bir çalışma alanı başka monitörden getirilirken pencereler
-- eski monitörün koordinatından kayarak gelir ve kaydırma animasyonuyla çakışır.
local function quiet(fn)
    hl.config({ animations = { enabled = false } })
    fn()
    hl.timer(function() hl.config({ animations = { enabled = true } }) end, { timeout = 150, type = "oneshot" })
end

local function on_other_monitor(id, mon_id)
    for _, ws in ipairs(hl.get_workspaces()) do
        if ws.id == id then return ws.monitor ~= nil and ws.monitor.id ~= mon_id end
    end
    return false
end

-- Çalışma alanına, hangi monitöre bağlı olursa olsun odaktaki monitörde geçer
-- (başka monitörde görünüyorsa iki monitör çalışma alanlarını değiştirir).
local function focus_on_current(target)
    local mon = hl.get_monitor_at_cursor()
    local go = function() hl.dispatch(hl.dsp.focus({ workspace = target, on_current_monitor = true })) end
    local id = tonumber(target)
    if mon and id and on_other_monitor(id, mon.id) then quiet(go) else go() end
end

local function has_windows(ws_id)
    for _, w in ipairs(hl.get_windows()) do
        if w.workspace and w.workspace.id == ws_id then return true end
    end
    return false
end

-- İmlecin olduğu monitörde komşu çalışma alanına geçer; uçlarda başa sarmaz.
-- Sondan sonrası yeni çalışma alanı yalnızca bulunduğun çalışma alanında pencere varsa açılır (boştan boşa zincirleme açılmasın).
local function step_workspace(delta, create_at_end)
    return function()
        local mon = hl.get_monitor_at_cursor()
        if not mon or not mon.active_workspace then return end

        local create = create_at_end and has_windows(mon.active_workspace.id)
        local target = neighbor_workspace(mon.id, mon.active_workspace.id, delta, create)
        if not target then return end
        if not mon.focused then hl.dispatch(hl.dsp.focus({ monitor = mon.name })) end
        focus_on_current(target)
    end
end

local function focus_workspace(ws)
    return function()
        local delta = tostring(ws):match("^m([+-]%d+)$")
        if delta then step_workspace(tonumber(delta), false)() else focus_on_current(ws) end
    end
end

-- Odaktaki pencereyi komşu çalışma alanına taşır. Hedef başka monitöre bağlıysa önce bu monitöre alınır,
-- pencere gizli bir monitörde kaybolmasın.
local function move_window_step(delta, create_at_end)
    return function()
        local win = hl.get_active_window()
        if not win or not win.monitor or not win.workspace then return end

        local target = neighbor_workspace(win.monitor.id, win.workspace.id, delta, create_at_end)
        if not target then return end
        for _, ws in ipairs(hl.get_workspaces()) do
            if ws.id == target and ws.monitor and ws.monitor.id ~= win.monitor.id then
                quiet(function() hl.dispatch(hl.dsp.workspace.move({ workspace = target, monitor = win.monitor.name })) end)
                break
            end
        end
        hl.dispatch(hl.dsp.window.move({ workspace = target }))
    end
end

-- end-4'ün göreli çalışma alanı kısayollarının yerine havuza duyarlı olanlar.
hl.unbind("CTRL + SUPER + Left")
hl.unbind("CTRL + SUPER + Right")
hl.bind("CTRL + SUPER + Right", focus_workspace("m+1"), { description = "Workspace: Pool next" })
hl.bind("CTRL + SUPER + Left", focus_workspace("m-1"), { description = "Workspace: Pool previous" })
hl.bind("CTRL + SUPER + Down", focus_workspace("emptym"), { description = "Workspace: Pool next empty" })
hl.bind("SUPER + mouse_right", step_workspace(-1, false), { description = "Workspace: Pool previous (horizontal wheel)" })
hl.bind("SUPER + mouse_left", step_workspace(1, true), { description = "Workspace: Pool next (horizontal wheel)" })
hl.bind("SUPER + SHIFT + mouse_right", move_window_step(-1, false), { description = "Window: Send to previous pool workspace" })
hl.bind("SUPER + SHIFT + mouse_left", move_window_step(1, true), { description = "Window: Send to next pool workspace" })
hl.unbind("SUPER + X") -- end-4: metin düzenleyici
hl.bind("SUPER + X", swap_monitors, { description = "Workspace: Swap monitors" })
hl.bind("SUPER + mouse:276", swap_monitors)

-- ---------------------------------------------------------------------------------------------
-- end-4'ün 10'luk dilimleri (workspace_in_group) korunur; farkı: seçilen çalışma alanı odaktaki monitöre gelir
-- ve gezinme ortak havuzdadır. Aşağıda kısayollar buna çevrilir.
-- ---------------------------------------------------------------------------------------------

-- Hedef çalışma alanı başka monitörde gizliyse önce bu monitöre alır; pencere görünmez yerde kalmasın.
local function bring_here(target, mon)
    for _, ws in ipairs(hl.get_workspaces()) do
        if ws.id == target and ws.monitor and ws.monitor.id ~= mon.id
            and not (ws.monitor.active_workspace and ws.monitor.active_workspace.id == ws.id) then
            quiet(function() hl.dispatch(hl.dsp.workspace.move({ workspace = target, monitor = mon.name })) end)
            return
        end
    end
end

local function send_to_workspace(i)
    return function()
        local win = hl.get_active_window()
        if not win or not win.monitor then return end
        local id = workspace_in_group(i)
        bring_here(id, win.monitor)
        hl.dispatch(hl.dsp.window.move({ workspace = id, follow = false }))
    end
end

local function rebind(keys, fn, description)
    hl.unbind(keys)
    hl.bind(keys, fn, description and { description = description } or nil)
end

local numpad = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
for i = 1, 10 do
    local goto_ws = function() focus_on_current(workspace_in_group(i)) end
    rebind("SUPER + " .. (i % 10), goto_ws, "Workspace: Focus " .. i)
    rebind("SUPER + code:" .. (9 + i), goto_ws)
    rebind("SUPER + code:" .. numpad[i], goto_ws)
    local send = send_to_workspace(i)
    rebind("SUPER + ALT + " .. (i % 10), send, "Window: Send to workspace " .. i)
    rebind("SUPER + ALT + code:" .. numpad[i], send)
end

-- Göreli gezinme ve taşıma: havuzda bir sonraki/öncekine (sondan sonrası yeni çalışma alanı açar)
for _, k in ipairs({ "SUPER + Page_Down", "CTRL + SUPER + Page_Down", "SUPER + mouse_down", "CTRL + SUPER + mouse_down" }) do
    rebind(k, step_workspace(1, true))
end
for _, k in ipairs({ "SUPER + Page_Up", "CTRL + SUPER + Page_Up", "SUPER + mouse_up", "CTRL + SUPER + mouse_up" }) do
    rebind(k, step_workspace(-1, false))
end
for _, k in ipairs({ "SUPER + SHIFT + mouse_down", "SUPER + ALT + mouse_down", "SUPER + ALT + Page_Down", "CTRL + SUPER + SHIFT + Right" }) do
    rebind(k, move_window_step(1, true))
end
for _, k in ipairs({ "SUPER + SHIFT + mouse_up", "SUPER + ALT + mouse_up", "SUPER + ALT + Page_Up", "CTRL + SUPER + SHIFT + Left" }) do
    rebind(k, move_window_step(-1, false))
end
rebind("SUPER + SHIFT + Page_Down", move_window_step(1, true), "Window: Send to workspace right")
rebind("SUPER + SHIFT + Page_Up", move_window_step(-1, false), "Window: Send to workspace left")

-- Quickshell (çubuk göstergesi) havuz işlevlerini `hyprctl eval "POOL.step(1, true)()"` ile çağırır.
POOL = { step = step_workspace, send = move_window_step, go = focus_on_current }
