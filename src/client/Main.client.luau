--!strict
-- Presentation only. Roles, objectives, captures, and BP are owned by the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local Rules = require(shared:WaitForChild("Rules"))
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local Hud = require(script.Parent:WaitForChild("Hud"))
local colors = Hud.Colors
local label = Hud.label
local connections: { RBXScriptConnection } = {}
local destroyed = false
local ui = Hud.create(localPlayer:WaitForChild("PlayerGui"))
local screen, timer, role = ui.Screen, ui.Timer, ui.Role
local message, objective, progressFill = ui.Message, ui.Objective, ui.ProgressFill
local rank, nextRank, help = ui.Rank, ui.NextRank, ui.Help
local chaseWarning, dangerStroke = ui.ChaseWarning, ui.DangerStroke

table.insert(connections, ui.HelpButton.Activated:Connect(function()
	ui.setHelpVisible(not ui.Details.Visible)
end))
table.insert(connections, ui.Close.Activated:Connect(function() ui.setHelpVisible(false) end))
table.insert(connections, ui.Hide.Activated:Connect(function() ui.setHudVisible(false) end))
table.insert(connections, ui.Restore.Activated:Connect(function() ui.setHudVisible(true) end))
table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and not UserInputService:GetFocusedTextBox() and input.KeyCode == Enum.KeyCode.H then
		ui.setHelpVisible(not ui.Details.Visible)
	end
end))

local chaseSound = Instance.new("Sound")
chaseSound.Name = "ChadChase"
chaseSound.Looped = true
chaseSound.Volume = 0
local configuredAudio = tostring(Config.ChaseSoundId or "")
local hasAudio = configuredAudio:match("^rbxassetid://%d+$") ~= nil
if hasAudio then
	chaseSound.SoundId = configuredAudio
end
chaseSound.Parent = SoundService

local function stringAttribute(instance: Instance, name: string, fallback: string): string
	local value = instance:GetAttribute(name)
	return if type(value) == "string" then value else fallback
end

