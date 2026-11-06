--!strict
-- Shared gameplay tuning. BP is an entirely fictional, round-local score.
-- Upload assets/audio/chase-placeholder.wav to Roblox, grant this experience
-- access, then set ChaseSoundId to "rbxassetid://YOUR_AUDIO_ASSET_ID".
local Config = {
	MinPlayers = 2,
	IntermissionSeconds = 15,
	RoundSeconds = 300,
	ResultsSeconds = 12,
	-- Once the exit powers up the remaining time collapses to at most this.
	EndgameSeconds = 90,

	-- BP and ranks (per round, reset every round).
	BPPerObjective = 25,
	BPPerRevive = 15,
	BPPerRescue = 20,
	BPPerHeal = 10,
	MaxBP = 100,
	Ranks = {
		table.freeze({ Name = "LTN", BP = 0 }),
		table.freeze({ Name = "MTN", BP = 25 }),
		table.freeze({ Name = "HTN", BP = 50 }),
		table.freeze({ Name = "Chadlite", BP = 75 }),
		table.freeze({ Name = "Chad", BP = 100 }),
	},

	-- Interactions (hold durations in seconds).
	ObjectiveHoldSeconds = 2.5,
	ObjectiveCooldownSeconds = 6,
	TerminalOverheatSeconds = 9,
	TerminalPingSeconds = 4,
	EscapeHoldSeconds = 1,
	RescueHoldSeconds = 2,
	ReviveHoldSeconds = 3,
	HealHoldSeconds = 4,
	PickupHoldSeconds = 0.6,
	InteractionDistance = 12,

	-- Movement. The client applies these; the server sets the state attributes.
	WalkSpeed = 14,
	SprintSpeed = 24,
	SlideSpeed = 32,
	SlideSeconds = 0.7,
	SlideStaminaCost = 22,
	SlideCooldown = 1.6,
	DashSpeed = 58,
	InjuredBoostSpeed = 26,
	InjuredBoostSeconds = 2.5,
	DownedSpeed = 3.5,
	KillerWalkSpeed = 18,
	KillerChargeSpeed = 32,
	KillerJumpHeight = 1.5,
	SurvivorJumpHeight = 6,
	StaminaMax = 100,
	StaminaDrain = 24,
	StaminaRegen = 16,
	StaminaRegenDelay = 0.9,
	StaminaExhaustedThreshold = 35,
	VaultRange = 5,
	SurvivorVaultSeconds = 0.45,
	KillerVaultSeconds = 1.1,
	ScratchMarkSpeed = 19,

	-- Killer combat.
	AttackRange = 7.5,
	AttackConeDot = 0.35,
	AttackHitCooldown = 2.6,
	AttackMissCooldown = 1.4,
	AttackHitSlowSeconds = 2,
	AttackMissSlowSeconds = 0.8,
	AttackSlowSpeed = 9,
	StunSeconds = 2.2,

	-- Survivor health states.
	DownedRecoverSeconds = 45,
	CarryMaxSeconds = 18,
	WiggleGoal = 26,
	WiggleMaxPerSecond = 9,
	CageSeconds = { 40, 22 }, -- third cage eliminates immediately
	CageEscapeAttempts = 3,
	CageEscapeChance = 0.12,
	CaptureGraceSeconds = 5,

	-- Lockers.
	LockerCooldownSeconds = 1.5,

	-- Round results: survivors win if at least this fraction escapes.
	SurvivorWinFraction = 0.5,

	-- Chase presentation.
	ChaseSoundId = "",
	ChaseRadius = 65,
	ChaseFullVolumeRadius = 18,
	ChaseMaxVolume = 0.65,

	-- Persistence. Studio without API access falls back to memory only.
	DataStoreName = "EscapeTheChad_Profiles_v1",
	LeaderboardStoreName = "EscapeTheChad_Wins_v1",
	AutosaveSeconds = 120,
	LeaderboardRefreshSeconds = 90,
}

table.freeze(Config.Ranks)
table.freeze(Config.CageSeconds)
return table.freeze(Config)
