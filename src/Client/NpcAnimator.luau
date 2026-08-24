--!strict
-- Procedural walk/idle for the R15 customer rigs, driven by writing Motor6D
-- C0 offsets directly.
--
-- Why not real Roblox animations: doing that meant reading the default walk
-- and idle asset ids off the local player's own Animate script, which breaks
-- the moment the player's avatar is R6 and the customer rigs are R15 -- the
-- track plays but drives joints that do not exist, and the customer slides.
-- Hardcoding animation ids instead just moves the guess somewhere else.
--
-- Writing the joints ourselves needs no assets, cannot desync from anything,
-- and gives us impatient foot-tapping for free.
--
-- Angles are in radians. If a limb swings on the wrong axis or the wrong way,
-- these six constants are the only things to touch.

local NpcAnimator = {}

local LEG_SWING = 0.62     -- hip rotation at full stride
local KNEE_BEND = 0.85     -- how far the trailing knee folds
local ARM_SWING = 0.45     -- shoulder counter-swing
local TORSO_TWIST = 0.07   -- waist rotation, keeps it from looking rigid
local STRIDE_RATE = 9.0    -- radians/sec -- walk cycle speed
local BOB_HEIGHT = 0.11    -- vertical lift per step, applied by the caller

-- R6 and R15 name their joints differently -- R6 uses spaces ("Left Shoulder",
-- "Left Hip") and R15 does not. Binding only the R15 spellings meant an R6 rig
-- matched nothing, bound no joints, and stood in its raw T-pose while sliding
-- around: exactly the symptom that looked like "animation is broken".
--
-- Canonical name -> the spellings it may appear under, most specific first.
-- Third spelling in each list is the body part the joint moves: skinned rigs
-- often name the bone after the part rather than the joint.
local ALIASES = {
	Neck          = { "Neck", "Head" },
	Waist         = { "Waist", "UpperTorso" },
	LeftShoulder  = { "LeftShoulder", "Left Shoulder", "LeftUpperArm" },
	RightShoulder = { "RightShoulder", "Right Shoulder", "RightUpperArm" },
	LeftElbow     = { "LeftElbow", "LeftLowerArm" },   -- R15 only; no-ops on R6
	RightElbow    = { "RightElbow", "RightLowerArm" },
	LeftHip       = { "LeftHip", "Left Hip", "LeftUpperLeg" },
	RightHip      = { "RightHip", "Right Hip", "RightUpperLeg" },
	LeftKnee      = { "LeftKnee", "LeftLowerLeg" },    -- R15 only
	RightKnee     = { "RightKnee", "RightLowerLeg" },
}

-- Without hips there is nothing worth calling a walk.
local REQUIRED = { "LeftHip", "RightHip" }

export type Rig = {
	joints: { [string]: { apply: (CFrame) -> (), clear: () -> () } },
	phase: number,
}

-- The R15 skeleton: joint name, the part it hangs from, and the part it moves.
-- Both parts carry an Attachment called "<jointName>RigAttachment", and the
-- pair of those defines the joint completely.
-- The fourth field is where the joint pivot sits on the CHILD part: limbs
-- swing from their top end, the head and upper torso from their bottom.
local R15_JOINTS = {
	{ "Root",          "HumanoidRootPart", "LowerTorso",    "center" },
	{ "Waist",         "LowerTorso",       "UpperTorso",    "bottom" },
	{ "Neck",          "UpperTorso",       "Head",          "bottom" },
	{ "LeftShoulder",  "UpperTorso",       "LeftUpperArm",  "top" },
	{ "LeftElbow",     "LeftUpperArm",     "LeftLowerArm",  "top" },
	{ "LeftWrist",     "LeftLowerArm",     "LeftHand",      "top" },
	{ "RightShoulder", "UpperTorso",       "RightUpperArm", "top" },
	{ "RightElbow",    "RightUpperArm",    "RightLowerArm", "top" },
	{ "RightWrist",    "RightLowerArm",    "RightHand",     "top" },
	{ "LeftHip",       "LowerTorso",       "LeftUpperLeg",  "top" },
	{ "LeftKnee",      "LeftUpperLeg",     "LeftLowerLeg",  "top" },
	{ "LeftAnkle",     "LeftLowerLeg",     "LeftFoot",      "top" },
	{ "RightHip",      "LowerTorso",       "RightUpperLeg", "top" },
	{ "RightKnee",     "RightUpperLeg",    "RightLowerLeg", "top" },
	{ "RightAnkle",    "RightLowerLeg",    "RightFoot",     "top" },
}

