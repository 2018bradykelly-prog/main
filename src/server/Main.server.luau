--!strict
-- Server authority: clients can only request ProximityPrompt interactions.
-- All roles, score, captures, rescues, and exits are validated here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local RoundState = require(Shared.RoundState)
local World = require(script.Parent.World)

local world = World.create()
local match = ReplicatedStorage:WaitForChild("MatchState")
local random = Random.new()
local round: any = nil
local phase = "Waiting"
local holds: { [ProximityPrompt]: { [Player]: { At: number, Round: any } } } = {}
Players.RespawnTime = 2

local function setPhase(nextPhase: string, message: string)
	phase = nextPhase
	match:SetAttribute("Phase", phase)
	match:SetAttribute("Message", message)
	world.ObjectivePrompt.Enabled = phase == "Active"
	world.ExitPrompt.Enabled = phase == "Active"
	world.RescuePrompt.Enabled = phase == "Active"
	-- A hold from an earlier phase cannot be reused in a subsequent round.
	for _, perPlayer in holds do table.clear(perPlayer) end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function survivorSpawn(): CFrame
	return world.SurvivorSpawns[random:NextInteger(1, #world.SurvivorSpawns)]
end

local function teleport(player: Player, destination: CFrame)
	local root = rootOf(player)
	if root and player.Character then
		player.Character:PivotTo(destination)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

local function syncPlayer(player: Player)
	local survivor = round and round.Survivors[player.UserId]
	local isKiller = round and round.KillerId == player.UserId
	local role = if isKiller then "Killer" elseif survivor then "Survivor" else "Lobby"
	local status = if survivor then survivor.Status elseif isKiller then "Alive"
		elseif phase == "Active" then "Spectating" else "Lobby"
	local bp = if survivor then survivor.BP else 0
	player:SetAttribute("Role", role)
	player:SetAttribute("Status", status)
	player:SetAttribute("BP", bp)
	player:SetAttribute("Rank", if isKiller then "OG Chad" else Rules.rankForBP(bp))
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local bpValue = stats:FindFirstChild("BP") :: IntValue
		local rankValue = stats:FindFirstChild("Rank") :: StringValue
		bpValue.Value = bp
		rankValue.Value = if isKiller then "OG Chad" else Rules.rankForBP(bp)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = if isKiller then Config.KillerWalkSpeed else Config.WalkSpeed
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		-- Plain placeholder bodies; no player appearance assets are loaded.
		local colors = character:FindFirstChildOfClass("BodyColors")
		if not colors then colors = Instance.new("BodyColors"); colors.Parent = character end
		local tint = if isKiller then Color3.fromRGB(189, 85, 62) else Color3.fromRGB(101, 139, 151)
		colors.HeadColor3 = tint
		colors.TorsoColor3 = tint
		colors.LeftArmColor3 = tint
		colors.RightArmColor3 = tint
		colors.LeftLegColor3 = tint
		colors.RightLegColor3 = tint
	end
end

local function syncMatch()
	match:SetAttribute("ObjectiveCount", if round then round.ObjectiveCount else 0)
	match:SetAttribute("ObjectiveGoal", if round then round.ObjectiveGoal else 0)
	for _, player in Players:GetPlayers() do syncPlayer(player) end
end

local function placeCharacter(player: Player)
	syncPlayer(player)
	if phase ~= "Active" or not round then
		teleport(player, world.LobbySpawn)
	elseif player.UserId == round.KillerId then
		teleport(player, world.KillerSpawn)
	else
		local survivor = round.Survivors[player.UserId]
		if not survivor or survivor.Status == "Escaped" then
			teleport(player, world.LobbySpawn)
		elseif survivor.Status == "Captured" then
			teleport(player, world.CageSpawn)
		else
			teleport(player, survivorSpawn())
		end
	end
end

local function onPlayer(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local bp = Instance.new("IntValue")
	bp.Name = "BP"
	bp.Parent = stats
	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Parent = stats
	stats.Parent = player
	syncPlayer(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not humanoid or not root or player.Character ~= character then return end
		humanoid.Died:Connect(function()
			-- Resetting cannot erase BP or free a captured survivor.
			if phase == "Active" and round then
				RoundState.capture(round, player.UserId, os.clock())
				syncPlayer(player)
			end
		end)
		placeCharacter(player)
	end)
	if player.Character then placeCharacter(player) end
end

local function nearPrompt(player: Player, prompt: ProximityPrompt): boolean
	local root = rootOf(player)
	local target = prompt.Parent
	if not root or not target or not target:IsA("BasePart") then return false end
	if (root.Position - target.Position).Magnitude > Config.InteractionDistance then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local hit = Workspace:Raycast(root.Position, target.Position - root.Position, params)
	return not hit or hit.Instance == target
end

local function bindPrompt(prompt: ProximityPrompt, holdSeconds: number, action: (Player, number) -> ())
	prompt.HoldDuration = holdSeconds
	local perPlayer: { [Player]: { At: number, Round: any } } = {}
	holds[prompt] = perPlayer
	prompt.PromptButtonHoldBegan:Connect(function(player)
		if phase ~= "Active" or not round or round.Ended then return end
		local survivor = round.Survivors[player.UserId]
		if survivor and survivor.Status == "Alive" and nearPrompt(player, prompt) then
			perPlayer[player] = { At = os.clock(), Round = round }
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		local hold = perPlayer[player]
		if not hold then return end
		-- An early release is a cancellation. A completed release may arrive just
		-- before Triggered; give that event a short window, never the next hold.
		if os.clock() - hold.At < holdSeconds - 0.1 then
			perPlayer[player] = nil
		else
			task.delay(0.25, function()
				if perPlayer[player] == hold then perPlayer[player] = nil end
			end)
		end
	end)
	prompt.Triggered:Connect(function(player)
		local hold = perPlayer[player]
		perPlayer[player] = nil
		if phase ~= "Active" or not round or round.Ended or not hold or hold.Round ~= round then return end
		local now = os.clock()
		local elapsed = now - hold.At
		if elapsed < holdSeconds - 0.1 or elapsed > holdSeconds + 5 then return end
		if not nearPrompt(player, prompt) then return end
		action(player, now)
		syncMatch()
		RoundState.updateResult(round, now)
	end)
end

bindPrompt(world.ObjectivePrompt, Config.ObjectiveHoldSeconds, function(player, now)
	if RoundState.objective(round, player.UserId, now) then
		match:SetAttribute("Message", if round.ObjectiveCount >= round.ObjectiveGoal
			then "Exit powered. Reach Chad (100 BP), then hold E at the exit."
			else "Terminal calibrated. +25 fictional BP. Keep the team moving.")
	end
end)

bindPrompt(world.ExitPrompt, Config.EscapeHoldSeconds, function(player, now)
	if RoundState.escape(round, player.UserId, now) then
		teleport(player, world.LobbySpawn)
	end
end)

bindPrompt(world.RescuePrompt, Config.RescueHoldSeconds, function(player, now)
	local oldestId: number? = nil
	local oldestExpiry = math.huge
	for id, survivor in round.Survivors do
		if survivor.Status == "Captured" and survivor.CapturedUntil < oldestExpiry then
			oldestId, oldestExpiry = id, survivor.CapturedUntil
		end
	end
	if oldestId and RoundState.rescue(round, player.UserId, oldestId, now) then
		local rescued = Players:GetPlayerByUserId(oldestId)
		if rescued then teleport(rescued, survivorSpawn()) end
		match:SetAttribute("Message", "Rescue successful. Five seconds of capture immunity.")
	end
end)

Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	for _, perPlayer in holds do perPlayer[player] = nil end
	if round then
		RoundState.removePlayer(round, player.UserId)
		RoundState.updateResult(round, os.clock())
		syncMatch()
	end
end)
for _, player in Players:GetPlayers() do onPlayer(player) end

local function tickRound(now: number)
	for _, id in RoundState.releaseExpired(round, now) do
		local player = Players:GetPlayerByUserId(id)
		if player then teleport(player, survivorSpawn()); syncPlayer(player) end
	end
	local killer = Players:GetPlayerByUserId(round.KillerId)
	local killerRoot = killer and rootOf(killer)
	if killerRoot then
		for id, survivor in round.Survivors do
			if survivor.Status == "Alive" then
				local player = Players:GetPlayerByUserId(id)
				local root = player and rootOf(player)
				if root and (root.Position - killerRoot.Position).Magnitude <= Config.CaptureRadius then
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { killer.Character :: Model, player.Character :: Model }
					local wall = Workspace:Raycast(killerRoot.Position, root.Position - killerRoot.Position, params)
					if not wall and RoundState.capture(round, id, now) then
						teleport(player, world.CageSpawn)
						syncPlayer(player)
					end
				end
			end
		end
	end
	RoundState.updateResult(round, now)
	match:SetAttribute("TimeRemaining", math.max(0, math.ceil(round.EndsAt - now)))
end

setPhase("Waiting", "Waiting for at least two players.")
match:SetAttribute("TimeRemaining", 0)
syncMatch()

while true do
	while #Players:GetPlayers() < Config.MinPlayers do task.wait(0.5) end
	setPhase("Intermission", "OG Chad is about to be chosen. Your BP resets each round.")
	local startsAt = os.clock() + Config.IntermissionSeconds
	while os.clock() < startsAt and #Players:GetPlayers() >= Config.MinPlayers do
		match:SetAttribute("TimeRemaining", math.max(0, math.ceil(startsAt - os.clock())))
		task.wait(0.2)
	end
	local participants = Players:GetPlayers()
	if #participants < Config.MinPlayers then
		setPhase("Waiting", "Waiting for at least two players.")
		match:SetAttribute("TimeRemaining", 0)
		continue
	end
	local ids = {}
	for _, player in participants do table.insert(ids, player.UserId) end
	round = assert(RoundState.new(ids, random:NextInteger(1, #ids), os.clock()))
	setPhase("Active", "Hold E at the BP terminal. OG Chad captures survivors on contact.")
	syncMatch()
	for _, player in participants do placeCharacter(player) end
	while not round.Ended do
		tickRound(os.clock())
		task.wait(0.15)
	end
	setPhase("Results", round.Result or "Round complete.")
	for _, player in Players:GetPlayers() do teleport(player, world.LobbySpawn) end
	local resultsEnd = os.clock() + Config.ResultsSeconds
	while os.clock() < resultsEnd do
		match:SetAttribute("TimeRemaining", math.max(0, math.ceil(resultsEnd - os.clock())))
		task.wait(0.2)
	end
	round = nil
	setPhase("Waiting", "Waiting for at least two players.")
	match:SetAttribute("TimeRemaining", 0)
	syncMatch()
end
