--!strict
-- Player-facing settings, held in one place so the settings panel does not
-- need to know about Audio, Customers or Scene, and they do not need to know
-- about the panel.
--
-- Persisted through the profile: `apply` takes what the server loaded, and
-- `onChanged` sends edits back.

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

-- Set by the client once, so a change can be pushed to the server to persist.
-- Settings lives below Audio and the panel in the dependency order, so it
-- cannot reach the network itself.
Settings.onChanged = nil :: any

function Settings.set(key: string, value: any)
	if Settings.values[key] == value then
		return
	end
	Settings.values[key] = value
	Settings.changed:Fire(key, value)
	if Settings.onChanged then
		Settings.onChanged(key, value)
	end
end

-- Applied from a loaded profile. Fires nothing back at the server: this IS the
-- server's value, and echoing it would be a pointless round trip.
function Settings.apply(values)
	if typeof(values) ~= "table" then
		return
	end
	for key, value in values do
		if Settings.values[key] ~= nil and Settings.values[key] ~= value then
			Settings.values[key] = value
			Settings.changed:Fire(key, value)
		end
	end
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