-- Where the joint hinges, in world space, derived from the child part itself.
local function pivotOf(childPart: BasePart, mode: string): CFrame
	if mode == "top" then
		return childPart.CFrame * CFrame.new(0, childPart.Size.Y / 2, 0)
	elseif mode == "bottom" then
		return childPart.CFrame * CFrame.new(0, -childPart.Size.Y / 2, 0)
	end
	return childPart.CFrame
end

-- Assembles the Motor6Ds a rig should already have.
--
-- Rigs from CreateHumanoidModelFromDescription arrive as correctly-positioned
-- but entirely unconnected body parts: 56 rig attachments and zero joints.
-- Humanoid:BuildRigFromAttachments() reports success on them and creates
-- nothing, so the parts hold whatever pose they were laid out in and move as
-- one rigid lump -- a T-pose that slides.
--
-- Everything needed is already on the model, so we can just do it: pair the
-- attachments up and make the joints. Skips any joint that already exists, so
-- it is safe to call on a properly assembled rig.
function NpcAnimator.buildJoints(model: Model): (number, string)
	local created = 0
	local notes = {}

	for _, spec in R15_JOINTS do
		local jointName, parentName, childName, pivotMode = spec[1], spec[2], spec[3], spec[4]

		local parentPart = model:FindFirstChild(parentName)
		local childPart = model:FindFirstChild(childName)

		-- Say why, per joint. Reasoning about why "nothing was created" from
		-- the outside has cost several rounds; the loop knows the answer.
		if not parentPart then
			table.insert(notes, jointName .. ":noParent(" .. parentName .. ")")
		elseif not childPart then
			table.insert(notes, jointName .. ":noChild(" .. childName .. ")")
		elseif not parentPart:IsA("BasePart") then
			table.insert(notes, jointName .. ":parentIs" .. parentPart.ClassName)
		elseif not childPart:IsA("BasePart") then
			table.insert(notes, jointName .. ":childIs" .. childPart.ClassName)
		elseif childPart:FindFirstChild(jointName) then
			local existing = childPart:FindFirstChild(jointName) :: Instance
			table.insert(notes, jointName .. ":exists(" .. existing.ClassName .. ")")
		end

		if parentPart and childPart
			and parentPart:IsA("BasePart") and childPart:IsA("BasePart")
			and not childPart:FindFirstChild(jointName)
		then
			local c0, c1

			-- Preferred: the rig attachments, if this rig has them under the
			-- names it is supposed to.
			local attachmentName = jointName .. "RigAttachment"
			local parentAttachment = parentPart:FindFirstChild(attachmentName)
			local childAttachment = childPart:FindFirstChild(attachmentName)

			if parentAttachment and childAttachment
				and parentAttachment:IsA("Attachment") and childAttachment:IsA("Attachment")
			then
				c0 = parentAttachment.CFrame
				c1 = childAttachment.CFrame
			else
				-- Fallback that needs nothing but the parts themselves. They
				-- are already sitting in the right places relative to each
				-- other -- that is why the avatar renders correctly despite
				-- having no skeleton -- so the joint can be read straight off
				-- their geometry.
				--
				-- Anchoring both C0 and C1 to the same world pivot means
				-- Part1.CFrame comes out exactly where it already is, and
				-- rotating C0 swings the limb about that pivot rather than
				-- about the parent's centre.
				local pivot = pivotOf(childPart, pivotMode)
				c0 = parentPart.CFrame:Inverse() * pivot
				c1 = childPart.CFrame:Inverse() * pivot
			end

			local motor = Instance.new("Motor6D")
			motor.Name = jointName
			motor.Part0 = parentPart
			motor.Part1 = childPart
			motor.C0 = c0
			motor.C1 = c1
			motor.Parent = childPart
			created += 1
		end
	end

	return created, table.concat(notes, " ")
