--!strict
-- Presentation only. Roles, objectives, captures, and BP are owned by the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local localPlayer = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local Rules = require(shared:WaitForChild("Rules"))
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local colors = {
	Background = Color3.fromRGB(13, 19, 27),
	Border = Color3.fromRGB(62, 82, 100),
	Text = Color3.fromRGB(231, 239, 243),
	Muted = Color3.fromRGB(158, 177, 189),
	Survivor = Color3.fromRGB(124, 212, 202),
	Killer = Color3.fromRGB(255, 137, 87),
	Danger = Color3.fromRGB(241, 79, 79),
	Chad = Color3.fromRGB(247, 213, 111),
}

local connections: { RBXScriptConnection } = {}
local destroyed = false

local screen = Instance.new("ScreenGui")
screen.Name = "EscapeTheChadHUD"
screen.ResetOnSpawn = false
screen.DisplayOrder = 10
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = localPlayer:WaitForChild("PlayerGui")

local function panel(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = colors.Background
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = colors.Border
	stroke.Transparency = 0.25
	stroke.Parent = frame
	return frame
end

local function label(name: string, parent: Instance, size: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamMedium
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Text = ""
	item.Parent = parent
	return item
end

local main = panel("MatchPanel", screen)
main.AnchorPoint = Vector2.new(0.5, 0)
main.Position = UDim2.new(0.5, 0, 0, 12)
main.Size = UDim2.new(1, -24, 0, 206)
local mainLimit = Instance.new("UISizeConstraint")
mainLimit.MaxSize = Vector2.new(740, math.huge)
mainLimit.Parent = main

local title = label("Title", main, 21, colors.Text)
title.Font = Enum.Font.GothamBlack
title.Position = UDim2.fromOffset(16, 10)
title.Size = UDim2.new(1, -110, 0, 30)
title.Text = "ESCAPE THE CHAD"

local timer = label("Timer", main, 28, colors.Text)
timer.Font = Enum.Font.GothamBold
timer.TextXAlignment = Enum.TextXAlignment.Right
timer.Position = UDim2.new(1, -100, 0, 10)
timer.Size = UDim2.fromOffset(84, 32)

local role = label("Role", main, 13, colors.Survivor)
role.Position = UDim2.fromOffset(16, 43)
role.Size = UDim2.new(1, -32, 0, 22)

local message = label("Message", main, 14, colors.Muted)
message.Position = UDim2.fromOffset(16, 68)
message.Size = UDim2.new(1, -32, 0, 36)
message.TextWrapped = true

local objective = label("ObjectiveProgress", main, 13, colors.Text)
objective.Position = UDim2.fromOffset(16, 107)
objective.Size = UDim2.new(1, -32, 0, 20)

local progressTrack = Instance.new("Frame")
progressTrack.Name = "TeamProgress"
progressTrack.BorderSizePixel = 0
progressTrack.BackgroundColor3 = Color3.fromRGB(42, 55, 66)
progressTrack.Position = UDim2.fromOffset(16, 132)
progressTrack.Size = UDim2.new(1, -32, 0, 5)
progressTrack.Parent = main
local progressFill = Instance.new("Frame")
progressFill.Name = "Fill"
progressFill.BorderSizePixel = 0
progressFill.BackgroundColor3 = colors.Survivor
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.Parent = progressTrack

local rank = label("BPRank", main, 15, colors.Survivor)
rank.Font = Enum.Font.GothamBold
rank.Position = UDim2.fromOffset(16, 144)
rank.Size = UDim2.new(1, -32, 0, 22)
local nextRank = label("NextRank", main, 12, colors.Muted)
nextRank.Position = UDim2.fromOffset(16, 171)
nextRank.Size = UDim2.new(1, -32, 0, 20)
nextRank.TextWrapped = true

local footer = panel("Instructions", screen)
footer.AnchorPoint = Vector2.new(0.5, 1)
footer.Position = UDim2.new(0.5, 0, 1, -16)
footer.Size = UDim2.new(1, -24, 0, 66)
local footerLimit = Instance.new("UISizeConstraint")
footerLimit.MaxSize = Vector2.new(740, math.huge)
footerLimit.Parent = footer
local help = label("Controls", footer, 13, colors.Text)
help.Position = UDim2.fromOffset(14, 8)
help.Size = UDim2.new(1, -28, 1, -16)
help.TextWrapped = true

local chaseWarning = label("ChaseWarning", screen, 18, colors.Danger)
chaseWarning.Font = Enum.Font.GothamBlack
chaseWarning.TextStrokeTransparency = 0.35
chaseWarning.TextXAlignment = Enum.TextXAlignment.Center
chaseWarning.AnchorPoint = Vector2.new(0.5, 1)
chaseWarning.Position = UDim2.new(0.5, 0, 1, -92)
chaseWarning.Size = UDim2.new(1, -24, 0, 28)
chaseWarning.Text = "OG CHAD IS NEAR"
chaseWarning.Visible = false

local chaseBorder = Instance.new("Frame")
chaseBorder.Name = "ChaseBorder"
chaseBorder.BackgroundTransparency = 1
chaseBorder.Position = UDim2.fromOffset(5, 5)
chaseBorder.Size = UDim2.new(1, -10, 1, -10)
chaseBorder.Parent = screen
local dangerStroke = Instance.new("UIStroke")
dangerStroke.Thickness = 5
dangerStroke.Color = colors.Danger
dangerStroke.Transparency = 1
dangerStroke.Parent = chaseBorder

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
	role.Text = string.upper(phase) .. "  /  " .. roleText .. "  /  " .. string.upper(status)
	role.TextColor3 = if currentRole == "Killer" then colors.Killer else colors.Survivor
	message.Text = stringAttribute(matchState, "Message", "Waiting for more players...")
	if goal > 0 then
		objective.Text = string.format("TEAM OBJECTIVES  %d / %d%s", completed, goal, if completed >= goal then "  •  EXIT POWERED" else "")
	else
		objective.Text = "TEAM OBJECTIVES  •  Awaiting next round"
	end
	progressFill.Size = UDim2.fromScale(if goal > 0 then math.clamp(completed / goal, 0, 1) else 0, 1)
	if currentRole == "Survivor" then
		rank.Text = string.format("%s  •  %d BP", string.upper(currentRank), points)
		rank.TextColor3 = if currentRank == "Chad" then colors.Chad else colors.Survivor
		local upcoming = Rules.nextRank(points)
		nextRank.Text = if upcoming then string.format("%d BP until %s", math.max(0, upcoming.BP - points), upcoming.Name) else "CHAD ACHIEVED  •  Escape once the team powers the exit"
	else
		rank.Text = if currentRole == "Killer" then "OG CHAD  •  THE ORIGINAL MENACE" else "LTN → MTN → HTN → CHADLITE → CHAD"
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
		help.Text = "Hold E / the prompt at the terminal for BP. Reach Chad + power the exit to escape. Rescue allies at the cage."
	else
		help.Text = "One OG Chad. Everyone else starts LTN. Work together, climb the fictional ranks, and escape."
	end
	if not hasAudio then
		nextRank.Text ..= "  •  Audio upload pending"
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
	local narrow = camera ~= nil and camera.ViewportSize.X < 520
	title.TextSize = if narrow then 16 else 21
	role.TextSize = if narrow then 11 else 13
	objective.TextSize = if narrow then 11 else 13
	nextRank.TextSize = if narrow then 11 else 12
	nextRank.Size = UDim2.new(1, -32, 0, if narrow then 38 else 20)
	main.Size = UDim2.new(1, -24, 0, if narrow then 220 else 206)
	footer.Size = UDim2.new(1, -24, 0, if narrow then 86 else 66)
	help.TextSize = if narrow then 12 else 13
	chaseWarning.Position = UDim2.new(0.5, 0, 1, if narrow then -112 else -92)
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
