--!strict
-- Pure calculations shared by server, client and tests.
-- The string require supports Lune tests; Studio uses the ModuleScript branch.
local Config = if script then require(script.Parent.Config) else require("./Config")

local Rules = {}

function Rules.rankForBP(points: number): string
	local name = Config.Ranks[1].Name
	for _, rank in Config.Ranks do
		if points >= rank.BP then
			name = rank.Name
		end
	end
	return name
end

function Rules.nextRank(points: number): { Name: string, BP: number }?
	for _, rank in Config.Ranks do
		if points < rank.BP then
			return rank
		end
	end
	return nil
end

function Rules.chaseIntensity(distance: number): number
	if distance ~= distance then
		return 0
	end
	return math.clamp(
		(Config.ChaseRadius - distance) / (Config.ChaseRadius - Config.ChaseFullVolumeRadius),
		0,
		1
	)
end

function Rules.objectiveGoal(survivorCount: number): number
	return math.max(4, survivorCount * 3)
end

-- Seconds a survivor stays caged for their Nth cage (1-based). nil means the
-- cage eliminates them immediately.
function Rules.cageSeconds(cageCount: number): number?
	return Config.CageSeconds[cageCount]
end

-- Killer attack geometry: a hit needs range and a forward-facing cone.
-- `forward` must be a unit vector; positions are { X, Z } style numbers.
function Rules.inAttackCone(dx: number, dz: number, forwardX: number, forwardZ: number): boolean
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance ~= distance or distance > Config.AttackRange then
		return false
	end
	if distance < 1.5 then
		return true -- Overlapping bodies always connect.
	end
	return (dx * forwardX + dz * forwardZ) / distance >= Config.AttackConeDot
end

-- Survivors win when at least half of the starting survivors escape.
function Rules.survivorsWin(escaped: number, total: number): boolean
	if total <= 0 then
		return false
	end
	return escaped > 0 and escaped >= math.ceil(total * Config.SurvivorWinFraction)
end

-- Progression ----------------------------------------------------------------

Rules.XP = table.freeze({
	Participation = 20,
	Calibration = 10,
	Revive = 15,
	Heal = 10,
	Rescue = 25,
	Escape = 60,
	SurvivorWin = 40,
	Hit = 8,
	Down = 15,
	Cage = 25,
	Elimination = 35,
	KillerWin = 80,
})

-- XP needed to go from `level` to `level + 1`.
function Rules.xpToNext(level: number): number
	return 100 + (math.max(1, level) - 1) * 50
end

-- Returns level (starting at 1), XP into that level, and XP needed for the next.
function Rules.levelForXP(xp: number): (number, number, number)
	if xp ~= xp or xp < 0 then
		xp = 0
	end
	xp = math.floor(xp)
	local level = 1
	while level < 999 do
		local need = Rules.xpToNext(level)
		if xp < need then
			return level, xp, need
		end
		xp -= need
		level += 1
	end
	return level, 0, Rules.xpToNext(level)
end

Rules.Titles = table.freeze({
	table.freeze({ Level = 1, Name = "Mewing Rookie" }),
	table.freeze({ Level = 5, Name = "Jawline Apprentice" }),
	table.freeze({ Level = 10, Name = "Gym Regular" }),
	table.freeze({ Level = 20, Name = "Certified Mogger" }),
	table.freeze({ Level = 35, Name = "Giga Legend" }),
})

function Rules.titleForLevel(level: number): string
	local title = Rules.Titles[1].Name
	for _, entry in Rules.Titles do
		if level >= entry.Level then
			title = entry.Name
		end
	end
	return title
end

-- Majority vote with deterministic tie breaking via the provided roll (1..n).
function Rules.pickVote(options: { string }, votes: { [any]: string }, roll: (number) -> number): string
	local counts: { [string]: number } = {}
	for _, option in options do
		counts[option] = 0
	end
	for _, choice in votes do
		if counts[choice] then
			counts[choice] += 1
		end
	end
	local best = -1
	local leaders: { string } = {}
	for _, option in options do
		local count = counts[option]
		if count > best then
			best = count
			leaders = { option }
		elseif count == best then
			table.insert(leaders, option)
		end
	end
	return leaders[roll(#leaders)]
end

return table.freeze(Rules)
