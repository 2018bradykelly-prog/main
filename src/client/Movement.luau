--!strict
-- Local movement controller: stamina sprint, slide, window vaults and dashes.
-- The server sets state attributes (Status, SlowUntil, BoostUntil, ChargeUntil,
-- StunnedUntil, Carrying); this module turns them into WalkSpeed each frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Movement = {}
Movement.__index = Movement

export type Controller = typeof(setmetatable({} :: {
	Player: Player,
	Stamina: number,
	Exhausted: boolean,
	SprintHeld: boolean,
	SprintToggled: boolean,
	Sprinting: boolean,
	SlideUntil: number,
	NextSlideAt: number,
	LastDrainAt: number,
	Vaulting: boolean,
	Dashing: boolean,
	Speed: number,
}, Movement))

local function attributeNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function attributeString(instance: Instance, name: string): string
	local value = instance:GetAttribute(name)
	return if type(value) == "string" then value else ""
end

function Movement.new(player: Player): Controller
	local self = setmetatable({
		Player = player,
		Stamina = Config.StaminaMax,
		Exhausted = false,
		SprintHeld = false,
		SprintToggled = false,
		Sprinting = false,
		SlideUntil = 0,
		NextSlideAt = 0,
		LastDrainAt = 0,
		Vaulting = false,
		Dashing = false,
		Speed = Config.WalkSpeed,
	}, Movement)
	return self
end

function Movement.character(self: Controller): (Humanoid?, BasePart?)
	local character = self.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

function Movement.isKiller(self: Controller): boolean
	return attributeString(self.Player, "Role") == "Killer"
end

-- Survivors (or lobby players) who can move freely under their own power.
function Movement.canMove(self: Controller): boolean
	local status = attributeString(self.Player, "Status")
	if self.Player:GetAttribute("Hidden") == true then
		return false
	end
	return status ~= "Downed" and status ~= "Carried" and status ~= "Caged"
end

function Movement.wantsSprint(self: Controller): boolean
	return self.SprintHeld or self.SprintToggled
end

function Movement.refill(self: Controller)
	self.Stamina = Config.StaminaMax
	self.Exhausted = false
end

function Movement.update(self: Controller, dt: number)
	local humanoid, root = self:character()
	if not humanoid or not root then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local clock = os.clock()
	local player = self.Player
	local status = attributeString(player, "Status")
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local speed: number

	if self:isKiller() then
		self.Sprinting = false
		if now < attributeNumber(player, "StunnedUntil") then
			speed = 0
		elseif now < attributeNumber(player, "ChargeUntil") then
			speed = Config.KillerChargeSpeed
		elseif now < attributeNumber(player, "SlowUntil") then
			speed = Config.AttackSlowSpeed
		else
			speed = Config.KillerWalkSpeed
		end
		if attributeNumber(player, "Carrying") ~= 0 then
			speed *= 0.9
		end
		humanoid.JumpHeight = Config.KillerJumpHeight
	elseif not self:canMove() then
		self.Sprinting = false
		speed = if status == "Downed" and player:GetAttribute("Hidden") ~= true then Config.DownedSpeed else 0
		humanoid.JumpHeight = 0
		-- Downed survivors lie on the floor; keep the camera down with them.
		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(
			if status == "Downed" then Vector3.new(0, -2, 0) else Vector3.zero,
			math.clamp(dt * 8, 0, 1)
		)
	else
		local canSprint = self:wantsSprint() and moving and not self.Exhausted and self.Stamina > 0
		self.Sprinting = canSprint
		speed = Config.WalkSpeed
		if canSprint then
			speed = Config.SprintSpeed
			self.Stamina = math.max(0, self.Stamina - Config.StaminaDrain * dt)
			self.LastDrainAt = clock
			if self.Stamina <= 0 then
				self.Exhausted = true
			end
		elseif clock - self.LastDrainAt >= Config.StaminaRegenDelay then
			self.Stamina = math.min(Config.StaminaMax, self.Stamina + Config.StaminaRegen * dt)
			if self.Exhausted and self.Stamina >= Config.StaminaExhaustedThreshold then
				self.Exhausted = false
			end
		end
		if clock < self.SlideUntil then
			local remaining = (self.SlideUntil - clock) / Config.SlideSeconds
			speed = math.max(speed, Config.WalkSpeed + (Config.SlideSpeed - Config.WalkSpeed) * remaining)
		end
		if now < attributeNumber(player, "BoostUntil") then
			speed = math.max(speed, Config.InjuredBoostSpeed)
		end
		if now < attributeNumber(player, "SlowUntil") then
			speed = math.min(speed, Config.AttackSlowSpeed)
		end
		humanoid.JumpHeight = Config.SurvivorJumpHeight
		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(
			if clock < self.SlideUntil then Vector3.new(0, -1.6, 0) else Vector3.zero,
			math.clamp(dt * 12, 0, 1)
		)
	end
	self.Speed = speed
	humanoid.UseJumpPower = false
	humanoid.WalkSpeed = speed
