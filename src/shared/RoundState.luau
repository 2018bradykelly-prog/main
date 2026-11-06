--!strict
-- Pure, server-owned round state. Roblox adapters validate distance, character
-- health, line of sight and prompt hold duration before invoking these rules.
--
-- Survivor lifecycle:
--   Healthy --hit--> Injured --hit--> Downed --pickup--> Carried --cage--> Caged
--   Downed recovers on its own, or teammates revive it. Carried survivors can
--   wiggle free. Caged survivors are rescued, escape by luck, or are eliminated
--   when their cage timer runs out (the third cage eliminates immediately).
local Config = if script then require(script.Parent.Config) else require("./Config")
local Rules = if script then require(script.Parent.Rules) else require("./Rules")

export type Status = "Healthy" | "Injured" | "Downed" | "Carried" | "Caged" | "Escaped" | "Eliminated"

export type SurvivorStats = {
	Calibrations: number,
	Revives: number,
	Heals: number,
	Rescues: number,
}

export type Survivor = {
	BP: number,
	Status: Status,
	ImmuneUntil: number,
	LastObjectiveAt: number?,
	RecoverAt: number?,
	CarriedAt: number?,
	Wiggles: number,
	WiggleWindowAt: number,
	WiggleWindowCount: number,
	CageCount: number,
	CagedUntil: number?,
	EscapeAttempts: number,
	Hidden: string?,
	Stats: SurvivorStats,
}

export type KillerStats = {
	Hits: number,
	Downs: number,
	Cages: number,
	Eliminations: number,
}

export type Event = { Kind: string, Id: number }

export type State = {
	KillerId: number,
	KillerPresent: boolean,
	KillerStats: KillerStats,
	CarryingId: number?,
	Survivors: { [number]: Survivor },
	TotalSurvivors: number,
	ObjectiveCount: number,
	ObjectiveGoal: number,
	ExitPowered: boolean,
	Terminals: { [string]: number },
	StartedAt: number,
	EndsAt: number,
	Ended: boolean,
	Result: string?,
	Winner: string?,
	EscapedCount: number,
	EliminatedCount: number,
}

local RoundState = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function active(state: State, now: number): boolean
	return not state.Ended and finite(now) and now >= state.StartedAt and now < state.EndsAt
end

-- Free survivors can move, interact and help teammates.
function RoundState.isFree(survivor: Survivor?): boolean
	return survivor ~= nil and (survivor.Status == "Healthy" or survivor.Status == "Injured")
end

-- Finished survivors no longer take part in the round.
function RoundState.isFinished(survivor: Survivor?): boolean
	return survivor ~= nil and (survivor.Status == "Escaped" or survivor.Status == "Eliminated")
end

local function freeSurvivor(state: State, id: number): Survivor?
	local survivor = state.Survivors[id]
	if RoundState.isFree(survivor) and not (survivor :: Survivor).Hidden then
		return survivor
	end
	return nil
end

local function addBP(survivor: Survivor, amount: number)
	survivor.BP = math.min(Config.MaxBP, survivor.BP + amount)
end

local function release(survivor: Survivor, now: number)
	survivor.Status = "Injured"
	survivor.RecoverAt = nil
	survivor.CarriedAt = nil
	survivor.CagedUntil = nil
	survivor.Wiggles = 0
	survivor.ImmuneUntil = now + Config.CaptureGraceSeconds
end

function RoundState.new(participantIds: { number }, killerIndex: number, now: number): (State?, string?)
	if type(participantIds) ~= "table" or #participantIds < Config.MinPlayers then
		return nil, "At least two players are required."
	end
	if not finite(killerIndex) or killerIndex % 1 ~= 0 or killerIndex < 1 or killerIndex > #participantIds then
		return nil, "Killer index must identify a participant."
	end
	if not finite(now) then
		return nil, "Round start time must be finite."
	end
	local seen: { [number]: boolean } = {}
	local count = 0
	for index, id in participantIds do
		if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #participantIds then
			return nil, "Participants must be a dense array."
		end
		if not finite(id) or id % 1 ~= 0 or seen[id] then
			return nil, "Participant IDs must be unique, finite integers."
		end
		seen[id] = true
		count += 1
	end
	if count ~= #participantIds then
		return nil, "Participants must be a dense array."
	end

	local killerId = participantIds[killerIndex]
	local survivors: { [number]: Survivor } = {}
	for _, id in participantIds do
		if id ~= killerId then
			survivors[id] = {
				BP = 0,
				Status = "Healthy",
				ImmuneUntil = now + Config.CaptureGraceSeconds,
				Wiggles = 0,
				WiggleWindowAt = now,
				WiggleWindowCount = 0,
				CageCount = 0,
				EscapeAttempts = 0,
				Stats = { Calibrations = 0, Revives = 0, Heals = 0, Rescues = 0 },
			}
		end
	end
	return {
		KillerId = killerId,
		KillerPresent = true,
		KillerStats = { Hits = 0, Downs = 0, Cages = 0, Eliminations = 0 },
		Survivors = survivors,
		TotalSurvivors = count - 1,
		ObjectiveCount = 0,
		ObjectiveGoal = Rules.objectiveGoal(count - 1),
		ExitPowered = false,
		Terminals = {},
		StartedAt = now,
		EndsAt = now + Config.RoundSeconds,
		Ended = false,
		EscapedCount = 0,
		EliminatedCount = 0,
	}, nil
