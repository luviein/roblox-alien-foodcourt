--!strict
-- Builds the 3D stall as local-only geometry and locks the camera to it.
--
-- Everything here is created on the client, so none of it replicates and none
-- of it needs Rojo to manage Workspace -- you can keep using a plain Baseplate
-- place. The set is built 500 studs up so the baseplate and your character
-- never intrude on frame.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Scene = {}

local ORIGIN = Vector3.new(0, 500, 0)

-- Composition: camera sits behind the counter looking out over the plate at
-- the queue. Plate near, customers far, so both read at a glance.
-- The bottom ~35% of the screen is the key grid and action bar, so the scene
-- has to compose its content in the upper two thirds: customers around a third
-- of the way down, plate just above the keys. Pulled back and higher than the
-- first pass, which cropped the queue behind the counter.
local CAMERA_POSITION = ORIGIN + Vector3.new(0, 11.5, 15.5)
local CAMERA_FOCUS    = ORIGIN + Vector3.new(0, 3.0, -4.5)

local COUNTER_TOP = 3.0
local PLATE_CENTER = ORIGIN + Vector3.new(0, COUNTER_TOP + 0.18, 1.4)

local QUEUE_Z = -5.5
local QUEUE_X = { -6.3, -2.1, 2.1, 6.3 }
local SPAWN_X = 18   -- customers walk in from stage right

local PALETTE = {
	floor   = Color3.fromRGB(28, 30, 40),
	wall    = Color3.fromRGB(20, 21, 30),
	counter = Color3.fromRGB(52, 56, 72),
	trim    = Color3.fromRGB(88, 198, 255),
	plate   = Color3.fromRGB(228, 232, 240),
	neonA   = Color3.fromRGB(255, 96, 180),
	neonB   = Color3.fromRGB(96, 230, 255),
}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- ---------------------------------------------------------------- build ----

function Scene.build()
	local existing = workspace:FindFirstChild("AFC_Scene")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Model")
	folder.Name = "AFC_Scene"
	folder.Parent = workspace

	-- Floor and back wall.
	part({
		Name = "Floor",
		Size = Vector3.new(70, 1, 60),
		Position = ORIGIN + Vector3.new(0, -0.5, -10),
		Color = PALETTE.floor,
	}, folder)

	part({
		Name = "BackWall",
		Size = Vector3.new(70, 26, 1),
		Position = ORIGIN + Vector3.new(0, 13, -22),
		Color = PALETTE.wall,
	}, folder)

	-- Neon signage: cheap, and it sells "alien food court" instantly.
	part({
		Name = "NeonA",
		Size = Vector3.new(34, 0.22, 0.22),
		Position = ORIGIN + Vector3.new(0, 11.5, -21.4),
		Color = PALETTE.neonA,
		Material = Enum.Material.Neon,
	}, folder)

	part({
		Name = "NeonB",
		Size = Vector3.new(22, 0.16, 0.16),
		Position = ORIGIN + Vector3.new(0, 13.2, -21.4),
		Color = PALETTE.neonB,
		Material = Enum.Material.Neon,
	}, folder)

	-- The counter the player works behind.
	part({
		Name = "Counter",
		Size = Vector3.new(20, COUNTER_TOP, 5),
		Position = ORIGIN + Vector3.new(0, COUNTER_TOP / 2, 0.5),
		Color = PALETTE.counter,
	}, folder)

	-- A trim strip along the FRONT edge only. Covering the whole countertop in
	-- neon (the first pass) blew out the bottom third of the frame.
	part({
		Name = "CounterTrim",
		Size = Vector3.new(20.3, 0.12, 0.3),
		Position = ORIGIN + Vector3.new(0, COUNTER_TOP + 0.02, 3.0),
		Color = PALETTE.trim,
		Material = Enum.Material.Neon,
	}, folder)

	-- The plate the order is built on.
	local plate = part({
		Name = "Plate",
		Size = Vector3.new(3.6, 0.16, 3.6),
		Position = PLATE_CENTER,
		Color = PALETTE.plate,
	}, folder)
	local plateMesh = Instance.new("CylinderMesh")
	plateMesh.Parent = plate

	local plateLight = Instance.new("PointLight")
	plateLight.Brightness = 0.9
	plateLight.Range = 11
	plateLight.Color = Color3.fromRGB(255, 240, 214)
	plateLight.Parent = plate

	-- Fill light on the queue so the aliens are readable.
	local queueLamp = part({
		Name = "QueueLamp",
		Size = Vector3.new(18, 0.2, 0.2),
		Position = ORIGIN + Vector3.new(0, 11, QUEUE_Z),
		Transparency = 1,
	}, folder)
	local queueLight = Instance.new("PointLight")
	queueLight.Brightness = 1.4
	queueLight.Range = 34
	queueLight.Color = Color3.fromRGB(210, 226, 255)
	queueLight.Parent = queueLamp

	-- Queue positions, all facing the counter.
	local slots = {}
	for index, x in QUEUE_X do
		local position = ORIGIN + Vector3.new(x, 0, QUEUE_Z)
		slots[index] = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
	end

	local spawnPosition = ORIGIN + Vector3.new(SPAWN_X, 0, QUEUE_Z)
	local exitPosition = ORIGIN + Vector3.new(-SPAWN_X, 0, QUEUE_Z)

	return {
		folder = folder,
		plateTop = PLATE_CENTER + Vector3.new(0, 0.08, 0),
		slots = slots,
		spawnCFrame = CFrame.lookAt(spawnPosition, spawnPosition + Vector3.new(0, 0, 1)),
		exitCFrame = CFrame.lookAt(exitPosition, exitPosition + Vector3.new(0, 0, 1)),
	}
