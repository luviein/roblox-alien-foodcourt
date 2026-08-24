--!strict
-- Builds the order in 3D on the plate, one layer at a time.
--
-- Each ingredient drops in from above and squashes on landing -- that impact
-- is most of what makes a keypress feel like it did something. Shapes come
-- from the `visual` descriptor in DishDefs, so swapping any layer for a
-- MeshPart later means changing one branch in `createLayer`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DishDefs = require(Shared.DishDefs)

local FoodStack = {}

local DROP_HEIGHT = 5
local DROP_TIME = 0.14
local SQUASH_TIME = 0.07

local scene: any = nil
local layers: { any } = {}
local stackHeight = 0
local rng = Random.new()

-- ---------------------------------------------------------------- shapes ---

local function createLayer(ingredientId: string, targetPosition: Vector3): Part?
	local ingredient = DishDefs.ingredient(ingredientId)
	if not ingredient or not ingredient.visual then
		return nil
	end

	local visual = ingredient.visual

	local layer = Instance.new("Part")
	layer.Name = ingredientId
	layer.Anchored = true
	layer.CanCollide = false
	layer.CanQuery = false
	layer.CanTouch = false
	layer.Material = Enum.Material.SmoothPlastic
	layer.Color = ingredient.color
	layer.Size = visual.size

	if visual.shape == "cylinder" then
		Instance.new("CylinderMesh").Parent = layer
	elseif visual.shape == "dome" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = layer
	elseif visual.shape == "rod" then
		Instance.new("CylinderMesh").Parent = layer
	end

	-- A little randomised tilt and spin so a stack never looks machine-made.
	local tilt = math.rad(visual.tilt or 0)
	local orientation = CFrame.Angles(
		rng:NextNumber(-tilt, tilt),
		rng:NextNumber(-math.pi, math.pi),
		rng:NextNumber(-tilt, tilt)
	)

	-- Rods lie on their side.
	if visual.shape == "rod" then
		orientation = CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), math.rad(90))
	end

	layer.CFrame = CFrame.new(targetPosition + Vector3.new(0, DROP_HEIGHT, 0)) * orientation
	layer.Parent = scene.folder

	return layer
end

local function animateDrop(layer: Part, targetPosition: Vector3, fullSize: Vector3)
	local orientation = layer.CFrame - layer.CFrame.Position

	local drop = TweenService:Create(
		layer,
		TweenInfo.new(DROP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(targetPosition) * orientation }
	)

	drop.Completed:Connect(function()
		if not layer.Parent then
			return
		end
		-- Squash on impact, then spring back. This is the whole trick.
		local squashed = Vector3.new(fullSize.X * 1.14, fullSize.Y * 0.6, fullSize.Z * 1.14)
		local squash = TweenService:Create(
			layer,
			TweenInfo.new(SQUASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = squashed }
		)
		squash.Completed:Connect(function()
			if not layer.Parent then
				return
			end
			TweenService:Create(
				layer,
				TweenInfo.new(SQUASH_TIME * 1.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = fullSize }
			):Play()
		end)
		squash:Play()
	end)

	drop:Play()
end

-- --------------------------------------------------------------- public ----

function FoodStack.init(sceneRefs)
	scene = sceneRefs
	layers = {}
	stackHeight = 0
end

function FoodStack.clear()
	for _, entry in layers do
		entry.part:Destroy()
	end
	layers = {}
	stackHeight = 0
end

local function addLayer(ingredientId: string, animate: boolean)
	local ingredient = DishDefs.ingredient(ingredientId)
	if not ingredient or not ingredient.visual then
		return
	end

	local rise = ingredient.visual.rise
	local targetPosition = scene.plateTop + Vector3.new(0, stackHeight + rise / 2, 0)

	local layer = createLayer(ingredientId, targetPosition)
	if not layer then
		return
	end

	local fullSize = layer.Size

	if animate then
		animateDrop(layer, targetPosition, fullSize)
	else
		local orientation = layer.CFrame - layer.CFrame.Position
		layer.CFrame = CFrame.new(targetPosition) * orientation
	end

	table.insert(layers, { part = layer, ingredientId = ingredientId })
	stackHeight += rise
end

-- Reconciles the visual stack against the server's build list. Growth is
-- animated; anything else (scrap, ticket switch, serve) rebuilds instantly.
function FoodStack.sync(build: { string })
	if not scene then
		return
	end

	local matches = #build >= #layers
	if matches then
		for index, entry in layers do
			if build[index] ~= entry.ingredientId then
				matches = false
				break
			end
		end
	end

	if not matches then
		FoodStack.clear()
		for _, ingredientId in build do
			addLayer(ingredientId, false)
		end
		return
	end

	for index = #layers + 1, #build do
		addLayer(build[index], true)
	end
end

-- Sends the finished plate off toward the customer.
function FoodStack.serve()
	local flung = layers
	layers = {}
	stackHeight = 0

	for index, entry in flung do
		local layer = entry.part
		local goal = layer.CFrame
			* CFrame.new(0, 1.5 + index * 0.2, -6)
			* CFrame.Angles(math.rad(40), 0, 0)

		TweenService:Create(
			layer,
			TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = goal, Transparency = 1 }
		):Play()

		Debris:AddItem(layer, 0.5)
	end
end

-- A wrong order gets swept off the counter instead.
function FoodStack.dump()
	local dumped = layers
	layers = {}
	stackHeight = 0

	for _, entry in dumped do
		local layer = entry.part
		local goal = layer.CFrame * CFrame.new(2.5, -6, 2) * CFrame.Angles(0, 0, math.rad(70))

		TweenService:Create(
			layer,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = goal, Transparency = 1 }
		):Play()

		Debris:AddItem(layer, 0.6)
	end
end

return FoodStack
