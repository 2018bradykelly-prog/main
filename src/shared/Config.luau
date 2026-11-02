--!strict
-- Shared gameplay tuning. BP is an entirely fictional, round-local score.
-- Upload assets/audio/chase-placeholder.wav to Roblox, grant this experience
-- access, then set ChaseSoundId to "rbxassetid://YOUR_AUDIO_ASSET_ID".
local Config = {
	MinPlayers = 2,
	IntermissionSeconds = 12,
	RoundSeconds = 240,
	ResultsSeconds = 8,
	BPPerObjective = 25,
	MaxBP = 100,
	ObjectiveHoldSeconds = 2,
	ObjectiveCooldownSeconds = 6,
	Ranks = {
		table.freeze({ Name = "LTN", BP = 0 }),
		table.freeze({ Name = "MTN", BP = 25 }),
		table.freeze({ Name = "HTN", BP = 50 }),
		table.freeze({ Name = "Chadlite", BP = 75 }),
		table.freeze({ Name = "Chad", BP = 100 }),
	},
	WalkSpeed = 16,
	KillerWalkSpeed = 19,
	CaptureRadius = 4.5,
	CaptureSeconds = 20,
	CaptureGraceSeconds = 5,
	RescueHoldSeconds = 2,
	EscapeHoldSeconds = 0.5,
	InteractionDistance = 12,
	ChaseSoundId = "",
	ChaseRadius = 65,
	ChaseFullVolumeRadius = 18,
	ChaseMaxVolume = 0.65,
}

table.freeze(Config.Ranks)
return table.freeze(Config)