end

-- --------------------------------------------------------------- camera ----

local shakeAmount = 0
local shakeDecay = 1

-- A short kick on the camera. Used sparingly: Perfect serves and fumbles only.
-- Failure gets a dull thud and no shake -- never reward a mistake with spectacle.
function Scene.shake(amount: number, duration: number?)
	shakeAmount = math.max(shakeAmount, amount)
	shakeDecay = 1 / math.max(duration or 0.25, 0.05)
end

function Scene.lockCamera()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 55

	local locked = CFrame.lookAt(CAMERA_POSITION, CAMERA_FOCUS)
	camera.CFrame = locked

	-- Re-assert every frame: respawning otherwise hands the camera back to
	-- the default controller.
	RunService:BindToRenderStep("AFC_Camera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end

		cam.CameraType = Enum.CameraType.Scriptable

		if shakeAmount > 0.0001 then
			shakeAmount = math.max(0, shakeAmount - shakeDecay * shakeAmount * dt * 6)
			local offset = Vector3.new(
				(math.random() - 0.5) * shakeAmount,
				(math.random() - 0.5) * shakeAmount,
				0
			)
			cam.CFrame = locked * CFrame.new(offset)
		else
			shakeAmount = 0
			cam.CFrame = locked
		end
	end)
end

-- Park the character out of the way so it cannot wander off the baseplate and
-- trigger respawns behind our fixed camera.
function Scene.parkCharacter()
	local player = Players.LocalPlayer

	local function park(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if root then
			root.Anchored = true
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		end
	end

	if player.Character then
		park(player.Character)
	end
	player.CharacterAdded:Connect(park)
end

function Scene.applyLighting()
	Lighting.Ambient = Color3.fromRGB(48, 50, 66)
	Lighting.OutdoorAmbient = Color3.fromRGB(38, 40, 56)
	Lighting.Brightness = 1.2
	Lighting.ClockTime = 21
	Lighting.FogEnd = 220
	Lighting.FogColor = Color3.fromRGB(18, 19, 28)
end

Scene.ORIGIN = ORIGIN
Scene.COUNTER_TOP = COUNTER_TOP

return Scene
