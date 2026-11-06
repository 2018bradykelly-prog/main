--!strict
-- Server authority. Clients can only request ProximityPrompt interactions and
-- send rate-limited Action remotes. Roles, health states, BP, captures,
-- abilities and persistence are validated and owned here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local RoundState = require(Shared.RoundState)
local Abilities = require(Shared.Abilities)
local Maps = require(Shared.Maps)
local World = require(script.Parent.World)
local DataService = require(script.Parent.DataService)

local match = ReplicatedStorage:WaitForChild("MatchState")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("Action") :: RemoteEvent
local notifyRemote = remotes:WaitForChild("Notify") :: RemoteEvent

local random = Random.new()
local lobby = World.createLobby()
local arena: World.Arena? = nil
local round: RoundState.State? = nil
local phase = "Waiting"
Players.RespawnTime = 3

local CARRIED_GROUP = "CarriedSurvivor"
pcall(function()
	PhysicsService:RegisterCollisionGroup(CARRIED_GROUP)
	PhysicsService:CollisionGroupSetCollidable(CARRIED_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(CARRIED_GROUP, CARRIED_GROUP, false)
end)

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Per-round bookkeeping that is presentation/physics only (rules live in RoundState).
type KillerRuntime = {
	NextAttackAt: number,
	Weld: WeldConstraint?,
}
local killer: KillerRuntime = { NextAttackAt = 0, Weld = nil }
local cageOf: { [number]: string } = {}
local lockerOf: { [number]: string } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local lockerUsedAt: { [Player]: number } = {}
local votes: { [Player]: string } = {}
local smokes: { { Position: Vector3, Radius: number, Until: number } } = {}
local holds: { [Player]: { Prompt: ProximityPrompt, At: number, Round: any } } = {}
local actionBudget: { [Player]: { Window: number, Count: number } } = {}

-- Messaging -------------------------------------------------------------------

local function notify(player: Player, payload: { [string]: any })
	notifyRemote:FireClient(player, payload)
end

local function notifyAll(payload: { [string]: any })
	notifyRemote:FireAllClients(payload)
end

local function toast(text: string, tone: string?)
	notifyAll({ Kind = "Toast", Text = text, Tone = tone or "info" })
end

local function setMessage(text: string)
	match:SetAttribute("Message", text)
end

local function setPhase(nextPhase: string, message: string)
	phase = nextPhase
	match:SetAttribute("Phase", phase)
	setMessage(message)
	table.clear(holds)
end

-- Characters ------------------------------------------------------------------

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = humanoidOf(player)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function teleport(player: Player, destination: CFrame)
	local root = rootOf(player)
	if root and player.Character then
		player.Character:PivotTo(destination)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

local function setAnchored(player: Player, anchored: boolean)
	local root = rootOf(player)
	if root then
		root.Anchored = anchored
	end
end

local function survivorSpawn(): CFrame
	local spawns = if arena then arena.SurvivorSpawns else { lobby.Spawn }
	return spawns[random:NextInteger(1, #spawns)] * CFrame.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3))
end

local function killerPlayer(): Player?
	return if round then Players:GetPlayerByUserId(round.KillerId) else nil
end

local function findCage(id: string?): World.Cage?
	if not arena or not id then
		return nil
	end
	for _, cage in arena.Cages do
		if cage.Id == id then
			return cage
		end
	end
	return nil
end

local function findLocker(id: string?): World.Locker?
	if not arena or not id then
		return nil
	end
	for _, locker in arena.Lockers do
		if locker.Id == id then
			return locker
		end
	end
	return nil
end

-- Carrying --------------------------------------------------------------------

local function setCarriedPhysics(player: Player, carried: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Massless = carried
			descendant.CollisionGroup = if carried then CARRIED_GROUP else "Default"
		end
	end
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.PlatformStand = carried
	end
end

local function detachCarry(survivorId: number?)
	if killer.Weld then
		killer.Weld:Destroy()
		killer.Weld = nil
	end
	local survivor = survivorId and Players:GetPlayerByUserId(survivorId)
	if survivor then
		setCarriedPhysics(survivor, false)
	end
	local chad = killerPlayer()
	if chad then
		chad:SetAttribute("Carrying", 0)
	end
end

local function attachCarry(survivor: Player)
	local chad = killerPlayer()
	local killerRoot = chad and rootOf(chad)
	local survivorRoot = rootOf(survivor)
	if not chad or not killerRoot or not survivorRoot then
		return
	end
	detachCarry(nil)
	setAnchored(survivor, false)
	setCarriedPhysics(survivor, true)
	survivorRoot.CFrame = killerRoot.CFrame * CFrame.new(0, 2.6, 0.4) * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = killerRoot
	weld.Part1 = survivorRoot
	weld.Parent = killerRoot
	killer.Weld = weld
	chad:SetAttribute("Carrying", survivor.UserId)
end

-- Releases the carried survivor next to the killer (wiggle, flash, timeout).
local function dropCarriedPlayer(id: number)
	detachCarry(id)
	local survivor = Players:GetPlayerByUserId(id)
	local chad = killerPlayer()
	local killerRoot = chad and rootOf(chad)
	if survivor and killerRoot then
		teleport(survivor, killerRoot.CFrame * CFrame.new(0, 0, 3))
	end
end

-- Attribute sync --------------------------------------------------------------

local function setPromptActive(prompt: ProximityPrompt?, active: boolean)
	if prompt and prompt:GetAttribute("Active") ~= active then
		prompt:SetAttribute("Active", active)
	end
end

local function characterPrompt(player: Player, name: string): ProximityPrompt?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local found = root and root:FindFirstChild(name)
	return if found and found:IsA("ProximityPrompt") then found else nil
end

local function syncPlayer(player: Player)
	local survivor = round and round.Survivors[player.UserId]
	local isKiller = round ~= nil and round.KillerId == player.UserId
	local role = if isKiller then "Killer" elseif survivor then "Survivor" else "Lobby"
	local status = if survivor then survivor.Status
		elseif isKiller then "Hunting"
		elseif phase == "Active" then "Spectating"
		else "Lobby"
	local bp = if survivor then survivor.BP else 0
	local rank = if isKiller then "OG Chad" else Rules.rankForBP(bp)
	player:SetAttribute("Role", role)
	player:SetAttribute("Status", status)
	player:SetAttribute("BP", bp)
	player:SetAttribute("Rank", rank)
	player:SetAttribute("Hidden", survivor ~= nil and survivor.Hidden ~= nil)
	player:SetAttribute("HiddenLocker", if survivor and survivor.Hidden then survivor.Hidden else "")
	player:SetAttribute("CagedUntil", if survivor and survivor.CagedUntil then survivor.CagedUntil else 0)
	player:SetAttribute("RecoverAt", if survivor and survivor.RecoverAt then survivor.RecoverAt else 0)
	player:SetAttribute("CageCount", if survivor then survivor.CageCount else 0)
	player:SetAttribute("EscapeAttemptsLeft", if survivor then Config.CageEscapeAttempts - survivor.EscapeAttempts else 0)
	player:SetAttribute("WiggleProgress", if survivor then survivor.Wiggles / Config.WiggleGoal else 0)
	local stats = player:FindFirstChild("leaderstats")
	local rankValue = stats and stats:FindFirstChild("Rank")
	if rankValue and rankValue:IsA("StringValue") then
		rankValue.Value = if role == "Lobby" then "-" else rank
	end
	local active = phase == "Active" and survivor ~= nil
	setPromptActive(characterPrompt(player, "RevivePrompt"), active and status == "Downed")
	setPromptActive(characterPrompt(player, "PickupPrompt"), active and status == "Downed")
	setPromptActive(characterPrompt(player, "HealPrompt"), active and status == "Injured" and not (survivor and survivor.Hidden))
	local character = player.Character
	local humanoid = humanoidOf(player)
	if humanoid and character then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		local colors = character:FindFirstChildOfClass("BodyColors")
		if not colors then
			colors = Instance.new("BodyColors")
			colors.Parent = character
		end
		local bodyColors = colors :: BodyColors
		local tint = if isKiller then Color3.fromRGB(189, 85, 62)
			elseif status == "Injured" then Color3.fromRGB(150, 110, 110)
			else Color3.fromRGB(101, 139, 151)
		bodyColors.HeadColor3 = if isKiller then Color3.fromRGB(214, 160, 120) else tint
		bodyColors.TorsoColor3 = tint
		bodyColors.LeftArmColor3 = tint
		bodyColors.RightArmColor3 = tint
		bodyColors.LeftLegColor3 = if isKiller then Color3.fromRGB(40, 40, 48) else tint
		bodyColors.RightLegColor3 = if isKiller then Color3.fromRGB(40, 40, 48) else tint
		-- Rough server baseline; the client movement controller refines it.
		humanoid.WalkSpeed = if isKiller then Config.KillerWalkSpeed
			elseif status == "Downed" then Config.DownedSpeed
			elseif status == "Carried" or status == "Caged" then 0
			else Config.WalkSpeed
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = if isKiller then Config.KillerJumpHeight
			elseif status == "Downed" or status == "Carried" or status == "Caged" then 0
			else Config.SurvivorJumpHeight
	end
end

local function syncMatch()
	local current = round
	match:SetAttribute("ObjectiveCount", if current then current.ObjectiveCount else 0)
	match:SetAttribute("ObjectiveGoal", if current then current.ObjectiveGoal else 0)
	match:SetAttribute("ExitPowered", if current then current.ExitPowered else false)
	match:SetAttribute("EndsAt", if current then current.EndsAt else 0)
	if current then
		local alive, escaped, eliminated = 0, current.EscapedCount, current.EliminatedCount
		for _, survivor in current.Survivors do
			if not RoundState.isFinished(survivor) then
				alive += 1
			end
		end
		match:SetAttribute("SurvivorsLeft", alive)
		match:SetAttribute("Escaped", escaped)
		match:SetAttribute("Eliminated", eliminated)
	end
	for _, player in Players:GetPlayers() do
		syncPlayer(player)
	end
end

-- Terminals and exits ---------------------------------------------------------

local function refreshTerminals()
	if not arena or not round then
		return
	end
	local t = now()
	for _, terminal in arena.Terminals do
		local ready = RoundState.terminalReady(round, terminal.Id, t)
		local color = if ready then World.Colors.Cyan else World.Colors.Red
		if terminal.Screen.Color ~= color then
			terminal.Screen.Color = color
			terminal.Light.Color = color
		end
		setPromptActive(terminal.Prompt, phase == "Active" and ready)
	end
end

local function powerExits()
	if not arena then
		return
	end
	for _, exit in arena.Exits do
		exit.Light.Color = World.Colors.Green
		local glow = exit.Light:FindFirstChildOfClass("PointLight")
		if glow then
			glow.Color = World.Colors.Green
		end
		exit.Part.Color = Color3.fromRGB(47, 106, 69)
	end
end

local function activateArenaPrompts(active: boolean)
	if not arena then
		return
	end
	for _, exit in arena.Exits do
		setPromptActive(exit.Prompt, active)
	end
	for _, cage in arena.Cages do
		setPromptActive(cage.RescuePrompt, active)
		setPromptActive(cage.CagePrompt, active)
	end
	for _, locker in arena.Lockers do
		setPromptActive(locker.Prompt, active)
	end
	refreshTerminals()
end

-- Placement -------------------------------------------------------------------

local function unhidePlayer(player: Player, survivorId: number)
	local lockerId = lockerOf[survivorId]
	lockerOf[survivorId] = nil
	if round then
		RoundState.unhide(round, survivorId)
	end
	setAnchored(player, false)
	local locker = findLocker(lockerId)
	if locker then
		teleport(player, locker.Outside)
	end
end

local function placeCharacter(player: Player)
	syncPlayer(player)
	local current = round
	if phase ~= "Active" or not current or not arena then
		teleport(player, lobby.Spawn * CFrame.new(random:NextNumber(-6, 6), 0, random:NextNumber(-4, 4)))
		return
	end
	if player.UserId == current.KillerId then
		teleport(player, arena.KillerSpawn)
		return
	end
	local survivor = current.Survivors[player.UserId]
	if not survivor or RoundState.isFinished(survivor) then
		teleport(player, lobby.Spawn)
	elseif survivor.Status == "Caged" then
		local cage = findCage(cageOf[player.UserId]) or arena.Cages[1]
		teleport(player, cage.Spawn)
	else
		teleport(player, survivorSpawn())
	end
end

local function addCharacterPrompts(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end
	local function make(name: string, action: string, hold: number, kind: string, role: string)
		local prompt = World.prompt(root, name, action, player.DisplayName, hold, kind, role)
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt:SetAttribute("OwnerId", player.UserId)
	end
	make("RevivePrompt", "Revive", Config.ReviveHoldSeconds, "Revive", "Survivor")
	make("HealPrompt", "Heal", Config.HealHoldSeconds, "Heal", "Survivor")
	make("PickupPrompt", "Pick up", Config.PickupHoldSeconds, "Pickup", "Killer")
end

local function onPlayer(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = 1
	level.Parent = stats
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = stats
	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Value = "-"
	rank.Parent = stats
	stats.Parent = player
	cooldowns[player] = {}
	player:SetAttribute("Ability", Abilities.DefaultSurvivor)
	task.spawn(DataService.load, player)
	syncPlayer(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid or player.Character ~= character then
			return
		end
		humanoid.BreakJointsOnDeath = false
		humanoid.Died:Connect(function()
			-- Dying (falling, resetting) never frees a survivor or erases BP.
			local current = round
			if phase ~= "Active" or not current then
				return
			end
			local survivor = current.Survivors[player.UserId]
			if survivor and current.CarryingId == player.UserId then
				detachCarry(player.UserId)
				RoundState.cage(current, player.UserId, now())
				cageOf[player.UserId] = if arena then arena.Cages[1].Id else nil
			elseif player.UserId == current.KillerId and current.CarryingId then
				local carried = current.CarryingId
				RoundState.dropCarried(current, now())
				dropCarriedPlayer(carried)
			end
			if survivor and survivor.Hidden then
				lockerOf[player.UserId] = nil
				RoundState.unhide(current, player.UserId)
			end
			syncMatch()
		end)
		addCharacterPrompts(player, character)
		placeCharacter(player)
	end)
	if player.Character then
		placeCharacter(player)
	end
end

-- Interaction validation ------------------------------------------------------

local function nearPart(player: Player, target: BasePart, ignore: { Instance }?): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	if (root.Position - target.Position).Magnitude > Config.InteractionDistance then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { player.Character :: Model }
	for _, item in ignore or {} do
		table.insert(exclude, item)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(root.Position, target.Position - root.Position, params)
	return not hit or hit.Instance == target or hit.Instance:IsDescendantOf(target.Parent :: Instance)
end

local function ownerOf(prompt: ProximityPrompt): Player?
	local id = prompt:GetAttribute("OwnerId")
	return if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
end

local function isSurvivorFree(player: Player): boolean
	local survivor = round and round.Survivors[player.UserId]
	return survivor ~= nil and RoundState.isFree(survivor) and not survivor.Hidden
end

local function isKiller(player: Player): boolean
	return round ~= nil and round.KillerId == player.UserId
end

local function killerCanAct(player: Player, t: number): boolean
	if not isKiller(player) then
		return false
	end
	local stunned = player:GetAttribute("StunnedUntil")
	return not (type(stunned) == "number" and t < stunned)
end

-- Who is allowed to begin holding each kind of prompt.
local function mayHold(player: Player, prompt: ProximityPrompt): boolean
	if phase ~= "Active" or not round or round.Ended or prompt:GetAttribute("Active") ~= true then
		return false
	end
	local kind = prompt:GetAttribute("Kind")
	local t = now()
	if kind == "Locker" then
		local survivor = round.Survivors[player.UserId]
		if survivor and survivor.Hidden then
			return true -- Leaving a locker.
		end
		return isSurvivorFree(player) or (killerCanAct(player, t) and not round.CarryingId)
	elseif kind == "Pickup" then
		return killerCanAct(player, t) and not round.CarryingId
	elseif kind == "Cage" then
		return killerCanAct(player, t) and round.CarryingId ~= nil
	else
		return isSurvivorFree(player) and ownerOf(prompt) ~= player
	end
end

local function finishAction()
	syncMatch()
	refreshTerminals()
	if round then
		RoundState.updateResult(round, now())
	end
end

local handlers: { [string]: (Player, ProximityPrompt, number) -> () } = {}

handlers.Terminal = function(player, prompt, t)
	local current = round :: RoundState.State
	local body = prompt.Parent :: BasePart
	local terminalId = body:GetAttribute("TerminalId")
	if type(terminalId) ~= "string" then
		return
	end
	local wasPowered = current.ExitPowered
	if not RoundState.objective(current, player.UserId, t, terminalId) then
		return
	end
	notify(player, { Kind = "Toast", Text = string.format("+%d BP · %s", Config.BPPerObjective, Rules.rankForBP(current.Survivors[player.UserId].BP)), Tone = "good" })
	local chad = killerPlayer()
	if chad then
		notify(chad, { Kind = "Ping", Position = body.Position, Label = "Terminal calibrated", Duration = Config.TerminalPingSeconds })
	end
	if current.ExitPowered and not wasPowered then
		powerExits()
		setMessage("EXIT GATES POWERED! Reach Chad rank and escape before the collapse.")
		toast("The exit gates are powered. Endgame collapse has started!", "warn")
	else
		setMessage(string.format("Terminal calibrated (%d/%d).", current.ObjectiveCount, current.ObjectiveGoal))
	end
end

handlers.Exit = function(player, _prompt, t)
	local current = round :: RoundState.State
	local survivor = current.Survivors[player.UserId]
	if survivor and survivor.BP < Config.MaxBP then
		notify(player, { Kind = "Toast", Text = "You need Chad rank (100 BP) to escape.", Tone = "bad" })
		return
	end
	if not current.ExitPowered then
		notify(player, { Kind = "Toast", Text = "The exit has no power yet. Calibrate more terminals.", Tone = "bad" })
		return
	end
	if RoundState.escape(current, player.UserId, t) then
		teleport(player, lobby.Spawn)
		toast(player.DisplayName .. " escaped the Chad!", "good")
	end
end

handlers.Rescue = function(player, prompt, t)
	local current = round :: RoundState.State
	local cageId = (prompt.Parent :: BasePart):GetAttribute("CageId")
	local targetId: number? = nil
	local soonest = math.huge
	for id, survivor in current.Survivors do
		if survivor.Status == "Caged" and cageOf[id] == cageId and (survivor.CagedUntil or math.huge) < soonest then
			targetId, soonest = id, survivor.CagedUntil or math.huge
		end
	end
	if not targetId then
		notify(player, { Kind = "Toast", Text = "Nobody is locked in this cage.", Tone = "info" })
		return
	end
	if RoundState.rescue(current, player.UserId, targetId, t) then
		cageOf[targetId] = nil
		local rescued = Players:GetPlayerByUserId(targetId)
		local panel = prompt.Parent :: BasePart
		if rescued then
			teleport(rescued, CFrame.new(panel.Position + panel.CFrame.LookVector * 4 + Vector3.new(0, 2, 0)))
		end
		toast(string.format("%s freed %s from the Mog Cage!", player.DisplayName, if rescued then rescued.DisplayName else "a teammate"), "good")
	end
end

handlers.Cage = function(player, prompt, t)
	local current = round :: RoundState.State
	local carriedId = current.CarryingId
	if not carriedId then
		return
	end
	local cageId = (prompt.Parent :: BasePart):GetAttribute("CageId")
	local result = RoundState.cage(current, carriedId, t)
	if not result then
		return
	end
	detachCarry(carriedId)
	local victim = Players:GetPlayerByUserId(carriedId)
	local name = if victim then victim.DisplayName else "A survivor"
	if result == "Caged" then
		cageOf[carriedId] = if type(cageId) == "string" then cageId else nil
		local cage = findCage(cageOf[carriedId])
		if victim and cage then
			teleport(victim, cage.Spawn * CFrame.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3)))
		end
		toast(name .. " was locked in a Mog Cage! Free them before time runs out.", "bad")
	else
		cageOf[carriedId] = nil
		if victim then
			teleport(victim, lobby.Spawn)
		end
		toast(name .. " was eliminated (third cage).", "bad")
	end
end

handlers.Pickup = function(player, prompt, t)
	local current = round :: RoundState.State
	local target = ownerOf(prompt)
	if not target or not RoundState.pickup(current, target.UserId, t) then
		return
	end
	attachCarry(target)
	notify(target, { Kind = "Toast", Text = "You were picked up! Mash SPACE (or the button) to wiggle free.", Tone = "bad" })
end

handlers.Revive = function(player, prompt, t)
	local target = ownerOf(prompt)
	if target and RoundState.revive(round :: RoundState.State, player.UserId, target.UserId, t) then
		toast(player.DisplayName .. " revived " .. target.DisplayName .. ".", "good")
	end
end

handlers.Heal = function(player, prompt, t)
	local target = ownerOf(prompt)
	if target and RoundState.heal(round :: RoundState.State, player.UserId, target.UserId, t) then
		notify(target, { Kind = "Toast", Text = player.DisplayName .. " patched you up. You are healthy.", Tone = "good" })
		notify(player, { Kind = "Toast", Text = string.format("+%d BP for healing", Config.BPPerHeal), Tone = "good" })
	end
end

handlers.Locker = function(player, prompt, t)
	local current = round :: RoundState.State
	local door = prompt.Parent :: BasePart
	local lockerId = door:GetAttribute("LockerId")
	local locker = findLocker(if type(lockerId) == "string" then lockerId else nil)
	if not locker then
		return
	end
	local last = lockerUsedAt[player]
	if last and t - last < Config.LockerCooldownSeconds then
		return
	end
	lockerUsedAt[player] = t
	local survivor = current.Survivors[player.UserId]
	if survivor then
		if survivor.Hidden == locker.Id then
			unhidePlayer(player, player.UserId)
		elseif not survivor.Hidden and RoundState.hide(current, player.UserId, locker.Id, t) then
			lockerOf[player.UserId] = locker.Id
			teleport(player, locker.Inside)
			setAnchored(player, true)
		end
		return
	end
	if player.UserId == current.KillerId then
		local occupantId = RoundState.lockerOccupant(current, locker.Id)
		if occupantId and RoundState.grabFromLocker(current, occupantId, t) then
			lockerOf[occupantId] = nil
			local occupant = Players:GetPlayerByUserId(occupantId)
			if occupant then
				setAnchored(occupant, false)
				attachCarry(occupant)
				notify(occupant, { Kind = "Toast", Text = "Found you! Wiggle free (mash SPACE).", Tone = "bad" })
			end
			toast("OG Chad pulled a survivor out of a locker!", "bad")
		else
			notify(player, { Kind = "Toast", Text = "Empty locker.", Tone = "info" })
		end
	end
end

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
	if mayHold(player, prompt) then
		holds[player] = { Prompt = prompt, At = os.clock(), Round = round }
	end
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, player)
	local hold = holds[player]
	if not hold or hold.Prompt ~= prompt then
		return
	end
	-- An early release cancels. A completed release can arrive just before
	-- Triggered; give that event a short window, never the next hold.
	if os.clock() - hold.At < prompt.HoldDuration - 0.1 then
		holds[player] = nil
	else
		task.delay(0.25, function()
			if holds[player] == hold then
				holds[player] = nil
			end
		end)
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	local hold = holds[player]
	holds[player] = nil
	local kind = prompt:GetAttribute("Kind")
	local handler = if type(kind) == "string" then handlers[kind] else nil
	if not handler or not round or round.Ended or phase ~= "Active" then
		return
	end
	if not mayHold(player, prompt) then
		return
	end
	-- Very short holds may not fire HoldBegan on every platform; anything
	-- longer than half a second must have a matching, completed hold.
	if prompt.HoldDuration > 0.5 then
		if not hold or hold.Prompt ~= prompt or hold.Round ~= round then
			return
		end
		local elapsed = os.clock() - hold.At
		if elapsed < prompt.HoldDuration - 0.15 or elapsed > prompt.HoldDuration + 5 then
			return
		end
	end
	local target = prompt.Parent
	if not target or not target:IsA("BasePart") then
		return
	end
	local ignore: { Instance } = {}
	local owner = ownerOf(prompt)
	if owner and owner.Character then
		table.insert(ignore, owner.Character)
	end
	local survivor = round.Survivors[player.UserId]
	if not (survivor and survivor.Hidden) and not nearPart(player, target, ignore) then
		return
	end
	handler(player, prompt, now())
	finishAction()
end)

-- Abilities and combat --------------------------------------------------------

local function abilityReady(player: Player, id: string, t: number): boolean
	local list = cooldowns[player]
	return list ~= nil and (list[id] == nil or t >= list[id])
end

local function startCooldown(player: Player, ability: Abilities.Ability, t: number)
	local list = cooldowns[player]
	if list then
		list[ability.Id] = t + ability.Cooldown
	end
	player:SetAttribute("Ready_" .. ability.Id, t + ability.Cooldown)
end

local function insideSmoke(position: Vector3, t: number): boolean
	for _, smoke in smokes do
		if t < smoke.Until and (position - smoke.Position).Magnitude <= smoke.Radius then
			return true
		end
	end
	return false
end

-- Segment/sphere test: does the line from a to b pass through any active smoke?
local function smokeBlocks(a: Vector3, b: Vector3, t: number): boolean
	local direction = b - a
	local length = direction.Magnitude
	if length < 1e-3 then
		return false
	end
	local unit = direction / length
	for _, smoke in smokes do
		if t < smoke.Until then
			local projection = math.clamp((smoke.Position - a):Dot(unit), 0, length)
			if (a + unit * projection - smoke.Position).Magnitude <= smoke.Radius then
				return true
			end
		end
	end
	return false
end

local function clearLine(fromPlayer: Player, toPlayer: Player, a: Vector3, b: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { fromPlayer.Character :: Model, toPlayer.Character :: Model }
	return Workspace:Raycast(a, b - a, params) == nil
end

local function stunKiller(seconds: number, reason: string)
	local chad = killerPlayer()
	local current = round
	if not chad or not current then
		return
	end
	chad:SetAttribute("StunnedUntil", now() + seconds)
	notify(chad, { Kind = "Blind", Duration = seconds, Reason = reason })
	if current.CarryingId then
		local carried = current.CarryingId
		RoundState.dropCarried(current, now())
		dropCarriedPlayer(carried)
		local freed = Players:GetPlayerByUserId(carried)
		toast((if freed then freed.DisplayName else "A survivor") .. " broke free from the OG Chad!", "good")
	end
end

local function killerAttack(player: Player, t: number)
	local current = round
	if not current or not killerCanAct(player, t) or current.CarryingId or t < killer.NextAttackAt then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.new(0, 0, -1)
	local bestId: number? = nil
	local bestDistance = math.huge
	for id, survivor in current.Survivors do
		if RoundState.isFree(survivor) and not survivor.Hidden and t >= survivor.ImmuneUntil then
			local target = Players:GetPlayerByUserId(id)
			local targetRoot = target and rootOf(target)
			if target and targetRoot then
				local offset = targetRoot.Position - root.Position
				if math.abs(offset.Y) < 6 and Rules.inAttackCone(offset.X, offset.Z, forward.X, forward.Z)
					and not insideSmoke(targetRoot.Position, t)
					and not smokeBlocks(root.Position, targetRoot.Position, t)
					and clearLine(player, target, root.Position, targetRoot.Position)
				then
					local distance = offset.Magnitude
					if distance < bestDistance then
						bestId, bestDistance = id, distance
					end
				end
			end
		end
	end
	notifyAll({ Kind = "Swing", Id = player.UserId })
	if not bestId then
		killer.NextAttackAt = t + Config.AttackMissCooldown
		player:SetAttribute("SlowUntil", t + Config.AttackMissSlowSeconds)
		player:SetAttribute("AttackReadyAt", killer.NextAttackAt)
		return
	end
	local result = RoundState.hit(current, bestId, t)
	killer.NextAttackAt = t + (if result then Config.AttackHitCooldown else Config.AttackMissCooldown)
	player:SetAttribute("SlowUntil", t + (if result then Config.AttackHitSlowSeconds else Config.AttackMissSlowSeconds))
	player:SetAttribute("AttackReadyAt", killer.NextAttackAt)
	if not result then
		return
	end
	local victim = Players:GetPlayerByUserId(bestId)
	notifyAll({ Kind = "Hit", Id = bestId, Downed = result == "Downed" })
	if victim then
		if result == "Injured" then
			victim:SetAttribute("BoostUntil", t + Config.InjuredBoostSeconds)
			notify(victim, { Kind = "Toast", Text = "You're injured! Run! One more hit downs you.", Tone = "bad" })
		else
			toast(victim.DisplayName .. " is down! Revive them before they are caged.", "bad")
		end
	end
	finishAction()
end

local function useAbility(player: Player, abilityId: any, t: number)
	local current = round
	local ability = Abilities.get(abilityId)
	if not current or phase ~= "Active" or not ability or not abilityReady(player, ability.Id, t) then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	if ability.Role == "Killer" then
		if not killerCanAct(player, t) then
			return
		end
		if ability.Id == "Charge" then
			if current.CarryingId then
				return
			end
			player:SetAttribute("ChargeUntil", t + ability.Duration)
		elseif ability.Id == "Reveal" then
			local ids = {}
			for id, survivor in current.Survivors do
				if not RoundState.isFinished(survivor) and not survivor.Hidden then
					table.insert(ids, id)
				end
			end
			notify(player, { Kind = "Reveal", Ids = ids, Duration = ability.Duration })
			for id in current.Survivors do
				local survivorPlayer = Players:GetPlayerByUserId(id)
				if survivorPlayer then
					notify(survivorPlayer, { Kind = "Toast", Text = "MOG AURA! The OG Chad can see you (lockers hide you).", Tone = "warn" })
				end
			end
		else
			return
		end
		startCooldown(player, ability, t)
		return
	end

	-- Survivor abilities: must be their selected loadout and they must be free.
	if player:GetAttribute("Ability") ~= ability.Id or not isSurvivorFree(player) then
		return
	end
	if ability.Id == "Dash" then
		notify(player, { Kind = "Dash", Duration = ability.Duration })
	elseif ability.Id == "Smoke" then
		local radius = 11
		local position = root.Position
		table.insert(smokes, { Position = position, Radius = radius, Until = t + ability.Duration })
		local cloud = Instance.new("Part")
		cloud.Name = "SmokeCloud"
		cloud.Shape = Enum.PartType.Ball
		cloud.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		cloud.CFrame = CFrame.new(position)
		cloud.Anchored = true
		cloud.CanCollide = false
		cloud.CanQuery = false
		cloud.CanTouch = false
		cloud.CastShadow = false
		cloud.Material = Enum.Material.SmoothPlastic
		cloud.Color = Color3.fromRGB(170, 178, 196)
		cloud.Transparency = 0.25
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 40
		emitter.Lifetime = NumberRange.new(2, 3)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.Size = NumberSequence.new(6, 10)
		emitter.Transparency = NumberSequence.new(0.3, 1)
		emitter.Color = ColorSequence.new(Color3.fromRGB(190, 196, 210))
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = cloud
		cloud.Parent = if arena then arena.Folder else Workspace
		Debris:AddItem(cloud, ability.Duration)
	elseif ability.Id == "Flash" then
		notifyAll({ Kind = "Flash", Position = root.Position })
		local chad = killerPlayer()
		local killerRoot = chad and rootOf(chad)
		if chad and killerRoot then
			local offset = root.Position - killerRoot.Position
			local facingDot = if offset.Magnitude > 1e-3 then killerRoot.CFrame.LookVector:Dot(offset.Unit) else 1
			if offset.Magnitude <= 16 and facingDot > 0.2 and clearLine(player, chad, root.Position, killerRoot.Position) then
				stunKiller(ability.Duration, "Jawline Flash")
				notify(player, { Kind = "Toast", Text = "Direct hit! OG Chad is blinded.", Tone = "good" })
			else
				notify(player, { Kind = "Toast", Text = "The flash missed. Aim at the OG Chad's face.", Tone = "info" })
			end
		end
	elseif ability.Id == "Shake" then
		local survivor = current.Survivors[player.UserId]
		if survivor.Status == "Injured" then
			player:SetAttribute("SlowUntil", t + ability.Duration)
			notify(player, { Kind = "Toast", Text = "Drinking... stay alive for 4 seconds.", Tone = "info" })
			local expected = current
			task.delay(ability.Duration, function()
				if round == expected and RoundState.selfHeal(expected, player.UserId, now()) then
					notify(player, { Kind = "Toast", Text = "Protein Shake: fully healed!", Tone = "good" })
					syncMatch()
				end
			end)
		else
			player:SetAttribute("BoostUntil", t + 3)
			notify(player, { Kind = "Stamina" })
		end
	else
		return
	end
	startCooldown(player, ability, t)
end

local function refreshVoteCounts()
	local counts: { [string]: number } = {}
	for _, choice in votes do
		counts[choice] = (counts[choice] or 0) + 1
	end
	for _, def in Maps.List do
		match:SetAttribute("Votes_" .. def.Id, counts[def.Id] or 0)
	end
end

local function allowAction(player: Player): boolean
	local clock = os.clock()
	local budget = actionBudget[player]
	if not budget or clock - budget.Window >= 1 then
		budget = { Window = clock, Count = 0 }
		actionBudget[player] = budget
	end
	budget.Count += 1
	return budget.Count <= 25
end

actionRemote.OnServerEvent:Connect(function(player: Player, action: any, argument: any)
	if type(action) ~= "string" or not allowAction(player) then
		return
	end
	local t = now()
	if action == "Attack" then
		if phase == "Active" then
			killerAttack(player, t)
		end
	elseif action == "Ability" then
		useAbility(player, argument, t)
		syncMatch()
	elseif action == "Wiggle" then
		local current = round
		if phase == "Active" and current then
			local result = RoundState.wiggle(current, player.UserId, t)
			if result == "Freed" then
				dropCarriedPlayer(player.UserId)
				local chad = killerPlayer()
				if chad then
					chad:SetAttribute("StunnedUntil", t + 1.5)
					notify(chad, { Kind = "Blind", Duration = 0.6, Reason = "Wiggle" })
				end
				toast(player.DisplayName .. " wiggled free!", "good")
				syncMatch()
			elseif result then
				player:SetAttribute("WiggleProgress", current.Survivors[player.UserId].Wiggles / Config.WiggleGoal)
			end
		end
	elseif action == "Struggle" then
		local current = round
		if phase == "Active" and current then
			local result = RoundState.attemptCageEscape(current, player.UserId, t, random:NextNumber())
			if result == true then
				local cage = findCage(cageOf[player.UserId])
				cageOf[player.UserId] = nil
				if cage then
					teleport(player, CFrame.new(cage.Panel.Position + cage.Panel.CFrame.LookVector * 4 + Vector3.new(0, 2, 0)))
				end
				toast(player.DisplayName .. " broke out of the cage by themselves!", "good")
			elseif result == false then
				notify(player, { Kind = "Toast", Text = "The bars hold...", Tone = "bad" })
			end
			syncMatch()
		end
	elseif action == "Vote" then
		if (phase == "Waiting" or phase == "Intermission") and type(argument) == "string" and Maps.get(argument) then
			votes[player] = argument
			refreshVoteCounts()
		end
	elseif action == "Loadout" then
		local inRound = round ~= nil and (round.Survivors[player.UserId] ~= nil or round.KillerId == player.UserId)
		if not inRound and type(argument) == "string" and DataService.setAbility(player, argument) then
			notify(player, { Kind = "Toast", Text = "Loadout: " .. (Abilities.get(argument) :: Abilities.Ability).Name, Tone = "good" })
		end
	end
end)

-- Players leaving -------------------------------------------------------------

Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	holds[player] = nil
	votes[player] = nil
	refreshVoteCounts()
	cooldowns[player] = nil
	lockerUsedAt[player] = nil
	actionBudget[player] = nil
	local current = round
	if current then
		if current.CarryingId == player.UserId or (player.UserId == current.KillerId and current.CarryingId) then
			detachCarry(current.CarryingId)
		end
		RoundState.removePlayer(current, player.UserId)
		RoundState.updateResult(current, now())
		cageOf[player.UserId] = nil
		lockerOf[player.UserId] = nil
		syncMatch()
	end
	DataService.release(player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
DataService.start()

-- Leaderboard -----------------------------------------------------------------

local function refreshLeaderboard()
	local rows, global = DataService.topWins(#lobby.LeaderboardRows)
	lobby.LeaderboardTitle.Text = if global then "TOP MOGGERS (GLOBAL WINS)" else "TOP MOGGERS (THIS SERVER)"
	for index, label in lobby.LeaderboardRows do
		local row = rows[index]
		label.Text = if row then string.format("  %d.  %s  —  %d wins", index, row.Name, row.Wins) else ""
	end
end

task.spawn(function()
	while true do
		task.wait(5)
		refreshLeaderboard()
		task.wait(Config.LeaderboardRefreshSeconds - 5)
	end
end)

-- Round loop ------------------------------------------------------------------

local function tickRound(t: number)
	local current = round
	if not current then
		return
	end
	for _, event in RoundState.tick(current, t) do
		local player = Players:GetPlayerByUserId(event.Id)
		local name = if player then player.DisplayName else "A survivor"
		if event.Kind == "Eliminated" then
			cageOf[event.Id] = nil
			if player then
				teleport(player, lobby.Spawn)
			end
			toast(name .. " ran out of time in the cage and was eliminated.", "bad")
		elseif event.Kind == "CarryTimeout" then
			dropCarriedPlayer(event.Id)
			toast(name .. " slipped free from the OG Chad's grip.", "good")
		elseif event.Kind == "Recovered" then
			if player then
				notify(player, { Kind = "Toast", Text = "You picked yourself up.", Tone = "good" })
			end
		end
	end
	-- Expired smoke clouds.
	for index = #smokes, 1, -1 do
		if t >= smokes[index].Until then
			table.remove(smokes, index)
		end
	end
	-- Keep hidden survivors pinned inside their locker.
	for id, lockerId in lockerOf do
		local player = Players:GetPlayerByUserId(id)
		local locker = findLocker(lockerId)
		local root = player and rootOf(player)
		if player and locker and root and (root.Position - locker.Inside.Position).Magnitude > 2 then
			teleport(player, locker.Inside)
			setAnchored(player, true)
		end
	end
	RoundState.updateResult(current, t)
	match:SetAttribute("TimeRemaining", math.max(0, math.ceil(current.EndsAt - t)))
	syncMatch()
	refreshTerminals()
end

local function resetRuntime()
	detachCarry(nil)
	table.clear(cageOf)
	table.clear(lockerOf)
	table.clear(smokes)
	table.clear(holds)
	killer.NextAttackAt = 0
	for player, list in cooldowns do
		table.clear(list)
		for _, list2 in { Abilities.Survivor, Abilities.Killer } do
			for _, ability in list2 do
				player:SetAttribute("Ready_" .. ability.Id, 0)
			end
		end
	end
	for _, player in Players:GetPlayers() do
		setAnchored(player, false)
		for _, name in { "SlowUntil", "BoostUntil", "StunnedUntil", "ChargeUntil", "AttackReadyAt" } do
			player:SetAttribute(name, 0)
		end
		player:SetAttribute("Carrying", 0)
	end
end

local function chooseMap(): any
	local options = Maps.ids()
	local chosen = Rules.pickVote(options, votes, function(count)
		return random:NextInteger(1, count)
	end)
	return Maps.get(chosen) or Maps.List[1]
end

local function publishVoteOptions()
	local entries = {}
	for _, def in Maps.List do
		table.insert(entries, def.Id .. "|" .. def.Name .. "|" .. def.Blurb)
	end
	match:SetAttribute("MapOptions", table.concat(entries, ";"))
	refreshVoteCounts()
end

local function finishRound(current: RoundState.State)
	local rows = {}
	for _, player in Players:GetPlayers() do
		local id = player.UserId
		local survivor = current.Survivors[id]
		local isChad = id == current.KillerId
		if survivor or isChad then
			local xp = RoundState.xpFor(current, id)
			local won = (isChad and current.Winner == "Killer") or (survivor ~= nil and current.Winner == "Survivors")
			local stats = current.KillerStats
			local before, after = DataService.record(player, {
				XP = xp,
				Won = won,
				Role = if isChad then "Killer" else "Survivor",
				Escaped = survivor ~= nil and survivor.Status == "Escaped",
				Calibrations = if survivor then survivor.Stats.Calibrations else 0,
				Rescues = if survivor then survivor.Stats.Rescues else 0,
				Revives = if survivor then survivor.Stats.Revives else 0,
				Downs = if isChad then stats.Downs else 0,
				Cages = if isChad then stats.Cages else 0,
			})
			table.insert(rows, {
				Name = player.DisplayName,
				Role = if isChad then "OG Chad" else "Survivor",
				Outcome = if isChad then string.format("%d downs · %d cages", stats.Downs, stats.Cages)
					elseif survivor then (survivor :: any).Status
					else "",
				Rank = if survivor then Rules.rankForBP(survivor.BP) else "OG Chad",
				XP = xp,
				Won = won,
				LevelUp = after > before,
				Level = after,
			})
		end
	end
	notifyAll({ Kind = "Results", Winner = current.Winner or "None", Result = current.Result or "Round over.", Rows = rows })
end

setPhase("Waiting", "Waiting for at least two players.")
match:SetAttribute("TimeRemaining", 0)
match:SetAttribute("MapName", "")
publishVoteOptions()
syncMatch()

while true do
	while #Players:GetPlayers() < Config.MinPlayers do
		task.wait(0.5)
	end
	publishVoteOptions()
	setPhase("Intermission", "Vote for a map and pick your ability!")
	local startsAt = now() + Config.IntermissionSeconds
	while now() < startsAt and #Players:GetPlayers() >= Config.MinPlayers do
		match:SetAttribute("TimeRemaining", math.max(0, math.ceil(startsAt - now())))
		task.wait(0.2)
	end
	local participants = Players:GetPlayers()
	if #participants < Config.MinPlayers then
		setPhase("Waiting", "Waiting for at least two players.")
		match:SetAttribute("TimeRemaining", 0)
		continue
	end

	local def = chooseMap()
	table.clear(votes)
	refreshVoteCounts()
	arena = World.build(def)
	match:SetAttribute("MapName", def.Name)
	match:SetAttribute("MapId", def.Id)
	resetRuntime()
	local ids = {}
	for _, player in participants do
		table.insert(ids, player.UserId)
	end
	local created = assert(RoundState.new(ids, random:NextInteger(1, #ids), now()))
	round = created
	setPhase("Active", "Calibrate BP terminals. Avoid the OG Chad.")
	activateArenaPrompts(true)
	syncMatch()
	local chad = killerPlayer()
	for _, player in participants do
		placeCharacter(player)
		notify(player, {
			Kind = "RoleReveal",
			Role = if player.UserId == created.KillerId then "Killer" else "Survivor",
			MapName = def.Name,
			KillerName = if chad then chad.DisplayName else "?",
		})
	end
	while not created.Ended do
		tickRound(now())
		task.wait(0.1)
	end

	setPhase("Results", created.Result or "Round complete.")
	activateArenaPrompts(false)
	detachCarry(created.CarryingId)
	finishRound(created)
	for _, player in Players:GetPlayers() do
		setAnchored(player, false)
		teleport(player, lobby.Spawn * CFrame.new(random:NextNumber(-6, 6), 0, random:NextNumber(-4, 4)))
	end
	local resultsEnd = now() + Config.ResultsSeconds
	while now() < resultsEnd do
		match:SetAttribute("TimeRemaining", math.max(0, math.ceil(resultsEnd - now())))
		task.wait(0.2)
	end
	round = nil
	World.clear()
	arena = nil
	resetRuntime()
	match:SetAttribute("MapName", "")
	setPhase("Waiting", "Waiting for at least two players.")
	match:SetAttribute("TimeRemaining", 0)
	syncMatch()
	refreshLeaderboard()
end
