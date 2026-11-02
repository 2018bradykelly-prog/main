--!strict
-- A completely generated, asset-free graybox map. All collision is anchored.
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local World = {}

local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
	local object = Instance.new("Part")
	object.Name = name
	object.Anchored = true
	object.Size = size
	object.Position = position
	object.Color = color
	object.Material = material or Enum.Material.Concrete
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.Parent = parent
	return object
end

local function label(parent: BasePart, text: string, color: Color3, height: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "WorldLabel"
	gui.Adornee = parent
	gui.Size = UDim2.fromOffset(260, 64)
	gui.StudsOffset = Vector3.new(0, height or 5, 0)
	gui.MaxDistance = 100
	gui.AlwaysOnTop = false
	gui.Parent = parent
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 0.25
	textLabel.BackgroundColor3 = Color3.fromRGB(12, 15, 20)
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 18
	textLabel.TextWrapped = true
	textLabel.TextColor3 = color
	textLabel.Text = text
	textLabel.Parent = gui
end

local function prompt(parent: BasePart, name: string, action: string, object: string, hold: number): ProximityPrompt
	local result = Instance.new("ProximityPrompt")
	result.Name = name
	result.ActionText = action
	result.ObjectText = object
	result.HoldDuration = hold
	result.MaxActivationDistance = 10
	result.RequiresLineOfSight = true
	result.KeyboardKeyCode = Enum.KeyCode.E
	result.GamepadKeyCode = Enum.KeyCode.ButtonX
	result.Enabled = false -- Round controller enables interactions at round start.
	result.Parent = parent
	return result
end

local function lamp(parent: Instance, position: Vector3, color: Color3, brightness: number)
	local fixture = part(parent, "EmergencyLamp", Vector3.new(2, 1, 2), position, color, Enum.Material.Neon)
	fixture.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 44
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = fixture
end

function World.create()
	local previous = Workspace:FindFirstChild("PrototypeMap")
	if previous then
		previous:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "PrototypeMap"
	map.Parent = Workspace

	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(48, 52, 67)
	Lighting.OutdoorAmbient = Color3.fromRGB(43, 47, 60)
	Lighting.FogColor = Color3.fromRGB(20, 24, 35)
	Lighting.FogStart = 70
	Lighting.FogEnd = 230

	local concrete = Color3.fromRGB(57, 62, 71)
	local wallColor = Color3.fromRGB(38, 43, 52)
	local orange = Color3.fromRGB(255, 160, 66)
	local cyan = Color3.fromRGB(93, 226, 225)
	local green = Color3.fromRGB(127, 239, 151)
	local red = Color3.fromRGB(241, 77, 94)
	part(map, "ArenaFloor", Vector3.new(204, 2, 204), Vector3.new(0, -1, 0), concrete)
	part(map, "NorthWall", Vector3.new(204, 20, 4), Vector3.new(0, 10, -102), wallColor)
	part(map, "SouthWall", Vector3.new(204, 20, 4), Vector3.new(0, 10, 102), wallColor)
	part(map, "EastWall", Vector3.new(4, 20, 204), Vector3.new(102, 10, 0), wallColor)
	part(map, "WestWall", Vector3.new(4, 20, 204), Vector3.new(-102, 10, 0), wallColor)

	-- Staggered walls leave multiple routes and a broad circulation path at the edges.
	for _, geometry in {
		{ -48, -52, 4, 48 }, { 42, -46, 4, 60 },
		{ -65, 8, 42, 4 }, { -5, -12, 46, 4 },
		{ 48, 18, 52, 4 }, { -35, 52, 4, 44 },
		{ 0, 62, 32, 4 }, { 15, 28, 4, 34 },
	} do
		part(map, "CorridorWall", Vector3.new(geometry[3], 13, geometry[4]), Vector3.new(geometry[1], 6.5, geometry[2]), wallColor)
	end
	for _, position in { Vector3.new(-70, 3, -25), Vector3.new(70, 3, -25), Vector3.new(-65, 3, 65), Vector3.new(0, 3, 12) } do
		part(map, "StorageCrate", Vector3.new(10, 6, 10), position, Color3.fromRGB(80, 69, 60), Enum.Material.WoodPlanks)
	end
	for _, position in {
		Vector3.new(-78, 12, -75), Vector3.new(0, 12, -70), Vector3.new(76, 12, -70),
		Vector3.new(-80, 12, 32), Vector3.new(0, 12, 30), Vector3.new(78, 12, 32),
		Vector3.new(-65, 12, 85), Vector3.new(20, 12, 85),
	} do
		lamp(map, position, orange, 1.1)
	end

	local objective = part(map, "BPCalibrator", Vector3.new(8, 5, 5), Vector3.new(0, 2.5, -52), Color3.fromRGB(39, 87, 96), Enum.Material.Metal)
	local screen = part(map, "CalibratorScreen", Vector3.new(6, 2.5, 0.2), Vector3.new(0, 3, -54.61), cyan, Enum.Material.Neon)
	screen.CanCollide = false
	screen.CanQuery = false -- Decorative glass must not block terminal interactions.
	label(objective, "BP CALIBRATOR\nFictional gains. Real panic.", cyan, 6)
	lamp(map, Vector3.new(0, 9, -52), cyan, 1.6)
	local objectivePrompt = prompt(objective, "ObjectivePrompt", "Calibrate BP", "BP Calibrator", 2)

	local exit = part(map, "EscapeDoor", Vector3.new(12, 12, 1), Vector3.new(-76, 6, -99), Color3.fromRGB(47, 106, 69), Enum.Material.Metal)
	label(exit, "ESCAPE\nComplete team calibrations", green, 8)
	lamp(map, Vector3.new(-76, 13, -95), green, 1.5)
	local exitPrompt = prompt(exit, "ExitPrompt", "Escape", "Emergency exit", 0.5)

	-- Solid, tall cage walls and a roof keep prisoners inside. The rescue panel
	-- sits outside its north face, and a rescuer never needs to enter the cage.
	local cage = Instance.new("Folder")
	cage.Name = "CaptureCage"
	cage.Parent = map
	for _, z in { 55, 75 } do
		for x = 60, 80, 4 do
			part(cage, "Bar", Vector3.new(0.7, 18, 0.7), Vector3.new(x, 9, z), Color3.fromRGB(100, 105, 116), Enum.Material.Metal)
		end
		local blocker = part(cage, "GlassBarrier", Vector3.new(21, 18, 0.5), Vector3.new(70, 9, z), Color3.fromRGB(65, 75, 90), Enum.Material.Glass)
		blocker.Transparency = 0.8
	end
	for _, x in { 60, 80 } do
		local side = part(cage, "SideBarrier", Vector3.new(0.7, 18, 20), Vector3.new(x, 9, 65), Color3.fromRGB(65, 75, 90), Enum.Material.Glass)
		side.Transparency = 0.7
	end
	part(cage, "Roof", Vector3.new(21, 1, 21), Vector3.new(70, 18, 65), wallColor, Enum.Material.Metal)
	local panel = part(map, "RescuePanel", Vector3.new(3, 4, 1), Vector3.new(70, 2, 52), red, Enum.Material.Metal)
	label(panel, "CAPTURE CAGE\nHold to rescue teammates", red, 6)
	lamp(map, Vector3.new(70, 11, 50), red, 1.5)
	local rescuePrompt = prompt(panel, "RescuePrompt", "Rescue teammates", "Cage release", 2)

	-- A separate lobby is the only automatic Roblox spawn. Round placement is
	-- controlled by the server; joining during a round does not enter the arena.
	part(map, "LobbyFloor", Vector3.new(72, 2, 52), Vector3.new(0, -1, 170), concrete)
	for _, geometry in {
		{ 0, 144, 74, 2 }, { 0, 196, 74, 2 },
		{ -36, 170, 2, 52 }, { 36, 170, 2, 52 },
	} do
		part(map, "LobbyWall", Vector3.new(geometry[3], 18, geometry[4]), Vector3.new(geometry[1], 9, geometry[2]), wallColor)
	end
	lamp(map, Vector3.new(-20, 12, 170), cyan, 2)
	lamp(map, Vector3.new(20, 12, 170), cyan, 2)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 0.5, 12)
	spawn.Position = Vector3.new(0, 0.25, 170)
	spawn.Color = cyan
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.45
	spawn.Parent = map
	local sign = part(map, "LobbySign", Vector3.new(24, 9, 1), Vector3.new(0, 7, 146), Color3.fromRGB(21, 29, 40))
	label(sign, "ESCAPE THE CHAD\nWaiting room · 2+ players", cyan, 0)

	return {
		Objective = objective,
		ObjectivePrompt = objectivePrompt,
		Exit = exit,
		ExitPrompt = exitPrompt,
		RescuePrompt = rescuePrompt,
		CageSpawn = CFrame.new(70, 4, 65),
		SurvivorSpawns = {
			CFrame.new(-78, 4, 78), CFrame.new(-60, 4, 82),
			CFrame.new(-82, 4, 48), CFrame.new(-13, 4, 82),
			CFrame.new(20, 4, 82), CFrame.new(-80, 4, -12),
		},
		KillerSpawn = CFrame.new(78, 4, -82),
		LobbySpawn = CFrame.new(0, 4, 170),
	}
end

return World