local function numberAttribute(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function updateHUD()
	local phase = stringAttribute(matchState, "Phase", "Waiting")
	local currentRole = stringAttribute(localPlayer, "Role", "Lobby")
	local status = stringAttribute(localPlayer, "Status", "Lobby")
	local seconds = math.max(0, math.ceil(numberAttribute(matchState, "TimeRemaining", 0)))
	local points = numberAttribute(localPlayer, "BP", 0)
	local currentRank = stringAttribute(localPlayer, "Rank", Rules.rankForBP(points))
	local completed = numberAttribute(matchState, "ObjectiveCount", 0)
	local goal = numberAttribute(matchState, "ObjectiveGoal", 0)
	timer.Text = if phase == "Waiting" then "--:--" else string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	local roleText = if currentRole == "Killer" then "OG CHAD" elseif currentRole == "Survivor" then "SURVIVOR" else "LOBBY"
	role.Text = roleText .. (if status == "Captured" or status == "Escaped" then " • " .. string.upper(status) else "")
	role.TextColor3 = if currentRole == "Killer" then colors.Killer else colors.Survivor
	message.Text = stringAttribute(matchState, "Message", "Waiting for more players...")
	if goal > 0 then
		objective.Text = string.format("TERMINAL %d/%d%s", completed, goal, if completed >= goal then " • EXIT OPEN" else "")
	else
		objective.Text = if phase == "Intermission" then "Round starting soon" else "Waiting for 2 players"
	end
	if phase == "Results" then objective.Text = "Round over • Help for results" end
	progressFill.Size = UDim2.fromScale(if goal > 0 then math.clamp(completed / goal, 0, 1) else 0, 1)
	if currentRole == "Survivor" then
		rank.Text = string.format("%s  •  %d BP", string.upper(currentRank), points)
		rank.TextColor3 = if currentRank == "Chad" then colors.Chad else colors.Survivor
		local upcoming = Rules.nextRank(points)
		nextRank.Text = if upcoming then string.format("%d BP until %s", math.max(0, upcoming.BP - points), upcoming.Name) else "CHAD ACHIEVED  •  Escape once the team powers the exit"
	else
		rank.Text = if currentRole == "Killer" then "Catch survivors on contact" else "ESCAPE THE CHAD"
		rank.TextColor3 = if currentRole == "Killer" then colors.Killer else colors.Muted
		nextRank.Text = "Fictional ranks. Very real cardio."
	end
	if status == "Captured" then
		help.Text = "CAPTURED  •  A teammate can rescue you at the cage. You will also be released when your capture timer expires."
	elseif status == "Escaped" then
		help.Text = "YOU ESCAPED  •  Your jawline has left the building. Wait here for the next round."
	elseif status == "Spectating" then
		help.Text = "You joined during a round. Relax in the lobby; you will enter the next match."
	elseif currentRole == "Killer" and phase == "Active" then
		help.Text = "Catch survivors by making contact. Guard the terminal and escape door. Captured survivors can be rescued."
	elseif currentRole == "Survivor" and phase == "Active" then
		help.Text = "Hold E at the cyan terminal for BP (6s cooldown). Reach Chad + power the exit to escape. Rescue allies at the cage."
	else
		help.Text = "One OG Chad. Everyone else starts LTN. Work together, climb the fictional ranks, and escape."
	end
end

-- A local billboard exists for every survivor, including players who join later.
-- AlwaysOnTop=false prevents rank labels from revealing survivors through walls.
type PlayerView = {
	Connections: { RBXScriptConnection },
	Gui: BillboardGui?,
	NameLabel: TextLabel?,
	RankLabel: TextLabel?,
	Generation: number,
}
local playerViews: { [Player]: PlayerView } = {}

local function refreshBillboard(player: Player)
	local view = playerViews[player]
	if not view or not view.Gui or not view.NameLabel or not view.RankLabel then
		return
	end
	local currentRole = stringAttribute(player, "Role", "Lobby")
	local status = stringAttribute(player, "Status", "Lobby")
	view.Gui.Enabled = currentRole == "Survivor" and (status == "Alive" or status == "Captured")
	view.NameLabel.Text = player.DisplayName
	view.RankLabel.Text = stringAttribute(player, "Rank", "LTN") .. (if status == "Captured" then " • CAPTURED" else "")
	view.RankLabel.TextColor3 = if status == "Captured" then colors.Danger elseif player:GetAttribute("Rank") == "Chad" then colors.Chad else colors.Survivor
end

local function removeBillboard(view: PlayerView)
	view.Generation += 1
	if view.Gui then
		view.Gui:Destroy()
	end
	view.Gui = nil
	view.NameLabel = nil
	view.RankLabel = nil
end

local function attachBillboard(player: Player, character: Model)
	local view = playerViews[player]
	if not view then
		return
	end
	removeBillboard(view)
	local generation = view.Generation
	task.spawn(function()
		local head = character:WaitForChild("Head", 5)
		if destroyed or not head or not head:IsA("BasePart") or playerViews[player] ~= view or view.Generation ~= generation or player.Character ~= character then
			return
		end
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "SurvivorBPRank"
		billboard.Adornee = head
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 45
		billboard.Size = UDim2.fromOffset(200, 44)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
		billboard.Parent = head
		local nameLabel = label("PlayerName", billboard, 12, colors.Text)
		nameLabel.Size = UDim2.fromScale(1, 0.45)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextStrokeTransparency = 0.3
		local rankLabel = label("Rank", billboard, 14, colors.Survivor)
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.Position = UDim2.fromScale(0, 0.45)
		rankLabel.Size = UDim2.fromScale(1, 0.55)
		rankLabel.TextXAlignment = Enum.TextXAlignment.Center
		rankLabel.TextStrokeTransparency = 0.3
		view.Gui = billboard
		view.NameLabel = nameLabel
		view.RankLabel = rankLabel
		refreshBillboard(player)
	end)
end

local function trackPlayer(player: Player)
	if playerViews[player] then
		return
	end
	local view: PlayerView = { Connections = {}, Gui = nil, NameLabel = nil, RankLabel = nil, Generation = 0 }
	playerViews[player] = view
	table.insert(view.Connections, player.CharacterAdded:Connect(function(character)
		attachBillboard(player, character)
	end))
	table.insert(view.Connections, player.CharacterRemoving:Connect(function()
		removeBillboard(view)
	end))
	for _, attribute in { "Role", "Status", "Rank", "BP" } do
		table.insert(view.Connections, player:GetAttributeChangedSignal(attribute):Connect(function()
			refreshBillboard(player)
		end))
	end
	if player.Character then
		attachBillboard(player, player.Character)
	end
end

local function untrackPlayer(player: Player)
	local view = playerViews[player]
	if not view then
		return
	end
	playerViews[player] = nil
	for _, connection in view.Connections do
		connection:Disconnect()
	end
	removeBillboard(view)
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local targetIntensity = 0
local currentIntensity = 0
local audioRequested = false
local sampleTime = 0
local eligible = false

local function sampleChase()
	eligible = matchState:GetAttribute("Phase") == "Active"
		and localPlayer:GetAttribute("Role") == "Survivor"
		and localPlayer:GetAttribute("Status") == "Alive"
	local survivorRoot = if eligible then livingRoot(localPlayer) else nil
	if not survivorRoot then
		eligible = false
		targetIntensity = 0
		return
	end
	local distance = math.huge
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == "Killer" then
			local killerRoot = livingRoot(player)
			if killerRoot then
				distance = math.min(distance, (killerRoot.Position - survivorRoot.Position).Magnitude)
			end
		end
	end
	if distance == math.huge then
		-- The killer disconnected or died: the chase is over immediately.
		eligible = false
		targetIntensity = 0
	else
		targetIntensity = Rules.chaseIntensity(distance)
	end
end

table.insert(connections, RunService.Heartbeat:Connect(function(deltaTime: number)
	sampleTime += deltaTime
	if sampleTime >= 0.1 then
		sampleTime = 0
		sampleChase()
	end
	-- End/capture/death turns sound off immediately, while ordinary distance changes fade.
	if not eligible then
		currentIntensity = 0
		audioRequested = false
		if chaseSound.IsPlaying then
			chaseSound:Stop()
		end
	else
		currentIntensity += (targetIntensity - currentIntensity) * (1 - math.exp(-deltaTime * 5))
		if targetIntensity > 0 and hasAudio and not audioRequested then
			audioRequested = true
			if not chaseSound.IsPlaying then
				chaseSound:Play()
			end
		elseif targetIntensity == 0 and currentIntensity < 0.005 then
			audioRequested = false
			if chaseSound.IsPlaying then
				chaseSound:Stop()
			end
		end
	end
	chaseSound.Volume = math.clamp(currentIntensity * Config.ChaseMaxVolume, 0, 1)
	dangerStroke.Transparency = 1 - currentIntensity * 0.7
	chaseWarning.Visible = eligible and currentIntensity > 0.12
end))

local viewportConnection: RBXScriptConnection? = nil
local function resize()
	local camera = workspace.CurrentCamera
	if camera then ui.resize(camera.ViewportSize) end
end

local function trackCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	resize()
end

table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(trackCamera))
table.insert(connections, matchState.AttributeChanged:Connect(updateHUD))
table.insert(connections, localPlayer.AttributeChanged:Connect(updateHUD))
table.insert(connections, Players.PlayerAdded:Connect(trackPlayer))
table.insert(connections, Players.PlayerRemoving:Connect(untrackPlayer))
for _, player in Players:GetPlayers() do
	trackPlayer(player)
end
trackCamera()
updateHUD()

script.Destroying:Connect(function()
	destroyed = true
	for _, connection in connections do
		connection:Disconnect()
	end
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	for player in playerViews do
		untrackPlayer(player)
	end
	chaseSound:Destroy()
	screen:Destroy()
end)
