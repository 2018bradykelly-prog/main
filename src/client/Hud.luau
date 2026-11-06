--!strict
-- Builds every on-screen element. This module only constructs instances and
-- exposes small setters; animation and game logic live in Main.client.luau.
-- It runs under Lune in tests, so it must not touch Roblox services.
local Hud = {}

Hud.Colors = {
	Background = Color3.fromRGB(13, 19, 27),
	Panel = Color3.fromRGB(20, 28, 39),
	Border = Color3.fromRGB(62, 82, 100),
	Text = Color3.fromRGB(231, 239, 243),
	Muted = Color3.fromRGB(158, 177, 189),
	Survivor = Color3.fromRGB(124, 212, 202),
	Killer = Color3.fromRGB(255, 137, 87),
	Danger = Color3.fromRGB(241, 79, 79),
	Warn = Color3.fromRGB(255, 196, 92),
	Good = Color3.fromRGB(127, 239, 151),
	Chad = Color3.fromRGB(247, 213, 111),
	Injured = Color3.fromRGB(255, 160, 96),
	Caged = Color3.fromRGB(200, 120, 255),
}
local colors = Hud.Colors

Hud.StatusColors = {
	Healthy = colors.Good,
	Injured = colors.Injured,
	Downed = colors.Danger,
	Carried = colors.Danger,
	Caged = colors.Caged,
	Escaped = colors.Chad,
	Eliminated = colors.Muted,
}

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
local label = Hud.label

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	local item = Instance.new("UIStroke")
	item.Color = color
	item.Thickness = thickness or 1
	item.Transparency = transparency or 0
	item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	item.Parent = parent
	return item
end

local function panel(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = colors.Background
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, 10)
	stroke(frame, colors.Border, 1, 0.2)
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
	item.AutoButtonColor = true
	item.Size = UDim2.fromOffset(44, 32)
	item.Selectable = true
	item.Parent = parent
	corner(item, 6)
	return item
end
Hud.button = button

