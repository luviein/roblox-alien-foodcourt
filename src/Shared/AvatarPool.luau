--!strict
-- The catalog assets customers are built from.
--
-- ============================ FILL THESE IN =============================
-- Every list below is empty on purpose. Asset IDs cannot be guessed -- a wrong
-- number either fails to load or loads something unrelated -- so they have to
-- come from you.
--
-- To get an ID: open the item on roblox.com/catalog and take the number out of
-- the URL. https://www.roblox.com/catalog/607702162/Pal-Hair  ->  607702162
--
-- Leave a list empty and that slot is simply skipped. An entirely empty file
-- still produces working customers, just plain-bodied ones -- nothing breaks.
--
-- Curate rather than grabbing at random: a hand-picked pool of 8-10 per slot
-- looks like a coherent cast, and avoids pulling in UGC you have not seen.
-- =======================================================================

local AvatarPool = {}

-- How many distinct rigs to pre-build at server start. Four are on screen at
-- once, so ten is plenty of variety.
AvatarPool.POOL_SIZE = 10

-- Play opens once this many exist. The rest keep building in the background
-- and land during the first minute of the shift, which nobody notices --
-- waiting for the full pool was most of the loading screen.
AvatarPool.MIN_READY = 4

-- Classic clothing (Shirt / Pants asset IDs -- NOT "Classic T-Shirt").
AvatarPool.Shirts = {}
AvatarPool.Pants = {}

-- Face decal asset IDs -- the neutral face customers wear while queueing.
AvatarPool.Faces = {}

-- Reaction faces. The customer's actual face is swapped to one of these when
-- their order lands or they walk out, so the emotion reads on the character
-- rather than only in a bubble above them.
--
-- Leave these empty and they are auto-filled from the catalog ("smile" and
-- "angry" face searches). Fill them to pick exactly which faces you want.
AvatarPool.HappyFaces = {}
AvatarPool.AngryFaces = {}

-- Accessory asset IDs.
AvatarPool.Hair = {13823150138,126263758311070,82005629783010,124004421267994,116805164568378}
AvatarPool.Hats = {79444031174743,13590822591}
AvatarPool.FaceAccessories = {}   -- glasses, masks, antennae if you find any

-- ---------------------------------------------------------------- bodies ---

-- Body colours need no assets at all, so this is where the variety comes from
-- until the lists above are filled.
--
-- These are deliberately alien rather than human: this is a food court on an
-- alien station, and a queue of ordinary Roblox avatars would read as a
-- different game. Flip ALIEN_SKIN to false for standard skin tones.
AvatarPool.ALIEN_SKIN = true

AvatarPool.AlienTones = {
	Color3.fromRGB(120, 210, 190),
	Color3.fromRGB(180, 140, 235),
	Color3.fromRGB(150, 220, 120),
	Color3.fromRGB(240, 150, 130),
	Color3.fromRGB(240, 200, 110),
	Color3.fromRGB(130, 180, 245),
	Color3.fromRGB(225, 130, 195),
	Color3.fromRGB(160, 235, 225),
	Color3.fromRGB(200, 235, 140),
	Color3.fromRGB(140, 150, 230),
}

AvatarPool.HumanTones = {
	Color3.fromRGB(234, 195, 158),
	Color3.fromRGB(205, 154, 120),
	Color3.fromRGB(160, 110, 80),
	Color3.fromRGB(112, 72, 48),
	Color3.fromRGB(246, 220, 190),
	Color3.fromRGB(80, 52, 36),
}

-- Body proportions. Wide ranges here do a lot of work: a queue of differently
-- shaped silhouettes reads as a crowd even before any clothing exists.
AvatarPool.Scale = {
	height     = { 0.82, 1.20 },
	width      = { 0.80, 1.25 },
	head       = { 0.85, 1.45 },
	depth      = { 0.90, 1.15 },
	proportion = { 0.00, 1.00 },
	bodyType   = { 0.00, 0.85 },
}

function AvatarPool.tones()
	return if AvatarPool.ALIEN_SKIN then AvatarPool.AlienTones else AvatarPool.HumanTones
end

-- Returns a random entry, or nil when the list has not been filled in yet.
function AvatarPool.pick<T>(list: { T }, rng: Random): T?
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

return AvatarPool
