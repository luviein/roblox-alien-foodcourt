--!strict
-- Player-facing settings, held in one place so the settings panel does not
-- need to know about Audio, Customers or Scene, and they do not need to know
-- about the panel.
--
-- Session-only for now: there is no saving anywhere in the game yet. When
-- DataService arrives in P2 these values get persisted with everything else.

local Settings = {}

Settings.values = {
	musicVolume = 0.35,
	sfxVolume = 0.70,
	reactionBubbles = true,
	screenShake = true,
}

-- Fired with (key, value) whenever anything changes. Modules that need to act
-- on a change (Audio) subscribe; modules that only need the current value
-- (Scene, Customers) just read `Settings.values` when they use it.
Settings.changed = Instance.new("BindableEvent")

function Settings.set(key: string, value: any)
	if Settings.values[key] == value then
		return
	end
	Settings.values[key] = value
	Settings.changed:Fire(key, value)
end

function Settings.get(key: string): any
	return Settings.values[key]
end

-- Steps a 0..1 value and clamps it, for the panel's -/+ buttons.
function Settings.nudge(key: string, delta: number)
	local current = Settings.values[key]
	if typeof(current) ~= "number" then
		return
	end
	Settings.set(key, math.clamp(math.round((current + delta) * 100) / 100, 0, 1))
end

function Settings.toggle(key: string)
	Settings.set(key, not Settings.values[key])
end

return Settings