end

-- Terminals -------------------------------------------------------------------

function RoundState.terminalReady(state: State, terminalId: string, now: number): boolean
	local overheat = state.Terminals[terminalId]
	return overheat == nil or now >= overheat
end

function RoundState.objective(state: State, id: number, now: number, terminalId: string?): boolean
	local survivor = freeSurvivor(state, id)
	local terminal = terminalId or "Main"
	if not active(state, now) or not survivor then
		return false
	end
	if survivor.LastObjectiveAt and now - survivor.LastObjectiveAt < Config.ObjectiveCooldownSeconds then
		return false
	end
	if not RoundState.terminalReady(state, terminal, now) then
		return false
	end
	survivor.LastObjectiveAt = now
	survivor.Stats.Calibrations += 1
	addBP(survivor, Config.BPPerObjective)
	state.Terminals[terminal] = now + Config.TerminalOverheatSeconds
	state.ObjectiveCount = math.min(state.ObjectiveGoal, state.ObjectiveCount + 1)
	if not state.ExitPowered and state.ObjectiveCount >= state.ObjectiveGoal then
		state.ExitPowered = true
		state.EndsAt = math.min(state.EndsAt, now + Config.EndgameSeconds)
	end
	return true
end

-- Killer actions --------------------------------------------------------------

-- Returns the new status ("Injured" or "Downed") when the hit lands.
function RoundState.hit(state: State, id: number, now: number): Status?
	local survivor = freeSurvivor(state, id)
	if not active(state, now) or not survivor or now < survivor.ImmuneUntil then
		return nil
	end
	state.KillerStats.Hits += 1
	if survivor.Status == "Healthy" then
		survivor.Status = "Injured"
	else
		survivor.Status = "Downed"
		survivor.RecoverAt = now + Config.DownedRecoverSeconds
		state.KillerStats.Downs += 1
	end
	return survivor.Status
end

function RoundState.pickup(state: State, id: number, now: number): boolean
	local survivor = state.Survivors[id]
	if not active(state, now) or state.CarryingId or not survivor or survivor.Status ~= "Downed" then
		return false
	end
	survivor.Status = "Carried"
	survivor.RecoverAt = nil
	survivor.CarriedAt = now
	survivor.Wiggles = 0
	state.CarryingId = id
	return true
end

-- Opening an occupied locker grabs the hider straight onto the killer's shoulder.
function RoundState.grabFromLocker(state: State, id: number, now: number): boolean
	local survivor = state.Survivors[id]
	if not active(state, now) or state.CarryingId or not RoundState.isFree(survivor) then
		return false
	end
	local target = survivor :: Survivor
	if not target.Hidden then
		return false
	end
	target.Hidden = nil
	state.KillerStats.Hits += 1
	state.KillerStats.Downs += 1
	target.Status = "Carried"
	target.CarriedAt = now
	target.Wiggles = 0
	state.CarryingId = id
	return true
end

-- Releases whoever the killer carries (wiggle, flash, timeout). Returns their id.
function RoundState.dropCarried(state: State, now: number): number?
	local id = state.CarryingId
	if not id then
		return nil
	end
	state.CarryingId = nil
	local survivor = state.Survivors[id]
	if survivor and survivor.Status == "Carried" then
		release(survivor, now)
	end
	return id
end

