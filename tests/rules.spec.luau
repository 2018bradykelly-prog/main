-- Run from the repository root: lune run tests/rules.spec.luau
local Config = require("../src/shared/Config")
local Rules = require("../src/shared/Rules")
local RoundState = require("../src/shared/RoundState")
local Abilities = require("../src/shared/Abilities")

local passed = 0
local failed = 0
local assertions = 0

local function equal(actual, expected, label)
	assertions += 1
	assert(actual == expected, string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)))
end

local function test(name, callback)
	local ok, message = pcall(callback)
	if ok then
		passed += 1
		print("PASS " .. name)
	else
		failed += 1
		warn("FAIL " .. name .. "\n" .. tostring(message))
	end
end

local function fresh(ids, killerIndex, now)
	local state, reason = RoundState.new(ids or { 101, 102, 103 }, killerIndex or 1, now or 0)
	assert(state, reason)
	return state
end

-- Four calibrations on four different terminals: 0 -> 100 BP.
local function promote(state, id, fromTime)
	for step = 0, 3 do
		local now = (fromTime or 6) + step * Config.ObjectiveCooldownSeconds
		equal(RoundState.objective(state, id, now, "P" .. id .. "_" .. step), true, "promotion objective")
	end
end

-- Hit twice (respecting immunity) and return when downed.
local function down(state, id, now)
	local expected = if state.Survivors[id].Status == "Healthy" then "Injured" else "Downed"
	equal(RoundState.hit(state, id, now), expected, "hit")
	if state.Survivors[id].Status == "Injured" then
		equal(RoundState.hit(state, id, now + 0.1), "Downed", "second hit")
	end
end

local function cageSurvivor(state, id, now)
	down(state, id, now)
	equal(RoundState.pickup(state, id, now + 1), true, "pickup")
	return RoundState.cage(state, id, now + 2)
end

-- Setup ---------------------------------------------------------------------

test("each participant can be the one killer, all others start healthy LTN survivors", function()
	for index = 1, 4 do
		local ids = { 101, 102, 103, 104 }
		local state = fresh(ids, index, 50)
		equal(state.KillerId, ids[index])
		equal(state.Survivors[state.KillerId], nil)
		local count = 0
		for id, survivor in state.Survivors do
			assert(id ~= state.KillerId)
			count += 1
			equal(survivor.Status, "Healthy")
			equal(survivor.BP, 0)
			equal(survivor.ImmuneUntil, 50 + Config.CaptureGraceSeconds)
			equal(survivor.CageCount, 0)
		end
		equal(count, 3)
		equal(state.TotalSurvivors, 3)
		equal(state.EndsAt, 50 + Config.RoundSeconds)
	end
end)

test("reject insufficient, duplicate, sparse and malformed participants", function()
	for _, ids in { {}, { 1 }, { 1, 1 }, { 1, "bad" }, { 1, 2.5 }, { 1, math.huge }, { 1, 0 / 0 }, { [1] = 1, [3] = 3 }, { 1, 2, extra = 3 } } do
		local state, message = RoundState.new(ids, 1, 0)
		equal(state, nil)
		equal(type(message), "string")
	end
end)

test("negative Studio test user IDs are valid", function()
	local state = fresh({ -1, -2 }, 2)
	equal(state.KillerId, -2)
	equal(state.Survivors[-1].BP, 0)
end)

test("invalid killer selection and invalid clock are rejected", function()
	for _, index in { 0, -1, 3, 1.5, math.huge, 0 / 0 } do
		equal(RoundState.new({ 1, 2 }, index, 0), nil)
	end
	for _, now in { math.huge, -math.huge, 0 / 0 } do
		equal(RoundState.new({ 1, 2 }, 1, now), nil)
	end
end)

-- Ranks and pure rules --------------------------------------------------------

