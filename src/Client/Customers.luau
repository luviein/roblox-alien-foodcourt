--!strict
-- Spawns, queues, animates and removes the alien customers, driven entirely by
-- the server snapshot. Purely presentational -- deleting this file would not
-- change a single gameplay outcome.
--
-- Each customer carries their own ticket on a BillboardGui above their head,
-- so the order literally walks in with the person who wants it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DishDefs = require(Shared.DishDefs)

local Alien = require(script.Parent.Alien)

local Customers = {}

local MAX_ROWS = 6
local WALK_SPEED = 11        -- studs/sec walking to a queue slot
local LEAVE_SPEED = 16
local LEAVE_DURATION = 1.1
local ARRIVE_EPSILON = 0.35

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
		MaxDistance = 200,
	}, adornee)

	local frame = make("Frame", {
		Name = "Panel",
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)

	local stroke = make("UIStroke", {
		Color = COLOR.stroke,
		Thickness = 2,
	}, frame)

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

local function spawnCustomer(order)
	local alien = Alien.build(nextSeed)
	nextSeed += 1

	alien.model.Parent = scene.folder

	local bill = buildBillboard(alien.root, alien.height + 2.4)

	local spawnPosition = scene.spawnCFrame.Position

	local entry = {
		orderId = order.id,
		alien = alien,
		bill = bill,
		position = spawnPosition,
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
	entry.alien.model:Destroy()
	active[entry.orderId] = nil
end

local function setModelTransparency(entry, alpha: number)
	for _, descendant in entry.alien.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "Root" then
			descendant.Transparency = alpha
		end
	end
	entry.bill.panel.BackgroundTransparency = math.max(0.08, alpha)
	entry.bill.gui.Enabled = alpha < 0.9
end

-- --------------------------------------------------------------- public ----

function Customers.init(sceneRefs)
	scene = sceneRefs
	active = {}
end

function Customers.clear()
	for _, entry in active do
		entry.alien.model:Destroy()
	end
	active = {}
end

-- Called when the server reports why a ticket left, so the exit animation can
-- match. Events always arrive before the snapshot that drops the order.
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

-- Per-frame animation. Walking is a bob plus a roll -- no animation assets.
function Customers.update(dt: number, snapshot)
	if not scene then
		return
	end

	local clock = workspace:GetServerTimeNow()

	for orderId, entry in active do
		local alien = entry.alien

		if entry.phase == "leaving" then
			entry.leaveClock += dt

			-- Happy customers stroll off; angry ones storm out faster.
			local angry = entry.mood == "angry"
			local speed = if angry then LEAVE_SPEED * 1.5 else LEAVE_SPEED
			local direction = if angry then -1 else 1
			local exitPosition = scene.exitCFrame.Position
			local goal = Vector3.new(
				exitPosition.X * direction,
				exitPosition.Y,
				exitPosition.Z + (if angry then -6 else 0)
			)

			entry.position = entry.position:Lerp(goal, math.min(1, dt * speed * 0.35))
			setModelTransparency(entry, math.clamp(entry.leaveClock / LEAVE_DURATION, 0, 1))

			if entry.leaveClock >= LEAVE_DURATION then
				destroyCustomer(entry)
				continue
			end
		else
			local toTarget = entry.targetPosition - entry.position
			local distance = toTarget.Magnitude

			if distance > ARRIVE_EPSILON then
				local step = math.min(distance, WALK_SPEED * dt)
				entry.position += toTarget.Unit * step
				entry.phase = "arriving"
			else
				entry.position = entry.targetPosition
				entry.phase = "queued"
			end

			-- Patience drives the mood: colour and squint.
			local span = math.max(entry.expiresAt - entry.createdAt, 0.001)
			local calm = math.clamp((entry.expiresAt - clock) / span, 0, 1)
			Alien.setMood(alien, calm)

			-- Impatient customers fidget harder.
			local agitation = 1 + (1 - calm) * 2.5
			local t = (os.clock() + entry.bobSeed)
			local walking = entry.phase == "arriving"

			local bobAmp = if walking then 0.22 else 0.07 * agitation
			local bobSpeed = if walking then 11 else 3 * agitation
			local rollAmp = if walking then 0.12 else 0.02 * agitation

			local bob = math.sin(t * bobSpeed) * bobAmp
			local roll = math.sin(t * bobSpeed * 0.5) * rollAmp

			local position = entry.position + Vector3.new(0, bob, 0)
			alien.model:PivotTo(
				CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
					* CFrame.Angles(0, 0, roll)
			)

			-- Patience bar on the billboard.
			entry.bill.fill.Size = UDim2.fromScale(calm, 1)
			entry.bill.fill.BackgroundColor3 = if calm > 0.5
				then COLOR.good
				elseif calm > 0.25 then COLOR.warn
				else COLOR.bad

			continue
		end

		-- Leaving customers still need their pivot applied.
		local position = entry.position
		alien.model:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, 1)))
	end
end

return Customers
