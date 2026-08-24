--!strict
-- Pre-builds a pool of R15 customer rigs at server start and parks them in
-- ReplicatedStorage for clients to clone.
--
-- Why the server, and why a pool:
--   * CreateHumanoidModelFromDescription makes web requests to load clothing,
--     hair and faces. Doing that once at startup is reliable; doing it per
--     customer mid-rush would stall the queue.
--   * Clients clone from the pool instantly, so a customer can walk in the
--     same frame their ticket appears.
--
-- If asset pools in AvatarPool are empty (or the web calls fail), the rigs are
-- still built -- just plain-bodied. The client falls back to the procedural
-- alien if the pool ends up empty entirely, so this can never hard-fail.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarPool = require(Shared.AvatarPool)

local CustomerRigs = {}

local FOLDER_NAME = "CustomerRigs"

local function randomIn(rng: Random, range: { number }): number
	return rng:NextNumber(range[1], range[2])
end

-- HumanoidDescription accessory fields take a comma-separated string of ids.
local function accessoryString(id: number?): string
	return if id then tostring(id) else ""
end

local function buildDescription(rng: Random): HumanoidDescription
	local description = Instance.new("HumanoidDescription")

	local shirt = AvatarPool.pick(AvatarPool.Shirts, rng)
	local pants = AvatarPool.pick(AvatarPool.Pants, rng)
	local face = AvatarPool.pick(AvatarPool.Faces, rng)

	if shirt then
		description.Shirt = shirt
	end
	if pants then
		description.Pants = pants
	end
	if face then
		description.Face = face
	end

	description.HairAccessory = accessoryString(AvatarPool.pick(AvatarPool.Hair, rng))
	description.HatAccessory = accessoryString(AvatarPool.pick(AvatarPool.Hats, rng))
	description.FaceAccessory = accessoryString(AvatarPool.pick(AvatarPool.FaceAccessories, rng))

	-- Body colour needs no assets, so this carries the variety on its own.
	local tones = AvatarPool.tones()
	local tone = tones[rng:NextInteger(1, #tones)]
	local limbTone = tone:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.15))

	description.HeadColor = tone
	description.TorsoColor = limbTone
	description.LeftArmColor = tone
	description.RightArmColor = tone
	description.LeftLegColor = limbTone
	description.RightLegColor = limbTone

	local scale = AvatarPool.Scale
	description.HeightScale = randomIn(rng, scale.height)
	description.WidthScale = randomIn(rng, scale.width)
	description.HeadScale = randomIn(rng, scale.head)
	description.DepthScale = randomIn(rng, scale.depth)
	description.ProportionScale = randomIn(rng, scale.proportion)
	description.BodyTypeScale = randomIn(rng, scale.bodyType)

	return description
end

-- Makes a freshly created rig safe to clone around: nothing collides, nothing
-- is queryable, no name/health bars, and the root is anchored so the client can
-- drive it with PivotTo while animations play on the joints.
local function prepareRig(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayDistance = 0
		humanoid.BreakJointsOnDeath = false
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.Anchored = descendant.Name == "HumanoidRootPart"
		end
	end
end

function CustomerRigs.build()
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage

	-- Yields on web calls, so never block server startup on it.
	task.spawn(function()
		local rng = Random.new()
		local built = 0

		for index = 1, AvatarPool.POOL_SIZE do
			local description = buildDescription(rng)

			local ok, result = pcall(function()
				return Players:CreateHumanoidModelFromDescription(
					description,
					Enum.HumanoidRigType.R15
				)
			end)

			if ok and result then
				local model = result :: Model
				model.Name = "Customer" .. index
				prepareRig(model)
				model.Parent = folder
				built += 1
			else
				warn(("[AlienFoodCourt] rig %d failed to build: %s"):format(index, tostring(result)))
			end
		end

		if built == 0 then
			warn("[AlienFoodCourt] no customer rigs built -- client will fall back to procedural aliens")
		else
			print(("[AlienFoodCourt] built %d/%d customer rigs"):format(built, AvatarPool.POOL_SIZE))
		end
	end)
end

return CustomerRigs
