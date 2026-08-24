--!strict
-- The fallback customer: a blocky alien built from primitives, jointed with
-- real Motor6Ds so it walks with the same code that drives the R15 rigs.
--
-- This used to be a limbless blob, which meant that whenever the server's
-- avatar pool failed to build -- a web call refused, Studio offline, the
-- catalog unavailable -- every customer silently lost their arms, legs and
-- face at once. The failure looked like an animation bug rather than a
-- missing-assets one.
--
-- Now the fallback is a proper character: torso, head, two arms, two legs,
-- joints named exactly as R15 names them, so NpcAnimator poses it without
-- knowing which kind of body it has, and Face draws on its head the same way.
--
-- Nothing here touches the network, so it cannot fail.

local Alien = {}

local BODY_COLORS = {
	Color3.fromRGB(120, 210, 190),
	Color3.fromRGB(180, 140, 235),
	Color3.fromRGB(150, 220, 120),
	Color3.fromRGB(240, 150, 130),
	Color3.fromRGB(240, 200, 110),
	Color3.fromRGB(130, 180, 245),
	Color3.fromRGB(225, 130, 195),
	Color3.fromRGB(160, 235, 225),
}

local ANTENNA_COLORS = {
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(120, 245, 255),
	Color3.fromRGB(255, 225, 120),
	Color3.fromRGB(180, 255, 160),
}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = false      -- limbs must be free for Motor6D to pose them
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = part1
	return motor
end

-- Builds one alien at the origin, standing on y = 0. The caller pivots it.
function Alien.build(seed: number)
	local rng = Random.new(seed)

	local color = BODY_COLORS[rng:NextInteger(1, #BODY_COLORS)]
	local limbColor = color:Lerp(Color3.new(0, 0, 0), 0.22)

	local legLength = rng:NextNumber(1.9, 2.6)
	local torsoHeight = rng:NextNumber(1.7, 2.3)
	local torsoWidth = rng:NextNumber(1.7, 2.4)
	local armLength = rng:NextNumber(1.7, 2.2)
	local headSize = rng:NextNumber(1.2, 1.7)
	local antennaCount = rng:NextInteger(0, 2)

	local torsoY = legLength + torsoHeight / 2
	local armWidth = 0.7

	local model = Instance.new("Model")
	model.Name = "AlienCustomer"

	-- Anchored root. Everything else hangs off it through joints, exactly as
	-- a real character does.
	local root = part({
		Name = "HumanoidRootPart",
		Size = Vector3.new(torsoWidth * 0.6, 1, 1),
		CFrame = CFrame.new(0, 0, 0),
		Transparency = 1,
		Anchored = true,
	}, model)
	model.PrimaryPart = root

	local torso = part({
		Name = "Torso",
		Size = Vector3.new(torsoWidth, torsoHeight, torsoWidth * 0.55),
		Color = color,
	}, model)
	joint("Root", root, torso, CFrame.new(0, torsoY, 0), CFrame.new())

	local head = part({
		Name = "Head",
		Size = Vector3.new(headSize, headSize, headSize),
		Color = color,
	}, model)
	joint("Neck", torso, head, CFrame.new(0, torsoHeight / 2 + headSize / 2, 0), CFrame.new())

	-- Arms. C0 sits at the shoulder and C1 at the top of the limb, so rotating
	-- C0 swings the arm about the shoulder rather than about its own centre.
	local shoulderX = torsoWidth / 2 + armWidth / 2
	local shoulderY = torsoHeight / 2 - 0.2

	local leftArm = part({
		Name = "LeftUpperArm",
		Size = Vector3.new(armWidth, armLength, armWidth),
		Color = limbColor,
	}, model)
	joint("LeftShoulder", torso, leftArm,
		CFrame.new(-shoulderX, shoulderY, 0), CFrame.new(0, armLength / 2, 0))

	local rightArm = part({
		Name = "RightUpperArm",
		Size = Vector3.new(armWidth, armLength, armWidth),
		Color = limbColor,
	}, model)
	joint("RightShoulder", torso, rightArm,
		CFrame.new(shoulderX, shoulderY, 0), CFrame.new(0, armLength / 2, 0))

	-- Legs.
	local hipX = torsoWidth * 0.24
	local legWidth = 0.8

	local leftLeg = part({
		Name = "LeftUpperLeg",
		Size = Vector3.new(legWidth, legLength, legWidth),
		Color = limbColor,
	}, model)
	joint("LeftHip", torso, leftLeg,
		CFrame.new(-hipX, -torsoHeight / 2, 0), CFrame.new(0, legLength / 2, 0))

	local rightLeg = part({
		Name = "RightUpperLeg",
		Size = Vector3.new(legWidth, legLength, legWidth),
		Color = limbColor,
	}, model)
	joint("RightHip", torso, rightLeg,
		CFrame.new(hipX, -torsoHeight / 2, 0), CFrame.new(0, legLength / 2, 0))

	-- Antennae, purely for silhouette variety.
	for index = 1, antennaCount do
		local lean = if antennaCount == 1 then 0 else (if index == 1 then -1 else 1)
		local stalkHeight = rng:NextNumber(0.6, 1.2)

		local stalk = part({
			Name = "Antenna" .. index,
			Size = Vector3.new(0.12, stalkHeight, 0.12),
			Color = limbColor,
		}, model)
		joint("AntennaJoint" .. index, head, stalk,
			CFrame.new(lean * headSize * 0.25, headSize / 2 + stalkHeight / 2, 0)
				* CFrame.Angles(0, 0, math.rad(-lean * 14)),
			CFrame.new())

		local tip = part({
			Name = "AntennaTip" .. index,
			Size = Vector3.new(0.3, 0.3, 0.3),
			Color = ANTENNA_COLORS[rng:NextInteger(1, #ANTENNA_COLORS)],
			Material = Enum.Material.Neon,
		}, model)
		local tipMesh = Instance.new("SpecialMesh")
		tipMesh.MeshType = Enum.MeshType.Sphere
		tipMesh.Parent = tip
		joint("AntennaTipJoint" .. index, stalk, tip,
			CFrame.new(0, stalkHeight / 2, 0), CFrame.new())
	end

	return {
		model = model,
		root = root,
		head = head,
		-- Feet sit on y = 0 and the root is at the feet, so the caller pivots
		-- straight to the floor position with no offset.
		yOffset = 0,
		height = legLength + torsoHeight + headSize,
	}
end

return Alien
