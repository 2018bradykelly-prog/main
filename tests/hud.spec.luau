-- Exercise the real HUD factory against Lune's Roblox instance model.
-- Rendering and input delivery still require a Roblox Studio client.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local env = {}
for _, key in { "Instance", "Vector2", "Color3", "Enum", "UDim", "UDim2" } do env[key] = roblox[key] end
local Hud = luau.load(fs.readFile("src/client/Hud.luau"), { environment = env })()
local parent = roblox.Instance.new("PlayerGui")
local ui = Hud.create(parent)
local checks = 0
local function check(condition, message)
	assert(condition, message)
	checks += 1
end
check(ui.Main.Visible, "Status must start visible")
check(not ui.Details.Visible, "Instructions must not cover gameplay on spawn")
check(not ui.Restore.Visible, "Restore control starts hidden")
check(not ui.Screen.ResetOnSpawn, "Respawn must preserve the player's HUD preference")
for _, viewport in { roblox.Vector2.new(1920, 1080), roblox.Vector2.new(800, 600), roblox.Vector2.new(360, 640), roblox.Vector2.new(640, 360) } do
	ui.resize(viewport)
	check(ui.Main.Size.X.Offset <= math.min(400, viewport.X - 24), "Status exceeds viewport/compact width")
	check(ui.Main.Size.Y.Offset == 92, "Status expanded to obstruct gameplay")
	local scale = ui.Details:FindFirstChildOfClass("UIScale").Scale
	check(ui.Details.Position.Y.Offset + ui.Details.Size.Y.Offset * scale < viewport.Y, "Instructions extend beyond viewport")
end
ui.setHelpVisible(true)
check(ui.Details.Visible and ui.Close.Visible, "Help must have an accessible close control")
ui.setHelpVisible(false)
check(not ui.Details.Visible and ui.HelpButton.Text == "Help", "Close did not dismiss help")
ui.setHelpVisible(true)
ui.setHudVisible(false)
check(not ui.Main.Visible and not ui.Details.Visible and ui.Restore.Visible, "Hide must dismiss both panels and expose restore")
ui.Message.Text = "A new round is starting"
ui.Rank.Text = "Chad • 100 BP"
ui.resize(roblox.Vector2.new(360, 640))
check(not ui.Main.Visible and not ui.Details.Visible, "State/layout updates reopened dismissed panels")
ui.setHudVisible(true)
check(ui.Main.Visible and not ui.Details.Visible and not ui.Restore.Visible, "Restore should reopen only the compact status")
ui.setHudVisible(false)
ui.setHelpVisible(true)
check(ui.Main.Visible and ui.Details.Visible and not ui.Restore.Visible, "Keyboard help must restore accessible controls")
for _, button in { ui.HelpButton, ui.Close, ui.Hide, ui.Restore } do
	check(button:IsA("TextButton") and button.Selectable and #button.Text > 0, "Controls must support button activation")
end
print(string.format("PASS %d HUD construction, dismissal, restore and viewport checks", checks))
