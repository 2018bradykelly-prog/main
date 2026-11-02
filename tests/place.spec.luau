-- Run from the repository root: lune run tests/place.spec.luau
-- These checks compile Luau and inspect the actual Rojo artifact. They do not
-- replace a Studio multiplayer session or perform Luau type analysis.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local scripts = {}
local function collect(directory: string)
	for _, entry in fs.readDir(directory) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path)
		elseif entry:match("%.luau$") then
			table.insert(scripts, path)
		end
	end
end
collect("src")
table.sort(scripts)
assert(#scripts >= 6, "Expected server, client and shared Luau sources")
for _, path in scripts do
	local ok, result = pcall(luau.compile, fs.readFile(path))
	assert(ok, path .. " failed compilation: " .. tostring(result))
	assert(#result > 0, path .. " produced no bytecode")
	print("PASS compile " .. path)
end

local place = roblox.deserializePlace(fs.readFile("build/escape-the-chad.rbxlx"))
local checks = 0
local function child(parent, name: string, class: string)
	local value = parent:FindFirstChild(name)
	assert(value, "Missing " .. name .. " under " .. parent:GetFullName())
	assert(value.ClassName == class, name .. " has incorrect class: " .. value.ClassName)
	checks += 1
	return value
end
local storage = child(place, "ReplicatedStorage", "ReplicatedStorage")
local shared = child(storage, "Shared", "Folder")
child(storage, "MatchState", "Folder")
for _, name in { "Config", "Rules", "RoundState" } do
	local module = child(shared, name, "ModuleScript")
	assert(module.Source == fs.readFile("src/shared/" .. name .. ".luau"), name .. " source differs from artifact")
	checks += 1
end
local serverService = child(place, "ServerScriptService", "ServerScriptService")
local server = child(serverService, "Server", "Folder")
local mainServer = child(server, "Main", "Script")
assert(mainServer.Source == fs.readFile("src/server/Main.server.luau"), "Built server script is stale")
assert(not mainServer.Disabled, "Server script is disabled")
checks += 2
local world = child(server, "World", "ModuleScript")
assert(world.Source == fs.readFile("src/server/World.luau"), "Built world source is stale")
checks += 1
local starterPlayer = child(place, "StarterPlayer", "StarterPlayer")
assert(not starterPlayer.LoadCharacterAppearance, "Placeholder characters must not load user appearance")
checks += 1
local starterScripts = child(starterPlayer, "StarterPlayerScripts", "StarterPlayerScripts")
local client = child(starterScripts, "Client", "Folder")
local mainClient = child(client, "Main", "LocalScript")
local hud = child(client, "Hud", "ModuleScript")
assert(hud.Source == fs.readFile("src/client/Hud.luau"), "Built HUD source is stale")
checks += 1
assert(mainClient.Source == fs.readFile("src/client/Main.client.luau"), "Built client script is stale")
assert(not mainClient.Disabled, "Client script is disabled")
checks += 2
child(place, "Workspace", "Workspace")
local soundService = child(place, "SoundService", "SoundService")
assert(soundService.RespectFilteringEnabled, "Sound filtering must remain enabled")
checks += 1
print(string.format("PASS %d source compilations; %d built-place checks", #scripts, checks))
