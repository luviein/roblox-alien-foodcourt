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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DishDefs = require(Shared.DishDefs)

local Alien = require(script.Parent.Alien)

local Customers = {}

local MAX_ROWS = 6
local WALK_SPEED = 9
local LEAVE_SPEED = 11
local LEAVE_DURATION = 1.2
local ARRIVE_EPSILON = 0.25

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
local animationIds: any = nil
local animationsChecked = false

-- ------------------------------------------------------------ animations ---

-- Reads the default walk/idle animation ids off the local player's own Animate
-- script. That avoids hardcoding animation asset ids (which I would only be
-- guessing at) and stays correct if Roblox changes the defaults.
local function defaultAnimationIds()
	if animationsChecked then
		return animationIds
	end

	local character = Players.LocalPlayer.Character
	local animate = character and character:FindFirstChild("Animate")
	if not animate then
		return nil   -- character not loaded yet; try again on the next spawn
	end

	animationsChecked = true

	local function idOf(groupName: string, animName: string): string?
		local group = animate:FindFirstChild(groupName)
		local anim = group and group:FindFirstChild(animName)
		if anim and anim:IsA("Animation") and anim.AnimationId ~= "" then
			return anim.AnimationId
		end
		return nil
	end

	animationIds = {
		idle = idOf("idle", "Animation1"),
		walk = idOf("walk", "WalkAnim"),
	}
	return animationIds
end

local function loadTrack(animator: Animator, id: string?): AnimationTrack?
	if not id then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Core
	return track
end

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

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local ids = defaultAnimationIds()
	local idleTrack = if ids then loadTrack(animator, ids.idle) else nil
	local walkTrack = if ids then loadTrack(animator, ids.walk) else nil

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

	return {
		kind = "rig",
		model = model,
		adornee = head or root,
		billboardOffset = 2.4,
		yOffset = yOffset,
		highlight = highlight,
		idleTrack = idleTrack,
		walkTrack = walkTrack,
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
	local spawnPosition = scene.spawnCFrame.Position

	local entry = {
		orderId = order.id,
		body = body,
		bill = bill,
		position = spawnPosition,
		targetPosition = spawnPosition,
		phase = "arriving",
		mood = nil,
		leaveClock = 0,
		bobSeed = math.random() * 100,
		createdAt = order.createdAt,
		expiresAt = order.expiresAt,
		playing = nil,
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
end

-- Swap between walk and idle without restarting a track that already plays.
local function setAnimation(entry, wanted: string)
	if entry.playing == wanted then
		return
	end
	entry.playing = wanted

	local body = entry.body
	if body.kind ~= "rig" then
		return
	end

	local play = if wanted == "walk" then body.walkTrack else body.idleTrack
	local stop = if wanted == "walk" then body.idleTrack else body.walkTrack

	if stop then
		stop:Stop(0.2)
	end
	if play and not play.IsPlaying then
		play:Play(0.2)
	end
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

-- Called when the server reports why a ticket left, so the exit animation can
-- match. Events arrive inside the snapshot that drops the order, ahead of the
-- sync that notices it is gone.
function Customers.markExit(orderId: number, mood: string)
	local entry = active[orderId]
	if entry and entry.phase ~= "leaving" then
		entry.mood = mood
	end
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

	for orderId, entry in active do
		if not seen[orderId] and entry.phase ~= "leaving" then
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

		if entry.phase == "leaving" then
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

			setAnimation(entry, "walk")
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
				setAnimation(entry, "walk")
			else
				entry.position = entry.targetPosition
				entry.phase = "queued"
				setAnimation(entry, "idle")
			end

			-- Patience, made visible.
			local span = math.max(entry.expiresAt - entry.createdAt, 0.001)
			local calm = math.clamp((entry.expiresAt - clock) / span, 0, 1)
			local anger = 1 - calm

			if body.kind == "rig" then
				body.highlight.FillTransparency = 1 - anger * 0.45
			else
				Alien.setMood(body.alien, calm)
			end

			entry.bill.fill.Size = UDim2.fromScale(calm, 1)
			entry.bill.fill.BackgroundColor3 = if calm > 0.5
				then COLOR.good
				elseif calm > 0.25 then COLOR.warn
				else COLOR.bad
		end

		-- Position. Rigs get no procedural bob at all -- their idle animation
		-- already breathes, and layering a sine wave on top is what produced
		-- the vibrating. The fallback alien gets one slow, fixed-rate bob:
		-- never scaled by impatience, which is what made it buzz.
		local lift = 0
		if body.kind == "alien" and entry.phase == "queued" then
			lift = math.sin((os.clock() + entry.bobSeed) * 1.6) * 0.05
		end

		local position = entry.position + Vector3.new(0, body.yOffset + lift, 0)
		body.model:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, 1)))
	end
end

return Customers