test("rank boundaries and next-rank thresholds follow fictional BP progression", function()
	local examples = { { -1, "LTN" }, { 0, "LTN" }, { 24, "LTN" }, { 25, "MTN" }, { 49, "MTN" }, { 50, "HTN" }, { 74, "HTN" }, { 75, "Chadlite" }, { 99, "Chadlite" }, { 100, "Chad" }, { 500, "Chad" } }
	for _, example in examples do
		equal(Rules.rankForBP(example[1]), example[2])
	end
	for index = 1, #Config.Ranks - 1 do
		local nextRank = Rules.nextRank(Config.Ranks[index].BP)
		equal(nextRank.Name, Config.Ranks[index + 1].Name)
	end
	equal(Rules.nextRank(100), nil)
end)

test("team objective goal scales for two-player and larger sessions", function()
	equal(Rules.objectiveGoal(1), 4)
	equal(Rules.objectiveGoal(2), 6)
	equal(Rules.objectiveGoal(5), 15)
end)

test("attack cone requires range and facing", function()
	equal(Rules.inAttackCone(0, 5, 0, 1), true)
	equal(Rules.inAttackCone(0, -5, 0, 1), false)
	equal(Rules.inAttackCone(5, 0, 0, 1), false)
	equal(Rules.inAttackCone(0, Config.AttackRange + 0.1, 0, 1), false)
	equal(Rules.inAttackCone(0.5, -0.5, 0, 1), true) -- overlapping bodies
	equal(Rules.inAttackCone(0 / 0, 1, 0, 1), false)
end)

test("levels, titles and XP curve are monotonic and safe", function()
	local level, into, need = Rules.levelForXP(0)
	equal(level, 1); equal(into, 0); equal(need, 100)
	level, into, need = Rules.levelForXP(99)
	equal(level, 1); equal(into, 99)
	level, into, need = Rules.levelForXP(100)
	equal(level, 2); equal(into, 0); equal(need, 150)
	level = Rules.levelForXP(250)
	equal(level, 3)
	equal(Rules.levelForXP(-5), 1)
	equal(Rules.levelForXP(0 / 0), 1)
	local previous = 0
	for xp = 0, 20000, 500 do
		local current = Rules.levelForXP(xp)
		assert(current >= previous, "levels must not decrease")
		previous = current
	end
	equal(Rules.titleForLevel(1), "Mewing Rookie")
	equal(Rules.titleForLevel(10), "Gym Regular")
	equal(Rules.titleForLevel(99), "Giga Legend")
end)

test("map vote picks the majority and breaks ties with the roll", function()
	local options = { "A", "B", "C" }
	equal(Rules.pickVote(options, { [1] = "B", [2] = "B", [3] = "A" }, function() return 1 end), "B")
	equal(Rules.pickVote(options, { [1] = "A", [2] = "C" }, function(n) return n end), "C")
	equal(Rules.pickVote(options, {}, function() return 2 end), "B")
	equal(Rules.pickVote(options, { [1] = "Hacked" }, function() return 1 end), "A")
end)

test("survivor win threshold is half the starting team", function()
	equal(Rules.survivorsWin(0, 1), false)
	equal(Rules.survivorsWin(1, 1), true)
	equal(Rules.survivorsWin(1, 2), true)
	equal(Rules.survivorsWin(1, 3), false)
	equal(Rules.survivorsWin(2, 3), true)
	equal(Rules.survivorsWin(0, 0), false)
end)

