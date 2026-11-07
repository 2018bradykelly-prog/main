--!strict
-- Procedural poses without animation assets. Every client poses every
-- character locally by overriding Motor6D.Transform after the Animator runs
-- (RunService.PreSimulation), so nothing here needs replication.
--
--   Downed   lies face down, arms pulling along the floor (legs keep the walk cycle)
--   Carried  limp over the OG Chad's shoulder, arms dangling
--   Caged    slumped forward, arms hanging
--   Injured  hunched forward, clutching one arm
--   Killer   overhead chop on attack; one arm braced while carrying
--
-- R15 only (the Roblox default). R6 characters are left to their animations.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Poses = {}

type Rig = {
	Character: Model,
	Root: Motor6D?,
	Waist: Motor6D?,
	Neck: Motor6D?,
	RightShoulder: Motor6D?,
	LeftShoulder: Motor6D?,
}

local rigs: { [Player]: Rig | false } = {}
local swingStarted: { [Player]: number } = {}
local lastPosed: { [Motor6D]: boolean } = {}
local posed: { [Motor6D]: boolean } = {}
local SWING_SECONDS = 0.35

local function motor(character: Model, partName: string, jointName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	return if joint and joint:IsA("Motor6D") then joint else nil
end

local function rigFor(player: Player): Rig?
	local character = player.Character
	if not character then
		rigs[player] = nil
		return nil
	end
	local rig = rigs[player]
	if rig ~= nil and (rig == false or rig.Character == character) then
		-- Re-check a non-R15 result only when the character changes.
		if rig == false then
			return nil
		end
		return rig
	end
	if not character:FindFirstChild("UpperTorso") then
		-- Body parts may still be streaming in; try again next frame.
		return nil
	end
	local created: Rig = {
		Character = character,
		Root = motor(character, "LowerTorso", "Root"),
		Waist = motor(character, "UpperTorso", "Waist"),
		Neck = motor(character, "Head", "Neck"),
		RightShoulder = motor(character, "RightUpperArm", "RightShoulder"),
		LeftShoulder = motor(character, "LeftUpperArm", "LeftShoulder"),
	}
	rigs[player] = created
	character.AncestryChanged:Once(function()
		if rigs[player] == created then
			rigs[player] = nil
		end
	end)
	return created
end

-- Sets an absolute Transform for this frame. R15 joints share orientation with
-- the body: +X rotation swings a hanging arm forward/up; -X pitches the torso forward.
local function set(joint: Motor6D?, transform: CFrame)
	if joint and joint.Parent then
		joint.Transform = transform
		posed[joint] = true
	end
end

local function lean(radians: number): CFrame
	return CFrame.Angles(-radians, 0, 0)
end

local function raise(radians: number): CFrame
	return CFrame.Angles(radians, 0, 0)
end

function Poses.swing(player: Player)
	swingStarted[player] = os.clock()
end

local function poseSurvivor(rig: Rig, state: string, clock: number)
	if state == "Downed" then
		local reach = math.sin(clock * 5) * 0.3
		set(rig.Root, CFrame.new(0, -1.6, 0) * lean(math.rad(80)))
		set(rig.Neck, lean(math.rad(-40)))
		set(rig.RightShoulder, raise(math.rad(150) + reach))
		set(rig.LeftShoulder, raise(math.rad(150) - reach))
	elseif state == "Carried" then
		local sway = math.sin(clock * 3) * 0.15
		set(rig.Waist, lean(math.rad(25)))
		set(rig.Neck, lean(math.rad(30)))
		set(rig.RightShoulder, raise(math.rad(-15) + sway))
		set(rig.LeftShoulder, raise(math.rad(-15) - sway))
	elseif state == "Caged" then
		set(rig.Waist, lean(math.rad(28)))
		set(rig.Neck, lean(math.rad(25)))
		set(rig.RightShoulder, raise(math.rad(20)))
		set(rig.LeftShoulder, raise(math.rad(20)))
	elseif state == "Injured" then
		set(rig.Waist, lean(math.rad(14)))
		set(rig.LeftShoulder, raise(math.rad(40)) * CFrame.Angles(0, 0, math.rad(-25)))
	end
end

local function poseKiller(player: Player, rig: Rig, clock: number)
	local carrying = player:GetAttribute("Carrying")
	if type(carrying) == "number" and carrying ~= 0 then
		set(rig.LeftShoulder, raise(math.rad(165)))
	end
	local started = swingStarted[player]
	if not started then
		return
	end
	local alpha = (clock - started) / SWING_SECONDS
	if alpha >= 1 or alpha < 0 then
		swingStarted[player] = nil
		return
	end
	-- Wind up overhead for the first 30%, then chop down and across.
	local angle = if alpha < 0.3 then math.rad(170) else math.rad(170 - 160 * ((alpha - 0.3) / 0.7))
	set(rig.RightShoulder, raise(angle) * CFrame.Angles(0, 0, math.rad(-20 * alpha)))
	set(rig.Waist, lean(math.rad(18 * alpha)))
end

local function update()
	table.clear(posed)
	local clock = os.clock()
	for _, player in Players:GetPlayers() do
		local rig = rigFor(player)
		if rig then
			local role = player:GetAttribute("Role")
			local state = player:GetAttribute("Status")
			if role == "Survivor" and type(state) == "string" and player:GetAttribute("Hidden") ~= true then
				poseSurvivor(rig, state, clock)
			elseif role == "Killer" then
				poseKiller(player, rig, clock)
			end
		end
	end
	-- Joints posed last frame but not this one go back to neutral once. The
	-- Animator overwrites animated joints anyway, but rarely writes Root.
	for joint in lastPosed do
		if not posed[joint] and joint.Parent then
			joint.Transform = CFrame.identity
		end
	end
	lastPosed, posed = posed, lastPosed
end

function Poses.start(): { RBXScriptConnection }
	return {
		RunService.PreSimulation:Connect(update),
		Players.PlayerRemoving:Connect(function(player)
			rigs[player] = nil
			swingStarted[player] = nil
		end),
	}
end

return Poses
