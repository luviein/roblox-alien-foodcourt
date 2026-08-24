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

-- ------------------------------------------------------------------ face ---

-- The reaction faces the server resolved and published as attributes on the
-- rig folder. Read lazily: the server finishes resolving these well after the
-- first client connects.
local function reactionFaceId(mood: string): number?
	local folder = ReplicatedStorage:FindFirstChild("CustomerRigs")
	if not folder then
		return nil
	end
	return folder:GetAttribute(if mood == "angry" then "AngryFace" else "HappyFace")
end

-- Swaps the decal on the customer's head. Passing nil restores whatever face
-- they were built with.
local function setFace(entry, assetId: number?)
	local decal = entry.body.faceDecal
	if not decal then
		return
	end
	decal.Texture = if assetId
		then ("rbxassetid://%d"):format(assetId)
		else entry.body.neutralFace
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

	-- Joint driver. Returns nil if this is not an R15 rig, in which case the
	-- customer simply stands still rather than erroring.
	local rig = NpcAnimator.bind(model)

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

	-- The head's face decal, so reactions can change their actual expression.
	local faceDecal = if head then head:FindFirstChildOfClass("Decal") else nil

	return {
		kind = "rig",
		model = model,
		adornee = head or root,
		billboardOffset = 2.4,
		yOffset = yOffset,
		highlight = highlight,
		rig = rig,
		faceDecal = faceDecal,
		neutralFace = if faceDecal then faceDecal.Texture else "",
	}
end

-- Fallback: the procedural alien, used when no rigs exist.
local function buildAlienCustomer()
	local alien = Alien.build(nextSeed)
	nextSeed += 1
	return {
		kind = "alien",
		model = alien.model,
		alien = alien,
		adornee = alien.root,
		billboardOffset = alien.height + 2.4,
		yOffset = 0,
	}
end

local function spawnCustomer(order)
	local body = buildRigCustomer() or buildAlienCustomer()

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

	if body.kind == "rig" then
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

	-- The procedural alien has no joints; it hops for joy and shakes in anger.
	if reacting then
		return if entry.mood == "angry"
			then math.sin(clock * 26) * 0.09
			else math.abs(math.sin(clock * 9)) * 0.4
	end
	if entry.phase == "queued" then
		return math.sin(clock * 1.6) * 0.05
	end
	return 0
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
	setFace(entry, reactionFaceId(reaction.mood))

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

	for slotIndex, order in snapshot.orders do
		seen[order.id] = true

		local entry = active[order.id]
		if not entry then
			entry = spawnCustomer(order)
		end

		local slot = scene.slots[slotIndex]
		if slot then
			entry.targetPosition = slot.Position
			entry.slotIndex = slotIndex
		end

		entry.createdAt = order.createdAt
		entry.expiresAt = order.expiresAt

		renderTicket(entry, order, slotIndex, snapshot)
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

			if body.kind == "rig" then
				body.highlight.FillTransparency = 1 - agitation * 0.45
			else
				Alien.setMood(body.alien, calm)
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

		body.model:PivotTo(CFrame.lookAt(position, lookAt))
	end
end

return Customers