local function bar(name: string, parent: Instance, color: Color3): (Frame, Frame)
	local track = Instance.new("Frame")
	track.Name = name
	track.BorderSizePixel = 0
	track.BackgroundColor3 = Color3.fromRGB(35, 45, 58)
	track.Parent = parent
	corner(track, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = color
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	corner(fill, 4)
	return track, fill
end

local function fullscreen(name: string, parent: Instance, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Active = false
	frame.Parent = parent
	return frame
end

export type AbilityButton = {
	Button: TextButton,
	Cooldown: Frame,
	CooldownText: TextLabel,
	Key: TextLabel,
	Name: TextLabel,
	Id: string,
}

export type TeamRow = {
	Frame: Frame,
	Dot: Frame,
	Name: TextLabel,
	Detail: TextLabel,
	TimerFill: Frame,
}

function Hud.create(parent: Instance)
	local screen = Instance.new("ScreenGui")
	screen.Name = "EscapeTheChadHUD"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = parent

	-- Full-screen effect layers sit underneath the panels.
	local blind = fullscreen("BlindOverlay", screen, Color3.new(1, 1, 1))
	local smoke = fullscreen("SmokeOverlay", screen, Color3.fromRGB(150, 156, 170))
	local vignette = fullscreen("DangerVignette", screen, colors.Danger)
	local border = Instance.new("Frame")
	border.Name = "ChaseBorder"
	border.BackgroundTransparency = 1
	border.Position = UDim2.fromOffset(4, 4)
	border.Size = UDim2.new(1, -8, 1, -8)
	border.Parent = screen
	local dangerStroke = stroke(border, colors.Danger, 6, 1)

	-- Match status panel (top centre) -------------------------------------
	local main = panel("MatchPanel", screen)
	main.AnchorPoint = Vector2.new(0.5, 0)
	main.Position = UDim2.new(0.5, 0, 0, 8)
	local role = label("Role", main, 13, colors.Survivor)
	role.Font = Enum.Font.GothamBlack
	role.Position = UDim2.fromOffset(12, 6)
	role.Size = UDim2.new(1, -140, 0, 24)
	role.TextTruncate = Enum.TextTruncate.AtEnd
	local timer = label("Timer", main, 20, colors.Text)
	timer.Font = Enum.Font.GothamBlack
	timer.Position = UDim2.new(1, -124, 0, 6)
	timer.Size = UDim2.fromOffset(66, 24)
	timer.TextXAlignment = Enum.TextXAlignment.Right
	local hide = button("HideHUD", "X", main)
	hide.Position = UDim2.new(1, -50, 0, 6)
	local rank = label("BPRank", main, 13, colors.Survivor)
	rank.Font = Enum.Font.GothamBold
	rank.Position = UDim2.fromOffset(12, 32)
	rank.Size = UDim2.new(1, -24, 0, 20)
	rank.TextTruncate = Enum.TextTruncate.AtEnd
	local objective = label("ObjectiveProgress", main, 12, colors.Muted)
	objective.Position = UDim2.fromOffset(12, 54)
	objective.Size = UDim2.new(1, -96, 0, 22)
	objective.TextTruncate = Enum.TextTruncate.AtEnd
	local helpButton = button("HelpToggle", "Help", main)
	helpButton.Position = UDim2.new(1, -78, 0, 50)
	helpButton.Size = UDim2.fromOffset(72, 30)
	local track, fill = bar("TeamProgress", main, colors.Survivor)
	track.Position = UDim2.new(0, 12, 1, -9)
	track.Size = UDim2.new(1, -24, 0, 4)

	-- Help / instructions ---------------------------------------------------
	local details = panel("Instructions", screen)
	details.AnchorPoint = Vector2.new(0.5, 0)
	details.Position = UDim2.new(0.5, 0, 0, 108)
	details.Visible = false
	details.ZIndex = 5
	local heading = label("Heading", details, 15, colors.Text)
	heading.Font = Enum.Font.GothamBlack
	heading.Text = "HOW TO PLAY"
	heading.Position = UDim2.fromOffset(12, 8)
	heading.Size = UDim2.new(1, -80, 0, 30)
	local close = button("CloseHelp", "Close", details)
	close.Position = UDim2.new(1, -68, 0, 6)
	close.Size = UDim2.fromOffset(60, 32)
	local help = label("Controls", details, 13, colors.Text)
	help.Position = UDim2.fromOffset(12, 42)
	help.Size = UDim2.new(1, -24, 0, 112)
	help.TextWrapped = true
	help.TextYAlignment = Enum.TextYAlignment.Top
	local message = label("Message", details, 12, colors.Muted)
	message.Position = UDim2.fromOffset(12, 160)
	message.Size = UDim2.new(1, -24, 0, 40)
	message.TextWrapped = true
	local nextRank = label("NextRank", details, 12, colors.Survivor)
	nextRank.Position = UDim2.fromOffset(12, 204)
	nextRank.Size = UDim2.new(1, -24, 0, 36)
	nextRank.TextWrapped = true
	local restore = button("RestoreHUD", "HUD", screen)
	restore.AnchorPoint = Vector2.new(1, 0)
	restore.Position = UDim2.new(1, -12, 0, 8)
	restore.Size = UDim2.fromOffset(60, 36)
	restore.Visible = false

	-- Team list (left) ------------------------------------------------------
	local team = panel("TeamPanel", screen)
	team.Position = UDim2.fromOffset(10, 110)
	team.Size = UDim2.fromOffset(200, 34)
	team.Visible = false
	local teamTitle = label("Title", team, 12, colors.Muted)
	teamTitle.Font = Enum.Font.GothamBlack
	teamTitle.Text = "SURVIVORS"
	teamTitle.Position = UDim2.fromOffset(10, 4)
	teamTitle.Size = UDim2.new(1, -20, 0, 22)
	local teamRows: { TeamRow } = {}
	for index = 1, 8 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. index
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(8, 28 + (index - 1) * 38)
		row.Size = UDim2.new(1, -16, 0, 36)
		row.Visible = false
		row.Parent = team
		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.BorderSizePixel = 0
		dot.Size = UDim2.fromOffset(10, 10)
		dot.Position = UDim2.fromOffset(2, 6)
		dot.BackgroundColor3 = colors.Good
		dot.Parent = row
		corner(dot, 5)
		local name = label("Name", row, 13, colors.Text)
		name.Font = Enum.Font.GothamBold
		name.Position = UDim2.fromOffset(18, 0)
		name.Size = UDim2.new(1, -18, 0, 20)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local detail = label("Detail", row, 11, colors.Muted)
		detail.Position = UDim2.fromOffset(18, 18)
		detail.Size = UDim2.new(1, -18, 0, 14)
		detail.TextTruncate = Enum.TextTruncate.AtEnd
		local timerTrack, timerFill = bar("CageTimer", row, colors.Caged)
		timerTrack.Position = UDim2.new(0, 18, 1, -2)
		timerTrack.Size = UDim2.new(1, -18, 0, 3)
		timerTrack.Visible = false
		table.insert(teamRows, { Frame = row, Dot = dot, Name = name, Detail = detail, TimerFill = timerFill })
	end

	-- Status banner, stamina, action button (bottom centre) -----------------
	local status = panel("StatusPanel", screen)
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -16)
	status.Size = UDim2.fromOffset(320, 64)
	status.Visible = false
	local statusText = label("StatusText", status, 14, colors.Text)
	statusText.Font = Enum.Font.GothamBlack
	statusText.TextXAlignment = Enum.TextXAlignment.Center
	statusText.Position = UDim2.fromOffset(10, 6)
	statusText.Size = UDim2.new(1, -20, 0, 22)
	statusText.TextTruncate = Enum.TextTruncate.AtEnd
	local staminaTrack, staminaFill = bar("Stamina", status, colors.Survivor)
	staminaTrack.Position = UDim2.new(0, 12, 0, 36)
	staminaTrack.Size = UDim2.new(1, -24, 0, 8)
	local staminaLabel = label("StaminaLabel", status, 10, colors.Muted)
	staminaLabel.Text = "STAMINA"
	staminaLabel.Position = UDim2.new(0, 12, 0, 46)
	staminaLabel.Size = UDim2.new(1, -24, 0, 14)
	local actionButton = button("ActionButton", "WIGGLE!", status)
	actionButton.AnchorPoint = Vector2.new(0.5, 0)
	actionButton.Position = UDim2.new(0.5, 0, 0, 32)
	actionButton.Size = UDim2.fromOffset(160, 28)
	actionButton.BackgroundColor3 = colors.Danger
	actionButton.Visible = false

	local chaseWarning = label("ChaseWarning", screen, 16, colors.Danger)
	chaseWarning.Font = Enum.Font.GothamBlack
	chaseWarning.TextStrokeTransparency = 0.35
	chaseWarning.TextXAlignment = Enum.TextXAlignment.Center
	chaseWarning.AnchorPoint = Vector2.new(0.5, 1)
	chaseWarning.Position = UDim2.new(0.5, 0, 1, -88)
	chaseWarning.Size = UDim2.new(1, -24, 0, 26)
	chaseWarning.Text = "OG CHAD IS NEAR"
	chaseWarning.Visible = false

	-- Ability bar (bottom right) --------------------------------------------
	local abilityBar = Instance.new("Frame")
	abilityBar.Name = "AbilityBar"
	abilityBar.BackgroundTransparency = 1
	abilityBar.AnchorPoint = Vector2.new(1, 1)
	abilityBar.Position = UDim2.new(1, -12, 1, -16)
	abilityBar.Size = UDim2.fromOffset(300, 78)
	abilityBar.Visible = false
	abilityBar.Parent = screen
	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	barLayout.Padding = UDim.new(0, 8)
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = abilityBar
	local abilityButtons: { [string]: AbilityButton } = {}

	-- Toasts (top right) and splash (centre) ---------------------------------
	local toasts = Instance.new("Frame")
	toasts.Name = "Toasts"
	toasts.BackgroundTransparency = 1
	toasts.AnchorPoint = Vector2.new(1, 0)
	toasts.Position = UDim2.new(1, -12, 0, 52)
	toasts.Size = UDim2.fromOffset(300, 240)
	toasts.Parent = screen
	local toastLayout = Instance.new("UIListLayout")
	toastLayout.FillDirection = Enum.FillDirection.Vertical
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	toastLayout.Padding = UDim.new(0, 6)
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Parent = toasts
	local toastCount = 0

	local splash = Instance.new("Frame")
	splash.Name = "Splash"
	splash.BackgroundTransparency = 1
	splash.AnchorPoint = Vector2.new(0.5, 0.5)
	splash.Position = UDim2.fromScale(0.5, 0.4)
	splash.Size = UDim2.new(1, -24, 0, 130)
	splash.Visible = false
	splash.Parent = screen
	local splashTitle = label("Title", splash, 44, colors.Text)
	splashTitle.Font = Enum.Font.GothamBlack
	splashTitle.TextXAlignment = Enum.TextXAlignment.Center
	splashTitle.TextStrokeTransparency = 0.4
	splashTitle.TextScaled = true
	splashTitle.Size = UDim2.new(1, 0, 0, 70)
	local splashTitleLimit = Instance.new("UITextSizeConstraint")
	splashTitleLimit.MaxTextSize = 54
	splashTitleLimit.Parent = splashTitle
	local splashSub = label("Subtitle", splash, 18, colors.Muted)
	splashSub.TextXAlignment = Enum.TextXAlignment.Center
	splashSub.TextStrokeTransparency = 0.5
	splashSub.TextWrapped = true
	splashSub.Position = UDim2.fromOffset(0, 74)
	splashSub.Size = UDim2.new(1, 0, 0, 50)

	-- Lobby panel (right): profile, loadout, map vote -------------------------
	local lobbyPanel = panel("LobbyPanel", screen)
	lobbyPanel.AnchorPoint = Vector2.new(1, 0.5)
	lobbyPanel.Position = UDim2.new(1, -12, 0.55, 0)
	lobbyPanel.Size = UDim2.fromOffset(280, 430)
	lobbyPanel.Visible = false
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 4)
	scroll.Size = UDim2.new(1, 0, 1, -8)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 4
	scroll.Parent = lobbyPanel
	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.Padding = UDim.new(0, 6)
	scrollLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Parent = scroll
	local function section(name: string, text: string, order: number): TextLabel
		local item = label(name, scroll, 12, colors.Chad)
		item.Font = Enum.Font.GothamBlack
		item.Text = text
		item.Size = UDim2.new(1, -20, 0, 20)
		item.LayoutOrder = order
		return item
	end
	section("ProfileHeading", "YOUR PROFILE", 1)
	local profileCard = Instance.new("Frame")
	profileCard.Name = "ProfileCard"
	profileCard.BackgroundColor3 = colors.Panel
	profileCard.BorderSizePixel = 0
	profileCard.Size = UDim2.new(1, -20, 0, 74)
	profileCard.LayoutOrder = 2
	profileCard.Parent = scroll
	corner(profileCard, 8)
	local profileLevel = label("Level", profileCard, 15, colors.Text)
	profileLevel.Font = Enum.Font.GothamBlack
	profileLevel.Position = UDim2.fromOffset(10, 4)
	profileLevel.Size = UDim2.new(1, -20, 0, 22)
	local profileTitle = label("Title", profileCard, 12, colors.Chad)
	profileTitle.Position = UDim2.fromOffset(10, 24)
	profileTitle.Size = UDim2.new(1, -20, 0, 16)
	local xpTrack, xpFill = bar("XPBar", profileCard, colors.Chad)
	xpTrack.Position = UDim2.fromOffset(10, 44)
	xpTrack.Size = UDim2.new(1, -20, 0, 6)
	local profileStats = label("Stats", profileCard, 11, colors.Muted)
	profileStats.Position = UDim2.fromOffset(10, 52)
	profileStats.Size = UDim2.new(1, -20, 0, 18)
	profileStats.TextTruncate = Enum.TextTruncate.AtEnd

	section("LoadoutHeading", "SURVIVOR ABILITY", 3)
	local loadoutButtons: { [string]: TextButton } = {}
	local loadoutOrder = 4

	local voteHeading = section("VoteHeading", "MAP VOTE", 50)
	local voteButtons: { [string]: TextButton } = {}
	local voteOrder = 51

	local lobbyToggle = button("LobbyToggle", "Loadout", screen)
	lobbyToggle.AnchorPoint = Vector2.new(1, 0)
	lobbyToggle.Position = UDim2.new(1, -80, 0, 8)
	lobbyToggle.Size = UDim2.fromOffset(84, 36)
	lobbyToggle.Visible = false

	-- Spectate bar ----------------------------------------------------------
	local spectate = panel("SpectatePanel", screen)
	spectate.AnchorPoint = Vector2.new(0.5, 1)
	spectate.Position = UDim2.new(0.5, 0, 1, -16)
	spectate.Size = UDim2.fromOffset(300, 44)
	spectate.Visible = false
	local spectatePrev = button("Prev", "<", spectate)
	spectatePrev.Position = UDim2.fromOffset(6, 6)
	local spectateNext = button("Next", ">", spectate)
	spectateNext.Position = UDim2.new(1, -50, 0, 6)
	local spectateName = label("Name", spectate, 13, colors.Text)
	spectateName.Font = Enum.Font.GothamBold
	spectateName.TextXAlignment = Enum.TextXAlignment.Center
	spectateName.Position = UDim2.fromOffset(54, 0)
	spectateName.Size = UDim2.new(1, -108, 1, 0)
	spectateName.TextTruncate = Enum.TextTruncate.AtEnd

	-- Results ---------------------------------------------------------------
	local results = panel("Results", screen)
	results.AnchorPoint = Vector2.new(0.5, 0.5)
	results.Position = UDim2.fromScale(0.5, 0.5)
	results.Size = UDim2.fromOffset(460, 380)
	results.Visible = false
	results.ZIndex = 8
	local resultsBanner = label("Banner", results, 26, colors.Chad)
	resultsBanner.Font = Enum.Font.GothamBlack
	resultsBanner.TextXAlignment = Enum.TextXAlignment.Center
	resultsBanner.Position = UDim2.fromOffset(12, 10)
	resultsBanner.Size = UDim2.new(1, -24, 0, 36)
	resultsBanner.TextScaled = true
	local resultsText = label("Summary", results, 14, colors.Muted)
	resultsText.TextXAlignment = Enum.TextXAlignment.Center
	resultsText.TextWrapped = true
	resultsText.Position = UDim2.fromOffset(12, 48)
	resultsText.Size = UDim2.new(1, -24, 0, 34)
	local resultsClose = button("CloseResults", "Close", results)
	resultsClose.AnchorPoint = Vector2.new(0.5, 1)
	resultsClose.Position = UDim2.new(0.5, 0, 1, -10)
	resultsClose.Size = UDim2.fromOffset(110, 32)
	local resultRows: { TextLabel } = {}
	for index = 1, 8 do
		local row = label("Row" .. index, results, 13, colors.Text)
		row.Position = UDim2.fromOffset(16, 88 + (index - 1) * 30)
		row.Size = UDim2.new(1, -32, 0, 28)
		row.BackgroundTransparency = if index % 2 == 1 then 0.88 else 1
		row.BackgroundColor3 = colors.Border
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.RichText = true
		table.insert(resultRows, row)
	end

	local ui = {
		Screen = screen, Main = main, Details = details, Role = role, Timer = timer,
		Rank = rank, Objective = objective, ProgressFill = fill, Message = message,
		NextRank = nextRank, Help = help, HelpButton = helpButton, Close = close,
		Hide = hide, Restore = restore, ChaseWarning = chaseWarning, DangerStroke = dangerStroke,
		Team = team, TeamRows = teamRows,
		Status = status, StatusText = statusText, StaminaTrack = staminaTrack, StaminaFill = staminaFill,
		StaminaLabel = staminaLabel, ActionButton = actionButton,
		AbilityBar = abilityBar, AbilityButtons = abilityButtons,
		Toasts = toasts, Splash = splash, SplashTitle = splashTitle, SplashSubtitle = splashSub,
		LobbyPanel = lobbyPanel, LobbyToggle = lobbyToggle, ProfileLevel = profileLevel, ProfileTitle = profileTitle,
		XPFill = xpFill, ProfileStats = profileStats, LoadoutButtons = loadoutButtons,
		VoteHeading = voteHeading, VoteButtons = voteButtons,
		Spectate = spectate, SpectatePrev = spectatePrev, SpectateNext = spectateNext, SpectateName = spectateName,
		Results = results, ResultsBanner = resultsBanner, ResultsText = resultsText, ResultsClose = resultsClose,
		ResultRows = resultRows,
		Blind = blind, Smoke = smoke, Vignette = vignette,
	}

	function ui.setHelpVisible(visible: boolean)
		details.Visible = visible
		if visible then
			main.Visible = true
			restore.Visible = false
		end
		helpButton.Text = if visible then "Close" else "Help"
	end

	function ui.setHudVisible(visible: boolean)
		main.Visible = visible
		restore.Visible = not visible
		if not visible then
			ui.setHelpVisible(false)
		end
	end

	function ui.resize(viewport: Vector2)
		local width = math.max(240, math.min(420, viewport.X - 24))
		main.Size = UDim2.fromOffset(width, 92)
		details.Size = UDim2.fromOffset(width, 246)
		local scale = details:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = details
		end
		(scale :: UIScale).Scale = math.clamp((viewport.Y - 124) / 246, 0.5, 1)
		-- Side panels shrink on phones so the centre of the screen stays clear.
		local compact = viewport.X < 700 or viewport.Y < 450
		local sideScale = if compact then 0.72 else 1
		for _, frame in { team, lobbyPanel, abilityBar, status, results, spectate } do
			local item = frame:FindFirstChildOfClass("UIScale")
			if not item then
				item = Instance.new("UIScale")
				item.Parent = frame
			end
			(item :: UIScale).Scale = sideScale
		end
		results.Size = UDim2.fromOffset(math.min(460, (viewport.X - 24) / sideScale), math.min(380, (viewport.Y - 24) / sideScale))
		lobbyPanel.Size = UDim2.fromOffset(280, math.min(430, (viewport.Y - 120) / sideScale))
		team.Position = UDim2.fromOffset(10, if compact then 96 else 110)
	end

	function ui.setTeam(entries: { { Name: string, Detail: string, Color: Color3, Timer: number? } })
		team.Visible = #entries > 0
		for index, row in teamRows do
			local entry = entries[index]
			row.Frame.Visible = entry ~= nil
			if entry then
				row.Name.Text = entry.Name
				row.Detail.Text = entry.Detail
				row.Dot.BackgroundColor3 = entry.Color
				local timerTrack = row.TimerFill.Parent :: Frame
				timerTrack.Visible = entry.Timer ~= nil
				row.TimerFill.Size = UDim2.fromScale(math.clamp(entry.Timer or 0, 0, 1), 1)
			end
		end
		team.Size = UDim2.fromOffset(200, 32 + math.min(#entries, #teamRows) * 38)
	end

	function ui.setAbilities(list: { { Id: string, Key: string, Name: string, Color: Color3? } }): { [string]: AbilityButton }
		for _, existing in abilityButtons do
			existing.Button:Destroy()
		end
		table.clear(abilityButtons)
		for index, ability in list do
			local item = button("Ability_" .. ability.Id, "", abilityBar)
			item.Size = UDim2.fromOffset(68, 72)
			item.LayoutOrder = index
			item.BackgroundColor3 = colors.Panel
			stroke(item, ability.Color or colors.Border, 2, 0.1)
			local key = label("Key", item, 18, ability.Color or colors.Text)
			key.Font = Enum.Font.GothamBlack
			key.Text = ability.Key
			key.TextXAlignment = Enum.TextXAlignment.Center
			key.Position = UDim2.fromOffset(0, 8)
			key.Size = UDim2.new(1, 0, 0, 26)
			local name = label("AbilityName", item, 10, colors.Text)
			name.Text = ability.Name
			name.TextXAlignment = Enum.TextXAlignment.Center
			name.TextWrapped = true
			name.Position = UDim2.fromOffset(2, 36)
			name.Size = UDim2.new(1, -4, 0, 30)
			local cooldown = Instance.new("Frame")
			cooldown.Name = "Cooldown"
			cooldown.BorderSizePixel = 0
			cooldown.BackgroundColor3 = Color3.new(0, 0, 0)
			cooldown.BackgroundTransparency = 0.35
			cooldown.AnchorPoint = Vector2.new(0, 1)
			cooldown.Position = UDim2.fromScale(0, 1)
			cooldown.Size = UDim2.fromScale(1, 0)
			cooldown.ZIndex = 2
			cooldown.Parent = item
			corner(cooldown, 6)
			local cooldownText = label("CooldownText", item, 20, colors.Text)
			cooldownText.Font = Enum.Font.GothamBlack
			cooldownText.TextXAlignment = Enum.TextXAlignment.Center
			cooldownText.Size = UDim2.fromScale(1, 1)
			cooldownText.ZIndex = 3
			abilityButtons[ability.Id] = { Button = item, Cooldown = cooldown, CooldownText = cooldownText, Key = key, Name = name, Id = ability.Id }
		end
		abilityBar.Size = UDim2.fromOffset(#list * 76, 78)
		return abilityButtons
	end

	-- fraction: 0 = ready, 1 = just used. active: highlighted (sprinting, crouched).
	function ui.setCooldown(id: string, fraction: number, seconds: number, active: boolean?)
		local entry = abilityButtons[id]
		if not entry then
			return
		end
		entry.Cooldown.Size = UDim2.fromScale(1, math.clamp(fraction, 0, 1))
		entry.CooldownText.Text = if seconds > 0 then tostring(math.ceil(seconds)) else ""
		entry.Button.BackgroundColor3 = if active then colors.Border else colors.Panel
	end

	function ui.pushToast(text: string, color: Color3): TextLabel
		toastCount += 1
		local item = label("Toast", toasts, 13, colors.Text)
		item.Font = Enum.Font.GothamBold
		item.Text = text
		item.TextWrapped = true
		item.AutomaticSize = Enum.AutomaticSize.Y
		item.Size = UDim2.new(1, 0, 0, 30)
		item.BackgroundColor3 = colors.Background
		item.BackgroundTransparency = 0.15
		item.LayoutOrder = toastCount
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.Parent = item
		corner(item, 8)
		stroke(item, color, 2, 0)
		local children = toasts:GetChildren()
		local labels = {}
		for _, child in children do
			if child:IsA("TextLabel") then
				table.insert(labels, child)
			end
		end
		table.sort(labels, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		while #labels > 5 do
			table.remove(labels, 1):Destroy()
		end
		return item
	end

	function ui.setLoadout(list: { { Id: string, Name: string, Description: string, Color: Color3? } }, selected: string)
		for _, ability in list do
			local item = loadoutButtons[ability.Id]
			if not item then
				local created = button("Loadout_" .. ability.Id, "", scroll)
				created.Size = UDim2.new(1, -20, 0, 52)
				created.LayoutOrder = loadoutOrder
				loadoutOrder += 1
				created.BackgroundColor3 = colors.Panel
				created.TextXAlignment = Enum.TextXAlignment.Left
				local title = label("Title", created, 13, ability.Color or colors.Text)
				title.Font = Enum.Font.GothamBlack
				title.Text = ability.Name
				title.Position = UDim2.fromOffset(10, 4)
				title.Size = UDim2.new(1, -20, 0, 18)
				local body = label("Body", created, 10, colors.Muted)
				body.Text = ability.Description
				body.TextWrapped = true
				body.TextYAlignment = Enum.TextYAlignment.Top
				body.Position = UDim2.fromOffset(10, 22)
				body.Size = UDim2.new(1, -20, 0, 28)
				stroke(created, ability.Color or colors.Border, 2, 1)
				loadoutButtons[ability.Id] = created
				item = created
			end
			local itemStroke = (item :: TextButton):FindFirstChildOfClass("UIStroke")
			if itemStroke then
				itemStroke.Transparency = if ability.Id == selected then 0 else 0.85
			end
		end
	end

	function ui.setVotes(options: { { Id: string, Name: string, Blurb: string, Votes: number } }, mine: string?, open: boolean)
		voteHeading.Visible = open and #options > 0
		for _, option in options do
			local item = voteButtons[option.Id]
			if not item then
				local created = button("Vote_" .. option.Id, "", scroll)
				created.Size = UDim2.new(1, -20, 0, 56)
				created.LayoutOrder = voteOrder
				voteOrder += 1
				created.BackgroundColor3 = colors.Panel
				local title = label("Title", created, 14, colors.Text)
				title.Font = Enum.Font.GothamBlack
				title.Position = UDim2.fromOffset(10, 4)
				title.Size = UDim2.new(1, -60, 0, 20)
				local body = label("Body", created, 10, colors.Muted)
				body.TextWrapped = true
				body.TextYAlignment = Enum.TextYAlignment.Top
				body.Position = UDim2.fromOffset(10, 24)
				body.Size = UDim2.new(1, -20, 0, 30)
				local count = label("Count", created, 16, colors.Chad)
				count.Font = Enum.Font.GothamBlack
				count.TextXAlignment = Enum.TextXAlignment.Right
				count.Position = UDim2.new(1, -54, 0, 4)
				count.Size = UDim2.fromOffset(44, 20)
				stroke(created, colors.Chad, 2, 1)
				voteButtons[option.Id] = created
				item = created
			end
			local voteButton = item :: TextButton
			voteButton.Visible = open
			local title = voteButton:FindFirstChild("Title") :: TextLabel?
			local body = voteButton:FindFirstChild("Body") :: TextLabel?
			local count = voteButton:FindFirstChild("Count") :: TextLabel?
			if title then title.Text = option.Name end
			if body then body.Text = option.Blurb end
			if count then count.Text = tostring(option.Votes) end
			local itemStroke = voteButton:FindFirstChildOfClass("UIStroke")
			if itemStroke then
				itemStroke.Transparency = if option.Id == mine then 0 else 0.85
			end
		end
	end

	function ui.setProfile(level: number, title: string, into: number, need: number, statsText: string)
		profileLevel.Text = string.format("LEVEL %d", level)
		profileTitle.Text = title
		xpFill.Size = UDim2.fromScale(if need > 0 then math.clamp(into / need, 0, 1) else 0, 1)
		profileStats.Text = statsText
	end

	function ui.setLobbyVisible(visible: boolean)
		lobbyPanel.Visible = visible
		lobbyToggle.Text = if visible then "Hide" else "Loadout"
	end

	function ui.showResults(banner: string, color: Color3, summary: string, rows: { string })
		results.Visible = true
		resultsBanner.Text = banner
		resultsBanner.TextColor3 = color
		resultsText.Text = summary
		for index, row in resultRows do
			row.Text = rows[index] or ""
			row.Visible = rows[index] ~= nil
		end
	end

	ui.resize(Vector2.new(800, 600))
	return ui
end

return Hud