end

-- R15 rigs built by CreateHumanoidModelFromDescription arrive in a T-pose:
-- there is no Animate script to settle them into an idle. Every angle we write
-- is relative to the joint's resting C0, so without correcting that first the
-- whole animation plays on top of outstretched arms.
--
-- Only applies to catalog rigs. The procedural alien is authored with its arms
-- already down, and would end up in a T-pose if this were applied to it.
-- Empty on purpose. Joints built from rig attachments land in the skeleton's
-- proper bind pose (arms down), so no correction is needed -- the T-pose was
-- never a pose, it was parts sitting where they were laid out because nothing
-- connected them. Kept as a hook in case a rig does need correcting.
local REST_OFFSET = {}

-- Two kinds of skeleton pose two different ways, so each joint carries its own
-- setter rather than the animation code branching on type everywhere.
--
--   Motor6D : classic rig. Pose by offsetting C0 from its resting value.
--   Bone    : skinned rig. Pose by writing Transform, which is already
--             relative to the bind pose, so there is no base to offset from.
--
-- Writing C0 on a skinned rig does nothing at all, which is exactly the
-- failure that made these customers look like an animation bug.
local function jointHandle(instance: Instance, rest: CFrame?)
	if instance:IsA("Motor6D") then
		local base = instance.C0 * (rest or CFrame.identity)
		return {
			apply = function(offset: CFrame)
				instance.C0 = base * offset
			end,
			clear = function()
				instance.C0 = base
			end,
		}
	elseif instance:IsA("Bone") then
		local base = rest or CFrame.identity
		return {
			apply = function(offset: CFrame)
				instance.Transform = base * offset
			end,
			clear = function()
				instance.Transform = base
			end,
		}
	end
	return nil
end

function NpcAnimator.bind(model: Model, tPosed: boolean?): Rig?
	-- Index every poseable joint by its actual name, then resolve canonical
	-- names through the alias table.
	local found = {}
	local names = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") or descendant:IsA("Bone") then
			found[descendant.Name] = descendant
			table.insert(names, descendant.ClassName .. ":" .. descendant.Name)
		end
	end

	local joints = {}
	for canonical, spellings in ALIASES do
		for _, spelling in spellings do
			local instance = found[spelling]
			if instance then
				local handle = jointHandle(instance, if tPosed then REST_OFFSET[canonical] else nil)
				if handle then
					joints[canonical] = handle
					break
				end
			end
		end
	end

	for _, name in REQUIRED do
		if not joints[name] then
			return nil, names
		end
	end

	return { joints = joints, phase = 0 }, names
end

local function setAngle(rig: Rig, name: string, x: number, y: number, z: number)
	local joint = rig.joints[name]
	if not joint then
		return
	end
	joint.apply(CFrame.Angles(x, y, z))
end

-- Advances the walk cycle and returns the vertical bob for this frame, so the
-- caller can lift the whole rig in step with the footfalls.
function NpcAnimator.walk(rig: Rig, dt: number): number
	rig.phase += dt * STRIDE_RATE

	local swing = math.sin(rig.phase)
	local counter = -swing

	setAngle(rig, "LeftHip", swing * LEG_SWING, 0, 0)
	setAngle(rig, "RightHip", counter * LEG_SWING, 0, 0)

	-- Knees only fold on the trailing leg; a straight-legged march reads as
	-- broken, a permanently bent one reads as a crouch.
	setAngle(rig, "LeftKnee", -math.max(0, -swing) * KNEE_BEND, 0, 0)
	setAngle(rig, "RightKnee", -math.max(0, -counter) * KNEE_BEND, 0, 0)

	setAngle(rig, "LeftShoulder", counter * ARM_SWING, 0, 0)
	setAngle(rig, "RightShoulder", swing * ARM_SWING, 0, 0)
	setAngle(rig, "LeftElbow", -math.abs(swing) * 0.25, 0, 0)
	setAngle(rig, "RightElbow", -math.abs(counter) * 0.25, 0, 0)

	setAngle(rig, "Waist", 0, swing * TORSO_TWIST, 0)
	setAngle(rig, "Neck", 0, -swing * TORSO_TWIST * 0.5, 0)

	-- Two footfalls per cycle, hence the doubled frequency.
	return math.abs(math.sin(rig.phase)) * BOB_HEIGHT
