-- Run from the repository root: lune run tests/rules.spec.luau
local Config = require("../src/shared/Config")
local Rules = require("../src/shared/Rules")
local RoundState = require("../src/shared/RoundState")

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

local function promote(state, id, fromTime)
	for step = 0, 3 do
		equal(RoundState.objective(state, id, (fromTime or 6) + step * Config.ObjectiveCooldownSeconds), true, "promotion objective")
	end
end

test("each participant can be the one killer, all others start as LTN survivors", function()
	for index = 1, 4 do
		local ids = { 101, 102, 103, 104 }
		local state = fresh(ids, index, 50)
		equal(state.KillerId, ids[index])
		equal(state.Survivors[state.KillerId], nil)
		local count = 0
		for id, survivor in state.Survivors do
			assert(id ~= state.KillerId)
			count += 1
			equal(survivor.Status, "Alive")
			equal(survivor.BP, 0)
			equal(survivor.ImmuneUntil, 55)
		end
		equal(count, 3)
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
		local state = RoundState.new({ 1, 2 }, index, 0)
		equal(state, nil)
	end
	for _, now in { math.huge, -math.huge, 0 / 0 } do
		local state = RoundState.new({ 1, 2 }, 1, now)
		equal(state, nil)
	end
end)

test("rank boundaries and next-rank thresholds follow fictional BP progression", function()
	local examples = { { -1, "LTN" }, { 0, "LTN" }, { 24, "LTN" }, { 25, "MTN" }, { 49, "MTN" }, { 50, "HTN" }, { 74, "HTN" }, { 75, "Chadlite" }, { 99, "Chadlite" }, { 100, "Chad" }, { 500, "Chad" } }
	for _, example in examples do
		equal(Rules.rankForBP(example[1]), example[2])
	end
	for index = 1, #Config.Ranks - 1 do
		local nextRank = Rules.nextRank(Config.Ranks[index].BP)
		equal(nextRank.Name, Config.Ranks[index + 1].Name)
		equal(nextRank.BP, Config.Ranks[index + 1].BP)
	end
		equal(Rules.nextRank(100), nil)
end)

test("team objective goal scales for two-player and larger sessions", function()
		equal(Rules.objectiveGoal(1), 4)
		equal(Rules.objectiveGoal(2), 6)
		equal(Rules.objectiveGoal(5), 15)
end)

test("objective awards capped points and per-player cooldown does not block teammates", function()
	local state = fresh()
		equal(RoundState.objective(state, 102, 1), true)
		equal(state.Survivors[102].BP, 25)
		equal(RoundState.objective(state, 102, 1.1), false)
		equal(RoundState.objective(state, 103, 1.1), true)
		equal(RoundState.objective(state, 102, 6.99), false)
		equal(RoundState.objective(state, 102, 7), true)
	for now = 13, 61, 6 do
		equal(RoundState.objective(state, 102, now), true)
	end
		equal(state.Survivors[102].BP, 100)
		equal(state.ObjectiveCount, state.ObjectiveGoal)
end)

test("killer, late joiner, captured survivor and escaped survivor cannot gain BP", function()
	local state = fresh({ 101, 102 })
		equal(RoundState.objective(state, 101, 6), false)
		equal(RoundState.objective(state, 999, 6), false)
		equal(RoundState.capture(state, 102, 6), true)
		equal(RoundState.objective(state, 102, 7), false)
		equal(state.Survivors[102].BP, 0)
	RoundState.releaseExpired(state, 26)
	promote(state, 102, 27)
		equal(RoundState.escape(state, 102, 46), true)
		equal(RoundState.objective(state, 102, 60), false)
end)

test("capture respects initial grace, roles, and repeat capture rejection", function()
	local state = fresh()
		equal(RoundState.capture(state, 102, 4.99), false)
		equal(RoundState.capture(state, 101, 5), false)
		equal(RoundState.capture(state, 999, 5), false)
		equal(RoundState.capture(state, 102, 5), true)
		equal(state.Survivors[102].Status, "Captured")
		equal(state.Survivors[102].CapturedUntil, 25)
		equal(RoundState.capture(state, 102, 6), false)
		equal(state.Survivors[102].CapturedUntil, 25)
end)

