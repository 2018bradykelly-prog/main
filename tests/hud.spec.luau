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

-- Compact by default, dismissible help, hide/restore -------------------------
check(ui.Main.Visible, "Status must start visible")
check(not ui.Details.Visible, "Instructions must not cover gameplay on spawn")
check(not ui.Restore.Visible, "Restore control starts hidden")
check(not ui.Screen.ResetOnSpawn, "Respawn must preserve the player's HUD preference")
check(not ui.Results.Visible and not ui.LobbyPanel.Visible and not ui.Splash.Visible, "Overlays start hidden")
for _, overlay in { ui.Blind, ui.Smoke, ui.Vignette } do
	check(overlay.BackgroundTransparency == 1 and not overlay.Active, "Effect overlays must start invisible and not eat input")
end
for _, viewport in { roblox.Vector2.new(1920, 1080), roblox.Vector2.new(800, 600), roblox.Vector2.new(360, 640), roblox.Vector2.new(640, 360) } do
	ui.resize(viewport)
	check(ui.Main.Size.X.Offset <= math.min(420, viewport.X - 24), "Status exceeds viewport/compact width")
	check(ui.Main.Size.Y.Offset == 92, "Status expanded to obstruct gameplay")
	local scale = ui.Details:FindFirstChildOfClass("UIScale").Scale
	check(ui.Details.Position.Y.Offset + ui.Details.Size.Y.Offset * scale < viewport.Y, "Instructions extend beyond viewport")
	local sideScale = ui.Results:FindFirstChildOfClass("UIScale").Scale
	check(ui.Results.Size.X.Offset * sideScale <= viewport.X - 24 + 0.01, "Results wider than the viewport")
	check(ui.Results.Size.Y.Offset * sideScale <= viewport.Y - 24 + 0.01, "Results taller than the viewport")
	check(ui.LobbyPanel.Size.Y.Offset * sideScale <= viewport.Y, "Lobby panel taller than the viewport")
