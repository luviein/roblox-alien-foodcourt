--!strict
-- Spawns, queues, animates and removes customers, driven entirely by the server
-- snapshot. Purely presentational -- deleting this file would not change a
-- single gameplay outcome.
--
-- Customers are real R15 rigs cloned from the pool the server pre-builds in
-- ReplicatedStorage.CustomerRigs (clothing, hair, faces, body scale). If that
-- pool is empty -- no asset ids filled in yet, or the web calls failed -- we
-- fall back to the procedural alien so the game always runs.
--
-- Each customer carries their own ticket on a BillboardGui above their head,
-- so the order literally walks in with the person who wants it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DishDefs = require(Shared.DishDefs)

local Alien = require(script.Parent.Alien)
local NpcAnimator = require(script.Parent.NpcAnimator)
local Face = require(script.Parent.Face)

local Customers = {}

local MAX_ROWS = 6
local WALK_SPEED = 9
local LEAVE_SPEED = 11
local LEAVE_DURATION = 1.2
local ARRIVE_EPSILON = 0.25

-- Customers hold their reaction for a beat before walking off. Without this
-- they turn and leave on the same frame they are served, and the reaction is
-- gone before you can read it.
local REACT_DURATION = 0.75

-- The emoji bubble is a second channel on top of the face swap, because a
-- face is only a few pixels tall at this camera distance. Set false if you
-- want the expression to read from the character alone.
local SHOW_REACTION_BUBBLE = true

-- How each outcome reads on the customer. Emoji need no asset ids and are
-- legible at any distance, which face decals are not.
local REACTIONS = {
	Perfect = { emoji = "🤩", mood = "happy" },
	Good    = { emoji = "😄", mood = "happy" },
	Sloppy  = { emoji = "🙂", mood = "happy" },
	Fail    = { emoji = "😠", mood = "angry" },
	Expired = { emoji = "😡", mood = "angry" },
}

local COLOR = {
	panel   = Color3.fromRGB(24, 26, 36),
	panelHi = Color3.fromRGB(46, 50, 66),
	stroke  = Color3.fromRGB(70, 76, 96),
	accent  = Color3.fromRGB(88, 198, 255),
	text    = Color3.fromRGB(234, 238, 246),
	dim     = Color3.fromRGB(140, 148, 168),
	good    = Color3.fromRGB(108, 220, 140),
	warn    = Color3.fromRGB(246, 184, 72),
	bad     = Color3.fromRGB(242, 92, 92),
}

local scene: any = nil
local active: { [number]: any } = {}
local nextSeed = 1
local warnedNoJoints = false

-- Draws the first customer's body composition on screen. Turn off once the
-- rig pipeline is settled.
local DEBUG_BODY = true

-- ------------------------------------------------------------- billboard ---

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

local function buildBillboard(adornee: BasePart, heightOffset: number)
	local gui = make("BillboardGui", {
		Name = "Ticket",
		Adornee = adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromScale(4.4, 3.6),
		StudsOffset = Vector3.new(0, heightOffset, 0),
		MaxDistance = 300,
	}, adornee)

	local frame = make("Frame", {
		Name = "Panel",
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)

	local stroke = make("UIStroke", { Color = COLOR.stroke, Thickness = 2 }, frame)

	make("UIPadding", {
		PaddingTop = UDim.new(0.05, 0),
		PaddingBottom = UDim.new(0.05, 0),
		PaddingLeft = UDim.new(0.05, 0),
		PaddingRight = UDim.new(0.05, 0),
	}, frame)

	local slotBadge = make("TextLabel", {
		Name = "Slot",
		BackgroundColor3 = COLOR.panelHi,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.16, 0.15),
		Font = Enum.Font.GothamBold,
		Text = "1",
		TextColor3 = COLOR.dim,
		TextScaled = true,
	}, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, slotBadge)

	local title = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.2, 0),
		Size = UDim2.fromScale(0.8, 0.15),
		Font = Enum.Font.GothamBold,
		Text = "Cheeseburger",
		TextColor3 = COLOR.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)

	local list = make("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.18),
		Size = UDim2.fromScale(1, 0.68),
	}, frame)

	make("UIListLayout", {
		Padding = UDim.new(0.02, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	local rows = {}
	for index = 1, MAX_ROWS do
		local row = make("Frame", {
			Name = "Row" .. index,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 0.15),
			Visible = false,
		}, list)

		local keyBadge = make("TextLabel", {
			Name = "Key",
			BackgroundColor3 = COLOR.panelHi,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0.15, 1),
			Font = Enum.Font.GothamBold,
			Text = "Q",
			TextColor3 = COLOR.text,
			TextScaled = true,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, keyBadge)

		local name = make("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.19, 0),
			Size = UDim2.fromScale(0.81, 1),
			Font = Enum.Font.GothamMedium,
			Text = "Bottom Bun",
			TextColor3 = COLOR.text,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)

		rows[index] = { frame = row, key = keyBadge, name = name }
	end

	local track = make("Frame", {
		Name = "PatienceTrack",
		BackgroundColor3 = Color3.fromRGB(14, 15, 22),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.07),
	}, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, track)

	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLOR.good,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, track)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, fill)

	return {
		gui = gui,
		panel = frame,
		stroke = stroke,
		slotBadge = slotBadge,
		title = title,
		rows = rows,
		fill = fill,
	}