test("one teammate rescues a captive and grants re-capture grace", function()
	local state = fresh()
	RoundState.capture(state, 102, 6)
		equal(RoundState.rescue(state, 102, 102, 7), false)
		equal(RoundState.rescue(state, 101, 102, 7), false)
		equal(RoundState.rescue(state, 999, 102, 7), false)
		equal(RoundState.rescue(state, 103, 999, 7), false)
		equal(RoundState.rescue(state, 103, 102, 7), true)
		equal(state.Survivors[102].Status, "Alive")
		equal(state.Survivors[102].CapturedUntil, nil)
		equal(state.Survivors[102].ImmuneUntil, 12)
		equal(RoundState.capture(state, 102, 11.99), false)
		equal(RoundState.capture(state, 102, 12), true)
end)

test("captured and escaped players cannot rescue others", function()
	local state = fresh()
	RoundState.capture(state, 102, 6)
	RoundState.capture(state, 103, 6)
		equal(RoundState.rescue(state, 103, 102, 7), false)
	RoundState.releaseExpired(state, 26)
	promote(state, 103, 27)
	RoundState.objective(state, 102, 27)
	RoundState.objective(state, 102, 33)
	RoundState.escape(state, 103, 46)
	RoundState.capture(state, 102, 47)
		equal(RoundState.rescue(state, 103, 102, 48), false)
end)

