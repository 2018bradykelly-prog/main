--!strict
-- Ability catalogue shared by the server (validation, cooldowns) and the client
-- (buttons, descriptions). Survivors pick one loadout ability in the lobby.
-- The killer always has the full killer kit.

export type Ability = {
	Id: string,
	Name: string,
	Role: "Survivor" | "Killer",
	Key: string,
	Cooldown: number,
	Duration: number,
	Color: Color3?,
	Description: string,
}

local function define(ability: Ability): Ability
	return table.freeze(ability)
end

-- Plain Lune tests have no Color3; Studio always does.
local color3: any = (getfenv() :: any).Color3
local function rgb(r: number, g: number, b: number): Color3?
	return if color3 then color3.fromRGB(r, g, b) else nil
end

local Abilities = {}

Abilities.Survivor = table.freeze({
	define({
		Id = "Dash", Name = "Mog Dash", Role = "Survivor", Key = "Q",
		Cooldown = 18, Duration = 0.3, Color = rgb(124, 212, 202),
		Description = "Burst forward a short distance. Great for breaking line of sight.",
	}),
	define({
		Id = "Smoke", Name = "Fog Machine", Role = "Survivor", Key = "Q",
		Cooldown = 35, Duration = 7, Color = rgb(170, 178, 196),
		Description = "Drop a thick smoke cloud. OG Chad cannot hit or see through it.",
	}),
	define({
		Id = "Flash", Name = "Jawline Flash", Role = "Survivor", Key = "Q",
		Cooldown = 40, Duration = 2.2, Color = rgb(255, 236, 140),
		Description = "Blind and stun OG Chad if they are close and facing you. Also frees a carried teammate.",
	}),
	define({
		Id = "Shake", Name = "Protein Shake", Role = "Survivor", Key = "Q",
		Cooldown = 45, Duration = 4, Color = rgb(196, 140, 255),
		Description = "Heal yourself when injured. When healthy, refills stamina and gives a speed boost.",
	}),
})

Abilities.Killer = table.freeze({
	define({
		Id = "Charge", Name = "Gym Charge", Role = "Killer", Key = "Q",
		Cooldown = 20, Duration = 2.2, Color = rgb(255, 137, 87),
		Description = "Sprint at full speed for a couple of seconds.",
	}),
	define({
		Id = "Reveal", Name = "Mog Aura", Role = "Killer", Key = "F",
		Cooldown = 45, Duration = 4.5, Color = rgb(241, 79, 79),
		Description = "Reveal every survivor who is not hiding in a locker.",
	}),
})

Abilities.DefaultSurvivor = "Dash"

local byId: { [string]: Ability } = {}
for _, list in { Abilities.Survivor, Abilities.Killer } do
	for _, ability in list do
		byId[ability.Id] = ability
	end
end

function Abilities.get(id: any): Ability?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function Abilities.isSurvivorAbility(id: any): boolean
	local ability = Abilities.get(id)
	return ability ~= nil and ability.Role == "Survivor"
end

return table.freeze(Abilities)