end

-- Standing at the counter. `agitation` runs 0 (patient) to 1 (about to leave)
-- and adds a foot tap rather than speeding the whole body up -- scaling an
-- idle oscillation by impatience is what made the first version vibrate.
function NpcAnimator.idle(rig: Rig, clock: number, agitation: number): number
	local breathe = math.sin(clock * 1.4)

	setAngle(rig, "Waist", breathe * 0.025, 0, 0)
	setAngle(rig, "Neck", breathe * 0.02, 0, 0)
	setAngle(rig, "LeftShoulder", 0, 0, -0.06 + breathe * 0.02)
	setAngle(rig, "RightShoulder", 0, 0, 0.06 - breathe * 0.02)
	setAngle(rig, "LeftElbow", -0.08, 0, 0)
	setAngle(rig, "RightElbow", -0.08, 0, 0)
	setAngle(rig, "LeftHip", 0, 0, 0)
	setAngle(rig, "LeftKnee", 0, 0, 0)

	if agitation > 0.35 then
		-- Impatient toe tap: a discrete, rhythmic motion reads as annoyance.
		-- A faster full-body wobble reads as a bug.
		local strength = (agitation - 0.35) / 0.65
		local tap = math.max(0, math.sin(clock * 7.5)) * strength
		setAngle(rig, "RightHip", tap * 0.12, 0, 0)
		setAngle(rig, "RightKnee", -tap * 0.55, 0, 0)
	else
		setAngle(rig, "RightHip", 0, 0, 0)
		setAngle(rig, "RightKnee", 0, 0, 0)
	end

	return breathe * 0.012
end

-- Served, and happy about it: arms up, small hop. Returns the hop height.
function NpcAnimator.cheer(rig: Rig, clock: number): number
	local bounce = math.abs(math.sin(clock * 9))

	setAngle(rig, "LeftShoulder", 0, 0, -0.5 - bounce * 2.0)
	setAngle(rig, "RightShoulder", 0, 0, 0.5 + bounce * 2.0)
	setAngle(rig, "LeftElbow", -0.3, 0, 0)
	setAngle(rig, "RightElbow", -0.3, 0, 0)
	setAngle(rig, "Waist", -bounce * 0.1, 0, 0)
	setAngle(rig, "Neck", -bounce * 0.12, 0, 0)
	setAngle(rig, "LeftHip", 0, 0, 0)
	setAngle(rig, "RightHip", 0, 0, 0)
	setAngle(rig, "LeftKnee", -bounce * 0.2, 0, 0)
	setAngle(rig, "RightKnee", -bounce * 0.2, 0, 0)

	return bounce * 0.4
end

-- Wrong order, or waited too long: hunched forward, arms out, foot stomping.
function NpcAnimator.stomp(rig: Rig, clock: number): number
	local stomp = math.max(0, math.sin(clock * 13))

	setAngle(rig, "Waist", -0.16, 0, 0)
	setAngle(rig, "Neck", 0.1, 0, 0)
	setAngle(rig, "LeftShoulder", 0, 0, -0.55)
	setAngle(rig, "RightShoulder", 0, 0, 0.55)
	setAngle(rig, "LeftElbow", -0.7, 0, 0)
	setAngle(rig, "RightElbow", -0.7, 0, 0)
	setAngle(rig, "LeftHip", 0, 0, 0)
	setAngle(rig, "LeftKnee", 0, 0, 0)
	setAngle(rig, "RightHip", stomp * 0.45, 0, 0)
	setAngle(rig, "RightKnee", -stomp * 0.95, 0, 0)

	return 0
end

-- Puts every joint back where the rig was built, for exits and cleanup.
function NpcAnimator.reset(rig: Rig)
	for _, joint in rig.joints do
		joint.clear()
	end
end

return NpcAnimator