test("ability catalogue is valid and survivors only pick survivor abilities", function()
	equal(#Abilities.Survivor >= 4, true)
	for _, ability in Abilities.Survivor do
		equal(ability.Role, "Survivor")
		equal(ability.Cooldown > 0, true)
		equal(Abilities.isSurvivorAbility(ability.Id), true)
	end
	for _, ability in Abilities.Killer do
		equal(Abilities.isSurvivorAbility(ability.Id), false)
	end
	equal(Abilities.isSurvivorAbility(Abilities.DefaultSurvivor), true)
	equal(Abilities.get("nope"), nil)
	equal(Abilities.get(42), nil)
end)

-- Terminals -------------------------------------------------------------------

test("objective awards capped points; cooldown is per player and overheat per terminal", function()
	local state = fresh()
	equal(RoundState.objective(state, 102, 1, "A"), true)
	equal(state.Survivors[102].BP, 25)
	equal(RoundState.objective(state, 102, 1.1, "B"), false) -- player cooldown
	equal(RoundState.objective(state, 103, 1.1, "A"), false) -- terminal overheated
	equal(RoundState.objective(state, 103, 1.1, "B"), true)
	equal(RoundState.terminalReady(state, "A", 1 + Config.TerminalOverheatSeconds - 0.01), false)
	equal(RoundState.terminalReady(state, "A", 1 + Config.TerminalOverheatSeconds), true)
	for step = 1, 5 do
		RoundState.objective(state, 102, 1 + step * 10, "T" .. step)
	end
	equal(state.Survivors[102].BP, 100)
	equal(state.Survivors[102].Stats.Calibrations, 6)
end)

test("powering the exit starts the endgame collapse", function()
	local state = fresh({ 101, 102 })
	equal(state.ObjectiveGoal, 4)
	promote(state, 102, 6)
	equal(state.ExitPowered, true)
	equal(state.EndsAt, 24 + Config.EndgameSeconds)
	-- Further calibrations do not extend the collapse.
	RoundState.objective(state, 102, 40, "Z")
	equal(state.EndsAt, 24 + Config.EndgameSeconds)
end)

test("killer, outsiders, injured-but-hidden and incapacitated survivors cannot calibrate", function()
	local state = fresh()
	equal(RoundState.objective(state, 101, 6, "A"), false)
	equal(RoundState.objective(state, 999, 6, "A"), false)
	down(state, 102, 6)
	equal(RoundState.objective(state, 102, 7, "A"), false)
	equal(RoundState.hide(state, 103, "L1", 7), true)
	equal(RoundState.objective(state, 103, 8, "A"), false)
	RoundState.unhide(state, 103)
	equal(RoundState.objective(state, 103, 8, "A"), true)
end)

-- Combat ----------------------------------------------------------------------

test("hits injure then down; immunity, killer and outsiders are rejected", function()
	local state = fresh()
	equal(RoundState.hit(state, 102, Config.CaptureGraceSeconds - 0.01), nil)
	equal(RoundState.hit(state, 101, 6), nil)
	equal(RoundState.hit(state, 999, 6), nil)
	equal(RoundState.hit(state, 102, 6), "Injured")
	equal(RoundState.hit(state, 102, 7), "Downed")
	equal(state.Survivors[102].RecoverAt, 7 + Config.DownedRecoverSeconds)
	equal(RoundState.hit(state, 102, 8), nil)
	equal(state.KillerStats.Hits, 2)
	equal(state.KillerStats.Downs, 1)
end)

test("lockers hide survivors from hits but the killer can grab them", function()
	local state = fresh()
	equal(RoundState.hide(state, 102, "L1", 6), true)
	equal(RoundState.hide(state, 103, "L1", 6), false) -- occupied
	equal(RoundState.lockerOccupant(state, "L1"), 102)
	equal(RoundState.hit(state, 102, 7), nil)
	equal(RoundState.grabFromLocker(state, 102, 7), true)
	equal(state.Survivors[102].Status, "Carried")
	equal(state.Survivors[102].Hidden, nil)
	equal(state.CarryingId, 102)
	equal(RoundState.lockerOccupant(state, "L1"), nil)
	equal(RoundState.grabFromLocker(state, 103, 7), false) -- not hidden
end)

test("pickup requires a downed survivor and one carry at a time", function()
	local state = fresh()
	equal(RoundState.pickup(state, 102, 6), false)
	down(state, 102, 6)
	down(state, 103, 6)
	equal(RoundState.pickup(state, 102, 7), true)
	equal(RoundState.pickup(state, 103, 7), false)
	equal(state.Survivors[102].RecoverAt, nil)
end)

test("wiggling frees a carried survivor and is rate limited", function()
	local state = fresh()
	down(state, 102, 6)
	RoundState.pickup(state, 102, 7)
	local now = 7
	local accepted = 0
	for _ = 1, 50 do
		if RoundState.wiggle(state, 102, now) then accepted += 1 end
	end
	equal(accepted, Config.WiggleMaxPerSecond)
	local result
	while state.Survivors[102].Status == "Carried" do
		now += 1
		for _ = 1, Config.WiggleMaxPerSecond do
			result = RoundState.wiggle(state, 102, now)
			if result == "Freed" then break end
		end
	end
	equal(result, "Freed")
	equal(state.Survivors[102].Status, "Injured")
	equal(state.CarryingId, nil)
	equal(state.Survivors[102].ImmuneUntil, now + Config.CaptureGraceSeconds)
	equal(RoundState.wiggle(state, 102, now + 1), nil)
end)

test("cage timers shrink and the third cage eliminates", function()
	local state = fresh({ 101, 102, 103 })
	equal(cageSurvivor(state, 102, 6), "Caged")
	equal(state.Survivors[102].CagedUntil, 8 + Config.CageSeconds[1])
	equal(RoundState.rescue(state, 103, 102, 10), true)
	equal(state.Survivors[102].Status, "Injured")
	equal(state.Survivors[103].BP, Config.BPPerRescue)
	equal(cageSurvivor(state, 102, 20), "Caged")
	equal(state.Survivors[102].CagedUntil, 22 + Config.CageSeconds[2])
	RoundState.rescue(state, 103, 102, 23)
	equal(cageSurvivor(state, 102, 40), "Eliminated")
	equal(state.EliminatedCount, 1)
	equal(state.KillerStats.Eliminations, 1)
	equal(state.KillerStats.Cages, 3)
end)

test("cage expiry eliminates; tick reports downed recovery and carry timeout", function()
	local state = fresh({ 101, 102, 103 })
	cageSurvivor(state, 102, 6)
	down(state, 103, 6)
	-- The cage (40s) expires before the downed recovery (45s).
	local events = RoundState.tick(state, 8 + Config.CageSeconds[1])
	equal(#events, 1)
	equal(events[1].Kind, "Eliminated")
	equal(events[1].Id, 102)
	equal(state.Survivors[102].Status, "Eliminated")
	events = RoundState.tick(state, 6.1 + Config.DownedRecoverSeconds)
	equal(#events, 1)
	equal(events[1].Kind, "Recovered")
	equal(state.Survivors[103].Status, "Injured")
	down(state, 103, 60)
	RoundState.pickup(state, 103, 61)
	equal(#RoundState.tick(state, 61 + Config.CarryMaxSeconds - 0.1), 0)
	events = RoundState.tick(state, 61 + Config.CarryMaxSeconds)
	equal(events[1].Kind, "CarryTimeout")
	equal(state.Survivors[103].Status, "Injured")
	equal(state.CarryingId, nil)
end)

test("caged survivors get limited lucky escape attempts", function()
	local state = fresh({ 101, 102 })
	cageSurvivor(state, 102, 6)
	equal(RoundState.attemptCageEscape(state, 102, 9, 0.99), false)
	equal(RoundState.attemptCageEscape(state, 102, 9, 0 / 0), nil)
	equal(RoundState.attemptCageEscape(state, 102, 9, 0.99), false)
	equal(RoundState.attemptCageEscape(state, 102, 9, 0.0), true)
	equal(state.Survivors[102].Status, "Injured")
	cageSurvivor(state, 102, 20)
	for _ = 1, Config.CageEscapeAttempts do
		equal(RoundState.attemptCageEscape(state, 102, 25, 0.99), false)
	end
	equal(RoundState.attemptCageEscape(state, 102, 25, 0.0), nil)
end)

-- Support actions -------------------------------------------------------------

test("revive and heal reward the helper and reject self-help", function()
	local state = fresh()
	down(state, 102, 6)
	equal(RoundState.revive(state, 102, 102, 7), false)
	equal(RoundState.revive(state, 101, 102, 7), false)
	equal(RoundState.revive(state, 103, 102, 7), true)
	equal(state.Survivors[102].Status, "Injured")
	equal(state.Survivors[103].BP, Config.BPPerRevive)
	equal(RoundState.heal(state, 102, 102, 8), false)
	equal(RoundState.heal(state, 103, 102, 8), true)
	equal(state.Survivors[102].Status, "Healthy")
	equal(RoundState.heal(state, 103, 102, 9), false)
	equal(state.Survivors[103].Stats.Revives, 1)
	equal(state.Survivors[103].Stats.Heals, 1)
end)

test("self heal only works on free injured survivors", function()
	local state = fresh()
	equal(RoundState.selfHeal(state, 102, 6), false)
	RoundState.hit(state, 102, 6)
	equal(RoundState.selfHeal(state, 102, 7), true)
	equal(state.Survivors[102].Status, "Healthy")
	down(state, 102, 8)
	equal(RoundState.selfHeal(state, 102, 9), false)
end)

test("dropCarried (flash/stun) releases the carried survivor", function()
	local state = fresh()
	equal(RoundState.dropCarried(state, 6), nil)
	down(state, 102, 6)
	RoundState.pickup(state, 102, 7)
	equal(RoundState.dropCarried(state, 8), 102)
	equal(state.Survivors[102].Status, "Injured")
	equal(state.CarryingId, nil)
end)

-- Escape and results ----------------------------------------------------------

test("escape requires both Chad rank and the powered exit", function()
	local state = fresh()
	equal(RoundState.escape(state, 102, 1), false)
	promote(state, 102)
	equal(RoundState.escape(state, 102, 25), false)
	RoundState.objective(state, 103, 6, "X")
	RoundState.objective(state, 103, 12, "Y")
	equal(state.ExitPowered, true)
	equal(RoundState.escape(state, 103, 25), false)
	equal(RoundState.escape(state, 102, 25), true)
	equal(state.Survivors[102].Status, "Escaped")
	equal(state.EscapedCount, 1)
	equal(RoundState.escape(state, 102, 26), false)
	equal(RoundState.hit(state, 102, 26), nil)
	equal(RoundState.updateResult(state, 26), nil)
end)

test("all escapes finish the round and ended state cannot be mutated", function()
	local state = fresh({ 101, 102 })
	promote(state, 102)
	RoundState.escape(state, 102, 25)
	equal(RoundState.updateResult(state, 25), "Survivors win! 1 of 1 escaped the Chad.")
	equal(state.Winner, "Survivors")
	equal(state.Ended, true)
	equal(RoundState.objective(state, 102, 31, "Q"), false)
	equal(RoundState.hit(state, 102, 31), nil)
	equal(#RoundState.tick(state, 31), 0)
	RoundState.removePlayer(state, 101)
	equal(state.KillerPresent, true)
end)

test("eliminating everyone is a killer win", function()
	local state = fresh({ 101, 102 })
	cageSurvivor(state, 102, 6)
	RoundState.tick(state, 8 + Config.CageSeconds[1])
	equal(RoundState.updateResult(state, 50), "OG Chad wins! Every survivor was mogged.")
	equal(state.Winner, "Killer")
end)

test("timeout decides by escape fraction", function()
	local state = fresh()
	equal(RoundState.updateResult(state, Config.RoundSeconds - 0.01), nil)
	equal(RoundState.updateResult(state, Config.RoundSeconds), "OG Chad wins! Time ran out and nobody escaped.")
	state = fresh()
	promote(state, 102)
	RoundState.objective(state, 103, 6, "X")
	RoundState.objective(state, 103, 12, "Y")
	RoundState.escape(state, 102, 25)
	equal(RoundState.updateResult(state, state.EndsAt), "Survivors win! 1 of 2 escaped the Chad.")
	state = fresh({ 101, 102, 103, 104 })
	promote(state, 102)
	promote(state, 103, 6.5)
	RoundState.objective(state, 104, 6, "X")
	equal(state.ExitPowered, true)
	equal(RoundState.escape(state, 102, 25), true)
	equal(RoundState.updateResult(state, state.EndsAt), "OG Chad wins! Only 1 of 3 escaped.")
end)

test("timeout rejects last-moment actions", function()
	local state = fresh()
	local endsAt = state.EndsAt
	equal(RoundState.objective(state, 103, endsAt, "A"), false)
	equal(RoundState.hit(state, 103, endsAt), nil)
	equal(RoundState.escape(state, 103, endsAt), false)
	equal(#RoundState.tick(state, endsAt + 10), 0)
end)

test("killer departure immediately ends the round; survivor departure cleans its state", function()
	local state = fresh()
	down(state, 103, 6)
	RoundState.pickup(state, 103, 7)
	RoundState.removePlayer(state, 103)
	equal(state.Survivors[103], nil)
	equal(state.CarryingId, nil)
	equal(state.TotalSurvivors, 1)
	equal(RoundState.updateResult(state, 20), nil)
	RoundState.removePlayer(state, 101)
	equal(state.KillerPresent, false)
	equal(state.Ended, true)
	equal(state.Winner, "Survivors")
	equal(RoundState.updateResult(state, 21), "Survivors win! The OG Chad left the round.")
end)

test("last survivor departure finishes cleanly; unknown departure is harmless", function()
	local state = fresh({ 101, 102 })
	RoundState.removePlayer(state, 999)
	equal(state.Ended, false)
	RoundState.removePlayer(state, 102)
	equal(RoundState.updateResult(state, 20), "Round ended: all survivors left.")
	equal(state.Ended, true)
end)

test("invalid or before-start timestamps cannot mutate state", function()
	local state = fresh(nil, nil, 50)
	for _, now in { 49, math.huge, -math.huge, 0 / 0 } do
		equal(RoundState.objective(state, 102, now, "A"), false)
		equal(RoundState.hit(state, 102, now), nil)
		equal(RoundState.escape(state, 102, now), false)
		equal(#RoundState.tick(state, now), 0)
	end
	equal(state.Survivors[102].BP, 0)
	equal(RoundState.updateResult(state, 49), nil)
	equal(RoundState.updateResult(state, 0 / 0), nil)
end)

test("XP rewards reflect each role's contribution", function()
	local state = fresh({ 101, 102, 103 })
	promote(state, 102)
	RoundState.objective(state, 103, 6, "X")
	RoundState.objective(state, 103, 12, "Y")
	RoundState.escape(state, 102, 25)
	cageSurvivor(state, 103, 26)
	RoundState.updateResult(state, state.EndsAt)
	equal(state.Winner, "Survivors")
	local XP = Rules.XP
	equal(RoundState.xpFor(state, 102), XP.Participation + 4 * XP.Calibration + XP.Escape + XP.SurvivorWin)
	equal(RoundState.xpFor(state, 103), XP.Participation + 2 * XP.Calibration + XP.SurvivorWin)
	equal(RoundState.xpFor(state, 101), XP.Participation + 2 * XP.Hit + XP.Down + XP.Cage)
	equal(RoundState.xpFor(state, 999), 0)
end)

test("chase intensity clamps and interpolates smoothly by distance", function()
	equal(Rules.chaseIntensity(-10), 1)
	equal(Rules.chaseIntensity(Config.ChaseFullVolumeRadius), 1)
	equal(Rules.chaseIntensity(Config.ChaseRadius), 0)
	equal(Rules.chaseIntensity((Config.ChaseRadius + Config.ChaseFullVolumeRadius) / 2), 0.5)
	equal(Rules.chaseIntensity(math.huge), 0)
	equal(Rules.chaseIntensity(0 / 0), 0)
end)

print(string.format("\n%d passed; %d failed; %d assertions", passed, failed, assertions))
if failed > 0 then
	error("Round rules test suite failed", 0)
end
