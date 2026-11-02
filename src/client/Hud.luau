--!strict
-- Compact by default. Expanded instructions are always optional and dismissible.
local Hud = {}

Hud.Colors = {
	Background = Color3.fromRGB(13, 19, 27), Border = Color3.fromRGB(62, 82, 100),
	Text = Color3.fromRGB(231, 239, 243), Muted = Color3.fromRGB(158, 177, 189),
	Survivor = Color3.fromRGB(124, 212, 202), Killer = Color3.fromRGB(255, 137, 87),
	Danger = Color3.fromRGB(241, 79, 79), Chad = Color3.fromRGB(247, 213, 111),
}
local colors = Hud.Colors

function Hud.label(name: string, parent: Instance, size: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamMedium
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Text = ""
	item.Parent = parent
	return item
end

local function panel(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = colors.Background
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = colors.Border
	stroke.Parent = frame
	return frame
end

local function button(name: string, text: string, parent: Instance): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.Text = text
	item.TextSize = 13
	item.TextColor3 = colors.Text
	item.Font = Enum.Font.GothamBold
	item.BackgroundColor3 = colors.Border
	item.BorderSizePixel = 0
	item.Size = UDim2.fromOffset(44, 32)
	item.Selectable = true
	item.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = item
	return item
end

function Hud.create(parent: Instance)
	local screen = Instance.new("ScreenGui")
	screen.Name = "EscapeTheChadHUD"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = parent
	local main = panel("MatchPanel", screen)
	main.Position = UDim2.new(0.5, 0, 0, 8)
	local role = Hud.label("Role", main, 12, colors.Survivor)
	role.Position = UDim2.fromOffset(12, 6)
	role.Size = UDim2.new(1, -140, 0, 24)
	role.TextTruncate = Enum.TextTruncate.AtEnd
	local timer = Hud.label("Timer", main, 19, colors.Text)
	timer.Position = UDim2.new(1, -124, 0, 6)
	timer.Size = UDim2.fromOffset(64, 24)
	timer.TextXAlignment = Enum.TextXAlignment.Right
	local hide = button("HideHUD", "X", main)
	hide.Position = UDim2.new(1, -50, 0, 6)
	local rank = Hud.label("BPRank", main, 13, colors.Survivor)
	rank.Position = UDim2.fromOffset(12, 32)
	rank.Size = UDim2.new(1, -24, 0, 22)
	rank.TextTruncate = Enum.TextTruncate.AtEnd
	local objective = Hud.label("ObjectiveProgress", main, 12, colors.Muted)
	objective.Position = UDim2.fromOffset(12, 56)
	objective.Size = UDim2.new(1, -96, 0, 24)
	objective.TextTruncate = Enum.TextTruncate.AtEnd
	local helpButton = button("HelpToggle", "Help", main)
	helpButton.Position = UDim2.new(1, -78, 0, 50)
	helpButton.Size = UDim2.fromOffset(72, 32)
	local track = Instance.new("Frame")
	track.Name = "TeamProgress"
	track.BorderSizePixel = 0
	track.BackgroundColor3 = colors.Border
	track.Position = UDim2.new(0, 12, 1, -6)
	track.Size = UDim2.new(1, -24, 0, 2)
	track.Parent = main
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = colors.Survivor
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track

	local details = panel("Instructions", screen)
	details.Position = UDim2.new(0.5, 0, 0, 108)
	details.Visible = false
	local heading = Hud.label("Heading", details, 15, colors.Text)
	heading.Text = "HOW TO PLAY"
	heading.Position = UDim2.fromOffset(12, 8)
	heading.Size = UDim2.new(1, -80, 0, 30)
	local close = button("CloseHelp", "Close", details)
	close.Position = UDim2.new(1, -68, 0, 6)
	close.Size = UDim2.fromOffset(60, 32)
	local help = Hud.label("Controls", details, 13, colors.Text)
	help.Position = UDim2.fromOffset(12, 44)
	help.Size = UDim2.new(1, -24, 0, 72)
	help.TextWrapped = true
	local message = Hud.label("Message", details, 12, colors.Muted)
	message.Position = UDim2.fromOffset(12, 122)
	message.Size = UDim2.new(1, -24, 0, 54)
	message.TextWrapped = true
	local nextRank = Hud.label("NextRank", details, 12, colors.Survivor)
	nextRank.Position = UDim2.fromOffset(12, 180)
	nextRank.Size = UDim2.new(1, -24, 0, 42)
	nextRank.TextWrapped = true
	local restore = button("RestoreHUD", "HUD", screen)
	restore.AnchorPoint = Vector2.new(1, 0)
	restore.Position = UDim2.new(1, -12, 0, 8)
	restore.Size = UDim2.fromOffset(60, 36)
	restore.Visible = false

	local chaseWarning = Hud.label("ChaseWarning", screen, 16, colors.Danger)
	chaseWarning.Font = Enum.Font.GothamBlack
	chaseWarning.TextStrokeTransparency = 0.35
	chaseWarning.TextXAlignment = Enum.TextXAlignment.Center
	chaseWarning.AnchorPoint = Vector2.new(0.5, 1)
	chaseWarning.Position = UDim2.new(0.5, 0, 1, -24)
	chaseWarning.Size = UDim2.new(1, -24, 0, 28)
	chaseWarning.Text = "OG CHAD IS NEAR"
	chaseWarning.Visible = false
	local border = Instance.new("Frame")
	border.Name = "ChaseBorder"
	border.BackgroundTransparency = 1
	border.Position = UDim2.fromOffset(5, 5)
	border.Size = UDim2.new(1, -10, 1, -10)
	border.Parent = screen
	local dangerStroke = Instance.new("UIStroke")
	dangerStroke.Thickness = 5
	dangerStroke.Color = colors.Danger
	dangerStroke.Transparency = 1
	dangerStroke.Parent = border

	local ui = {
		Screen = screen, Main = main, Details = details, Role = role, Timer = timer,
		Rank = rank, Objective = objective, ProgressFill = fill, Message = message,
		NextRank = nextRank, Help = help, HelpButton = helpButton, Close = close,
		Hide = hide, Restore = restore, ChaseWarning = chaseWarning, DangerStroke = dangerStroke,
	}
	function ui.setHelpVisible(visible: boolean)
		details.Visible = visible
		if visible then main.Visible = true; restore.Visible = false end
		helpButton.Text = if visible then "Close" else "Help"
	end
	function ui.setHudVisible(visible: boolean)
		main.Visible = visible
		restore.Visible = not visible
		if not visible then ui.setHelpVisible(false) end
	end
	function ui.resize(viewport: Vector2)
		local width = math.max(240, math.min(400, viewport.X - 24))
		main.Size = UDim2.fromOffset(width, 92)
		details.Size = UDim2.fromOffset(width, 230)
		-- Optional instructions can still fit in short landscape test windows.
		local scale = details:FindFirstChildOfClass("UIScale")
		if not scale then scale = Instance.new("UIScale"); scale.Parent = details end
		scale.Scale = math.clamp((viewport.Y - 124) / 230, 0.5, 1)
	end
	ui.resize(Vector2.new(800, 600))
	return ui
end

return Hud
