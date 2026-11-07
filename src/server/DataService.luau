--!strict
-- Persistent player profiles and the global wins leaderboard.
-- Every DataStore call is wrapped in pcall. In Studio without "Enable Studio
-- Access to API Services", the service logs one warning and keeps profiles in
-- memory for the session, so the game remains fully playable.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local Abilities = require(Shared.Abilities)

export type Profile = {
	Version: number,
	XP: number,
	RoundsPlayed: number,
	SurvivorWins: number,
	KillerWins: number,
	Escapes: number,
	Calibrations: number,
	Rescues: number,
	Revives: number,
	Downs: number,
	Cages: number,
	SelectedAbility: string,
}

local DataService = {}

local profiles: { [number]: Profile } = {}
local dirty: { [number]: boolean } = {}
local loaded: { [number]: boolean } = {}
local storeAvailable = true
local warned = false
local nameCache: { [number]: string } = {}

local store: DataStore? = nil
local ordered: OrderedDataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	end
	local okOrdered, orderedResult = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	end)
	if okOrdered then
		ordered = orderedResult
	end
	if not store then
		storeAvailable = false
	end
end

local function disable(reason: any)
	storeAvailable = false
	if not warned then
		warned = true
		warn("[EscapeTheChad] DataStore unavailable; progress is kept for this session only. " .. tostring(reason))
	end
end

local function defaultProfile(): Profile
	return {
		Version = 1,
		XP = 0,
		RoundsPlayed = 0,
		SurvivorWins = 0,
		KillerWins = 0,
		Escapes = 0,
		Calibrations = 0,
		Rescues = 0,
		Revives = 0,
		Downs = 0,
		Cages = 0,
		SelectedAbility = Abilities.DefaultSurvivor,
	}
end

-- Copies only known, well-typed fields so corrupt data cannot break a session.
local function sanitize(raw: any): Profile
	local profile = defaultProfile()
	if type(raw) ~= "table" then
		return profile
	end
	for key, value in profile :: any do
		local incoming = raw[key]
		if type(incoming) == type(value) then
			if type(incoming) == "number" then
				if incoming == incoming and incoming >= 0 and incoming < 1e12 then
					(profile :: any)[key] = math.floor(incoming)
				end
			else
				(profile :: any)[key] = incoming
			end
		end
	end
	if not Abilities.isSurvivorAbility(profile.SelectedAbility) then
		profile.SelectedAbility = Abilities.DefaultSurvivor
	end
	return profile
end

local function key(userId: number): string
	return "player_" .. tostring(userId)
end

function DataService.publish(player: Player)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	local level, into, need = Rules.levelForXP(profile.XP)
	player:SetAttribute("Level", level)
	player:SetAttribute("XP", profile.XP)
	player:SetAttribute("XPInto", into)
	player:SetAttribute("XPNeed", need)
	player:SetAttribute("Title", Rules.titleForLevel(level))
	player:SetAttribute("Wins", profile.SurvivorWins + profile.KillerWins)
	player:SetAttribute("Escapes", profile.Escapes)
	player:SetAttribute("RoundsPlayed", profile.RoundsPlayed)
	player:SetAttribute("Ability", profile.SelectedAbility)
	player:SetAttribute("ProfileLoaded", true)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local levelValue = stats:FindFirstChild("Level")
		if levelValue and levelValue:IsA("IntValue") then
			levelValue.Value = level
		end
		local winsValue = stats:FindFirstChild("Wins")
		if winsValue and winsValue:IsA("IntValue") then
			winsValue.Value = profile.SurvivorWins + profile.KillerWins
		end
	end
end

function DataService.load(player: Player)
	local userId = player.UserId
	local raw: any = nil
	-- Studio test players have negative ids; never persist those.
	if storeAvailable and store and userId > 0 then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return (store :: DataStore):GetAsync(key(userId))
			end)
			if ok then
				raw = result
				break
			elseif attempt == 3 then
				disable(result)
			else
				task.wait(attempt)
			end
		end
	end
	if not player.Parent then
		return
	end
	profiles[userId] = sanitize(raw)
	loaded[userId] = true
	DataService.publish(player)
