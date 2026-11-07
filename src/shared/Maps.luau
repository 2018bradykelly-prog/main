--!strict
-- Map definitions as plain data. World.build turns a definition into parts.
-- Coordinates are studs on the XZ plane; every arena is centred on the origin.
--
-- Rules every map must satisfy (enforced by tests/world.spec.luau):
--   * every terminal, exit, rescue panel and locker is reachable WITHOUT
--     vaulting (windows are shortcuts, never the only route);
--   * cages are sealed;
--   * spawns are clear of geometry.

export type Rect = { X: number, Z: number, W: number, D: number, H: number? }
export type Window = { X: number, Z: number, Length: number, Axis: "X" | "Z" }
export type Point = { X: number, Z: number, Face: string? }

export type Definition = {
	Id: string,
	Name: string,
	Blurb: string,
	Half: number,
	Theme: {
		Floor: Color3,
		Wall: Color3,
		Prop: Color3,
		Lamp: Color3,
		Ambient: Color3,
		Fog: Color3,
		FogEnd: number,
		FloorMaterial: Enum.Material,
		WallMaterial: Enum.Material,
	},
	Walls: { Rect },
	Windows: { Window },
	Props: { Rect },
	Terminals: { Point },
	Lockers: { Point },
	Cages: { Point },
	Exits: { Point },
	Lamps: { Point },
	SurvivorSpawns: { Point },
	KillerSpawn: Point,
}

export type Opening = { At: number, Width: number, Kind: "Door" | "Window" }

local Maps = {}

local THICK = 2

-- Builds an axis-aligned wall from `from` to `to` with doors and windows cut
-- into it. axis "X" runs along X at z = fixed; axis "Z" runs along Z at x = fixed.
function Maps.wall(def: Definition, axis: "X" | "Z", fixed: number, from: number, to: number, openings: { Opening }?)
	local cuts = table.clone(openings or {})
	table.sort(cuts, function(a, b)
		return a.At < b.At
	end)
	local cursor = from
	local function segment(a: number, b: number)
		if b - a < 0.5 then
			return
		end
		local mid = (a + b) / 2
		if axis == "X" then
			table.insert(def.Walls, { X = mid, Z = fixed, W = b - a, D = THICK })
		else
			table.insert(def.Walls, { X = fixed, Z = mid, W = THICK, D = b - a })
		end
	end
	for _, cut in cuts do
		local a, b = cut.At - cut.Width / 2, cut.At + cut.Width / 2
		segment(cursor, a)
		if cut.Kind == "Window" then
			if axis == "X" then
				table.insert(def.Windows, { X = cut.At, Z = fixed, Length = cut.Width, Axis = "X" })
			else
				table.insert(def.Windows, { X = fixed, Z = cut.At, Length = cut.Width, Axis = "Z" })
			end
		end
		cursor = b
	end
	segment(cursor, to)
end

local function door(at: number): Opening
	return { At = at, Width = 12, Kind = "Door" }
end

local function window(at: number): Opening
	return { At = at, Width = 8, Kind = "Window" }
end

local function blank(id: string, name: string, blurb: string, half: number, theme: any): Definition
	return {
		Id = id,
		Name = name,
		Blurb = blurb,
		Half = half,
		Theme = theme,
		Walls = {},
		Windows = {},
		Props = {},
		Terminals = {},
		Lockers = {},
		Cages = {},
		Exits = {},
		Lamps = {},
		SurvivorSpawns = {},
		KillerSpawn = { X = 0, Z = 0 },
	}
end

-- A hollow square room with a door and an optional window on given sides.
local function room(def: Definition, cx: number, cz: number, size: number, doorSide: string, windowSide: string?)
	local h = size / 2
	local sides = {
		N = { "X", cz - h, cx - h, cx + h, cx },
		S = { "X", cz + h, cx - h, cx + h, cx },
		W = { "Z", cx - h, cz - h - THICK / 2, cz + h + THICK / 2, cz },
		E = { "Z", cx + h, cz - h - THICK / 2, cz + h + THICK / 2, cz },
	}
	for side, spec in sides do
		local openings: { Opening } = {}
		if side == doorSide then
			table.insert(openings, door(spec[5]))
		elseif side == windowSide then
			table.insert(openings, window(spec[5]))
		end
		Maps.wall(def, spec[1], spec[2], spec[3], spec[4], openings)
	end
