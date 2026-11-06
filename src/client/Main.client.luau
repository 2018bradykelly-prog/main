--!strict
-- Presentation and input only. Roles, health states, BP, captures, abilities
-- and progression are owned by the server; this script renders them and sends
-- requests through the Action remote.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local Rules = require(shared:WaitForChild("Rules"))
local Abilities = require(shared:WaitForChild("Abilities"))
local matchState = ReplicatedStorage:WaitForChild("MatchState")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("Action") :: RemoteEvent
local notifyRemote = remotes:WaitForChild("Notify") :: RemoteEvent

local Hud = require(script.Parent:WaitForChild("Hud"))
local Movement = require(script.Parent:WaitForChild("Movement"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local colors = Hud.Colors

local connections: { RBXScriptConnection } = {}
local destroyed = false
local ui = Hud.create(localPlayer:WaitForChild("PlayerGui"))
local movement = Movement.new(localPlayer)

local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
	table.insert(connections, signal:Connect(callback))
end

-- Resetting your character would be an escape from carries and cages.
task.spawn(function()
	for _ = 1, 20 do
		if pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end) then
			return
		end
		task.wait(1)
	end
end)

local function str(instance: Instance, name: string, fallback: string): string
	local value = instance:GetAttribute(name)
	return if type(value) == "string" then value else fallback
end

local function num(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function phase(): string
	return str(matchState, "Phase", "Waiting")
end

local function myRole(): string
	return str(localPlayer, "Role", "Lobby")
end

local function myStatus(): string
	return str(localPlayer, "Status", "Lobby")
end

local function inRound(): boolean
	return phase() == "Active" and (myRole() == "Survivor" or myRole() == "Killer")
end

local function isFreeSurvivor(): boolean
	local status = myStatus()
	return myRole() == "Survivor" and (status == "Healthy" or status == "Injured") and localPlayer:GetAttribute("Hidden") ~= true
end

local function action(name: string, argument: any?)
	actionRemote:FireServer(name, argument)
end

-- Toasts and splash -------------------------------------------------------------

local toneColors: { [string]: Color3 } = {
	good = colors.Good,
	bad = colors.Danger,
	warn = colors.Warn,
	info = colors.Border,
}

local function toast(text: string, tone: string?)
	local item = ui.pushToast(text, toneColors[tone or "info"] or colors.Border)
	task.delay(5, function()
		if item.Parent then
			local fade = TweenService:Create(item, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			item:Destroy()
		end
	end)
end

local splashToken = 0
local function splash(title: string, subtitle: string, color: Color3, seconds: number)
	splashToken += 1
	local token = splashToken
	ui.Splash.Visible = true
	ui.SplashTitle.Text = title
	ui.SplashTitle.TextColor3 = color
	ui.SplashTitle.TextTransparency = 1
	ui.SplashSubtitle.Text = subtitle
	ui.SplashSubtitle.TextTransparency = 1
	TweenService:Create(ui.SplashTitle, TweenInfo.new(0.35, Enum.EasingStyle.Back), { TextTransparency = 0 }):Play()
	TweenService:Create(ui.SplashSubtitle, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	task.delay(seconds, function()
		if token ~= splashToken then
			return
		end
		TweenService:Create(ui.SplashTitle, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		local fade = TweenService:Create(ui.SplashSubtitle, TweenInfo.new(0.6), { TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		if token == splashToken then
			ui.Splash.Visible = false
		end
	end)
end

-- HUD buttons ---------------------------------------------------------------------

local lobbyHiddenByUser = false
connect(ui.HelpButton.Activated, function()
	ui.setHelpVisible(not ui.Details.Visible)
end)
connect(ui.Close.Activated, function()
	ui.setHelpVisible(false)
end)
connect(ui.Hide.Activated, function()
	ui.setHudVisible(false)
end)
connect(ui.Restore.Activated, function()
	ui.setHudVisible(true)
end)
connect(ui.ResultsClose.Activated, function()
	ui.Results.Visible = false
end)
connect(ui.LobbyToggle.Activated, function()
	lobbyHiddenByUser = ui.LobbyPanel.Visible
	ui.setLobbyVisible(not ui.LobbyPanel.Visible)
end)
connect(ui.ActionButton.Activated, function()
	local status = myStatus()
	if status == "Carried" then
		action("Wiggle")
	elseif status == "Caged" then
		action("Struggle")
	end
end)

-- Abilities -------------------------------------------------------------------------

type BarEntry = { Id: string, Key: string, Name: string, Color: Color3?, Cooldown: number }
local barSignature = ""
local barEntries: { BarEntry } = {}

local function useAbility(id: string)
	if id == "Sprint" then
		movement.SprintToggled = not movement.SprintToggled
	elseif id == "Slide" then
		movement:slide()
	elseif id == "Attack" then
		if inRound() and myRole() == "Killer" then
			action("Attack")
		end
	elseif inRound() then
		action("Ability", id)
	end
end

local function rebuildAbilityBar()
	local role = myRole()
	local entries: { BarEntry } = {}
	if role == "Killer" and phase() == "Active" then
		table.insert(entries, { Id = "Attack", Key = "Click", Name = "Attack", Color = colors.Killer, Cooldown = Config.AttackHitCooldown })
		for _, ability in Abilities.Killer do
			table.insert(entries, { Id = ability.Id, Key = ability.Key, Name = ability.Name, Color = ability.Color, Cooldown = ability.Cooldown })
		end
	else
		table.insert(entries, { Id = "Sprint", Key = "Shift", Name = "Sprint", Color = colors.Survivor, Cooldown = 0 })
		table.insert(entries, { Id = "Slide", Key = "C", Name = "Slide", Color = colors.Survivor, Cooldown = Config.SlideCooldown })
		if role == "Survivor" and phase() == "Active" then
			local ability = Abilities.get(str(localPlayer, "Ability", Abilities.DefaultSurvivor))
			if ability then
				table.insert(entries, { Id = ability.Id, Key = ability.Key, Name = ability.Name, Color = ability.Color, Cooldown = ability.Cooldown })
			end
		end
	end
	local parts = {}
	for _, entry in entries do
		table.insert(parts, entry.Id)
	end
	local signature = table.concat(parts, ",")
	if signature == barSignature then
		return
	end
	barSignature = signature
	barEntries = entries
	local buttons = ui.setAbilities(entries)
	for id, entry in buttons do
		entry.Button.Activated:Connect(function()
			useAbility(id)
		end)
	end
end

local function updateCooldowns()
	local now = serverNow()
	local clock = os.clock()
	for _, entry in barEntries do
		local remaining = 0
		local active = false
		if entry.Id == "Sprint" then
			active = movement.Sprinting or movement:wantsSprint()
		elseif entry.Id == "Slide" then
			remaining = math.max(0, movement.NextSlideAt - clock)
		elseif entry.Id == "Attack" then
			remaining = math.max(0, num(localPlayer, "AttackReadyAt", 0) - now)
		else
			remaining = math.max(0, num(localPlayer, "Ready_" .. entry.Id, 0) - now)
		end
		local fraction = if entry.Cooldown > 0 then remaining / entry.Cooldown else 0
		ui.setCooldown(entry.Id, fraction, remaining, active)
	end
end

-- Input -----------------------------------------------------------------------------

local function survivorAbilityId(): string
	return str(localPlayer, "Ability", Abilities.DefaultSurvivor)
end

connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
		movement.SprintHeld = true
		return
	end
	if processed then
		return
	end
	if key == Enum.KeyCode.H then
		ui.setHelpVisible(not ui.Details.Visible)
	elseif key == Enum.KeyCode.C or key == Enum.KeyCode.ButtonB then
		movement:slide()
	elseif key == Enum.KeyCode.ButtonL3 then
		movement.SprintToggled = not movement.SprintToggled
	elseif key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonY then
		if myRole() == "Killer" then
			useAbility("Charge")
		elseif myRole() == "Survivor" then
			useAbility(survivorAbilityId())
		end
	elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonL1 then
		if myRole() == "Killer" then
			useAbility("Reveal")
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or key == Enum.KeyCode.ButtonR2 then
		if myRole() == "Killer" then
			useAbility("Attack")
		end
	end
end)

connect(UserInputService.InputEnded, function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		movement.SprintHeld = false
	end
end)

-- Jump (Space, the mobile jump button, gamepad A): wiggle when carried, vault near windows.
local lastJump = 0
connect(UserInputService.JumpRequest, function()
	local clock = os.clock()
	local status = myStatus()
	if status == "Carried" then
		if clock - lastJump > 0.08 then
			lastJump = clock
			action("Wiggle")
		end
		return
	end
	if clock - lastJump < 0.25 then
		return
	end
	lastJump = clock
	if phase() == "Active" then
		movement:tryVault()
	end
end)

-- Server notifications -------------------------------------------------------------------

connect(notifyRemote.OnClientEvent, function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.Kind
	if kind == "Toast" and type(payload.Text) == "string" then
		toast(payload.Text, payload.Tone)
	elseif kind == "RoleReveal" then
		ui.Results.Visible = false
		if payload.Role == "Killer" then
			splash("YOU ARE THE OG CHAD", string.format("%s · Hunt them down. Click to attack, Q to charge, F for Mog Aura.", tostring(payload.MapName)), colors.Killer, 4)
		else
			splash("SURVIVE THE CHAD", string.format("%s · The OG Chad is %s. Calibrate terminals, reach Chad rank, escape.", tostring(payload.MapName), tostring(payload.KillerName)), colors.Survivor, 4)
		end
	elseif kind == "Ping" and typeof(payload.Position) == "Vector3" then
		Effects.ping(payload.Position, tostring(payload.Label or "Noise"), tonumber(payload.Duration) or 4)
	elseif kind == "Reveal" and type(payload.Ids) == "table" then
		Effects.reveal(payload.Ids, tonumber(payload.Duration) or 4)
	elseif kind == "Dash" then
		movement:dash(tonumber(payload.Duration) or 0.3)
	elseif kind == "Stamina" then
		movement:refill()
		toast("Protein Shake: stamina refilled and a burst of speed!", "good")
	elseif kind == "Blind" then
		Effects.blind(ui.Blind, tonumber(payload.Duration) or 2)
		if payload.Reason == "Jawline Flash" then
			toast("BLINDED by a Jawline Flash!", "bad")
		end
	elseif kind == "Flash" and typeof(payload.Position) == "Vector3" then
		Effects.flashBurst(payload.Position)
	elseif kind == "Swing" and type(payload.Id) == "number" then
		local attacker = Players:GetPlayerByUserId(payload.Id)
		if attacker then
			Effects.swing(attacker)
		end
	elseif kind == "Hit" and type(payload.Id) == "number" then
		local victim = Players:GetPlayerByUserId(payload.Id)
		if victim then
			Effects.hitSpark(victim)
		end
		if payload.Id == localPlayer.UserId then
			Effects.hitFlash(ui.Vignette, payload.Downed == true)
		end
	elseif kind == "Results" then
		local winner = payload.Winner
		local banner = if winner == "Killer" then "OG CHAD WINS" elseif winner == "Survivors" then "SURVIVORS WIN" else "ROUND OVER"
		local color = if winner == "Killer" then colors.Killer elseif winner == "Survivors" then colors.Survivor else colors.Muted
		local rows = {}
		if type(payload.Rows) == "table" then
			for _, row in payload.Rows do
				if type(row) == "table" then
					local levelUp = if row.LevelUp then string.format("  <font color=\"#F7D56F\"><b>LEVEL UP → %d</b></font>", tonumber(row.Level) or 0) else ""
					local trophy = if row.Won then "🏆 " else ""
					table.insert(rows, string.format("%s<b>%s</b>  ·  %s  ·  %s  ·  <font color=\"#7FEF97\">+%d XP</font>%s",
						trophy, tostring(row.Name), tostring(row.Role), tostring(row.Outcome), tonumber(row.XP) or 0, levelUp))
				end
			end
		end
		ui.showResults(banner, color, tostring(payload.Result or ""), rows)
	end
end)

-- Prompt filtering ---------------------------------------------------------------------
-- The server enables every prompt; each client shows only the ones that apply.

local prompts: { [ProximityPrompt]: RBXScriptConnection } = {}

local function evaluatePrompt(prompt: ProximityPrompt)
	local kind = prompt:GetAttribute("Kind")
	local forRole = prompt:GetAttribute("ForRole")
	local visible = prompt:GetAttribute("Active") == true and phase() == "Active"
	local character = localPlayer.Character
	if character and prompt:IsDescendantOf(character) then
		visible = false
	end
	local role = myRole()
	local hiddenLocker = str(localPlayer, "HiddenLocker", "")
	if visible then
		if hiddenLocker ~= "" then
			local parent = prompt.Parent
			visible = kind == "Locker" and parent ~= nil and parent:GetAttribute("LockerId") == hiddenLocker
			prompt.ActionText = "Leave locker"
		elseif role == "Survivor" then
			visible = isFreeSurvivor() and (forRole == "Survivor" or forRole == "Any")
			if kind == "Locker" then
				prompt.ActionText = "Hide"
			end
		elseif role == "Killer" then
			local carrying = num(localPlayer, "Carrying", 0) ~= 0
			visible = forRole == "Killer" or forRole == "Any"
			if kind == "Pickup" then
				visible = visible and not carrying
			elseif kind == "Cage" then
				visible = visible and carrying
			elseif kind == "Locker" then
				visible = visible and not carrying
				prompt.ActionText = "Search locker"
			end
		else
			visible = false
		end
	end
	if prompt.Enabled ~= visible then
		prompt.Enabled = visible
	end
end

local function evaluateAllPrompts()
	for prompt in prompts do
		evaluatePrompt(prompt)
	end
end

local function trackPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") or prompts[instance] then
		return
	end
	local prompt = instance :: ProximityPrompt
	prompts[prompt] = prompt.AttributeChanged:Connect(function()
		evaluatePrompt(prompt)
	end)
	evaluatePrompt(prompt)
end

connect(Workspace.DescendantAdded, trackPrompt)
connect(Workspace.DescendantRemoving, function(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		local connection = prompts[instance :: ProximityPrompt]
		if connection then
			connection:Disconnect()
			prompts[instance :: ProximityPrompt] = nil
		end
	end
end)
for _, descendant in Workspace:GetDescendants() do
	trackPrompt(descendant)
end

-- Overhead labels ---------------------------------------------------------------------------
-- AlwaysOnTop=false so labels never reveal survivors through walls.

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
	local role = str(player, "Role", "Lobby")
	local status = str(player, "Status", "Lobby")
	local shown = role == "Survivor" and status ~= "Escaped" and status ~= "Eliminated" and player:GetAttribute("Hidden") ~= true
	view.Gui.Enabled = shown and player ~= localPlayer
	view.NameLabel.Text = player.DisplayName
	local rank = str(player, "Rank", "LTN")
	local suffix = if status == "Healthy" then "" else " · " .. string.upper(status)
	view.RankLabel.Text = rank .. suffix
	view.RankLabel.TextColor3 = if status ~= "Healthy" then (Hud.StatusColors[status] or colors.Danger)
		elseif rank == "Chad" then colors.Chad
		else colors.Survivor
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
		billboard.MaxDistance = 50
		billboard.LightInfluence = 0
		billboard.Size = UDim2.fromOffset(200, 44)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
		billboard.Parent = head
		local nameLabel = Hud.label("PlayerName", billboard, 12, colors.Text)
		nameLabel.Size = UDim2.fromScale(1, 0.45)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextStrokeTransparency = 0.3
		local rankLabel = Hud.label("Rank", billboard, 14, colors.Survivor)
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
	table.insert(view.Connections, player.AttributeChanged:Connect(function()
		refreshBillboard(player)
	end))
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

-- Camera: lockers and spectating --------------------------------------------------------------

local cameraMode = "Default"
local spectateIndex = 1

local function spectateTargets(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local role = str(player, "Role", "Lobby")
		local status = str(player, "Status", "Lobby")
		if player ~= localPlayer and (role == "Killer" or (role == "Survivor" and status ~= "Escaped" and status ~= "Eliminated")) then
			if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
				table.insert(list, player)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

connect(ui.SpectatePrev.Activated, function()
	spectateIndex -= 1
end)
connect(ui.SpectateNext.Activated, function()
	spectateIndex += 1
end)

local doorCache: { [string]: BasePart } = {}
local function findLockerDoor(lockerId: string): BasePart?
	local cached = doorCache[lockerId]
	if cached and cached.Parent and cached:GetAttribute("LockerId") == lockerId then
		return cached
	end
	local map = Workspace:FindFirstChild("ActiveMap")
	if not map then
		return nil
	end
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("LockerId") == lockerId then
			doorCache[lockerId] = descendant
			return descendant
		end
	end
	return nil
end

local function updateCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local hiddenLocker = str(localPlayer, "HiddenLocker", "")
	local status = myStatus()
	local spectating = phase() == "Active" and (status == "Escaped" or status == "Eliminated" or status == "Spectating")
	if hiddenLocker ~= "" then
		local door = findLockerDoor(hiddenLocker)
		if door then
			cameraMode = "Locker"
			camera.CameraType = Enum.CameraType.Scriptable
			-- Peek through the vents: slight sway, looking out of the door.
			local sway = math.sin(os.clock() * 1.3) * 0.04
			camera.CFrame = door.CFrame * CFrame.new(0, 1.7, -0.35) * CFrame.Angles(-0.05, sway, 0)
			ui.Spectate.Visible = false
			return
		end
	end
	if cameraMode == "Locker" then
		camera.CameraType = Enum.CameraType.Custom
		cameraMode = "Default"
	end
	if spectating then
		local targets = spectateTargets()
		ui.Spectate.Visible = #targets > 0
		if #targets > 0 then
			if spectateIndex < 1 then
				spectateIndex = #targets
			elseif spectateIndex > #targets then
				spectateIndex = 1
			end
			local target = targets[spectateIndex]
			local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and camera.CameraSubject ~= humanoid then
				camera.CameraSubject = humanoid
			end
			ui.SpectateName.Text = "Spectating " .. target.DisplayName .. "  ·  " .. str(target, "Status", "")
			cameraMode = "Spectate"
		end
		return
	end
	ui.Spectate.Visible = false
	if cameraMode == "Spectate" then
		cameraMode = "Default"
		local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

-- HUD refresh ------------------------------------------------------------------------------

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function mapOptions(): { { Id: string, Name: string, Blurb: string, Votes: number } }
	local options = {}
	for entry in string.gmatch(str(matchState, "MapOptions", ""), "[^;]+") do
		local id, name, blurb = string.match(entry, "^([^|]*)|([^|]*)|(.*)$")
		if id and name and blurb then
			table.insert(options, { Id = id, Name = name, Blurb = blurb, Votes = num(matchState, "Votes_" .. id, 0) })
		end
	end
	return options
end

local myVote: string? = nil
local voteConnections: { [string]: boolean } = {}
local loadoutConnections: { [string]: boolean } = {}

local function refreshLobby()
	local currentPhase = phase()
	local participating = inRound()
	ui.LobbyToggle.Visible = not participating
	if participating then
		ui.setLobbyVisible(false)
	elseif not lobbyHiddenByUser and not ui.LobbyPanel.Visible then
		ui.setLobbyVisible(true)
	end
	ui.setProfile(
		num(localPlayer, "Level", 1),
		str(localPlayer, "Title", Rules.titleForLevel(1)),
		num(localPlayer, "XPInto", 0),
		num(localPlayer, "XPNeed", Rules.xpToNext(1)),
		string.format("Wins %d · Escapes %d · Rounds %d", num(localPlayer, "Wins", 0), num(localPlayer, "Escapes", 0), num(localPlayer, "RoundsPlayed", 0))
	)
	ui.setLoadout(Abilities.Survivor :: any, survivorAbilityId())
	for id, loadoutButton in ui.LoadoutButtons do
		if not loadoutConnections[id] then
			loadoutConnections[id] = true
			loadoutButton.Activated:Connect(function()
				action("Loadout", id)
			end)
		end
	end
	local voting = currentPhase == "Waiting" or currentPhase == "Intermission"
	if not voting then
		myVote = nil
	end
	ui.setVotes(mapOptions(), myVote, voting)
	for id, voteButton in ui.VoteButtons do
		if not voteConnections[id] then
			voteConnections[id] = true
			voteButton.Activated:Connect(function()
				myVote = id
				action("Vote", id)
				refreshLobby()
			end)
		end
	end
end

local function teamEntries()
	local entries = {}
	if phase() ~= "Active" then
		return entries
	end
	local now = serverNow()
	local list = {}
	for _, player in Players:GetPlayers() do
		if str(player, "Role", "Lobby") == "Survivor" then
			table.insert(list, player)
		end
	end
	table.sort(list, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	for _, player in list do
		local status = str(player, "Status", "Healthy")
		local detail = str(player, "Rank", "LTN") .. " · " .. status
		local timer: number? = nil
		if status == "Caged" then
			local remaining = num(player, "CagedUntil", 0) - now
			local total = Rules.cageSeconds(num(player, "CageCount", 1)) or 1
			detail = string.format("Caged · %ds · cage %d/3", math.max(0, math.ceil(remaining)), num(player, "CageCount", 1))
			timer = remaining / total
		elseif status == "Downed" then
			detail = string.format("DOWNED · %ds", math.max(0, math.ceil(num(player, "RecoverAt", 0) - now)))
		elseif player:GetAttribute("Hidden") == true and player == localPlayer then
			detail ..= " · hiding"
		end
		table.insert(entries, {
			Name = player.DisplayName .. (if player == localPlayer then " (you)" else ""),
			Detail = detail,
			Color = Hud.StatusColors[status] or colors.Muted,
			Timer = timer,
		})
	end
	return entries
end

local function updateHUD()
	local currentPhase = phase()
	local role = myRole()
	local status = myStatus()
	local now = serverNow()
	local seconds = num(matchState, "TimeRemaining", 0)
	ui.Timer.Text = if currentPhase == "Waiting" then "--:--" else formatTime(seconds)
	ui.Timer.TextColor3 = if currentPhase == "Active" and seconds <= 30 then colors.Danger else colors.Text
	local points = num(localPlayer, "BP", 0)
	local rank = str(localPlayer, "Rank", Rules.rankForBP(points))
	local roleText = if role == "Killer" then "OG CHAD" elseif role == "Survivor" then "SURVIVOR" else "LOBBY"
	ui.Role.Text = roleText .. (if role ~= "Lobby" then " · " .. string.upper(status) else "  ·  " .. string.upper(str(matchState, "MapName", "")))
	ui.Role.TextColor3 = if role == "Killer" then colors.Killer elseif role == "Survivor" then (Hud.StatusColors[status] or colors.Survivor) else colors.Muted
	ui.Message.Text = str(matchState, "Message", "Waiting for more players...")

	local completed = num(matchState, "ObjectiveCount", 0)
	local goal = num(matchState, "ObjectiveGoal", 0)
	local powered = matchState:GetAttribute("ExitPowered") == true
	if currentPhase == "Active" and goal > 0 then
		ui.Objective.Text = string.format("TERMINALS %d/%d  ·  %s", completed, goal, if powered then "EXIT POWERED!" else "exit locked")
		ui.Objective.TextColor3 = if powered then colors.Good else colors.Muted
	elseif currentPhase == "Intermission" then
		ui.Objective.Text = "Next round soon · vote for a map"
		ui.Objective.TextColor3 = colors.Muted
	elseif currentPhase == "Results" then
		ui.Objective.Text = "Round over"
		ui.Objective.TextColor3 = colors.Muted
	else
		ui.Objective.Text = "Waiting for 2+ players"
		ui.Objective.TextColor3 = colors.Muted
	end
	ui.ProgressFill.Size = UDim2.fromScale(if goal > 0 then math.clamp(completed / goal, 0, 1) else 0, 1)
	ui.ProgressFill.BackgroundColor3 = if powered then colors.Good else colors.Survivor

	if role == "Survivor" then
		ui.Rank.Text = string.format("%s  ·  %d BP", string.upper(rank), points)
		ui.Rank.TextColor3 = if rank == "Chad" then colors.Chad else colors.Survivor
		local upcoming = Rules.nextRank(points)
		ui.NextRank.Text = if upcoming then string.format("%d BP until %s. Terminals +%d · revives +%d · rescues +%d.", math.max(0, upcoming.BP - points), upcoming.Name, Config.BPPerObjective, Config.BPPerRevive, Config.BPPerRescue)
			else "CHAD ACHIEVED · Escape through a powered exit gate."
	elseif role == "Killer" then
		local carrying = num(localPlayer, "Carrying", 0) ~= 0
		ui.Rank.Text = if carrying then "CARRYING · take them to a Mog Cage" else string.format("%d survivors left", num(matchState, "SurvivorsLeft", 0))
		ui.Rank.TextColor3 = colors.Killer
		ui.NextRank.Text = "Terminal pings show where survivors are working. Scratch marks show who sprinted."
	else
		ui.Rank.Text = string.format("LEVEL %d  ·  %s", num(localPlayer, "Level", 1), str(localPlayer, "Title", ""))
		ui.Rank.TextColor3 = colors.Chad
		ui.NextRank.Text = "Fictional ranks. Very real cardio."
	end

	if status == "Caged" then
		ui.Help.Text = "CAGED · A teammate can free you at the cage panel. You can try to STRUGGLE free a few times. If the timer runs out you're eliminated; a third cage eliminates you instantly."
	elseif status == "Carried" then
		ui.Help.Text = "CARRIED · Mash SPACE (or the WIGGLE button) to break free. Teammates can blind the OG Chad with a Jawline Flash."
	elseif status == "Downed" then
		ui.Help.Text = "DOWNED · Crawl to safety. A teammate can revive you (hold E), or you'll pick yourself up when the timer ends."
	elseif status == "Escaped" or status == "Eliminated" or status == "Spectating" then
		ui.Help.Text = "You're out of this round. Use the < > buttons to spectate the remaining players."
	elseif role == "Killer" and currentPhase == "Active" then
		ui.Help.Text = "CLICK attack (2 hits = downed) · Q Gym Charge · F Mog Aura (reveal)\nE pick up downed survivors and lock them in Mog Cages · E search lockers\nSPACE vault windows (slowly). You can't jump high."
	elseif role == "Survivor" and currentPhase == "Active" then
		ui.Help.Text = "E calibrate cyan terminals (+BP) · SHIFT sprint · C slide · Q ability\nSPACE vault windows · E hide in lockers · E revive/heal/free teammates\nReach Chad (100 BP), then escape through a powered exit gate."
	else
		ui.Help.Text = "One player becomes the OG Chad. Everyone else starts LTN.\nCalibrate terminals, climb the ranks and escape together.\nPick your ability and vote for a map in the Loadout panel."
	end

	-- Status panel
	local showStatus = true
	local statusLine = ""
	local statusColor = colors.Text
	local barFraction = movement.Stamina / Config.StaminaMax
	local barLabel = if movement.Exhausted then "EXHAUSTED" else "STAMINA"
	local barColor = if movement.Exhausted then colors.Danger else colors.Survivor
	local actionText: string? = nil
	if role == "Killer" and currentPhase == "Active" then
		local stunned = now < num(localPlayer, "StunnedUntil", 0)
		local carrying = num(localPlayer, "Carrying", 0) ~= 0
		statusLine = if stunned then "STUNNED!" elseif carrying then "CARRYING · find a Mog Cage" elseif now < num(localPlayer, "ChargeUntil", 0) then "CHARGING" else "HUNTING"
		statusColor = colors.Killer
		local attackRemaining = math.max(0, num(localPlayer, "AttackReadyAt", 0) - now)
		barFraction = 1 - math.clamp(attackRemaining / Config.AttackHitCooldown, 0, 1)
		barLabel = if attackRemaining > 0 then "RECOVERING" else "ATTACK READY"
		barColor = colors.Killer
	elseif localPlayer:GetAttribute("Hidden") == true then
		statusLine = "HIDING IN A LOCKER · E to leave"
		statusColor = colors.Survivor
	elseif status == "Downed" then
		statusLine = string.format("DOWNED · getting up in %ds", math.max(0, math.ceil(num(localPlayer, "RecoverAt", 0) - now)))
		statusColor = colors.Danger
		barFraction = 0
		barLabel = "WAIT FOR A REVIVE"
		barColor = colors.Danger
	elseif status == "Carried" then
		statusLine = "CARRIED! MASH SPACE"
		statusColor = colors.Danger
		barFraction = num(localPlayer, "WiggleProgress", 0)
		barLabel = "WIGGLE"
		barColor = colors.Warn
		actionText = "WIGGLE!"
	elseif status == "Caged" then
		local left = num(localPlayer, "EscapeAttemptsLeft", 0)
		statusLine = string.format("CAGED · %ds left", math.max(0, math.ceil(num(localPlayer, "CagedUntil", 0) - now)))
		statusColor = colors.Caged
		actionText = if left > 0 then string.format("STRUGGLE (%d)", left) else nil
	elseif role == "Survivor" and currentPhase == "Active" then
		statusLine = if status == "Injured" then "INJURED · find a teammate to heal you" else "HEALTHY"
		statusColor = Hud.StatusColors[status] or colors.Text
		if now < num(localPlayer, "BoostUntil", 0) then
			statusLine ..= " · SPEED BOOST"
		end
	elseif status == "Escaped" or status == "Eliminated" or status == "Spectating" then
		showStatus = false
	else
		statusLine = "LOBBY · try sprinting and sliding"
		statusColor = colors.Muted
	end
	ui.Status.Visible = showStatus and not ui.Results.Visible
	ui.StatusText.Text = statusLine
	ui.StatusText.TextColor3 = statusColor
	ui.StaminaFill.Size = UDim2.fromScale(math.clamp(barFraction, 0, 1), 1)
	ui.StaminaFill.BackgroundColor3 = barColor
	ui.StaminaLabel.Text = barLabel
	ui.ActionButton.Visible = actionText ~= nil
	ui.ActionButton.Text = actionText or ""
	ui.StaminaTrack.Visible = actionText == nil or status == "Carried"
	ui.StaminaLabel.Visible = actionText == nil

	ui.setTeam(teamEntries())
	ui.AbilityBar.Visible = not ui.Results.Visible and status ~= "Escaped" and status ~= "Eliminated" and status ~= "Spectating"
	rebuildAbilityBar()
	refreshLobby()
	evaluateAllPrompts()
end

-- Frame loop ------------------------------------------------------------------------------

local slowClock = 0
connect(RunService.RenderStepped, function(dt: number)
	movement:update(dt)
	updateCamera()
end)

connect(RunService.Heartbeat, function(dt: number)
	local currentPhase = phase()
	local intensity = Effects.updateChase(dt, currentPhase)
	ui.DangerStroke.Transparency = 1 - intensity * 0.7
	ui.ChaseWarning.Visible = intensity > 0.12 and not ui.Results.Visible
	local status = myStatus()
	-- Downed/carried survivors see a pulsing red vignette.
	if status == "Downed" or status == "Carried" then
		ui.Vignette.BackgroundTransparency = 0.78 + math.sin(os.clock() * 4) * 0.06
	elseif ui.Vignette.BackgroundTransparency > 0.7 and ui.Vignette.BackgroundTransparency < 0.95 then
		ui.Vignette.BackgroundTransparency = 1
	end
	-- Inside a smoke cloud the screen fogs over.
	local inSmoke = false
	local root = Effects.rootOf(localPlayer)
	local map = Workspace:FindFirstChild("ActiveMap")
	if root and map then
		for _, child in map:GetChildren() do
			if child.Name == "SmokeCloud" and child:IsA("BasePart") and (child.Position - root.Position).Magnitude < child.Size.X / 2 then
				inSmoke = true
				break
			end
		end
	end
	ui.Smoke.BackgroundTransparency = if inSmoke then 0.25 else 1
	if myRole() == "Killer" and currentPhase == "Active" then
		Effects.updateScratches(dt)
	end
	updateCooldowns()
	slowClock += dt
	if slowClock >= 0.2 then
		slowClock = 0
		updateHUD()
	end
end)

-- Wiring ----------------------------------------------------------------------------------

local viewportConnection: RBXScriptConnection? = nil
local function resize()
	local camera = Workspace.CurrentCamera
	if camera then
		ui.resize(camera.ViewportSize)
	end
end

local function trackCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	resize()
end

local lastPhase = phase()
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), trackCamera)
connect(matchState.AttributeChanged, function(name: string)
	if name == "Phase" then
		local current = phase()
		if current ~= lastPhase then
			lastPhase = current
			if current == "Intermission" then
				toast("Next round starting soon. Vote for a map!", "info")
			end
			movement.SprintToggled = false
		end
	end
	updateHUD()
end)
connect(localPlayer.AttributeChanged, function()
	updateHUD()
end)
connect(Players.PlayerAdded, trackPlayer)
connect(Players.PlayerRemoving, untrackPlayer)
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
	for _, connection in prompts do
		connection:Disconnect()
	end
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	for player in playerViews do
		untrackPlayer(player)
	end
	Effects.destroy()
	ui.Screen:Destroy()
end)
