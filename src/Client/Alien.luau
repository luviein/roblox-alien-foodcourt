--!strict
-- Procedurally generated alien customers. No rigs, no meshes, no animations --
-- a body blob, some eyes, maybe antennae, all from primitives, seeded so every
-- customer is distinct but reproducible.
--
-- They face +Z, which is both the counter and the camera, so we always see the
-- face. "Walking" is done by the caller nudging the pivot; there is no
-- Humanoid and nothing to animate-import.

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

local function sphere(props: { [string]: any }, parent: Instance): Part
	local p = part(props, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function cylinder(props: { [string]: any }, parent: Instance): Part
	local p = part(props, parent)
	local mesh = Instance.new("CylinderMesh")
	mesh.Parent = p
	return p
end

-- Builds one alien at the world origin; the caller pivots it into place.
function Alien.build(seed: number)
	local rng = Random.new(seed)

	local bodyColor = BODY_COLORS[rng:NextInteger(1, #BODY_COLORS)]
	local bodyWidth = rng:NextNumber(1.9, 2.9)
	local bodyHeight = rng:NextNumber(2.2, 3.4)
	local legHeight = rng:NextNumber(0.8, 1.6)
	local eyeCount = rng:NextInteger(1, 3)
	local antennaCount = rng:NextInteger(0, 2)

	local model = Instance.new("Model")
	model.Name = "Alien"

	local root = part({
		Name = "Root",
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = CFrame.new(0, 0, 0),
		Transparency = 1,
	}, model)
	model.PrimaryPart = root

	-- Legs -------------------------------------------------------------------
	local legSpan = bodyWidth * 0.26
	for side = -1, 1, 2 do
		cylinder({
			Name = "Leg",
			Size = Vector3.new(0.42, legHeight, 0.42),
			CFrame = CFrame.new(side * legSpan, legHeight / 2, 0),
			Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.25),
		}, model)
	end

	-- Body -------------------------------------------------------------------
	local bodyY = legHeight + bodyHeight / 2
	local body = sphere({
		Name = "Body",
		Size = Vector3.new(bodyWidth, bodyHeight, bodyWidth * 0.85),
		CFrame = CFrame.new(0, bodyY, 0),
		Color = bodyColor,
	}, model)

	-- Eyes -------------------------------------------------------------------
	local eyes = {}
	local pupils = {}
	local eyeY = bodyY + bodyHeight * 0.18
	local eyeSize = if eyeCount == 1 then 0.85 elseif eyeCount == 2 then 0.62 else 0.5
	local spread = bodyWidth * 0.24

	for index = 1, eyeCount do
		local offset = if eyeCount == 1
			then 0
			else -spread + (index - 1) * (spread * 2 / (eyeCount - 1))

		local eye = sphere({
			Name = "Eye",
			Size = Vector3.new(eyeSize, eyeSize, eyeSize * 0.6),
			CFrame = CFrame.new(offset, eyeY, bodyWidth * 0.4),
			Color = Color3.fromRGB(250, 250, 252),
		}, model)

		local pupil = sphere({
			Name = "Pupil",
			Size = Vector3.new(eyeSize * 0.42, eyeSize * 0.42, eyeSize * 0.3),
			CFrame = CFrame.new(offset, eyeY, bodyWidth * 0.4 + eyeSize * 0.18),
			Color = Color3.fromRGB(18, 18, 26),
		}, model)

		table.insert(eyes, eye)
		table.insert(pupils, pupil)
	end

	-- Antennae ---------------------------------------------------------------
	local antennae = {}
	local topY = legHeight + bodyHeight
	for index = 1, antennaCount do
		local lean = if antennaCount == 1 then 0 else (index == 1 and -1 or 1)
		local stalkHeight = rng:NextNumber(0.7, 1.3)
		local tipColor = ANTENNA_COLORS[rng:NextInteger(1, #ANTENNA_COLORS)]

		local stalk = cylinder({
			Name = "Antenna",
			Size = Vector3.new(0.12, stalkHeight, 0.12),
			CFrame = CFrame.new(lean * bodyWidth * 0.2, topY + stalkHeight / 2 - 0.1, 0)
				* CFrame.Angles(0, 0, math.rad(-lean * 12)),
			Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.3),
		}, model)

		local tip = sphere({
			Name = "AntennaTip",
			Size = Vector3.new(0.3, 0.3, 0.3),
			CFrame = CFrame.new(lean * bodyWidth * 0.24, topY + stalkHeight, 0),
			Color = tipColor,
			Material = Enum.Material.Neon,
		}, model)

		table.insert(antennae, { stalk = stalk, tip = tip })
	end

	local totalHeight = topY + 0.6

	return {
		model = model,
		root = root,
		body = body,
		eyes = eyes,
		pupils = pupils,
		antennae = antennae,
		height = totalHeight,
		baseColor = bodyColor,
		eyeSize = eyeSize,
		eyeY = eyeY,
	}
end

-- Patience made visible: relaxed -> twitchy -> furious. `calm` runs 1 down to 0.
function Alien.setMood(alien, calm: number)
	calm = math.clamp(calm, 0, 1)

	-- Colour drifts toward angry red as patience burns down.
	local anger = 1 - calm
	alien.body.Color = alien.baseColor:Lerp(Color3.fromRGB(230, 60, 50), anger * 0.75)

	-- Eyes narrow into a glare.
	local squint = 1 - anger * 0.6
	for index, eye in alien.eyes do
		local size = eye.Size
		eye.Size = Vector3.new(size.X, alien.eyeSize * squint, size.Z)
		local pupil = alien.pupils[index]
		if pupil then
			local pupilSize = pupil.Size
			pupil.Size = Vector3.new(pupilSize.X, alien.eyeSize * 0.42 * squint, pupilSize.Z)
		end
	end
end

return Alien
