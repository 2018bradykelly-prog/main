-- Executes the actual map builder for every map definition with Lune's Roblox
-- instance/datatype model. It validates geometry and walkable routes (without
-- jumping or vaulting), not engine physics or rendering.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local env = { game = game }
for _, key in { "Instance", "Vector3", "Color3", "Enum", "UDim", "UDim2", "CFrame" } do
	env[key] = roblox[key]
end
local function load(path: string, name: string)
	return luau.load(fs.readFile(path), { debugName = name, environment = env })()
end
local World = load("src/server/World.luau", "World")
local Maps = load("src/shared/Maps.luau", "Maps")

local checks = 0
local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

-- Lobby -----------------------------------------------------------------------
local lobby = World.createLobby()
check(workspace:FindFirstChild("Lobby") == lobby.Folder, "Lobby not parented")
check(#lobby.LeaderboardRows == 10, "Leaderboard needs ten rows")
local lobbySpawns = 0
for _, instance in lobby.Folder:GetDescendants() do
	if instance:IsA("SpawnLocation") then
		lobbySpawns += 1
		check((instance.CFrame.Position - lobby.Spawn.Position).Magnitude < 6, "Automatic spawn is not at the lobby spawn")
	end
	if instance:IsA("BasePart") then
		check(instance.Anchored, "Unanchored lobby geometry: " .. instance.Name)
	end
end
check(lobbySpawns == 1, "Exactly one automatic spawn should exist (in the lobby)")
World.createLobby()
local lobbies = 0
for _, child in workspace:GetChildren() do
	if child.Name == "Lobby" then lobbies += 1 end
end
check(lobbies == 1, "Lobby recreation left duplicates")

-- Arenas ----------------------------------------------------------------------
local function extents(instance)
	local cf, size = instance.CFrame, instance.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local function axis(component: string): number
		return math.abs(r[component]) * size.X / 2 + math.abs(u[component]) * size.Y / 2 + math.abs(l[component]) * size.Z / 2
	end
	return axis("X"), axis("Y"), axis("Z")
end

check(#Maps.List >= 2, "At least two maps are required")
local seenIds = {}
local totalCells = 0
for _, def in Maps.List do
	check(not seenIds[def.Id], "Duplicate map id " .. def.Id)
	seenIds[def.Id] = true
	check(Maps.get(def.Id) == def, "Maps.get failed for " .. def.Id)
	local arena = World.build(def)
	local map = workspace:FindFirstChild("ActiveMap")
	check(map == arena.Folder, def.Id .. ": map not parented")
	check(map:GetAttribute("MapName") == def.Name, def.Id .. ": map name attribute")
	check(#arena.Terminals >= 4, def.Id .. ": needs at least four terminals")
	check(#arena.Exits >= 2, def.Id .. ": needs at least two exits")
	check(#arena.Cages >= 2, def.Id .. ": needs at least two cages")
	check(#arena.Lockers >= 6, def.Id .. ": needs at least six lockers")
	check(#arena.SurvivorSpawns >= 4, def.Id .. ": needs several survivor spawns")

	local prompts = 0
	local obstacles = {}
	local sills = 0
	for _, instance in map:GetDescendants() do
		if instance:IsA("ProximityPrompt") then
			prompts += 1
			check(instance:GetAttribute("Active") == false, def.Id .. ": prompts must start inactive")
			check(type(instance:GetAttribute("Kind")) == "string", def.Id .. ": prompt without Kind")
			local role = instance:GetAttribute("ForRole")
			check(role == "Survivor" or role == "Killer" or role == "Any", def.Id .. ": prompt without ForRole")
			check(instance.Parent:IsA("BasePart"), def.Id .. ": prompt must be attached to a part")
			check(instance.HoldDuration > 0 and instance.MaxActivationDistance > 0, def.Id .. ": invalid prompt settings")
		elseif instance:IsA("SpawnLocation") then
			check(false, def.Id .. ": arenas must not contain automatic spawns")
		elseif instance:IsA("BasePart") then
			check(instance.Anchored, def.Id .. ": unanchored geometry " .. instance.Name)
			if instance.Name == "VaultSill" then
				sills += 1
				check(instance.Size.Y == World.SillHeight, def.Id .. ": sill height")
			end
			if instance.Name == "Screen" then
				check(not instance.CanQuery, def.Id .. ": decorative screen must not block interaction rays")
			end
			local ex, ey, ez = extents(instance)
			local p = instance.CFrame.Position
			-- Walking clearance for a five-stud-high body; the floor is excluded.
			if instance.CanCollide and p.Y + ey > 0.2 and p.Y - ey < 5 then
				table.insert(obstacles, { X = p.X, Z = p.Z, HX = ex, HZ = ez })
			end
		end
	end
	check(sills == #def.Windows and sills >= 4, def.Id .. ": vault windows missing")
	check(prompts == #arena.Terminals + #arena.Exits + #arena.Lockers + 2 * #arena.Cages, def.Id .. ": unexpected prompt count")

	local function blocked(x: number, z: number): boolean
		for _, o in obstacles do
			if math.abs(x - o.X) < o.HX + 1.3 and math.abs(z - o.Z) < o.HZ + 1.3 then
				return true
			end
		end
		return false
	end
	for _, spawn in arena.SurvivorSpawns do
		check(not blocked(spawn.Position.X, spawn.Position.Z), def.Id .. ": survivor spawn intersects geometry")
	end
	check(not blocked(arena.KillerSpawn.Position.X, arena.KillerSpawn.Position.Z), def.Id .. ": killer spawn intersects geometry")

	-- Flood fill on a two-stud grid from the first survivor spawn.
	local limit = def.Half - 2
	local function key(x: number, z: number): number return (x + 1000) * 10000 + (z + 1000) end
	local start = arena.SurvivorSpawns[1].Position
	local sx, sz = math.round(start.X / 2) * 2, math.round(start.Z / 2) * 2
	local visited = { [key(sx, sz)] = true }
	local queue = { { sx, sz } }
	local cursor = 1
	while cursor <= #queue do
		local cell = queue[cursor]
		cursor += 1
		for _, offset in { { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } } do
			local x, z = cell[1] + offset[1], cell[2] + offset[2]
			local id = key(x, z)
			if x >= -limit and x <= limit and z >= -limit and z <= limit and not visited[id] and not blocked(x, z) then
				visited[id] = true
				table.insert(queue, { x, z })
			end
		end
	end
	totalCells += #queue
	local function accessible(position, distance: number): boolean
		for _, cell in queue do
			local dx, dz = cell[1] - position.X, cell[2] - position.Z
			if dx * dx + dz * dz <= distance * distance then return true end
		end
		return false
	end
	for index, spawn in arena.SurvivorSpawns do
		check(accessible(spawn.Position, 3), def.Id .. ": survivor spawn " .. index .. " is disconnected")
	end
	check(accessible(arena.KillerSpawn.Position, 3), def.Id .. ": killer spawn is disconnected")
	for _, terminal in arena.Terminals do
		check(accessible(terminal.Part.CFrame.Position, 8), def.Id .. ": terminal " .. terminal.Id .. " cannot be reached")
	end
	for index, exit in arena.Exits do
		check(accessible(exit.Part.CFrame.Position, 8), def.Id .. ": exit " .. index .. " cannot be reached")
	end
	for _, cage in arena.Cages do
		check(accessible(cage.Panel.CFrame.Position, 6), def.Id .. ": cage panel " .. cage.Id .. " cannot be reached")
		check(not accessible(cage.Spawn.Position, 3), def.Id .. ": cage " .. cage.Id .. " is not sealed")
	end
	for _, locker in arena.Lockers do
		check(accessible(locker.Outside.Position, 3), def.Id .. ": locker " .. locker.Id .. " front cannot be reached")
		check(not blocked(locker.Outside.Position.X, locker.Outside.Position.Z), def.Id .. ": locker " .. locker.Id .. " exit is blocked")
	end
	-- Both sides of every vault window must be walkable.
	for _, window in def.Windows do
		local normal = if window.Axis == "X" then { 0, 1 } else { 1, 0 }
		for _, sign in { -1, 1 } do
			local side = { X = window.X + normal[1] * 4 * sign, Z = window.Z + normal[2] * 4 * sign }
			check(accessible(side, 3), def.Id .. string.format(": window at %d,%d has an unreachable side", window.X, window.Z))
		end
	end
	print(string.format("PASS map %s: %d reachable cells", def.Id, #queue))
end

World.clear()
check(workspace:FindFirstChild("ActiveMap") == nil, "World.clear must remove the arena")
print(string.format("PASS %d map checks across %d maps; %d reachable walkable grid cells", checks, #Maps.List, totalCells))
