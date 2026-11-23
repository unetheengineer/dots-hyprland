hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

hl.bind("SUPER + space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"), { locked = true, description = "Switch keyboard layout" })

require("custom.workspace-pool")
