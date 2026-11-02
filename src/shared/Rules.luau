--!strict
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

return table.freeze(Rules)
