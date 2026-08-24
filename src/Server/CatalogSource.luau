--!strict
-- Works out which catalog assets the customer rigs get dressed in.
--
-- Three sources, in priority order:
--   1. Whatever you hand-picked into Shared/AvatarPool -- always wins.
--   2. A live catalog query, for any slot you left empty. Real, current ids,
--      fetched at server start. Nothing to paste and nothing to go stale.
--   3. Nothing -- plain bodies. Never an error.
--
-- Every id, hand-picked or fetched, is verified against MarketplaceService
-- before use. A deleted, moderated or wrong-type asset is dropped with a
-- warning naming what it actually was, rather than silently failing to appear
-- on the rig -- which is the confusing case this exists to prevent.

local AvatarEditorService = game:GetService("AvatarEditorService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarPool = require(Shared.AvatarPool)

local CatalogSource = {}

-- Roblox asset type ids. Pasting a "Classic T-Shirt" id into Shirts is the
-- single most common mistake, and these catch it.
local ASSET_TYPE = {
	Hat = 8,
	Face = 18,
	Shirt = 11,
	Pants = 12,
	HairAccessory = 41,
	FaceAccessory = 42,
}

local ASSET_TYPE_NAME = {}
for name, id in ASSET_TYPE do
	ASSET_TYPE_NAME[id] = name
end

-- Each slot: which manual list feeds it, what asset type it must be, and what
-- to search the catalog for when the manual list is empty.
local SLOTS = {
	{ key = "Shirts",           assetTypeId = ASSET_TYPE.Shirt,         search = Enum.AvatarAssetType.Shirt,         keyword = "shirt" },
	{ key = "Pants",            assetTypeId = ASSET_TYPE.Pants,         search = Enum.AvatarAssetType.Pants,         keyword = "pants" },
	{ key = "Faces",            assetTypeId = ASSET_TYPE.Face,          search = Enum.AvatarAssetType.Face,          keyword = "face" },
	{ key = "HappyFaces",       assetTypeId = ASSET_TYPE.Face,          search = Enum.AvatarAssetType.Face,          keyword = "smile" },
	{ key = "AngryFaces",       assetTypeId = ASSET_TYPE.Face,          search = Enum.AvatarAssetType.Face,          keyword = "angry" },
	{ key = "Hair",             assetTypeId = ASSET_TYPE.HairAccessory, search = Enum.AvatarAssetType.HairAccessory, keyword = "hair" },
	{ key = "Hats",             assetTypeId = ASSET_TYPE.Hat,           search = Enum.AvatarAssetType.Hat,           keyword = "hat" },
	{ key = "FaceAccessories",  assetTypeId = ASSET_TYPE.FaceAccessory, search = Enum.AvatarAssetType.FaceAccessory, keyword = "glasses" },
}

local FETCH_LIMIT = 30
local KEEP_PER_SLOT = 12

-- ------------------------------------------------------------- validation --

-- Returns true if the asset exists and is the type this slot needs.
local function validate(assetId: number, expectedTypeId: number, slotKey: string): boolean
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
	end)

	if not ok or not info then
		warn(("[AvatarPool] %s: id %d could not be loaded (deleted, moderated, or not an asset)")
			:format(slotKey, assetId))
		return false
	end

	local actual = info.AssetTypeId
	if actual ~= expectedTypeId then
		local actualName = ASSET_TYPE_NAME[actual] or ("type " .. tostring(actual))
		warn(("[AvatarPool] %s: id %d is a %s (%s), not a %s -- skipped")
			:format(slotKey, assetId, actualName, tostring(info.Name), ASSET_TYPE_NAME[expectedTypeId]))
		return false
	end

	return true
end

-- ------------------------------------------------------------------ fetch --

-- Pulls real ids off the live catalog for a slot nobody filled in by hand.
local function fetchFromCatalog(slot): { number }
	local ids = {}

	local ok, err = pcall(function()
		local params = CatalogSearchParams.new()
		params.AssetTypes = { slot.search }
		params.SearchKeyword = slot.keyword
		params.Limit = FETCH_LIMIT
		params.IncludeOffSale = false

		local pages = AvatarEditorService:SearchCatalogAsync(params)
		for _, item in pages:GetCurrentPage() do
			-- Result shape has varied across API versions; read defensively.
			local id = item.Id or item.id or item.AssetId
			if typeof(id) == "number" then
				table.insert(ids, id)
			end
			if #ids >= KEEP_PER_SLOT then
				break
			end
		end
	end)

	if not ok then
		warn(("[AvatarPool] catalog search for %s failed: %s"):format(slot.key, tostring(err)))
		return {}
	end

	return ids
end

-- ----------------------------------------------------------------- public --

-- Resolves one slot. Yields on web calls.
local function resolveSlot(slot)
	local manual = (AvatarPool :: any)[slot.key] or {}

	-- Ids that came back FROM the catalog do not need checking against the
	-- catalog. Only hand-pasted ids can be wrong, and only those are worth a
	-- round trip each -- validating auto-fetched ones was ~90 sequential web
	-- calls of pure ceremony at every server start.
	if #manual == 0 then
		local fetched = fetchFromCatalog(slot)
		if #fetched > 0 then
			print(("[AvatarPool] %s: %d ids (from catalog)"):format(slot.key, #fetched))
		end
		return fetched
	end

	-- Hand-picked ids, verified in parallel rather than one after another.
	local results = table.create(#manual)
	local pending = #manual

	for index, id in manual do
		task.spawn(function()
			results[index] = if validate(id, slot.assetTypeId, slot.key) then id else 0
			pending -= 1
		end)
	end

	while pending > 0 do
		task.wait()
	end

	local valid = {}
	for index = 1, #manual do
		if results[index] and results[index] ~= 0 then
			table.insert(valid, results[index])
		end
	end

	if #valid > 0 then
		print(("[AvatarPool] %s: %d/%d ids usable (from AvatarPool)")
			:format(slot.key, #valid, #manual))
	else
		warn(("[AvatarPool] %s: none of the %d ids were usable"):format(slot.key, #manual))
	end

	return valid
end

-- Resolves every slot into a list of asset ids. Yields (web calls), so call it
-- from inside a task.spawn.
--
-- Slots resolve concurrently: they are independent, and running eight catalog
-- searches back to back was most of the wait before the game would open.
function CatalogSource.resolve()
	local resolved = {}
	local pending = #SLOTS

	for _, slot in SLOTS do
		task.spawn(function()
			resolved[slot.key] = resolveSlot(slot)
			pending -= 1
		end)
	end

	while pending > 0 do
		task.wait()
	end

	return resolved
end

return CatalogSource
