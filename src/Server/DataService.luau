--!strict
-- Player profiles: load on join, autosave, flush on shutdown.
--
-- Deliberately small. ProfileService and friends exist mainly to solve session
-- locking across servers, which matters when duping is the threat -- trading
-- games, tradeable inventories. This is one profile per player with no
-- transfers, so retry-on-failure plus autosave covers what actually goes wrong
-- here, and it is a dependency we can read in full.
--
-- The one rule that matters: a profile that FAILED to load is never saved.
-- Writing defaults over a good save because a GetAsync timed out is the worst
-- thing this file could do, and it is the easy mistake to make.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataService = {}

local STORE_NAME = "AFC_Profiles_v1"
local AUTOSAVE_INTERVAL = 120
local MAX_ATTEMPTS = 4

local store: DataStore? = nil

-- Everything a profile holds. Missing keys are filled from here on load, so
-- adding a field does not need a migration -- old saves simply gain it.
local DEFAULT = {
	version = 1,

	cash = 0,
	debtPaid = 0,

	-- Dish ids the player can be given orders for. Everything else is locked.
	unlocked = {
		burger = true,
	},

	-- One shift is one day. Drives the repeat penalty and, later, dailies.
	day = 1,

	-- Dish ids that were on yesterday's menu. Serving one again today costs
	-- hype; resting it a single day clears it, because this is simply
	-- overwritten by whatever menu is run next.
	lastMenu = {},

	-- How many dishes can go on the board at once.
	menuSlots = 3,

	-- Upgrade id -> levels owned.
	upgrades = {
		slots = 0,
		tips = 0,
		shift = 0,
	},

	rebirths = 0,

	stats = {
		shifts = 0,
		served = 0,
		bestScore = 0,
		bestCombo = 0,
	},

	settings = {
		musicVolume = 0.20,
		sfxVolume = 0.70,
		reactionBubbles = true,
		screenShake = true,
	},
}

type Profile = {
	data: any,
	canSave: boolean,   -- false when the load failed; see the note above
	dirty: boolean,
}

local profiles: { [Player]: Profile } = {}

-- ---------------------------------------------------------------- helpers --

local function deepCopy(value)
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Fills anything the save is missing from DEFAULT, recursively. Lets the
-- schema grow without a migration step for every added field.
local function reconcile(saved, template)
	if typeof(saved) ~= "table" then
		return deepCopy(template)
	end
	for key, value in template do
		if saved[key] == nil then
			saved[key] = deepCopy(value)
		elseif typeof(value) == "table" then
			saved[key] = reconcile(saved[key], value)
		end
	end
	return saved
end

local function keyFor(player: Player): string
	return "p_" .. tostring(player.UserId)
end

-- Retries with backoff. DataStore failures are usually transient.
local function attempt(label: string, fn)
	local ok, result
	for tries = 1, MAX_ATTEMPTS do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(0.5 * 2 ^ (tries - 1))
	end
	warn(("[DataService] %s failed after %d attempts: %s")
		:format(label, MAX_ATTEMPTS, tostring(result)))
	return false, result
end

-- ------------------------------------------------------------------ load --

local function loadProfile(player: Player): Profile
	if not store then
		-- No DataStore access at all: play with defaults, save nothing.
		return { data = deepCopy(DEFAULT), canSave = false, dirty = false }
	end

	local ok, saved = attempt("load " .. player.Name, function()
		return (store :: DataStore):GetAsync(keyFor(player))
	end)

	if not ok then
		warn(("[DataService] %s is playing on a temporary profile -- progress "
			.. "will NOT be saved this session, to avoid overwriting their real one.")
			:format(player.Name))
		return { data = deepCopy(DEFAULT), canSave = false, dirty = false }
	end

	-- nil simply means a new player.
	local data = reconcile(saved or {}, DEFAULT)
	return { data = data, canSave = true, dirty = false }
end

-- ------------------------------------------------------------------ save --

function DataService.save(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.canSave or not store then
		return false
	end

	local ok = attempt("save " .. player.Name, function()
		-- UpdateAsync rather than SetAsync: if the same profile were written
		-- from elsewhere, this merges against what is actually there instead
		-- of blindly replacing it.
		(store :: DataStore):UpdateAsync(keyFor(player), function()
			return profile.data
		end)
	end)

	if ok then
		profile.dirty = false
	end
	return ok
end

-- ----------------------------------------------------------------- public --

function DataService.get(player: Player)
	local profile = profiles[player]
	return profile and profile.data or nil
end

-- Mutates the profile and marks it for the next autosave. Everything that
-- changes a profile should go through here so nothing is silently lost.
function DataService.update(player: Player, mutator: (any) -> ())
	local profile = profiles[player]
	if not profile then
		return
	end
	mutator(profile.data)
	profile.dirty = true
end

function DataService.isTemporary(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and not profile.canSave
end

-- ------------------------------------------------------------------ init --

function DataService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)

	if ok then
		store = result
	else
		warn("[DataService] no DataStore access. In Studio this means "
			.. "Game Settings > Security > Enable Studio Access to API Services "
			.. "is off, or the place is not published. Progress will not save.")
	end

	local function onPlayerAdded(player: Player)
		profiles[player] = loadProfile(player)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		profiles[player] = nil
	end)

	-- Autosave only what has actually changed.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				if profile.dirty then
					DataService.save(player)
				end
			end
		end
	end)

	-- Last chance on shutdown. Studio gives roughly 30s; a live server less,
	-- so save in parallel rather than one player after another.
	game:BindToClose(function()
		if RunService:IsStudio() then
			-- Studio shutdown races the DataStore; a brief wait is enough for
			-- the saves below to actually go out.
			task.wait(1)
		end

		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(player)
				pending -= 1
			end)
		end

		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

DataService.DEFAULT = DEFAULT

return DataService