-- Returns "Freed" when enough wiggles accumulate, "Progress" otherwise.
function RoundState.wiggle(state: State, id: number, now: number): string?
	local survivor = state.Survivors[id]
	if not active(state, now) or not survivor or survivor.Status ~= "Carried" or state.CarryingId ~= id then
		return nil
	end
	if now - survivor.WiggleWindowAt >= 1 then
		survivor.WiggleWindowAt = now
		survivor.WiggleWindowCount = 0
	end
	if survivor.WiggleWindowCount >= Config.WiggleMaxPerSecond then
		return nil -- Auto-clickers do not wiggle faster than a human.
	end
	survivor.WiggleWindowCount += 1
	survivor.Wiggles += 1
	if survivor.Wiggles >= Config.WiggleGoal then
		RoundState.dropCarried(state, now)
		return "Freed"
	end
	return "Progress"
end

-- Returns "Caged" or "Eliminated".
function RoundState.cage(state: State, id: number, now: number): Status?
	local survivor = state.Survivors[id]
	if not active(state, now) or not survivor or survivor.Status ~= "Carried" or state.CarryingId ~= id then
		return nil
	end
	state.CarryingId = nil
	survivor.CarriedAt = nil
	survivor.CageCount += 1
	state.KillerStats.Cages += 1
	local seconds = Rules.cageSeconds(survivor.CageCount)
	if seconds then
		survivor.Status = "Caged"
		survivor.CagedUntil = now + seconds
		survivor.EscapeAttempts = 0
	else
		survivor.Status = "Eliminated"
		state.EliminatedCount += 1
		state.KillerStats.Eliminations += 1
	end
	return survivor.Status
end

-- Survivor actions ------------------------------------------------------------

function RoundState.rescue(state: State, rescuerId: number, targetId: number, now: number): boolean
	local rescuer = freeSurvivor(state, rescuerId)
	local target = state.Survivors[targetId]
	if not active(state, now) or not rescuer or rescuerId == targetId or not target or target.Status ~= "Caged" then
		return false
	end
	release(target, now)
	rescuer.Stats.Rescues += 1
	addBP(rescuer, Config.BPPerRescue)
	return true
end

-- `roll` is a number in [0, 1) supplied by the caller's random source.
function RoundState.attemptCageEscape(state: State, id: number, now: number, roll: number): boolean?
	local survivor = state.Survivors[id]
	if not active(state, now) or not survivor or survivor.Status ~= "Caged" then
		return nil
	end
	if survivor.EscapeAttempts >= Config.CageEscapeAttempts or not finite(roll) then
		return nil
	end
	survivor.EscapeAttempts += 1
	if roll < Config.CageEscapeChance then
		release(survivor, now)
		return true
	end
	return false
end

function RoundState.revive(state: State, helperId: number, targetId: number, now: number): boolean
	local helper = freeSurvivor(state, helperId)
	local target = state.Survivors[targetId]
	if not active(state, now) or not helper or helperId == targetId or not target or target.Status ~= "Downed" then
		return false
	end
	release(target, now)
	target.ImmuneUntil = now -- Revives do not grant capture immunity.
	helper.Stats.Revives += 1
	addBP(helper, Config.BPPerRevive)
	return true
end

function RoundState.heal(state: State, helperId: number, targetId: number, now: number): boolean
	local helper = freeSurvivor(state, helperId)
	local target = freeSurvivor(state, targetId)
	if not active(state, now) or not helper or not target or helperId == targetId or target.Status ~= "Injured" then
		return false
	end
	target.Status = "Healthy"
	helper.Stats.Heals += 1
	addBP(helper, Config.BPPerHeal)
	return true
end

function RoundState.selfHeal(state: State, id: number, now: number): boolean
	local survivor = freeSurvivor(state, id)
	if not active(state, now) or not survivor or survivor.Status ~= "Injured" then
		return false
	end
	survivor.Status = "Healthy"
	return true
end

function RoundState.escape(state: State, id: number, now: number): boolean
	local survivor = freeSurvivor(state, id)
	if not active(state, now) or not survivor then
		return false
	end
	if survivor.BP < Config.MaxBP or not state.ExitPowered then
		return false
	end
	survivor.Status = "Escaped"
	state.EscapedCount += 1
	return true
end

function RoundState.hide(state: State, id: number, lockerId: string, now: number): boolean
	local survivor = freeSurvivor(state, id)
	if not active(state, now) or not survivor or type(lockerId) ~= "string" then
		return false
	end
	for _, other in state.Survivors do
		if other.Hidden == lockerId then
			return false
		end
	end
	survivor.Hidden = lockerId
	return true
end