end

-- Map 1: Looksmax Labs ---------------------------------------------------------
-- A research facility: four corner labs around a central calibration core.

local function facility(): Definition
	local def = blank("Labs", "Looksmax Labs", "Cold corridors, four corner labs and a central calibration core.", 100, {
		Floor = Color3.fromRGB(57, 62, 71),
		Wall = Color3.fromRGB(38, 43, 52),
		Prop = Color3.fromRGB(80, 69, 60),
		Lamp = Color3.fromRGB(255, 160, 66),
		Ambient = Color3.fromRGB(48, 52, 67),
		Fog = Color3.fromRGB(20, 24, 35),
		FogEnd = 230,
		FloorMaterial = Enum.Material.Concrete,
		WallMaterial = Enum.Material.Concrete,
	})

	-- Central core: doors north/south, vault windows east/west.
	Maps.wall(def, "X", -25, -25, 25, { door(0) })
	Maps.wall(def, "X", 25, -25, 25, { door(0) })
	Maps.wall(def, "Z", -25, -26, 26, { window(0) })
	Maps.wall(def, "Z", 25, -26, 26, { window(0) })

	-- Corner labs: each has a door and a window toward the middle lanes.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Maps.wall(def, "Z", 45 * sx, math.min(100 * sz, 45 * sz), math.max(100 * sz, 45 * sz), { door(74 * sz) })
			Maps.wall(def, "X", 45 * sz, math.min(100 * sx, 45 * sx), math.max(100 * sx, 45 * sx), { window(81 * sx) })
			-- Interior lab bench to loop around.
			table.insert(def.Props, { X = 66 * sx, Z = 66 * sz, W = 14, D = 4, H = 3.5 })
		end
	end

	-- Middle lanes (north/south): a short wall with a window makes a loop.
	for _, sz in { -1, 1 } do
		Maps.wall(def, "X", 70 * sz, -14, 14, { window(0) })
		table.insert(def.Props, { X = -30, Z = 62 * sz, W = 8, D = 8, H = 6 })
		table.insert(def.Props, { X = 30, Z = 62 * sz, W = 8, D = 8, H = 6 })
	end
	-- East/west lanes hold the cages, flanked by crates.
	for _, sx in { -1, 1 } do
		table.insert(def.Props, { X = 62 * sx, Z = -32, W = 10, D = 6, H = 6 })
		table.insert(def.Props, { X = 62 * sx, Z = 32, W = 10, D = 6, H = 6 })
	end

	def.Terminals = {
		{ X = 0, Z = 0, Face = "N" },
		{ X = -72, Z = -80, Face = "S" }, { X = 72, Z = -80, Face = "S" },
		{ X = -72, Z = 82, Face = "N" }, { X = 72, Z = 82, Face = "N" },
	}
	def.Lockers = {
		{ X = -20, Z = -12, Face = "E" }, { X = 20, Z = 12, Face = "W" },
		{ X = -96, Z = -60, Face = "E" }, { X = 96, Z = -60, Face = "W" },
		{ X = -96, Z = 60, Face = "E" }, { X = 96, Z = 60, Face = "W" },
		{ X = -50, Z = -96, Face = "S" }, { X = 50, Z = 96, Face = "N" },
		{ X = -14, Z = -66, Face = "S" }, { X = 14, Z = 66, Face = "N" },
	}
	def.Cages = { { X = 76, Z = 0, Face = "W" }, { X = -76, Z = 0, Face = "E" } }
	def.Exits = { { X = 0, Z = -100, Face = "S" }, { X = 0, Z = 100, Face = "N" } }
	def.Lamps = {
		{ X = 0, Z = 0 }, { X = -72, Z = -72 }, { X = 72, Z = -72 }, { X = -72, Z = 72 }, { X = 72, Z = 72 },
		{ X = 0, Z = -85 }, { X = 0, Z = 85 }, { X = -76, Z = 0 }, { X = 76, Z = 0 },
	}
	def.SurvivorSpawns = {
		{ X = -85, Z = 85 }, { X = 85, Z = 88 }, { X = -88, Z = -85 },
		{ X = -35, Z = 88 }, { X = 35, Z = 88 }, { X = -85, Z = 30 },
	}
	def.KillerSpawn = { X = 85, Z = -88 }
	return def