end

-- A big emoji that pops above the head on serve or walk-out.
local function buildReactionBubble(adornee: BasePart, heightOffset: number)
	local gui = make("BillboardGui", {
		Name = "Reaction",
		Adornee = adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromScale(2.6, 2.6),
		StudsOffset = Vector3.new(0, heightOffset, 0),
		MaxDistance = 300,
		Enabled = false,
	}, adornee)

	local label = make("TextLabel", {
		Name = "Emoji",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
	}, gui)

	return { gui = gui, label = label }
end

-- ------------------------------------------------------------------ life ---

local function rigPool(): { Model }
	local folder = ReplicatedStorage:FindFirstChild("CustomerRigs")
	if not folder then
		return {}
	end
	local rigs = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			table.insert(rigs, child)
		end
	end
	return rigs
end

-- A real R15 customer, cloned from the server-built pool.
local function buildRigCustomer()
	local pool = rigPool()
	if #pool == 0 then
		return nil
	end

	local model = pool[math.random(1, #pool)]:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = model:FindFirstChild("Head") :: BasePart?

	if not humanoid or not root then
		model:Destroy()
		return nil
	end

	model.PrimaryPart = root

	-- Belt and braces: the server already disables this, but a rig that
	-- somehow arrives with it on will silently ignore every pose we write.
	humanoid.AutomaticScalingEnabled = false

	-- Joint driver. Returns nil if this is not an R15 rig, in which case the
	-- customer simply stands still rather than erroring.
	-- true: catalog rigs arrive T-posed and need the rest offset applied.
	local rig, jointNames = NpcAnimator.bind(model, true)
	if not rig and not warnedNoJoints then
		warnedNoJoints = true
		local found = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("Motor6D") then
				table.insert(found, descendant.Name)
			end
		end
		warn(("[AlienFoodCourt] no poseable joints on customer rig -- walk and "
			.. "reaction poses disabled. Motor6Ds found: %s")
			:format(if #found > 0 then table.concat(found, ", ") else "none"))
	end

	-- Impatience is shown by tinting the whole customer rather than recolouring
	-- body parts, which would fight with their clothing.
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(235, 60, 50)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = model

	-- The root sits a hip-height above the floor, so pivoting to a floor
	-- position without this offset would bury them to the waist.
	local yOffset = humanoid.HipHeight + root.Size.Y / 2

	-- Expression. The drawn face replaces the head's decal outright: leaving
	-- the catalog face underneath would show two mouths.
	local faceDecal = if head then head:FindFirstChildOfClass("Decal") else nil
	local drawnFace = nil

	if head then
		if faceDecal then
			faceDecal.Transparency = 1
		end
		drawnFace = Face.attach(head)
	end

	return {
		kind = "rig",
		model = model,
		root = root,
		adornee = head or root,
		billboardOffset = 2.4,
		yOffset = yOffset,
		highlight = highlight,
		rig = rig,
		jointNames = jointNames,
		face = drawnFace,
	}
end

-- Fallback: the procedural alien. Built from primitives but jointed and
-- headed like a real character, so it takes the same animator and the same
-- drawn face as an R15 rig -- no second code path, and no silent loss of
-- limbs or expression when the avatar pool fails to build.
local function buildAlienCustomer()
	local alien = Alien.build(nextSeed)
	nextSeed += 1

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(235, 60, 50)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = alien.model

	return {
		kind = "alien",
		model = alien.model,
		root = alien.root,
		adornee = alien.head,
		billboardOffset = 2.4,
		yOffset = alien.yOffset,
		highlight = highlight,
		-- false: the alien is authored with its arms already down.
		rig = NpcAnimator.bind(alien.model, false),
		jointNames = nil,
		face = Face.attach(alien.head),
	}
end

local reportedFirst = false

-- Prints AND draws the composition of the first customer. On screen because
-- every symptom so far -- sliding, T-pose, no face -- looked like an animation
-- bug while actually being "this body is not what you think it is", and a
-- screenshot carries the answer where a scrolled-past Output line does not.
-- Set DEBUG_BODY to false once the rig pipeline is settled.
local function reportBody(body)
	local text = ("kind=%s | joints=%s | face=%s | head=%s\nMotor6Ds: %s"):format(
		body.kind,
		if body.rig then "BOUND" else "MISSING",
		if body.face then "drawn" else "MISSING",
		if body.adornee then body.adornee.Name else "none",
		if body.jointNames and #body.jointNames > 0
			then table.concat(body.jointNames, ", ")
			else "none found"
	)

	print("[AlienFoodCourt] customer body: " .. text)

	if not DEBUG_BODY then
		return
	end

	local player = game:GetService("Players").LocalPlayer
	local screen = make("ScreenGui", {
		Name = "AFC_BodyDebug",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 200,
	}, player:WaitForChild("PlayerGui"))

	local label = make("TextLabel", {
		BackgroundColor3 = Color3.fromRGB(10, 11, 16),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.005, 0.12),
		Size = UDim2.fromScale(0.5, 0.07),
		Font = Enum.Font.Code,
		Text = text,
		TextColor3 = if body.rig then Color3.fromRGB(120, 230, 150) else Color3.fromRGB(255, 120, 110),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, screen)
	make("UITextSizeConstraint", { MaxTextSize = 14 }, label)
end

local function spawnCustomer(order)
	local body = buildRigCustomer() or buildAlienCustomer()

	if not reportedFirst then
		reportedFirst = true
		reportBody(body)
	end

	body.model.Parent = scene.folder

	local bill = buildBillboard(body.adornee, body.billboardOffset)
	local reaction = buildReactionBubble(body.adornee, body.billboardOffset - 0.5)
	local spawnPosition = scene.spawnCFrame.Position

	local entry = {
		orderId = order.id,
		body = body,
		bill = bill,
		reaction = reaction,
		reactClock = 0,
		position = spawnPosition,
		lastPosition = spawnPosition,
		targetPosition = spawnPosition,
		phase = "arriving",
		mood = nil,
		leaveClock = 0,
		bobSeed = math.random() * 100,
		createdAt = order.createdAt,
		expiresAt = order.expiresAt,
	}

	active[order.id] = entry
	return entry
end

local function destroyCustomer(entry)
	entry.body.model:Destroy()
	active[entry.orderId] = nil
end

local function setModelTransparency(entry, alpha: number)
	for _, descendant in entry.body.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "Root" then
			descendant.LocalTransparencyModifier = alpha
		end
	end
	entry.bill.gui.Enabled = alpha < 0.9
	entry.reaction.label.TextTransparency = alpha
end

-- Drives the rig's joints for this frame and returns the vertical bob to apply.
-- The alien fallback has no joints, so it keeps its own gentle sway.
local function animate(entry, dt: number, walking: boolean, agitation: number): number
	local body = entry.body
	local clock = os.clock() + entry.bobSeed
	local reacting = entry.phase == "reacting"

	-- One path for both body kinds: the fallback alien is jointed with the
	-- same R15 joint names, so it poses identically.
	if not body.rig then
		return 0
	end

	if reacting then
		return if entry.mood == "angry"
			then NpcAnimator.stomp(body.rig, clock)
			else NpcAnimator.cheer(body.rig, clock)
	end
	if walking then
		return NpcAnimator.walk(body.rig, dt)
	end
	return NpcAnimator.idle(body.rig, clock, agitation)
end

-- --------------------------------------------------------------- public ----

function Customers.init(sceneRefs)
	scene = sceneRefs
	active = {}
end

function Customers.clear()
	for _, entry in active do
		entry.body.model:Destroy()
	end
	active = {}
end

-- Called when the server reports how a ticket ended -- a grade name, or
-- "Expired" for a walk-out. Events arrive inside the snapshot that drops the
-- order, ahead of the sync that notices it is gone, so the reaction is set
-- before anything starts leaving.
function Customers.markExit(orderId: number, outcome: string)
	local entry = active[orderId]
	if not entry or entry.phase == "reacting" or entry.phase == "leaving" then
		return
	end

	local reaction = REACTIONS[outcome] or REACTIONS.Expired

	entry.mood = reaction.mood
	entry.phase = "reacting"
	entry.reactClock = 0

	-- The expression goes on the customer's own face. The bubble is a second,
	-- readable-at-distance channel -- the face alone is small on screen.
	if entry.body.face then
		Face.set(entry.body.face, if reaction.mood == "angry" then -1 else 1)
	end

	entry.bill.gui.Enabled = false
	entry.reaction.label.Text = reaction.emoji
	entry.reaction.gui.Enabled = SHOW_REACTION_BUBBLE
end

local function renderTicket(entry, order, slotIndex: number, snapshot)
	local dish = DishDefs.get(order.dishId)
	local isActive = order.id == snapshot.activeOrderId
	local built = if isActive then #snapshot.build else 0

	local bill = entry.bill
	bill.title.Text = dish and dish.displayName or order.dishId
	bill.slotBadge.Text = tostring(slotIndex)
	bill.slotBadge.TextColor3 = if isActive then COLOR.accent else COLOR.dim
	bill.stroke.Color = if isActive then COLOR.accent else COLOR.stroke
	bill.stroke.Thickness = if isActive then 3 else 2

	for index = 1, MAX_ROWS do
		local row = bill.rows[index]
		local ingredientId = order.required[index]

		if not ingredientId then
			row.frame.Visible = false
			continue
		end

		row.frame.Visible = true
		row.key.Text = order.keys[index]
		row.name.Text = DishDefs.ingredientName(ingredientId)

		if index <= built then
			row.key.BackgroundColor3 = COLOR.good
			row.key.TextColor3 = Color3.fromRGB(16, 17, 24)
			row.name.TextColor3 = COLOR.dim
		elseif isActive and index == built + 1 then
			row.key.BackgroundColor3 = COLOR.accent
			row.key.TextColor3 = Color3.fromRGB(16, 17, 24)
			row.name.TextColor3 = COLOR.text
		else
			row.key.BackgroundColor3 = COLOR.panelHi
			row.key.TextColor3 = COLOR.text
			row.name.TextColor3 = COLOR.text
		end
	end
end

-- Reconcile the queue against the snapshot: spawn newcomers, shuffle everyone
-- forward when a slot frees up, and start exits for tickets that are gone.
function Customers.sync(snapshot)
	if not scene then
		return
	end

	local seen = {}

	-- A customer who is reacting or walking out still physically occupies
	-- their spot. Without this the queue shuffles forward the instant the
	-- server drops the order, and the next customer walks into the one still
	-- standing there.
	local held = {}
	for _, entry in active do
		if entry.slotIndex and (entry.phase == "reacting" or entry.phase == "leaving") then
			held[entry.slotIndex] = true
		end
	end

	local nextFree = 1

	-- `orderIndex` is the server's position in the queue and is what the 1-4
	-- keys select, so it drives the ticket badge. The visual slot is worked
	-- out separately, skipping anything still being vacated.
	for orderIndex, order in snapshot.orders do
		seen[order.id] = true

		local entry = active[order.id]
		if not entry then
			entry = spawnCustomer(order)
		end

		while nextFree <= #scene.slots and held[nextFree] do
			nextFree += 1
		end

		if nextFree <= #scene.slots then
			entry.slotIndex = nextFree
			entry.targetPosition = scene.slots[nextFree].Position
			nextFree += 1
		else
			-- Every slot is still being vacated; hang back at the entrance.
			entry.slotIndex = nil
			entry.targetPosition = scene.waitCFrame.Position
		end

		entry.createdAt = order.createdAt
		entry.expiresAt = order.expiresAt

		renderTicket(entry, order, orderIndex, snapshot)
	end

	-- Anything the snapshot dropped without an accompanying event just leaves
	-- quietly; markExit has normally already put it into "reacting".
	for orderId, entry in active do
		if not seen[orderId] and entry.phase ~= "leaving" and entry.phase ~= "reacting" then
			entry.phase = "leaving"
			entry.leaveClock = 0
			entry.bill.gui.Enabled = false
		end
	end
end

function Customers.update(dt: number, _snapshot)
	if not scene then
		return
	end

	local clock = workspace:GetServerTimeNow()

	for _, entry in active do
		local body = entry.body
		local walking = true
		local agitation = 0

		if entry.phase == "reacting" then
			-- Hold position and play the reaction before turning to leave.
			entry.reactClock += dt
			walking = false

			if entry.reactClock >= REACT_DURATION then
				entry.phase = "leaving"
				entry.leaveClock = 0
			end

		elseif entry.phase == "leaving" then
			entry.leaveClock += dt

			local angry = entry.mood == "angry"
			local exitPosition = scene.exitCFrame.Position
			local goal = Vector3.new(
				exitPosition.X * (if angry then -1 else 1),
				exitPosition.Y,
				exitPosition.Z + (if angry then -6 else 0)
			)

			local speed = if angry then LEAVE_SPEED * 1.6 else LEAVE_SPEED
			local toGoal = goal - entry.position
			if toGoal.Magnitude > 0.01 then
				entry.position += toGoal.Unit * math.min(toGoal.Magnitude, speed * dt)
			end

			setModelTransparency(entry, math.clamp(entry.leaveClock / LEAVE_DURATION, 0, 1))

			if entry.leaveClock >= LEAVE_DURATION then
				destroyCustomer(entry)
				continue
			end
		else
			local toTarget = entry.targetPosition - entry.position
			local distance = toTarget.Magnitude

			if distance > ARRIVE_EPSILON then
				entry.position += toTarget.Unit * math.min(distance, WALK_SPEED * dt)
				entry.phase = "arriving"
			else
				entry.position = entry.targetPosition
				entry.phase = "queued"
				walking = false
			end

			-- Patience, made visible.
			local span = math.max(entry.expiresAt - entry.createdAt, 0.001)
			local calm = math.clamp((entry.expiresAt - clock) / span, 0, 1)
			agitation = 1 - calm

			-- Both body kinds carry a highlight and a drawn face, so there is
			-- no branch here any more.
			body.highlight.FillTransparency = 1 - agitation * 0.45

			if body.face then
				-- A mild smile when they arrive, easing into a scowl as the
				-- timer burns down. The expression is continuous, so you can
				-- read how close someone is to walking out from their face
				-- alone, before checking the patience bar.
				Face.tween(body.face, 0.35 - agitation * 1.1, dt)
			end

			entry.bill.fill.Size = UDim2.fromScale(calm, 1)
			entry.bill.fill.BackgroundColor3 = if calm > 0.5
				then COLOR.good
				elseif calm > 0.25 then COLOR.warn
				else COLOR.bad
		end

		-- Face the direction of travel while walking in or out, then turn to
		-- the counter once settled -- otherwise they moonwalk to their slot.
		local travel = if walking then entry.position - entry.lastPosition else Vector3.zero
		local heading = Vector3.new(travel.X, 0, travel.Z)
		entry.lastPosition = entry.position

		local lift = animate(entry, dt, walking, agitation)
		local position = entry.position + Vector3.new(0, body.yOffset + lift, 0)

		local lookAt = if heading.Magnitude > 0.001
			then position + heading.Unit
			else position + Vector3.new(0, 0, 1)   -- squared up to the counter

		-- Move the anchored root ONLY. Model:PivotTo sets every part's CFrame
		-- while preserving their current offsets, which overwrites the pose
		-- NpcAnimator just wrote into the joints -- the character slides along
		-- frozen in whatever shape it happened to be in. Driving the root lets
		-- the Motor6D chain carry the rest of the body, which is the whole
		-- point of having joints.
		body.root.CFrame = CFrame.lookAt(position, lookAt)
	end
end

return Customers
