hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

hl.bind("SUPER + space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"), { locked = true, description = "Switch keyboard layout" })

require("custom.workspace-pool")

-- Eski dotfile'dan taşınanlar
hl.bind("SUPER + Escape", hl.dsp.window.close(), { description = "Window: Close (alternative)" })
hl.bind("SUPER + SHIFT + J", hl.dsp.layout("togglesplit"), { description = "Window: Toggle split direction" })
hl.bind("ALT + Tab", hl.dsp.window.cycle_next(), { description = "Window: Next window" })
hl.bind("ALT + Tab", hl.dsp.window.bring_to_top(), { description = "Window: Bring to front" })

-- Metin düzenleyici Super+X yerine Super+T'de (Super+X takas için kullanılıyor; Super+T end-4'te terminali ikinci kez açıyordu)
hl.unbind("SUPER + T")
hl.bind("SUPER + T", hl.dsp.exec_cmd(textEditor), { description = "App: Text editor" })