function RoundState.unhide(state: State, id: number): boolean
	local survivor = state.Survivors[id]
	if not survivor or not survivor.Hidden then
		return false
	end
	survivor.Hidden = nil
	return true
end

function RoundState.lockerOccupant(state: State, lockerId: string): number?
	for id, survivor in state.Survivors do
		if survivor.Hidden == lockerId and RoundState.isFree(survivor) then
			return id
		end
	end
	return nil
end

-- Time-based transitions. Returns events for the presentation layer.
function RoundState.tick(state: State, now: number): { Event }
	local events: { Event } = {}
	if not active(state, now) then
		return events
	end
	for id, survivor in state.Survivors do
		if survivor.Status == "Downed" and survivor.RecoverAt and now >= survivor.RecoverAt then
			release(survivor, now)
			survivor.ImmuneUntil = now
			table.insert(events, { Kind = "Recovered", Id = id })
		elseif survivor.Status == "Caged" and survivor.CagedUntil and now >= survivor.CagedUntil then
			survivor.Status = "Eliminated"
			survivor.CagedUntil = nil
			state.EliminatedCount += 1
			state.KillerStats.Eliminations += 1
			table.insert(events, { Kind = "Eliminated", Id = id })
		elseif survivor.Status == "Carried" and survivor.CarriedAt and now - survivor.CarriedAt >= Config.CarryMaxSeconds then
			RoundState.dropCarried(state, now)
			table.insert(events, { Kind = "CarryTimeout", Id = id })
		end
	end
	return events
end

function RoundState.removePlayer(state: State, id: number)
	if state.Ended then
		return
	end
	if id == state.KillerId then
		state.KillerPresent = false
		state.Ended = true
		state.Winner = "Survivors"
		state.Result = "Survivors win! The OG Chad left the round."
		return
	end
	local survivor = state.Survivors[id]
	if survivor then
		if state.CarryingId == id then
			state.CarryingId = nil
		end
		if survivor.Status == "Escaped" then
			state.EscapedCount -= 1
		elseif survivor.Status == "Eliminated" then
			state.EliminatedCount -= 1
		end
		state.Survivors[id] = nil
		state.TotalSurvivors -= 1
	end
end

function RoundState.updateResult(state: State, now: number): string?
	if state.Ended then
		return state.Result
	end
	if not finite(now) or now < state.StartedAt then
		return nil
	end
	local remaining = 0
	local total = 0
	for _, survivor in state.Survivors do
		total += 1
		if not RoundState.isFinished(survivor) then
			remaining += 1
		end
	end
	local escaped = state.EscapedCount
	if not state.KillerPresent then
		state.Winner = "Survivors"
		state.Result = "Survivors win! The OG Chad left the round."
	elseif total == 0 then
		state.Winner = "None"
		state.Result = "Round ended: all survivors left."
	elseif remaining == 0 or now >= state.EndsAt then
		local timeUp = remaining > 0
		if Rules.survivorsWin(escaped, total) then
			state.Winner = "Survivors"
			state.Result = string.format("Survivors win! %d of %d escaped the Chad.", escaped, total)
		else
			state.Winner = "Killer"
			if escaped == 0 then
				state.Result = if timeUp
					then "OG Chad wins! Time ran out and nobody escaped."
					else "OG Chad wins! Every survivor was mogged."
			else
				state.Result = string.format("OG Chad wins! Only %d of %d escaped.", escaped, total)
			end
		end
	end
	if state.Result then
		state.Ended = true
	end
	return state.Result
end

-- XP earned this round by a participant (used by persistence).
function RoundState.xpFor(state: State, id: number): number
	local XP = Rules.XP
	local xp = XP.Participation
	if id == state.KillerId then
		local stats = state.KillerStats
		xp += stats.Hits * XP.Hit + stats.Downs * XP.Down + stats.Cages * XP.Cage + stats.Eliminations * XP.Elimination
		if state.Winner == "Killer" then
			xp += XP.KillerWin
		end
		return xp
	end
	local survivor = state.Survivors[id]
	if not survivor then
		return 0
	end
	local stats = survivor.Stats
	xp += stats.Calibrations * XP.Calibration + stats.Revives * XP.Revive + stats.Heals * XP.Heal + stats.Rescues * XP.Rescue
	if survivor.Status == "Escaped" then
		xp += XP.Escape
	end
	if state.Winner == "Survivors" then
		xp += XP.SurvivorWin
	end
	return xp
end

return table.freeze(RoundState)