test("automatic release prevents a two-player capture deadlock", function()
	local state = fresh({ 101, 102 })
	RoundState.capture(state, 102, 6)
		equal(RoundState.updateResult(state, 7), nil)
		equal(#RoundState.releaseExpired(state, 25.99), 0)
	local ids = RoundState.releaseExpired(state, 26)
		equal(#ids, 1)
		equal(ids[1], 102)
		equal(state.Survivors[102].Status, "Alive")
		equal(state.Survivors[102].CapturedUntil, nil)
		equal(state.Survivors[102].ImmuneUntil, 31)
		equal(#RoundState.releaseExpired(state, 27), 0)
		equal(RoundState.capture(state, 102, 30.99), false)
		equal(RoundState.capture(state, 102, 31), true)
end)

test("escape requires both Chad rank and the team's objective goal", function()
	local state = fresh()
		equal(RoundState.escape(state, 102, 1), false)
	promote(state, 102)
		equal(RoundState.escape(state, 102, 25), false)
	RoundState.objective(state, 103, 6)
	RoundState.objective(state, 103, 12)
		equal(RoundState.escape(state, 103, 25), false)
		equal(RoundState.escape(state, 102, 25), true)
		equal(state.Survivors[102].Status, "Escaped")
		equal(state.EscapedCount, 1)
		equal(RoundState.escape(state, 102, 26), false)
		equal(RoundState.capture(state, 102, 26), false)
		equal(state.EscapedCount, 1)
		equal(RoundState.updateResult(state, 26), nil)
end)

test("all escapes finish the round and ended state cannot be mutated", function()
	local state = fresh({ 101, 102 })
	promote(state, 102)
	RoundState.escape(state, 102, 25)
		equal(RoundState.updateResult(state, 25), "Survivors win! 1 escaped.")
		equal(state.Ended, true)
		equal(RoundState.objective(state, 102, 31), false)
		equal(RoundState.capture(state, 102, 31), false)
		equal(RoundState.escape(state, 102, 31), false)
		equal(RoundState.rescue(state, 102, 102, 31), false)
		equal(#RoundState.releaseExpired(state, 31), 0)
	RoundState.removePlayer(state, 101)
		equal(state.KillerPresent, true)
		equal(RoundState.updateResult(state, 999), "Survivors win! 1 escaped.")
end)

test("timeout rejects last-moment actions before updateResult has run", function()
	local state = fresh()
	RoundState.capture(state, 102, 230)
		equal(RoundState.objective(state, 103, 240), false)
		equal(RoundState.capture(state, 103, 240), false)
		equal(RoundState.rescue(state, 103, 102, 240), false)
		equal(RoundState.escape(state, 103, 240), false)
		equal(#RoundState.releaseExpired(state, 251), 0)
		equal(RoundState.updateResult(state, 239.99), nil)
		equal(RoundState.updateResult(state, 240), "OG Chad wins! No survivors escaped before time ran out.")
		equal(state.Ended, true)
end)

test("mixed escape and timeout reports both outcomes", function()
	local state = fresh()
	promote(state, 102)
	RoundState.objective(state, 103, 6)
	RoundState.objective(state, 103, 12)
	RoundState.escape(state, 102, 25)
	RoundState.removePlayer(state, 102)
		equal(RoundState.updateResult(state, 240), "Time is up! 1 escaped; 1 failed to escape.")
end)

test("killer departure immediately ends the round; survivor departure cleans its state", function()
	local state = fresh()
	RoundState.removePlayer(state, 103)
		equal(state.Survivors[103], nil)
		equal(RoundState.updateResult(state, 20), nil)
	RoundState.removePlayer(state, 101)
		equal(state.KillerPresent, false)
		equal(state.Ended, true)
		equal(RoundState.updateResult(state, 21), "Survivors win! The OG Chad left the round.")
		equal(RoundState.objective(state, 102, 22), false)
end)

test("last survivor departure finishes cleanly", function()
	local state = fresh({ 101, 102 })
	RoundState.removePlayer(state, 102)
		equal(RoundState.updateResult(state, 20), "Round ended: all survivors left.")
		equal(state.Ended, true)
end)

test("unknown departure is harmless and does not change objective goal", function()
	local state = fresh()
	RoundState.removePlayer(state, 999)
		equal(state.Ended, false)
		equal(state.ObjectiveGoal, 6)
	RoundState.removePlayer(state, 103)
		equal(state.ObjectiveGoal, 6)
end)

test("invalid or before-start timestamps cannot mutate state", function()
	local state = fresh(nil, nil, 50)
	for _, now in { 49, math.huge, -math.huge, 0 / 0 } do
		equal(RoundState.objective(state, 102, now), false)
		equal(RoundState.capture(state, 102, now), false)
		equal(RoundState.escape(state, 102, now), false)
		equal(#RoundState.releaseExpired(state, now), 0)
	end
		equal(state.Survivors[102].BP, 0)
		equal(RoundState.updateResult(state, 49), nil)
		equal(RoundState.updateResult(state, 0 / 0), nil)
end)

test("chase intensity clamps and interpolates smoothly by distance", function()
		equal(Rules.chaseIntensity(-10), 1)
		equal(Rules.chaseIntensity(Config.ChaseFullVolumeRadius), 1)
		equal(Rules.chaseIntensity(Config.ChaseRadius), 0)
		equal(Rules.chaseIntensity(Config.ChaseRadius + 1), 0)
		equal(Rules.chaseIntensity((Config.ChaseRadius + Config.ChaseFullVolumeRadius) / 2), 0.5)
		equal(Rules.chaseIntensity(math.huge), 0)
		equal(Rules.chaseIntensity(0 / 0), 0)
end)

test("new rounds reset points, captures, cooldowns and scores", function()
	local old = fresh()
	RoundState.objective(old, 102, 6)
	RoundState.capture(old, 102, 7)
	local new = fresh(nil, 2, 300)
		equal(new.KillerId, 102)
		equal(new.ObjectiveCount, 0)
		equal(new.EscapedCount, 0)
		equal(new.Ended, false)
		equal(new.Survivors[103].BP, 0)
		equal(new.Survivors[103].LastObjectiveAt, nil)
		equal(new.Survivors[103].CapturedUntil, nil)
		equal(new.Survivors[103].Status, "Alive")
end)

print(string.format("\n%d passed; %d failed; %d assertions", passed, failed, assertions))
if failed > 0 then
	error("Round rules test suite failed", 0)
end
