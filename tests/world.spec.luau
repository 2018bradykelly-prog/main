-- Executes the actual map generator with Lune's Roblox instance/datatype model.
-- It validates geometry and walkable routes, not engine physics or rendering.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local env = { game = game }
for _, key in { "Instance", "Vector3", "Color3", "Enum", "UDim2", "CFrame" } do
	env[key] = roblox[key]
end
local World = luau.load(fs.readFile("src/server/World.luau"), {
	debugName = "World",
	environment = env,
})()
local world = World.create()
local checks = 0
local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end
local map = workspace:FindFirstChild("PrototypeMap")
check(map ~= nil, "Map was not generated")
for _, key in { "ObjectivePrompt", "ExitPrompt", "RescuePrompt" } do
	local prompt = world[key]
	check(prompt and prompt:IsA("ProximityPrompt"), "Missing prompt: " .. key)
	check(not prompt.Enabled, key .. " must initially be disabled")
	check(prompt.Parent:IsA("BasePart"), key .. " must be attached to a part")
	check(prompt.HoldDuration > 0 and prompt.MaxActivationDistance > 0, key .. " has invalid interaction settings")
end
check(#world.SurvivorSpawns >= 2, "Multiple survivor spawns required")
check(world.Objective == world.ObjectivePrompt.Parent, "Objective prompt parent mismatch")
check(not map.CalibratorScreen.CanQuery, "Decorative terminal screen must not block interaction rays")
check(world.Exit == world.ExitPrompt.Parent, "Exit prompt parent mismatch")

local obstacles = {}
local spawns = {}
for _, instance in map:GetDescendants() do
	if instance:IsA("BasePart") then
		check(instance.Anchored, "Unanchored map geometry: " .. instance.Name)
		if instance:IsA("SpawnLocation") then table.insert(spawns, instance) end
		local p, size = instance.Position, instance.Size
		-- Check walking clearance for a five-stud-high body; floor is excluded.
		if instance.CanCollide and p.Y + size.Y / 2 > 0.2 and p.Y - size.Y / 2 < 5 then
			table.insert(obstacles, { Position = p, Half = size / 2 })
		end
	end
end
check(#spawns == 1, "Exactly one automatic spawn should exist in the lobby")
check((spawns[1].Position - world.LobbySpawn.Position).Magnitude < 6, "Automatic spawn is not in the lobby")
local function blocked(x: number, z: number): boolean
	for _, obstacle in obstacles do
		if math.abs(x - obstacle.Position.X) < obstacle.Half.X + 1.3
			and math.abs(z - obstacle.Position.Z) < obstacle.Half.Z + 1.3 then
			return true
		end
	end
	return false
end
for _, spawn in world.SurvivorSpawns do
	check(not blocked(spawn.Position.X, spawn.Position.Z), "Survivor spawn intersects geometry")
end
check(not blocked(world.KillerSpawn.Position.X, world.KillerSpawn.Position.Z), "Killer spawn intersects geometry")
check(not blocked(world.CageSpawn.Position.X, world.CageSpawn.Position.Z), "Cage spawn intersects geometry")

-- Flood fill on a two-stud grid demonstrates routes without jumping. This
-- catches accidental sealed-off objectives and spawn rooms in the graybox.
local function key(x: number, z: number): string return tostring(x) .. ":" .. tostring(z) end
local start = world.SurvivorSpawns[1].Position
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
		if x >= -96 and x <= 96 and z >= -96 and z <= 96 and not visited[id] and not blocked(x, z) then
			visited[id] = true
			table.insert(queue, { x, z })
		end
	end
end
local function accessible(position, distance: number): boolean
	for _, cell in queue do
		if (roblox.Vector3.new(cell[1], 3, cell[2]) - position).Magnitude <= distance then return true end
	end
	return false
end
for _, spawn in world.SurvivorSpawns do
	check(accessible(spawn.Position, 3), "Survivor spawn has no walkable route to the arena")
end
check(accessible(world.KillerSpawn.Position, 3), "Killer spawn is disconnected")
check(accessible(world.Objective.Position, 9), "BP terminal cannot be reached")
check(accessible(world.Exit.Position, 9), "Escape door cannot be reached")
check(accessible(world.RescuePrompt.Parent.Position, 9), "Rescue panel cannot be reached")
check(not accessible(world.CageSpawn.Position, 3), "Cage must require release, not allow walking out")

local oldMap = map
World.create()
check(workspace:FindFirstChild("PrototypeMap") ~= oldMap, "Map recreation must replace the old map")
local generatedMaps = 0
for _, child in workspace:GetChildren() do
	if child.Name == "PrototypeMap" then generatedMaps += 1 end
end
check(generatedMaps == 1, "Map recreation left duplicate maps")
print(string.format("PASS %d map checks; %d reachable walkable grid cells", checks, #queue))