end

-- Map 2: Mewing Mall -----------------------------------------------------------
-- Eight shops around an open atrium. Shops are risky: one door, one window.

local function mall(): Definition
	local def = blank("Mall", "Mewing Mall", "Abandoned shops around a fountain atrium. Every shop has one door and one window.", 100, {
		Floor = Color3.fromRGB(92, 80, 74),
		Wall = Color3.fromRGB(60, 46, 52),
		Prop = Color3.fromRGB(116, 86, 64),
		Lamp = Color3.fromRGB(255, 120, 190),
		Ambient = Color3.fromRGB(62, 48, 60),
		Fog = Color3.fromRGB(34, 22, 32),
		FogEnd = 210,
		FloorMaterial = Enum.Material.Marble,
		WallMaterial = Enum.Material.Brick,
	})
	local shops = {
		{ -60, -60, "S", "E" }, { 0, -60, "S", "N" }, { 60, -60, "S", "W" },
		{ -60, 0, "E", "W" }, { 60, 0, "W", "E" },
		{ -60, 60, "N", "E" }, { 0, 60, "N", "S" }, { 60, 60, "N", "W" },
	}
	for _, shop in shops do
		room(def, shop[1], shop[2], 36, shop[3], shop[4])
	end
	-- Atrium fountain and benches.
	table.insert(def.Props, { X = 0, Z = 0, W = 10, D = 10, H = 3 })
	for _, offset in { { -18, 0, 2, 8 }, { 18, 0, 2, 8 }, { 0, -20, 8, 2 }, { 0, 20, 8, 2 } } do
		table.insert(def.Props, { X = offset[1], Z = offset[2], W = offset[3], D = offset[4], H = 2 })
	end
	-- Kiosks in the corridors for looping.
	for _, position in { { -30, -30 }, { 30, -30 }, { -30, 30 }, { 30, 30 } } do
		table.insert(def.Props, { X = position[1], Z = position[2], W = 6, D = 6, H = 7 })
	end
	def.Terminals = {
		{ X = -66, Z = -66, Face = "S" }, { X = 66, Z = -66, Face = "S" },
		{ X = -66, Z = 66, Face = "N" }, { X = 66, Z = 66, Face = "N" },
		{ X = 0, Z = 12, Face = "S" },
	}
	def.Lockers = {
		{ X = -73, Z = -8, Face = "E" }, { X = -73, Z = 8, Face = "E" },
		{ X = 73, Z = -8, Face = "W" }, { X = 73, Z = 8, Face = "W" },
		{ X = -96, Z = -30, Face = "E" }, { X = 96, Z = 30, Face = "W" },
		{ X = -30, Z = 96, Face = "N" }, { X = 30, Z = -96, Face = "S" },
	}
	def.Cages = { { X = 0, Z = -64, Face = "S" }, { X = 0, Z = 64, Face = "N" } }
	def.Exits = { { X = -100, Z = 0, Face = "E" }, { X = 100, Z = 0, Face = "W" } }
	def.Lamps = {
		{ X = 0, Z = 0 }, { X = -60, Z = -60 }, { X = 60, Z = -60 }, { X = -60, Z = 60 }, { X = 60, Z = 60 },
		{ X = -60, Z = 0 }, { X = 60, Z = 0 }, { X = 0, Z = -60 }, { X = 0, Z = 60 },
	}
	def.SurvivorSpawns = {
		{ X = -88, Z = 88 }, { X = 88, Z = 88 }, { X = -88, Z = -40 },
		{ X = 88, Z = 40 }, { X = -30, Z = 88 }, { X = 30, Z = 88 },
	}
	def.KillerSpawn = { X = 0, Z = -88 }
	return def
end

Maps.List = { facility(), mall() }

function Maps.get(id: string): Definition?
	for _, def in Maps.List do
		if def.Id == id then
			return def
		end
	end
	return nil
end

function Maps.ids(): { string }
	local ids = {}
	for _, def in Maps.List do
		table.insert(ids, def.Id)
	end
	return ids
end

return Maps
