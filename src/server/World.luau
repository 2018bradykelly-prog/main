--!strict
-- Builds arenas from data definitions (see Maps.luau) and the permanent lobby.
-- All geometry is generated and anchored; no external assets are used.
--
-- ProximityPrompts carry attributes the client uses to show only relevant prompts:
--   Kind    Terminal | Exit | Rescue | Cage | Locker | Revive | Heal | Pickup
--   ForRole Survivor | Killer | Any
--   Active  set by the server; the client hides inactive prompts
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local World = {}

World.LobbyOrigin = Vector3.new(0, 0, 400)
World.WallHeight = 13
World.SillHeight = 3
World.WindowTop = 10

local FACES: { [string]: Vector3 } = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

local CYAN = Color3.fromRGB(93, 226, 225)
local GREEN = Color3.fromRGB(127, 239, 151)
local RED = Color3.fromRGB(241, 77, 94)
local GOLD = Color3.fromRGB(247, 213, 111)

World.Colors = table.freeze({ Cyan = CYAN, Green = GREEN, Red = RED, Gold = GOLD })

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local object = Instance.new("Part")
	object.Name = name
	object.Anchored = true
	object.Size = size
	object.CFrame = cframe
	object.Color = color
	object.Material = material or Enum.Material.Concrete
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.Parent = parent
	return object
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Orientation whose LookVector (front, local -Z) points along the face direction.
local function facing(position: Vector3, face: string?): CFrame
	local direction = FACES[face or "S"] or FACES.S
	return CFrame.lookAt(position, position + direction)
end

