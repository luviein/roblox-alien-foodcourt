--!strict
-- A drawn face on the customer's head: two eyes, two brows, and a mouth made
-- of two bars that tilt into a smile or a frown.
--
-- Why drawn rather than swapping the head's face decal: the decal swap needs
-- happy/angry face asset ids, which come from a catalog search that may not
-- resolve (and silently does nothing when it does not -- exactly the failure
-- that made reactions show only an emoji). Drawing it needs no assets, cannot
-- fail, and gives something a two-state decal swap cannot: a continuous
-- expression, so impatience creeps across the face as the timer drains
-- instead of snapping between two pictures.
--
-- The plate is a BillboardGui, so it always squares up to the camera. That is
-- correct here because the camera is fixed and customers face it.

local Face = {}

local INK = Color3.fromRGB(24, 24, 30)

-- Expression runs -1 (furious) .. 0 (neutral) .. +1 (delighted).
local MOUTH_TILT = 22      -- degrees each mouth bar rotates at full expression
local BROW_TILT = 20
local EYE_SQUASH = 0.4     -- how far eyes narrow into a happy arc

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function bar(name: string, x: number, y: number, width: number, parent: Instance)
	local frame = make("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(width, 0.055),
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
	return frame
end

function Face.attach(head: BasePart)
	local gui = make("BillboardGui", {
		Name = "DrawnFace",
		Adornee = head,
		AlwaysOnTop = false,
		LightInfluence = 0,
		Size = UDim2.fromScale(1.5, 1.5),
		-- StudsOffset is camera-relative, so +Z floats the plate just in front
		-- of the head rather than z-fighting with the mesh.
		StudsOffset = Vector3.new(0, 0.08, 0.62),
		MaxDistance = 300,
	}, head)

	local container = make("Frame", {
		Name = "Container",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, gui)

	local function eye(name: string, x: number)
		local frame = make("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(x, 0.34),
			Size = UDim2.fromScale(0.15, 0.19),
		}, container)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
		return frame
	end

	local face = {
		gui = gui,
		eyeL = eye("EyeL", 0.32),
		eyeR = eye("EyeR", 0.68),
		browL = bar("BrowL", 0.32, 0.17, 0.20, container),
		browR = bar("BrowR", 0.68, 0.17, 0.20, container),
		mouthL = bar("MouthL", 0.41, 0.64, 0.19, container),
		mouthR = bar("MouthR", 0.59, 0.64, 0.19, container),
		current = 0,
	}

	Face.set(face, 0)
	return face
end

-- Snaps the face to an expression. -1 furious, 0 neutral, +1 delighted.
function Face.set(face, expression: number)
	expression = math.clamp(expression, -1, 1)
	face.current = expression

	local happy = math.max(0, expression)
	local angry = math.max(0, -expression)

	-- Mouth: two bars meeting in the middle. Positive rotation is clockwise,
	-- so the left bar's outer end lifts on +Rotation and the right bar's on
	-- -Rotation. Both corners up is a smile; both down is a frown.
	face.mouthL.Rotation = MOUTH_TILT * expression
	face.mouthR.Rotation = -MOUTH_TILT * expression

	-- Brows only appear as anger builds, sloping down toward the nose.
	face.browL.BackgroundTransparency = 1 - angry
	face.browR.BackgroundTransparency = 1 - angry
	face.browL.Rotation = BROW_TILT * angry
	face.browR.Rotation = -BROW_TILT * angry

	-- Eyes narrow into arcs when happy, widen slightly when angry.
	local height = 0.19 * (1 - EYE_SQUASH * happy) * (1 + 0.15 * angry)
	face.eyeL.Size = UDim2.fromScale(0.15, height)
	face.eyeR.Size = UDim2.fromScale(0.15, height)
end

-- Eases toward a target so impatience creeps in rather than snapping.
function Face.tween(face, target: number, dt: number, rate: number?)
	local alpha = math.clamp(dt * (rate or 6), 0, 1)
	Face.set(face, face.current + (target - face.current) * alpha)
end

function Face.destroy(face)
	face.gui:Destroy()
end

return Face