end

-- C: a quick slide while sprinting. Costs stamina; lowers the camera.
function Movement.slide(self: Controller): boolean
	local humanoid = self:character()
	local clock = os.clock()
	if not humanoid or self:isKiller() or not self:canMove() or self.Vaulting then
		return false
	end
	if clock < self.NextSlideAt or self.Stamina < Config.SlideStaminaCost or humanoid.MoveDirection.Magnitude < 0.1 then
		return false
	end
	self.Stamina -= Config.SlideStaminaCost
	self.LastDrainAt = clock
	self.SlideUntil = clock + Config.SlideSeconds
	self.NextSlideAt = clock + Config.SlideCooldown
	return true
end

-- Finds a window sill the character is facing and close to.
function Movement.findVault(self: Controller): (BasePart?, Vector3?, Vector3?)
	local _, root = self:character()
	local map = Workspace:FindFirstChild("ActiveMap")
	if not root or not map then
		return nil, nil, nil
	end
	local look = root.CFrame.LookVector
	for _, sill in map:GetChildren() do
		if sill:IsA("BasePart") and sill.Name == "VaultSill" then
			local axis = sill:GetAttribute("VaultAxis")
			local offset = root.Position - sill.Position
			local along = if axis == "X" then offset.X else offset.Z
			local across = if axis == "X" then offset.Z else offset.X
			local length = if axis == "X" then sill.Size.X else sill.Size.Z
			local normal = if axis == "X" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
			if math.abs(along) <= length / 2 - 0.5 and math.abs(across) <= Config.VaultRange and math.abs(across) > 0.3 then
				-- Direction across the sill, from our side to the far side.
				local direction = normal * (if across > 0 then -1 else 1)
				if look:Dot(direction) > 0.35 then
					local start = root.Position
					local landing = Vector3.new(start.X, start.Y, start.Z) + direction * (math.abs(across) + 3.2)
					return sill, start, landing
				end
			end
		end
	end
	return nil, nil, nil
end

-- Space/jump near a window performs a smooth vault. Returns true if it vaulted.
function Movement.tryVault(self: Controller): boolean
	if self.Vaulting or self.Dashing then
		return false
	end
	local humanoid, root = self:character()
	local status = attributeString(self.Player, "Status")
	if not humanoid or not root then
		return false
	end
	if not self:isKiller() and not self:canMove() then
		return false
	end
	if self:isKiller() and (attributeNumber(self.Player, "Carrying") ~= 0 or Workspace:GetServerTimeNow() < attributeNumber(self.Player, "StunnedUntil")) then
		return false
	end
	if status == "Lobby" or status == "Escaped" or status == "Eliminated" or status == "Spectating" then
		return false
	end
	local sill, start, landing = self:findVault()
	if not sill or not start or not landing then
		return false
	end
	local duration = if self:isKiller() then Config.KillerVaultSeconds else Config.SurvivorVaultSeconds
	local peak = sill.Position.Y + sill.Size.Y / 2 + 3.3
	local facing = (landing - start) * Vector3.new(1, 0, 1)
	local rotation = if facing.Magnitude > 0.01 then CFrame.lookAt(Vector3.zero, facing.Unit) else root.CFrame.Rotation
	self.Vaulting = true
	humanoid.PlatformStand = true
	local began = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		local alpha = math.clamp((os.clock() - began) / duration, 0, 1)
		local _, currentRoot = self:character()
		if not currentRoot or currentRoot ~= root then
			alpha = 1
		end
		local flat = start:Lerp(landing, alpha)
		local arc = math.sin(alpha * math.pi)
		local height = start.Y + (math.max(peak, start.Y) - start.Y) * arc
		if currentRoot == root then
			root.CFrame = CFrame.new(flat.X, height, flat.Z) * rotation
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if alpha >= 1 then
			if connection then
				connection:Disconnect()
			end
			humanoid.PlatformStand = false
			self.Vaulting = false
		end
	end)
	return true
end

-- Server-approved dash: a short, strong horizontal push.
function Movement.dash(self: Controller, duration: number)
	local humanoid, root = self:character()
	if not humanoid or not root or self.Vaulting then
		return
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		return
	end
	direction = direction.Unit
	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "Dash"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	velocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Config.DashSpeed
	velocity.MaxForce = 1e6
	velocity.Parent = root
	self.Dashing = true
	task.delay(duration, function()
		velocity:Destroy()
		attachment:Destroy()
		self.Dashing = false
	end)
end

return Movement
