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
local ALIASES = {
	Neck          = { "Neck" },
	Waist         = { "Waist" },
	LeftShoulder  = { "LeftShoulder", "Left Shoulder" },
	RightShoulder = { "RightShoulder", "Right Shoulder" },
	LeftElbow     = { "LeftElbow" },       -- R15 only; no-ops on R6
	RightElbow    = { "RightElbow" },
	LeftHip       = { "LeftHip", "Left Hip" },
	RightHip      = { "RightHip", "Right Hip" },
	LeftKnee      = { "LeftKnee" },        -- R15 only
	RightKnee     = { "RightKnee" },
}

-- Without hips there is nothing worth calling a walk.
local REQUIRED = { "LeftHip", "RightHip" }

export type Rig = {
	joints: { [string]: { motor: Motor6D, base: CFrame } },
	phase: number,
}

-- R15 rigs built by CreateHumanoidModelFromDescription arrive in a T-pose:
-- there is no Animate script to settle them into an idle. Every angle we write
-- is relative to the joint's resting C0, so without correcting that first the
-- whole animation plays on top of outstretched arms.
--
-- Only applies to catalog rigs. The procedural alien is authored with its arms
-- already down, and would end up in a T-pose if this were applied to it.
local REST_OFFSET = {
	LeftShoulder = CFrame.Angles(0, 0, math.rad(80)),
	RightShoulder = CFrame.Angles(0, 0, math.rad(-80)),
}

function NpcAnimator.bind(model: Model, tPosed: boolean?): Rig?
	-- Index every Motor6D by its actual name first, then resolve canonical
	-- names through the alias table.
	local found = {}
	local names = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			found[descendant.Name] = descendant
			table.insert(names, descendant.Name)
		end
	end

	local joints = {}
	for canonical, spellings in ALIASES do
		for _, spelling in spellings do
			local motor = found[spelling]
			if motor then
				local rest = if tPosed then REST_OFFSET[canonical] else nil
				joints[canonical] = {
					motor = motor,
					base = motor.C0 * (rest or CFrame.identity),
				}
				break
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
	joint.motor.C0 = joint.base * CFrame.Angles(x, y, z)
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
		joint.motor.C0 = joint.base
	end
end

return NpcAnimator