local function label(parent: BasePart, text: string, color: Color3, height: number?, maxDistance: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "WorldLabel"
	gui.Adornee = parent
	gui.Size = UDim2.fromOffset(220, 54)
	gui.StudsOffset = Vector3.new(0, height or 5, 0)
	gui.MaxDistance = maxDistance or 60
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = parent
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 0.3
	textLabel.BackgroundColor3 = Color3.fromRGB(12, 15, 20)
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 16
	textLabel.TextWrapped = true
	textLabel.TextColor3 = color
	textLabel.Text = text
	textLabel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = textLabel
	return textLabel
end

local function prompt(parent: BasePart, name: string, action: string, object: string, hold: number, kind: string, forRole: string): ProximityPrompt
	local result = Instance.new("ProximityPrompt")
	result.Name = name
	result.ActionText = action
	result.ObjectText = object
	result.HoldDuration = hold
	result.MaxActivationDistance = 9
	result.RequiresLineOfSight = true
	result.KeyboardKeyCode = Enum.KeyCode.E
	result.GamepadKeyCode = Enum.KeyCode.ButtonX
	result.Style = Enum.ProximityPromptStyle.Default
	result.Enabled = true -- Visibility is filtered per player by the client.
	result:SetAttribute("Kind", kind)
	result:SetAttribute("ForRole", forRole)
	result:SetAttribute("Active", false)
	result.Parent = parent
	return result
end
World.prompt = prompt

local function lamp(parent: Instance, position: Vector3, color: Color3, brightness: number, range: number?): Part
	local fixture = part(parent, "Lamp", Vector3.new(2, 0.6, 2), CFrame.new(position), color, Enum.Material.Neon)
	fixture.CanCollide = false
	fixture.CanQuery = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 40
	light.Brightness = brightness
	light.Shadows = true
	light.Parent = fixture
	return fixture
end

export type Terminal = { Id: string, Part: BasePart, Screen: BasePart, Prompt: ProximityPrompt, Light: PointLight }
export type Exit = { Part: BasePart, Prompt: ProximityPrompt, Light: Part, Outside: CFrame }
export type Cage = { Id: string, Panel: BasePart, RescuePrompt: ProximityPrompt, CagePrompt: ProximityPrompt, Spawn: CFrame }
export type Locker = { Id: string, Door: BasePart, Prompt: ProximityPrompt, Inside: CFrame, Outside: CFrame }
export type Arena = {
	Id: string,
	Name: string,
	Folder: Folder,
	Terminals: { Terminal },
	Exits: { Exit },
	Cages: { Cage },
	Lockers: { Locker },
	SurvivorSpawns: { CFrame },
	KillerSpawn: CFrame,
}

local function buildTerminal(map: Instance, index: number, point: any): Terminal
	local base = facing(Vector3.new(point.X, 2.5, point.Z), point.Face)
	local model = Instance.new("Model")
	model.Name = "BPCalibrator" .. index
	model.Parent = map
	local body = part(model, "Calibrator", Vector3.new(8, 5, 5), base, Color3.fromRGB(39, 87, 96), Enum.Material.Metal)
	body:SetAttribute("TerminalId", "T" .. index)
	local screen = part(model, "Screen", Vector3.new(6, 2.5, 0.2), base * CFrame.new(0, 0.5, -2.6), CYAN, Enum.Material.Neon)
	screen.CanCollide = false
	screen.CanQuery = false -- Decorative glass must not block interaction rays.
	local light = Instance.new("PointLight")
	light.Color = CYAN
	light.Range = 18
	light.Brightness = 1.4
	light.Parent = screen
	label(body, "BP CALIBRATOR", CYAN, 5, 70)
	local terminalPrompt = prompt(body, "TerminalPrompt", "Calibrate BP", "BP Calibrator", 2.5, "Terminal", "Survivor")
	return { Id = "T" .. index, Part = body, Screen = screen, Prompt = terminalPrompt, Light = light }
end

local function buildLocker(map: Instance, index: number, point: any, color: Color3): Locker
	local base = facing(Vector3.new(point.X, 0, point.Z), point.Face)
	local model = Instance.new("Model")
	model.Name = "Locker" .. index
	model.Parent = map
	local metal = Enum.Material.DiamondPlate
	part(model, "Back", Vector3.new(4.4, 8, 0.4), base * CFrame.new(0, 4, 1.5), color, metal)
	part(model, "Left", Vector3.new(0.4, 8, 3.4), base * CFrame.new(-2, 4, 0), color, metal)
	part(model, "Right", Vector3.new(0.4, 8, 3.4), base * CFrame.new(2, 4, 0), color, metal)
	part(model, "Top", Vector3.new(4.4, 0.4, 3.4), base * CFrame.new(0, 8.2, 0), color, metal)
	local door = part(model, "Door", Vector3.new(3.6, 7.6, 0.3), base * CFrame.new(0, 3.8, -1.55), color:Lerp(Color3.new(1, 1, 1), 0.12), metal)
	door:SetAttribute("LockerId", "L" .. index)
	local lockerPrompt = prompt(door, "LockerPrompt", "Hide", "Locker", 0.5, "Locker", "Any")
	lockerPrompt.MaxActivationDistance = 7
	return {
		Id = "L" .. index,
		Door = door,
		Prompt = lockerPrompt,
		Inside = base * CFrame.new(0, 3, 0.1),
		Outside = base * CFrame.new(0, 3, -4.5),
	}
end

local function buildCage(map: Instance, index: number, point: any, wallColor: Color3): Cage
	local center = Vector3.new(point.X, 0, point.Z)
	local model = Instance.new("Model")
	model.Name = "Cage" .. index
	model.Parent = map
	local half = 7
	local glass = Color3.fromRGB(65, 75, 90)
	for _, side in { { 0, -half, 14.5, 0.6 }, { 0, half, 14.5, 0.6 }, { -half, 0, 0.6, 14.5 }, { half, 0, 0.6, 14.5 } } do
		local barrier = part(model, "Barrier", Vector3.new(side[3], 16, side[4]), at(center.X + side[1], 8, center.Z + side[2]), glass, Enum.Material.Glass)
		barrier.Transparency = 0.75
	end
	for x = -half, half, 3.5 do
		for _, z in { -half, half } do
			part(model, "Bar", Vector3.new(0.6, 16, 0.6), at(center.X + x, 8, center.Z + z), Color3.fromRGB(100, 105, 116), Enum.Material.Metal)
			part(model, "Bar", Vector3.new(0.6, 16, 0.6), at(center.X + z, 8, center.Z + x), Color3.fromRGB(100, 105, 116), Enum.Material.Metal)
		end
	end
	part(model, "Roof", Vector3.new(15, 1, 15), at(center.X, 16.5, center.Z), wallColor, Enum.Material.Metal)
	local glow = part(model, "CageGlow", Vector3.new(13, 0.2, 13), at(center.X, 0.1, center.Z), RED, Enum.Material.Neon)
	glow.CanCollide = false
	glow.CanQuery = false
	glow.Transparency = 0.6
	local direction = FACES[point.Face or "S"] or FACES.S
	local panelPosition = center + direction * (half + 2) + Vector3.new(0, 2, 0)
	local panel = part(model, "CagePanel", Vector3.new(3, 4, 1), CFrame.lookAt(panelPosition, panelPosition + direction), RED, Enum.Material.Metal)
	panel:SetAttribute("CageId", "C" .. index)
	label(panel, "MOG CAGE", RED, 5, 70)
	lamp(model, center + Vector3.new(0, 15.5, 0), RED, 1.2, 26)
	local rescuePrompt = prompt(panel, "RescuePrompt", "Free teammate", "Mog Cage", 2, "Rescue", "Survivor")
	local cagePrompt = prompt(panel, "CagePrompt", "Lock in cage", "Mog Cage", 0.8, "Cage", "Killer")
	return { Id = "C" .. index, Panel = panel, RescuePrompt = rescuePrompt, CagePrompt = cagePrompt, Spawn = CFrame.new(center + Vector3.new(0, 4, 0)) }
end

local function buildExit(map: Instance, index: number, point: any, half: number): Exit
	local direction = FACES[point.Face or "S"] or FACES.S
	-- Doors sit flush with the inner face of the outer wall.
	local position = Vector3.new(point.X, 6, point.Z) + direction * 1.4
	local base = CFrame.lookAt(position, position + direction)
	local model = Instance.new("Model")
	model.Name = "Exit" .. index
	model.Parent = map
	local door = part(model, "ExitDoor", Vector3.new(12, 12, 1), base, Color3.fromRGB(70, 40, 44), Enum.Material.Metal)
	local light = part(model, "ExitLight", Vector3.new(12, 0.8, 0.6), base * CFrame.new(0, 6.6, -0.6), RED, Enum.Material.Neon)
	light.CanCollide = false
	light.CanQuery = false
	local glow = Instance.new("PointLight")
	glow.Color = RED
	glow.Range = 30
	glow.Brightness = 1.5
	glow.Parent = light
	label(door, "EXIT GATE", GREEN, 8, 90)
	local exitPrompt = prompt(door, "ExitPrompt", "Escape", "Exit gate", 1, "Exit", "Survivor")
	return { Part = door, Prompt = exitPrompt, Light = light, Outside = CFrame.new(position + direction * 5) }
end

function World.applyTheme(theme: any)
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = theme.Ambient
	Lighting.OutdoorAmbient = theme.Ambient
	Lighting.FogColor = theme.Fog
	Lighting.FogStart = 40
	Lighting.FogEnd = theme.FogEnd
end

function World.build(def: any): Arena
	local previous = Workspace:FindFirstChild("ActiveMap")
	if previous then
		previous:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "ActiveMap"
	map:SetAttribute("MapId", def.Id)
	map:SetAttribute("MapName", def.Name)
	local theme = def.Theme
	local half = def.Half
	local size = half * 2 + 4
	local wallHeight = World.WallHeight

	part(map, "Floor", Vector3.new(size, 2, size), at(0, -1, 0), theme.Floor, theme.FloorMaterial)
	part(map, "OuterWall", Vector3.new(size, 24, 4), at(0, 12, -half - 2), theme.Wall, theme.WallMaterial)
	part(map, "OuterWall", Vector3.new(size, 24, 4), at(0, 12, half + 2), theme.Wall, theme.WallMaterial)
	part(map, "OuterWall", Vector3.new(4, 24, size), at(-half - 2, 12, 0), theme.Wall, theme.WallMaterial)
	part(map, "OuterWall", Vector3.new(4, 24, size), at(half + 2, 12, 0), theme.Wall, theme.WallMaterial)

	for _, wall in def.Walls do
		local height = wall.H or wallHeight
		part(map, "Wall", Vector3.new(wall.W, height, wall.D), at(wall.X, height / 2, wall.Z), theme.Wall, theme.WallMaterial)
	end
	for _, window in def.Windows do
		local along = if window.Axis == "X" then Vector3.new(window.Length, 0, 2) else Vector3.new(2, 0, window.Length)
		local sill = part(map, "VaultSill", along + Vector3.new(0, World.SillHeight, 0), at(window.X, World.SillHeight / 2, window.Z), theme.Prop, Enum.Material.WoodPlanks)
		sill:SetAttribute("VaultAxis", window.Axis)
		local lintelHeight = wallHeight - World.WindowTop
		part(map, "Lintel", along + Vector3.new(0, lintelHeight, 0), at(window.X, World.WindowTop + lintelHeight / 2, window.Z), theme.Wall, theme.WallMaterial)
	end
	for _, prop in def.Props do
		local height = prop.H or 6
		part(map, "Prop", Vector3.new(prop.W, height, prop.D), at(prop.X, height / 2, prop.Z), theme.Prop, Enum.Material.WoodPlanks)
	end
	for _, point in def.Lamps do
		lamp(map, Vector3.new(point.X, 12, point.Z), theme.Lamp, 1.1, 44)
	end

	local terminals: { Terminal } = {}
	for index, point in def.Terminals do
		table.insert(terminals, buildTerminal(map, index, point))
	end
	local lockers: { Locker } = {}
	for index, point in def.Lockers do
		table.insert(lockers, buildLocker(map, index, point, Color3.fromRGB(72, 92, 104)))
	end
	local cages: { Cage } = {}
	for index, point in def.Cages do
		table.insert(cages, buildCage(map, index, point, theme.Wall))
	end
	local exits: { Exit } = {}
	for index, point in def.Exits do
		table.insert(exits, buildExit(map, index, point, half))
	end

	local spawns: { CFrame } = {}
	for _, point in def.SurvivorSpawns do
		table.insert(spawns, CFrame.new(point.X, 4, point.Z))
	end

	World.applyTheme(theme)
	map.Parent = Workspace
	return {
		Id = def.Id,
		Name = def.Name,
		Folder = map,
		Terminals = terminals,
		Exits = exits,
		Cages = cages,
		Lockers = lockers,
		SurvivorSpawns = spawns,
		KillerSpawn = CFrame.new(def.KillerSpawn.X, 4, def.KillerSpawn.Z),
	}
end

function World.applyLobbyTheme()
	World.applyTheme({ Ambient = Color3.fromRGB(70, 76, 96), Fog = Color3.fromRGB(20, 24, 35), FogEnd = 400 })
end

function World.clear()
	local previous = Workspace:FindFirstChild("ActiveMap")
	if previous then
		previous:Destroy()
	end
	World.applyLobbyTheme()
end

-- Lobby ------------------------------------------------------------------------

export type Lobby = {
	Folder: Folder,
	Spawn: CFrame,
	LeaderboardRows: { TextLabel },
	LeaderboardTitle: TextLabel,
}

local function board(parent: Instance, name: string, size: Vector3, cframe: CFrame, title: string, rows: number): (TextLabel, { TextLabel })
	local panel = part(parent, name, size, cframe, Color3.fromRGB(16, 22, 32), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = panel
	local heading = Instance.new("TextLabel")
	heading.Name = "Title"
	heading.BackgroundTransparency = 1
	heading.Size = UDim2.new(1, 0, 0.16, 0)
	heading.Font = Enum.Font.GothamBlack
	heading.TextScaled = true
	heading.TextColor3 = GOLD
	heading.Text = title
	heading.Parent = gui
	local list: { TextLabel } = {}
	for index = 1, rows do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. index
		row.BackgroundTransparency = if index % 2 == 0 then 1 else 0.85
		row.BackgroundColor3 = Color3.fromRGB(60, 80, 100)
		row.BorderSizePixel = 0
		row.Position = UDim2.new(0.04, 0, 0.18 + (index - 1) * (0.8 / rows), 0)
		row.Size = UDim2.new(0.92, 0, 0.8 / rows, 0)
		row.Font = Enum.Font.GothamMedium
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Color3.fromRGB(231, 239, 243)
		row.Text = ""
		row.Parent = gui
		table.insert(list, row)
	end
	return heading, list
end

function World.createLobby(): Lobby
	local previous = Workspace:FindFirstChild("Lobby")
	if previous then
		previous:Destroy()
	end
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	local o = World.LobbyOrigin
	local floorColor = Color3.fromRGB(42, 48, 60)
	local wallColor = Color3.fromRGB(28, 33, 44)
	part(lobby, "LobbyFloor", Vector3.new(96, 2, 76), at(o.X, -1, o.Z), floorColor, Enum.Material.SmoothPlastic)
	for _, geometry in { { 0, -38, 98, 2 }, { 0, 38, 98, 2 }, { -48, 0, 2, 76 }, { 48, 0, 2, 76 } } do
		part(lobby, "LobbyWall", Vector3.new(geometry[3], 20, geometry[4]), at(o.X + geometry[1], 10, o.Z + geometry[2]), wallColor, Enum.Material.SmoothPlastic)
	end
	part(lobby, "LobbyRoof", Vector3.new(98, 1, 78), at(o.X, 20.5, o.Z), wallColor, Enum.Material.SmoothPlastic)
	-- Neon trim along the floor edges.
	for _, geometry in { { 0, -36.6, 94, 0.4 }, { 0, 36.6, 94, 0.4 }, { -46.6, 0, 0.4, 72 }, { 46.6, 0, 0.4, 72 } } do
		local trim = part(lobby, "Trim", Vector3.new(geometry[3], 0.3, geometry[4]), at(o.X + geometry[1], 0.15, o.Z + geometry[2]), CYAN, Enum.Material.Neon)
		trim.CanCollide = false
		trim.CanQuery = false
	end
	for _, x in { -30, 0, 30 } do
		for _, z in { -18, 18 } do
			lamp(lobby, Vector3.new(o.X + x, 19.5, o.Z + z), if x == 0 then GOLD else CYAN, 1.3, 40)
		end
	end
	-- Training dummies and gym props to mess around with while waiting.
	for index, x in { -34, -26, 26, 34 } do
		local rack = part(lobby, "GymRack", Vector3.new(4, 5, 8), at(o.X + x, 2.5, o.Z + 24), Color3.fromRGB(70, 74, 86), Enum.Material.Metal)
		rack:SetAttribute("Decor", index)
	end
	local platform = part(lobby, "Stage", Vector3.new(20, 1, 12), at(o.X, 0.5, o.Z - 28), Color3.fromRGB(34, 40, 54), Enum.Material.SmoothPlastic)
	platform:SetAttribute("Decor", true)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 0.5, 12)
	spawn.CFrame = at(o.X, 0.25, o.Z + 8)
	spawn.Color = CYAN
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.45
	spawn.Parent = lobby

	-- Boards on the north wall face the spawn (+Z). A part's Front is -Z, so turn it around.
	local turn = CFrame.Angles(0, math.pi, 0)
	local title, rows = board(lobby, "Leaderboard", Vector3.new(26, 16, 1), at(o.X - 20, 9, o.Z - 36.4) * turn, "TOP MOGGERS", 10)
	local _, howRows = board(lobby, "HowToPlay", Vector3.new(26, 16, 1), at(o.X + 20, 9, o.Z - 36.4) * turn, "ESCAPE THE CHAD", 8)
	local lines = {
		"1. One player becomes the OG Chad.",
		"2. Survivors calibrate BP terminals.",
		"3. Reach Chad rank (100 BP) and power the exit.",
		"4. Chad hits: Injured, then Downed.",
		"5. Downed survivors get carried to cages.",
		"6. Free caged teammates. Third cage = out.",
		"7. Hide in lockers. Vault windows (Space).",
		"8. Shift sprint · C slide · Q ability · H help",
	}
	for index, line in lines do
		howRows[index].Text = "  " .. line
	end
	World.applyLobbyTheme()
	lobby.Parent = Workspace
	return {
		Folder = lobby,
		Spawn = CFrame.new(o.X, 4, o.Z + 8),
		LeaderboardRows = rows,
		LeaderboardTitle = title,
	}
end

return World
