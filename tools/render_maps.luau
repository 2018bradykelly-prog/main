-- Renders a top-down SVG of every map from the real World builder output.
-- Run from the repository root: lune run tools/render_maps.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local game = roblox.Instance.new("DataModel")
local env = { game = game }
for _, key in { "Instance", "Vector3", "Color3", "Enum", "UDim", "UDim2", "CFrame" } do
	env[key] = roblox[key]
end
local function load(path: string)
	return luau.load(fs.readFile(path), { debugName = path, environment = env })()
end
local World = load("src/server/World.luau")
local Maps = load("src/shared/Maps.luau")

local function hex(color): string
	return string.format("#%02x%02x%02x", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

if not fs.isDir("docs") then fs.writeDir("docs") end
if not fs.isDir("docs/maps") then fs.writeDir("docs/maps") end

for _, def in Maps.List do
	local arena = World.build(def)
	local half = def.Half + 4
	local scale = 4
	local size = half * 2 * scale
	local out = {}
	local function px(v: number): number
		return (v + half) * scale
	end
	table.insert(out, string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="Arial, sans-serif">', size, size + 70, size, size + 70))
	table.insert(out, string.format('<rect width="%d" height="%d" fill="%s"/>', size, size + 70, hex(def.Theme.Floor)))
	local function rect(part, fill: string, opacity: number?)
		local cf, s = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = math.abs(r.X) * s.X / 2 + math.abs(u.X) * s.Y / 2 + math.abs(l.X) * s.Z / 2
		local hz = math.abs(r.Z) * s.X / 2 + math.abs(u.Z) * s.Y / 2 + math.abs(l.Z) * s.Z / 2
		local p = cf.Position
		table.insert(out, string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="%.2f"/>',
			px(p.X - hx), px(p.Z - hz), hx * 2 * scale, hz * 2 * scale, fill, opacity or 1))
	end
	for _, part in arena.Folder:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Floor" and part.Name ~= "Lamp" and part.Name ~= "Lintel" then
			local name = part.Name
			if name == "VaultSill" then
				rect(part, "#e0a050")
			elseif name == "Wall" or name == "OuterWall" then
				rect(part, "#1b1f27")
			elseif name == "Prop" then
				rect(part, "#7a5a40")
			elseif name == "Barrier" or name == "Bar" or name == "Roof" then
				-- drawn as a cage marker below
			elseif part.Parent and part.Parent.Name:match("^Locker") then
				rect(part, "#4a90a8")
			elseif name == "Calibrator" then
				rect(part, "#5de2e1")
			elseif name == "ExitDoor" then
				rect(part, "#7fef97")
			end
		end
	end
	local function marker(x: number, z: number, color: string, text: string, radius: number?)
		table.insert(out, string.format('<circle cx="%.1f" cy="%.1f" r="%d" fill="%s" stroke="#000" stroke-width="1.5"/>', px(x), px(z), radius or 9, color))
		table.insert(out, string.format('<text x="%.1f" y="%.1f" font-size="11" font-weight="bold" text-anchor="middle" fill="#fff" stroke="#000" stroke-width="0.6">%s</text>', px(x), px(z) - (radius or 9) - 4, text))
	end
	for _, cage in arena.Cages do
		local p = cage.Spawn.Position
		table.insert(out, string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#f14d5e" stroke-width="4"/>', px(p.X - 7), px(p.Z - 7), 14 * scale, 14 * scale))
		marker(cage.Panel.CFrame.Position.X, cage.Panel.CFrame.Position.Z, "#f14d5e", "Cage", 6)
	end
	for _, spawn in arena.SurvivorSpawns do
		marker(spawn.Position.X, spawn.Position.Z, "#7cd4ca", "S", 6)
	end
	marker(arena.KillerSpawn.Position.X, arena.KillerSpawn.Position.Z, "#ff8957", "CHAD", 9)
	local legend = {
		{ "#5de2e1", "BP terminal" }, { "#7fef97", "Exit gate" }, { "#4a90a8", "Locker" },
		{ "#e0a050", "Vault window" }, { "#f14d5e", "Mog cage" }, { "#7cd4ca", "Survivor spawn" }, { "#7a5a40", "Cover" },
	}
	for index, entry in legend do
		local x = 12 + (index - 1) * (size - 24) / #legend
		table.insert(out, string.format('<rect x="%.1f" y="%d" width="14" height="14" fill="%s"/>', x, size + 12, entry[1]))
		table.insert(out, string.format('<text x="%.1f" y="%d" font-size="12" fill="#fff">%s</text>', x + 18, size + 24, entry[2]))
	end
	table.insert(out, string.format('<text x="12" y="%d" font-size="16" font-weight="bold" fill="#f7d56f">%s</text><text x="%d" y="%d" font-size="12" fill="#ddd" text-anchor="end">%s</text>',
		size + 56, def.Name, size - 12, size + 56, def.Blurb))
	table.insert(out, "</svg>")
	local path = "docs/maps/" .. string.lower(def.Id) .. ".svg"
	fs.writeFile(path, table.concat(out, "\n"))
	print("Wrote " .. path)
end