end

function DataService.get(player: Player): Profile?
	return profiles[player.UserId]
end

function DataService.save(userId: number)
	local profile = profiles[userId]
	if not profile or not dirty[userId] or not storeAvailable or not store or userId <= 0 or not loaded[userId] then
		return
	end
	local snapshot = table.clone(profile)
	local ok, result = pcall(function()
		(store :: DataStore):UpdateAsync(key(userId), function()
			return snapshot
		end)
	end)
	if ok then
		dirty[userId] = nil
		if ordered then
			pcall(function()
				(ordered :: OrderedDataStore):SetAsync(key(userId), snapshot.SurvivorWins + snapshot.KillerWins)
			end)
		end
	else
		warn("[EscapeTheChad] Profile save failed: " .. tostring(result))
	end
end

function DataService.setAbility(player: Player, abilityId: string): boolean
	local profile = profiles[player.UserId]
	if not profile or not Abilities.isSurvivorAbility(abilityId) then
		return false
	end
	profile.SelectedAbility = abilityId
	dirty[player.UserId] = true
	player:SetAttribute("Ability", abilityId)
	return true
end

export type RoundReport = {
	XP: number,
	Won: boolean,
	Role: string,
	Escaped: boolean,
	Calibrations: number,
	Rescues: number,
	Revives: number,
	Downs: number,
	Cages: number,
}

-- Applies a finished round. Returns (oldLevel, newLevel).
function DataService.record(player: Player, report: RoundReport): (number, number)
	local profile = profiles[player.UserId]
	if not profile then
		return 1, 1
	end
	local before = Rules.levelForXP(profile.XP)
	profile.XP += math.max(0, math.floor(report.XP))
	profile.RoundsPlayed += 1
	if report.Won then
		if report.Role == "Killer" then
			profile.KillerWins += 1
		else
			profile.SurvivorWins += 1
		end
	end
	if report.Escaped then
		profile.Escapes += 1
	end
	profile.Calibrations += report.Calibrations
	profile.Rescues += report.Rescues
	profile.Revives += report.Revives
	profile.Downs += report.Downs
	profile.Cages += report.Cages
	dirty[player.UserId] = true
	DataService.publish(player)
	local after = Rules.levelForXP(profile.XP)
	task.spawn(DataService.save, player.UserId)
	return before, after
end

function DataService.release(player: Player)
	local userId = player.UserId
	DataService.save(userId)
	profiles[userId] = nil
	dirty[userId] = nil
	loaded[userId] = nil
end

local function displayName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else ("Player " .. tostring(userId))
	nameCache[userId] = result
	return result
end

-- Returns up to `count` { Name, Wins } rows: global when possible, otherwise
-- the players in this server.
function DataService.topWins(count: number): ({ { Name: string, Wins: number } }, boolean)
	local rows = {}
	if storeAvailable and ordered then
		local ok, pages = pcall(function()
			return (ordered :: OrderedDataStore):GetSortedAsync(false, count)
		end)
		if ok and pages then
			local okPage, entries = pcall(function()
				return (pages :: DataStorePages):GetCurrentPage()
			end)
			if okPage and type(entries) == "table" then
				for _, entry in entries do
					local userId = tonumber(string.match(tostring(entry.key), "^player_(%-?%d+)$"))
					if userId then
						table.insert(rows, { Name = displayName(userId), Wins = tonumber(entry.value) or 0 })
					end
				end
				return rows, true
			end
		end
	end
	for _, player in Players:GetPlayers() do
		local profile = profiles[player.UserId]
		if profile then
			table.insert(rows, { Name = player.DisplayName, Wins = profile.SurvivorWins + profile.KillerWins })
		end
	end
	table.sort(rows, function(a, b)
		return a.Wins > b.Wins
	end)
	while #rows > count do
		table.remove(rows)
	end
	return rows, false
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for userId in profiles do
				DataService.save(userId)
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not storeAvailable then
			return
		end
		local pending = 0
		for userId in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(userId)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return DataService
