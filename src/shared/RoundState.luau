--!strict
-- Pure, server-owned round state. Roblox adapters validate distance, character
-- health and prompt hold duration before invoking these rules.
local Config = if script then require(script.Parent.Config) else require("./Config")
local Rules = if script then require(script.Parent.Rules) else require("./Rules")

export type Survivor = {
	BP: number,
	Status: "Alive" | "Captured" | "Escaped",
	CapturedUntil: number?,
	ImmuneUntil: number,
	LastObjectiveAt: number?,
}

export type State = {
	KillerId: number,
	KillerPresent: boolean,
	Survivors: { [number]: Survivor },
	ObjectiveCount: number,
	ObjectiveGoal: number,
	StartedAt: number,
	EndsAt: number,
	Ended: boolean,
	Result: string?,
	EscapedCount: number,
}

local RoundState = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function active(state: State, now: number): boolean
	return not state.Ended and finite(now) and now >= state.StartedAt and now < state.EndsAt
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
				Status = "Alive",
				ImmuneUntil = now + Config.CaptureGraceSeconds,
			}
		end
	end
	return {
		KillerId = killerId,
		KillerPresent = true,
		Survivors = survivors,
		ObjectiveCount = 0,
		ObjectiveGoal = Rules.objectiveGoal(count - 1),
		StartedAt = now,
		EndsAt = now + Config.RoundSeconds,
		Ended = false,
		EscapedCount = 0,
	}, nil
end

function RoundState.objective(state: State, id: number, now: number): boolean
	local survivor = state.Survivors[id]
	if not active(state, now) or not survivor or survivor.Status ~= "Alive" then
		return false
	end
	if survivor.LastObjectiveAt and now - survivor.LastObjectiveAt < Config.ObjectiveCooldownSeconds then
		return false
	end
	survivor.LastObjectiveAt = now
	survivor.BP = math.min(Config.MaxBP, survivor.BP + Config.BPPerObjective)
	state.ObjectiveCount = math.min(state.ObjectiveGoal, state.ObjectiveCount + 1)
	return true
end

function RoundState.capture(state: State, id: number, now: number): boolean
	local survivor = state.Survivors[id]
	if not active(state, now) or not survivor or survivor.Status ~= "Alive" or now < survivor.ImmuneUntil then
		return false
	end
	survivor.Status = "Captured"
	survivor.CapturedUntil = now + Config.CaptureSeconds
	return true
end

function RoundState.rescue(state: State, rescuerId: number, targetId: number, now: number): boolean
	local rescuer = state.Survivors[rescuerId]
	local target = state.Survivors[targetId]
	if not active(state, now) or not rescuer or rescuer.Status ~= "Alive" or not target or target.Status ~= "Captured" then
		return false
	end
	target.Status = "Alive"
	target.CapturedUntil = nil
	target.ImmuneUntil = now + Config.CaptureGraceSeconds
	return true
end

function RoundState.escape(state: State, id: number, now: number): boolean
	local survivor = state.Survivors[id]
	if not active(state, now) or not survivor or survivor.Status ~= "Alive" then
		return false
	end
	if survivor.BP < Config.MaxBP or state.ObjectiveCount < state.ObjectiveGoal then
		return false
	end
	survivor.Status = "Escaped"
	state.EscapedCount += 1
	return true
end

function RoundState.releaseExpired(state: State, now: number): { number }
	local released = {}
	if not active(state, now) then
		return released
	end
	for id, survivor in state.Survivors do
		if survivor.Status == "Captured" and survivor.CapturedUntil and now >= survivor.CapturedUntil then
			survivor.Status = "Alive"
			survivor.CapturedUntil = nil
			survivor.ImmuneUntil = now + Config.CaptureGraceSeconds
			table.insert(released, id)
		end
	end
	return released
end

function RoundState.removePlayer(state: State, id: number)
	if state.Ended then
		return
	end
	if id == state.KillerId then
		state.KillerPresent = false
		state.Ended = true
		state.Result = "Survivors win! The OG Chad left the round."
	else
		state.Survivors[id] = nil
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
		if survivor.Status ~= "Escaped" then
			remaining += 1
		end
	end
	if not state.KillerPresent then
		state.Result = "Survivors win! The OG Chad left the round."
	elseif total == 0 then
		state.Result = "Round ended: all survivors left."
	elseif remaining == 0 then
		state.Result = string.format("Survivors win! %d escaped.", state.EscapedCount)
	elseif now >= state.EndsAt then
		if state.EscapedCount == 0 then
			state.Result = "OG Chad wins! No survivors escaped before time ran out."
		else
			state.Result = string.format("Time is up! %d escaped; %d failed to escape.", state.EscapedCount, remaining)
		end
	end
	if state.Result then
		state.Ended = true
	end
	return state.Result
end

return table.freeze(RoundState)
