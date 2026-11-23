-- Yüzen pencere monitör değiştirince: o monitörde son bıraktığı konum/boyut varsa oraya döner, yoksa
-- ekrana sığacak biçimde küçülür/içeri itilir (ekran dışında kalmasın). Konumlar monitör başına, monitöre
-- göreli saklanır; takas/taşıma olayında pencere yeni monitördeyken eski konumu bilinmediğinden yoklanır.
local geom = {}

local function snapshot()
    for _, win in ipairs(hl.get_windows()) do
        if win.floating and win.mapped and win.monitor and not win.hidden then
            local m = win.monitor
            geom[win.address] = geom[win.address] or {}
            geom[win.address][m.name] = { x = win.at.x - m.x, y = win.at.y - m.y, w = win.size.x, h = win.size.y }
        end
    end
end
hl.timer(snapshot, { timeout = 500, type = "repeat" })
hl.on("window.close", function(win) if win then geom[win.address] = nil end end)

local function fit_to_monitor(win)
    if not win or not win.floating or not win.monitor then return end
    local mon = win.monitor
    local mw, mh = mon.width / mon.scale, mon.height / mon.scale
    local saved = geom[win.address] and geom[win.address][mon.name]
    local w, h = win.size.x, win.size.y
    local x, y = win.at.x, win.at.y
    if saved then w, h, x, y = saved.w, saved.h, mon.x + saved.x, mon.y + saved.y end
    local nw, nh = math.min(w, mw * 0.95), math.min(h, mh * 0.95)
    local nx = math.max(mon.x, math.min(x, mon.x + mw - nw))
    local ny = math.max(mon.y, math.min(y, mon.y + mh - nh))
    if nw ~= win.size.x or nh ~= win.size.y then
        hl.dispatch(hl.dsp.window.resize({ x = nw, y = nh, window = win }))
    end
    hl.dispatch(hl.dsp.window.move({ x = nx, y = ny, window = win }))
end

hl.on("window.move_to_workspace", fit_to_monitor)

-- Çalışma alanı takaslarında pencereler monitörle birlikte geçer.
hl.on("workspace.move_to_monitor", function()
    for _, win in ipairs(hl.get_windows()) do fit_to_monitor(win) end
end)