end
ui.setHelpVisible(true)
check(ui.Details.Visible and ui.Close.Visible, "Help must have an accessible close control")
ui.setHelpVisible(false)
check(not ui.Details.Visible and ui.HelpButton.Text == "Help", "Close did not dismiss help")
ui.setHelpVisible(true)
ui.setHudVisible(false)
check(not ui.Main.Visible and not ui.Details.Visible and ui.Restore.Visible, "Hide must dismiss both panels and expose restore")
ui.Message.Text = "A new round is starting"
ui.resize(roblox.Vector2.new(360, 640))
check(not ui.Main.Visible and not ui.Details.Visible, "State/layout updates reopened dismissed panels")
ui.setHudVisible(true)
check(ui.Main.Visible and not ui.Details.Visible and not ui.Restore.Visible, "Restore should reopen only the compact status")
ui.setHudVisible(false)
ui.setHelpVisible(true)
check(ui.Main.Visible and ui.Details.Visible and not ui.Restore.Visible, "Keyboard help must restore accessible controls")
for _, button in { ui.HelpButton, ui.Close, ui.Hide, ui.Restore, ui.ResultsClose, ui.LobbyToggle, ui.ActionButton, ui.SpectatePrev, ui.SpectateNext } do
	check(button:IsA("TextButton") and button.Selectable and #button.Text > 0, "Controls must support button activation")
end

-- Team list -------------------------------------------------------------------
local red = roblox.Color3.fromRGB(255, 0, 0)
ui.setTeam({
	{ Name = "Alpha", Detail = "HTN · Healthy", Color = red },
	{ Name = "Beta", Detail = "Caged 20s", Color = red, Timer = 0.5 },
})
check(ui.Team.Visible, "Team panel should show with entries")
check(ui.TeamRows[1].Frame.Visible and ui.TeamRows[2].Frame.Visible and not ui.TeamRows[3].Frame.Visible, "Team rows visibility")
check(ui.TeamRows[2].TimerFill.Parent.Visible and not ui.TeamRows[1].TimerFill.Parent.Visible, "Cage timer only for caged survivors")
check(ui.TeamRows[2].TimerFill.Size.X.Scale == 0.5, "Cage timer fill")
ui.setTeam({})
check(not ui.Team.Visible, "Empty team hides the panel")

-- Ability bar -------------------------------------------------------------------
local buttons = ui.setAbilities({
	{ Id = "Sprint", Key = "Shift", Name = "Sprint" },
	{ Id = "Dash", Key = "Q", Name = "Mog Dash", Color = red },
})
check(buttons.Sprint and buttons.Dash, "Ability buttons created")
check(buttons.Dash.Button.Parent == ui.AbilityBar, "Ability buttons parented to the bar")
ui.setCooldown("Dash", 0.5, 9.2, false)
check(buttons.Dash.Cooldown.Size.Y.Scale == 0.5 and buttons.Dash.CooldownText.Text == "10", "Cooldown overlay")
ui.setCooldown("Dash", 0, 0, true)
check(buttons.Dash.CooldownText.Text == "", "Ready abilities show no countdown")
ui.setCooldown("Unknown", 1, 1)
buttons = ui.setAbilities({ { Id = "Attack", Key = "Click", Name = "Attack" } })
check(buttons.Dash == nil and buttons.Attack ~= nil, "Rebuilding the bar replaces old buttons")
local count = 0
for _, child in ui.AbilityBar:GetChildren() do
	if child:IsA("TextButton") then count += 1 end
end
check(count == 1, "Old ability buttons must be destroyed")

-- Toasts --------------------------------------------------------------------
for index = 1, 9 do
	ui.pushToast("Toast " .. index, red)
end
local toasts = 0
for _, child in ui.Toasts:GetChildren() do
	if child:IsA("TextLabel") then toasts += 1 end
end
check(toasts == 5, "Toast feed keeps only the newest five")

-- Lobby: loadout, votes, profile ------------------------------------------------
ui.setLobbyVisible(true)
check(ui.LobbyPanel.Visible and ui.LobbyToggle.Text == "Hide", "Lobby panel toggle")
ui.setLoadout({ { Id = "Dash", Name = "Mog Dash", Description = "Go", Color = red }, { Id = "Smoke", Name = "Fog", Description = "Hide" } }, "Smoke")
check(ui.LoadoutButtons.Dash and ui.LoadoutButtons.Smoke, "Loadout cards")
check(ui.LoadoutButtons.Smoke:FindFirstChildOfClass("UIStroke").Transparency == 0, "Selected loadout highlighted")
check(ui.LoadoutButtons.Dash:FindFirstChildOfClass("UIStroke").Transparency > 0.5, "Unselected loadout dimmed")
ui.setVotes({ { Id = "Labs", Name = "Looksmax Labs", Blurb = "x", Votes = 2 }, { Id = "Mall", Name = "Mewing Mall", Blurb = "y", Votes = 0 } }, "Labs", true)
check(ui.VoteButtons.Labs.Visible and ui.VoteButtons.Labs.Count.Text == "2", "Vote card counts")
ui.setVotes({ { Id = "Labs", Name = "Looksmax Labs", Blurb = "x", Votes = 2 } }, nil, false)
check(not ui.VoteButtons.Labs.Visible and not ui.VoteHeading.Visible, "Votes hide outside voting phases")
ui.setProfile(3, "Mewing Rookie", 50, 200, "Wins 1")
check(ui.ProfileLevel.Text == "LEVEL 3" and ui.XPFill.Size.X.Scale == 0.25, "Profile card")
ui.setLobbyVisible(false)
check(not ui.LobbyPanel.Visible and ui.LobbyToggle.Text == "Loadout", "Lobby panel hides")

-- Results -----------------------------------------------------------------------
ui.showResults("SURVIVORS WIN", red, "2 of 3 escaped", { "a", "b" })
check(ui.Results.Visible and ui.ResultRows[2].Visible and not ui.ResultRows[3].Visible, "Results rows")
print(string.format("PASS %d HUD construction, dismissal, panel and viewport checks", checks))
