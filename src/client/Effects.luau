--!strict
-- Local-only presentation: chase music, reveal outlines, terminal pings,
-- blindness, hit flashes, swing arcs and sprint scratch marks.
-- Nothing here affects gameplay; the server owns all rules.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("Rules"))

local Effects = {}

local localPlayer = Players.LocalPlayer
local folder = Instance.new("Folder")
folder.Name = "LocalEffects"
folder.Parent = Workspace

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end
Effects.rootOf = rootOf

-- Chase music -------------------------------------------------------------------

local chaseSound = Instance.new("Sound")
chaseSound.Name = "ChadChase"
chaseSound.Looped = true
chaseSound.Volume = 0
local configuredAudio = tostring(Config.ChaseSoundId or "")
local hasAudio = configuredAudio:match("^rbxassetid://%d+$") ~= nil
if hasAudio then
	chaseSound.SoundId = configuredAudio
end
chaseSound.Parent = SoundService

local currentIntensity = 0
local targetIntensity = 0
local eligible = false

-- Returns the smoothed 0..1 chase intensity for UI use.
function Effects.updateChase(dt: number, matchPhase: string): number
	eligible = matchPhase == "Active"
		and localPlayer:GetAttribute("Role") == "Survivor"
		and (localPlayer:GetAttribute("Status") == "Healthy" or localPlayer:GetAttribute("Status") == "Injured")
	local survivorRoot = if eligible then rootOf(localPlayer) else nil
	if not survivorRoot then
		eligible = false
	end
	targetIntensity = 0
	if eligible and survivorRoot then
		local distance = math.huge
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Role") == "Killer" then
				local killerRoot = rootOf(player)
				if killerRoot then
					distance = math.min(distance, (killerRoot.Position - survivorRoot.Position).Magnitude)
				end
			end
		end
		if distance == math.huge then
			eligible = false
		else
			targetIntensity = Rules.chaseIntensity(distance)
		end
	end
	if not eligible then
		currentIntensity = 0
		if chaseSound.IsPlaying then
			chaseSound:Stop()
		end
	else
		currentIntensity += (targetIntensity - currentIntensity) * (1 - math.exp(-dt * 5))
		if targetIntensity > 0 and hasAudio and not chaseSound.IsPlaying then
			chaseSound:Play()
		elseif targetIntensity == 0 and currentIntensity < 0.005 and chaseSound.IsPlaying then
			chaseSound:Stop()
		end
	end
	chaseSound.Volume = math.clamp(currentIntensity * Config.ChaseMaxVolume, 0, 1)
	return currentIntensity
end

-- Reveal (Mog Aura) ---------------------------------------------------------------

function Effects.reveal(ids: { number }, duration: number)
	for _, id in ids do
		local player = Players:GetPlayerByUserId(id)
		local character = player and player.Character
		if character then
			local highlight = Instance.new("Highlight")
			highlight.Name = "MogAura"
			highlight.FillColor = Color3.fromRGB(241, 79, 79)
			highlight.FillTransparency = 0.55
			highlight.OutlineColor = Color3.fromRGB(255, 220, 220)
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Adornee = character
			highlight.Parent = folder
			Debris:AddItem(highlight, duration)
		end
	end
end

-- Terminal ping (killer) ------------------------------------------------------------

function Effects.ping(position: Vector3, text: string, duration: number)
	local anchor = Instance.new("Part")
	anchor.Name = "Ping"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 6, 0))
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(160, 40)
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
	label.TextColor3 = Color3.fromRGB(255, 196, 92)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 14
	label.Text = "⚠ " .. text
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	Debris:AddItem(anchor, duration)
end

-- Flash, blind, hits and swings --------------------------------------------------------

function Effects.flashBurst(position: Vector3)
	local burst = Instance.new("Part")
	burst.Name = "FlashBurst"
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CanTouch = false
	burst.Material = Enum.Material.Neon
	burst.Color = Color3.fromRGB(255, 244, 190)
	burst.Size = Vector3.new(2, 2, 2)
	burst.CFrame = CFrame.new(position)
	burst.Parent = folder
	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 6
	light.Color = burst.Color
	light.Parent = burst
	TweenService:Create(burst, TweenInfo.new(0.35), { Size = Vector3.new(20, 20, 20), Transparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
	Debris:AddItem(burst, 0.6)
end

function Effects.blind(overlay: Frame, duration: number)
	overlay.BackgroundTransparency = 0
	TweenService:Create(overlay, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
end

function Effects.hitFlash(overlay: Frame, strong: boolean)
	overlay.BackgroundTransparency = if strong then 0.35 else 0.55
	TweenService:Create(overlay, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
end

function Effects.swing(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local arc = Instance.new("Part")
	arc.Name = "Swing"
	arc.Anchored = true
	arc.CanCollide = false
	arc.CanQuery = false
	arc.CanTouch = false
	arc.Material = Enum.Material.Neon
	arc.Color = Color3.fromRGB(255, 137, 87)
	arc.Transparency = 0.35
	arc.Size = Vector3.new(7, 0.3, 3)
	arc.CFrame = root.CFrame * CFrame.new(0, 0.5, -Config.AttackRange * 0.55)
	arc.Parent = folder
	TweenService:Create(arc, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(10, 0.3, 4) }):Play()
	Debris:AddItem(arc, 0.3)
end

function Effects.hitSpark(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local spark = Instance.new("Part")
	spark.Name = "HitSpark"
	spark.Shape = Enum.PartType.Ball
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.CanTouch = false
	spark.Material = Enum.Material.Neon
	spark.Color = Color3.fromRGB(241, 79, 79)
	spark.Size = Vector3.new(1.5, 1.5, 1.5)
	spark.CFrame = root.CFrame
	spark.Parent = folder
	TweenService:Create(spark, TweenInfo.new(0.3), { Size = Vector3.new(7, 7, 7), Transparency = 1 }):Play()
	Debris:AddItem(spark, 0.35)
end

-- Scratch marks (killer only) ------------------------------------------------------------
-- Survivors running faster than ScratchMarkSpeed leave short-lived marks.

local scratchClock = 0
function Effects.updateScratches(dt: number)
	scratchClock += dt
	if scratchClock < 0.18 then
		return
	end
	scratchClock = 0
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and player:GetAttribute("Role") == "Survivor" then
			local root = rootOf(player)
			if root then
				local velocity = root.AssemblyLinearVelocity
				local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
				if horizontal.Magnitude >= Config.ScratchMarkSpeed then
					local mark = Instance.new("Part")
					mark.Name = "ScratchMark"
					mark.Anchored = true
					mark.CanCollide = false
					mark.CanQuery = false
					mark.CanTouch = false
					mark.Material = Enum.Material.Neon
					mark.Color = Color3.fromRGB(255, 90, 60)
					mark.Size = Vector3.new(0.25, 0.1, 2.2)
					local base = root.Position - Vector3.new(0, 2.9, 0) + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
					mark.CFrame = CFrame.lookAt(base, base + horizontal) * CFrame.Angles(0, math.rad(math.random(-35, 35)), 0)
					mark.Parent = folder
					TweenService:Create(mark, TweenInfo.new(4, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
					Debris:AddItem(mark, 4.2)
				end
			end
		end
	end
end

function Effects.destroy()
	chaseSound:Destroy()
	folder:Destroy()
end

return Effects
