--!strict
-- Grey-box UI, built entirely in code so it lives in git and Rojo can push it.
-- No art, no models -- the point of P0 is to find out whether the INPUT feels
-- good. Everything here is meant to be thrown away once it does.
--
-- Every on-screen button fires the same callback as its keyboard key, so
-- touch works from day one rather than being bolted on later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DishDefs = require(Shared.DishDefs)

local UI = {}

local COLOR = {
	bg       = Color3.fromRGB(16, 17, 24),
	panel    = Color3.fromRGB(30, 32, 43),
	panelHi  = Color3.fromRGB(46, 50, 66),
	stroke   = Color3.fromRGB(60, 65, 84),
	accent   = Color3.fromRGB(88, 198, 255),
	text     = Color3.fromRGB(234, 238, 246),
	dim      = Color3.fromRGB(122, 130, 150),
	good     = Color3.fromRGB(108, 220, 140),
	warn     = Color3.fromRGB(246, 184, 72),
	bad      = Color3.fromRGB(242, 92, 92),
	perfect  = Color3.fromRGB(255, 214, 92),
}

local KEY_ROWS = {
	{ "Q", "W", "E", "R", "T" },
	{ "A", "S", "D", "F", "G" },
}

local MAX_INGREDIENT_ROWS = 6
local MAX_BUILD_CHIPS = 8

-- ---------------------------------------------------------------- helpers --

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Green while there is time, amber as it tightens, red at the end.
local function patienceColor(fraction: number): Color3
	if fraction > 0.5 then
		return COLOR.good
	elseif fraction > 0.25 then
		return COLOR.warn
	end
	return COLOR.bad
end

-- ----------------------------------------------------------------- build ---

local function buildTopBar(parent: Instance)
	local bar = make("Frame", {
		Name = "TopBar",
		BackgroundColor3 = COLOR.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.012),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.96, 0.085),
	}, parent)
	corner(bar, 10)

	local score = make("TextLabel", {
		Name = "Score",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.015, 0),
		Size = UDim2.fromScale(0.28, 1),
		Font = Enum.Font.GothamBold,
		Text = "0 c",
		TextColor3 = COLOR.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, bar)
	make("UITextSizeConstraint", { MaxTextSize = 40 }, score)

	local timeLabel = make("TextLabel", {
		Name = "Time",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.36, 0.08),
		Size = UDim2.fromScale(0.28, 0.5),
		Font = Enum.Font.GothamBold,
		Text = "3:00",
		TextColor3 = COLOR.text,
		TextScaled = true,
	}, bar)
	make("UITextSizeConstraint", { MaxTextSize = 34 }, timeLabel)

	local timeTrack = make("Frame", {
		Name = "TimeTrack",
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.36, 0.66),
		Size = UDim2.fromScale(0.28, 0.16),
	}, bar)
	corner(timeTrack, 4)

	local timeFill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, timeTrack)
	corner(timeFill, 4)

	local combo = make("TextLabel", {
		Name = "Combo",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.7, 0),
		Size = UDim2.fromScale(0.285, 1),
		Font = Enum.Font.GothamBold,
		Text = "x1.00",
		TextColor3 = COLOR.dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, bar)
	make("UITextSizeConstraint", { MaxTextSize = 40 }, combo)

	return {
		frame = bar,
		score = score,
		time = timeLabel,
		timeFill = timeFill,
		combo = combo,
	}
end

local function buildTicket(parent: Instance, slot: number, onSelect: (number) -> ())
	local ticket = make("TextButton", {
		Name = "Ticket" .. slot,
		BackgroundColor3 = COLOR.panel,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = slot,
		Size = UDim2.fromScale(0.235, 1),
		Visible = false,
	}, parent)
	corner(ticket, 10)
	local ticketStroke = stroke(ticket, COLOR.stroke, 2)

	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, ticket)

	local slotBadge = make("TextLabel", {
		Name = "Slot",
		BackgroundColor3 = COLOR.panelHi,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(26, 26),
		Font = Enum.Font.GothamBold,
		Text = tostring(slot),
		TextColor3 = COLOR.dim,
		TextSize = 15,
	}, ticket)
	corner(slotBadge, 6)

	local title = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -34, 0, 26),
		Font = Enum.Font.GothamBold,
		Text = "Cheeseburger",
		TextColor3 = COLOR.text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, ticket)

	local list = make("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -56),
	}, ticket)

	make("UIListLayout", {
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	local rows = {}
	for index = 1, MAX_INGREDIENT_ROWS do
		local row = make("Frame", {
			Name = "Row" .. index,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 22),
			Visible = false,
		}, list)

		local keyBadge = make("TextLabel", {
			Name = "Key",
			BackgroundColor3 = COLOR.panelHi,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(22, 22),
			Font = Enum.Font.GothamBold,
			Text = "Q",
			TextColor3 = COLOR.text,
			TextSize = 13,
		}, row)
		corner(keyBadge, 5)

		local name = make("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(28, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Font = Enum.Font.GothamMedium,
			Text = "Bottom Bun",
			TextColor3 = COLOR.text,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)

		rows[index] = { frame = row, key = keyBadge, name = name }
	end

	local patienceTrack = make("Frame", {
		Name = "PatienceTrack",
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 8),
	}, ticket)
	corner(patienceTrack, 4)

	local patienceFill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLOR.good,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, patienceTrack)
	corner(patienceFill, 4)

	ticket.Activated:Connect(function()
		onSelect(slot)
	end)

	return {
		frame = ticket,
		stroke = ticketStroke,
		slotBadge = slotBadge,
		title = title,
		rows = rows,
		patienceFill = patienceFill,
		orderId = nil :: number?,
		expiresAt = 0,
		createdAt = 0,
	}
end

local function buildOrderRail(parent: Instance, onSelect: (number) -> ())
	local rail = make("Frame", {
		Name = "OrderRail",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.115),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.96, 0.33),
	}, parent)

	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, rail)

	local tickets = {}
	for slot = 1, Config.MAX_ORDER_SLOTS do
		tickets[slot] = buildTicket(rail, slot, onSelect)
	end

	local empty = make("TextLabel", {
		Name = "Empty",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamMedium,
		Text = "no customers yet",
		TextColor3 = COLOR.dim,
		TextSize = 18,
		Visible = false,
	}, rail)

	return { frame = rail, tickets = tickets, empty = empty }
end

local function buildPlate(parent: Instance)
	local plate = make("Frame", {
		Name = "Plate",
		BackgroundColor3 = COLOR.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.465),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.96, 0.115),
	}, parent)
	corner(plate, 10)

	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.fromOffset(120, 18),
		Font = Enum.Font.GothamBold,
		Text = "PLATE  0/0",
		TextColor3 = COLOR.dim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, plate)

	local strip = make("Frame", {
		Name = "Strip",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 28),
		Size = UDim2.new(1, -28, 1, -40),
	}, plate)

	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, strip)

	local chips = {}
	for index = 1, MAX_BUILD_CHIPS do
		local chip = make("TextLabel", {
			Name = "Chip" .. index,
			BackgroundColor3 = COLOR.panelHi,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.fromOffset(104, 30),
			Font = Enum.Font.GothamMedium,
			Text = "",
			TextColor3 = COLOR.bg,
			TextSize = 13,
			Visible = false,
		}, strip)
		corner(chip, 6)
		chips[index] = chip
	end

	return { frame = plate, label = label, chips = chips }
end

local function buildKeyGrid(parent: Instance, onKey: (string) -> ())
	local grid = make("Frame", {
		Name = "KeyGrid",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.6),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.7, 0.26),
	}, parent)

	make("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, grid)

	local buttons = {}

	for rowIndex, keys in KEY_ROWS do
		local row = make("Frame", {
			Name = "Row" .. rowIndex,
			BackgroundTransparency = 1,
			LayoutOrder = rowIndex,
			Size = UDim2.new(1, 0, 0.5, -5),
		}, grid)

		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, row)

		for keyIndex, key in keys do
			local button = make("TextButton", {
				Name = key,
				BackgroundColor3 = COLOR.panel,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				LayoutOrder = keyIndex,
				Size = UDim2.fromScale(0.185, 1),
				Text = "",
			}, row)
			corner(button, 8)
			local buttonStroke = stroke(button, COLOR.stroke, 2)

			local letter = make("TextLabel", {
				Name = "Letter",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0, 0.1),
				Size = UDim2.fromScale(1, 0.45),
				Font = Enum.Font.GothamBold,
				Text = key,
				TextColor3 = COLOR.text,
				TextScaled = true,
			}, button)
			make("UITextSizeConstraint", { MaxTextSize = 30 }, letter)

			local name = make("TextLabel", {
				Name = "Ingredient",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.05, 0.6),
				Size = UDim2.fromScale(0.9, 0.3),
				Font = Enum.Font.GothamMedium,
				Text = "",
				TextColor3 = COLOR.dim,
				TextScaled = true,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, button)
			make("UITextSizeConstraint", { MaxTextSize = 13 }, name)

			button.Activated:Connect(function()
				onKey(key)
			end)

			buttons[key] = {
				button = button,
				stroke = buttonStroke,
				letter = letter,
				name = name,
			}
		end
	end

	return { frame = grid, buttons = buttons }
end

local function buildActionBar(parent: Instance, onServe: () -> (), onScrap: () -> ())
	local bar = make("Frame", {
		Name = "ActionBar",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.88),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.7, 0.09),
	}, parent)

	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, bar)

	local function actionButton(name: string, text: string, color: Color3, order: number, callback: () -> ())
		local button = make("TextButton", {
			Name = name,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			LayoutOrder = order,
			Size = UDim2.fromScale(0.36, 1),
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = COLOR.bg,
			TextScaled = true,
		}, bar)
		corner(button, 8)
		make("UITextSizeConstraint", { MaxTextSize = 24 }, button)
		button.Activated:Connect(callback)
		return button
	end

	local serve = actionButton("Serve", "SERVE  [space]", COLOR.good, 1, onServe)
	local scrap = actionButton("Scrap", "SCRAP  [x]", COLOR.bad, 2, onScrap)

	return { frame = bar, serve = serve, scrap = scrap }
end

local function buildOverlay(parent: Instance, onStart: () -> ())
	local overlay = make("Frame", {
		Name = "Overlay",
		BackgroundColor3 = COLOR.bg,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = true,
		ZIndex = 10,
	}, parent)

	local title = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.24),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.8, 0.12),
		Font = Enum.Font.GothamBold,
		Text = "SECTOR 7 FOOD COURT",
		TextColor3 = COLOR.text,
		TextScaled = true,
		ZIndex = 11,
	}, overlay)
	make("UITextSizeConstraint", { MaxTextSize = 48 }, title)

	local body = make("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.38),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.7, 0.26),
		Font = Enum.Font.GothamMedium,
		Text = "connecting to the station...",
		TextColor3 = COLOR.dim,
		TextSize = 18,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 11,
	}, overlay)

	local start = make("TextButton", {
		Name = "Start",
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.5, 0.7),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.26, 0.09),
		Font = Enum.Font.GothamBold,
		Text = "START SHIFT  [E]",
		TextColor3 = COLOR.bg,
		TextScaled = true,
		ZIndex = 11,
	}, overlay)
	corner(start, 8)
	make("UITextSizeConstraint", { MaxTextSize = 24 }, start)
	start.Activated:Connect(onStart)

	return { frame = overlay, title = title, body = body, start = start }
end

local function buildFlash(parent: Instance)
	local flash = make("TextLabel", {
		Name = "Flash",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.1),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.perfect,
		TextScaled = true,
		TextTransparency = 1,
		ZIndex = 9,
	}, parent)
	make("UITextSizeConstraint", { MaxTextSize = 56 }, flash)
	return flash
end

-- Public: assemble the whole screen. `callbacks` wires both keyboard and touch.
function UI.build(playerGui: Instance, callbacks): any
	local screen = make("ScreenGui", {
		Name = "AlienFoodCourt",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	local root = make("Frame", {
		Name = "Root",
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, screen)

	local refs = {
		screen = screen,
		root = root,
		topBar = buildTopBar(root),
		rail = buildOrderRail(root, callbacks.onSelect),
		plate = buildPlate(root),
		keyGrid = buildKeyGrid(root, callbacks.onKey),
		actionBar = buildActionBar(root, callbacks.onServe, callbacks.onScrap),
		overlay = buildOverlay(root, callbacks.onStart),
		flash = buildFlash(root),
	}

	return refs
end

-- ---------------------------------------------------------------- render ---

local IDLE_BODY = table.concat({
	"You have been abducted. The locals are curious about Earth food.",
	"",
	"1-4 . select a ticket        Q W E R T / A S D F G . add ingredient",
	"SPACE . serve                X . scrap the plate",
	"",
	"Build each ticket in the order listed, top to bottom.",
}, "\n")

-- Called on every snapshot from the server.
function UI.render(refs, snapshot)
	local state = snapshot.state

	-- Overlay ---------------------------------------------------------------
	refs.overlay.frame.Visible = state ~= "Service"

	if state == "Idle" then
		refs.overlay.title.Text = "SECTOR 7 FOOD COURT"
		refs.overlay.body.Text = IDLE_BODY
		refs.overlay.start.Text = "START SHIFT  [E]"
	elseif state == "Results" then
		local stats = snapshot.stats
		refs.overlay.title.Text = string.format("SHIFT OVER . %d c", snapshot.score)
		refs.overlay.body.Text = table.concat({
			string.format("Perfect %d      Good %d      Sloppy %d", stats.perfect, stats.good, stats.sloppy),
			string.format("Wrong order %d      Walked out %d", stats.failed, stats.expired),
			"",
			string.format("Best combo  x%d", snapshot.bestCombo),
		}, "\n")
		refs.overlay.start.Text = "CONTINUE  [E]"
	end

	-- Top bar ---------------------------------------------------------------
	refs.topBar.score.Text = string.format("%d c", snapshot.score)
	refs.topBar.combo.Text = string.format("x%.2f", snapshot.comboMult)
	refs.topBar.combo.TextColor3 = if snapshot.combo > 0 then COLOR.perfect else COLOR.dim

	-- Tickets ---------------------------------------------------------------
	local orders = snapshot.orders
	refs.rail.empty.Visible = state == "Service" and #orders == 0

	for slot = 1, Config.MAX_ORDER_SLOTS do
		local ticket = refs.rail.tickets[slot]
		local order = orders[slot]

		if not order then
			ticket.frame.Visible = false
			ticket.orderId = nil
			continue
		end

		local dish = DishDefs.get(order.dishId)
		local isActive = order.id == snapshot.activeOrderId

		ticket.frame.Visible = true
		ticket.orderId = order.id
		ticket.expiresAt = order.expiresAt
		ticket.createdAt = order.createdAt
		ticket.title.Text = dish and dish.displayName or order.dishId

		ticket.stroke.Color = if isActive then COLOR.accent else COLOR.stroke
		ticket.stroke.Thickness = if isActive then 3 else 2
		ticket.slotBadge.TextColor3 = if isActive then COLOR.accent else COLOR.dim

		local built = if isActive then #snapshot.build else 0

		for index = 1, MAX_INGREDIENT_ROWS do
			local row = ticket.rows[index]
			local ingredientId = order.required[index]

			if not ingredientId then
				row.frame.Visible = false
				continue
			end

			row.frame.Visible = true
			row.key.Text = order.keys[index]
			row.name.Text = DishDefs.ingredientName(ingredientId)

			-- Only the selected ticket shows build progress: done, next, pending.
			if index <= built then
				row.key.BackgroundColor3 = COLOR.good
				row.key.TextColor3 = COLOR.bg
				row.name.TextColor3 = COLOR.dim
			elseif isActive and index == built + 1 then
				row.key.BackgroundColor3 = COLOR.accent
				row.key.TextColor3 = COLOR.bg
				row.name.TextColor3 = COLOR.text
			else
				row.key.BackgroundColor3 = COLOR.panelHi
				row.key.TextColor3 = COLOR.text
				row.name.TextColor3 = COLOR.text
			end
		end
	end

	-- Plate -----------------------------------------------------------------
	local activeOrder = nil
	for _, order in orders do
		if order.id == snapshot.activeOrderId then
			activeOrder = order
			break
		end
	end

	local total = if activeOrder then #activeOrder.required else 0
	refs.plate.label.Text = string.format("PLATE  %d/%d", #snapshot.build, total)

	for index = 1, MAX_BUILD_CHIPS do
		local chip = refs.plate.chips[index]
		local ingredientId = snapshot.build[index]
		if ingredientId then
			chip.Visible = true
			chip.Text = DishDefs.ingredientName(ingredientId)
			chip.BackgroundColor3 = DishDefs.ingredientColor(ingredientId)
		else
			chip.Visible = false
		end
	end

	-- Key grid --------------------------------------------------------------
	-- Relabelled per selected dish. The player still has to map ingredient to
	-- key themselves -- we never highlight the answer on the keys.
	local dish = if activeOrder then DishDefs.get(activeOrder.dishId) else nil
	local keyToName = {}
	if dish then
		for _, component in dish.components do
			keyToName[component.key] = DishDefs.ingredientName(component.id)
		end
	end

	for key, entry in refs.keyGrid.buttons do
		local name = keyToName[key]
		if name then
			entry.name.Text = name
			entry.letter.TextColor3 = COLOR.text
			entry.button.BackgroundColor3 = COLOR.panel
			entry.stroke.Color = COLOR.stroke
		else
			entry.name.Text = ""
			entry.letter.TextColor3 = COLOR.stroke
			entry.button.BackgroundColor3 = COLOR.bg
			entry.stroke.Color = COLOR.bg
		end
	end
end

-- Called every frame: smooth bars, interpolated locally off server timestamps
-- so nothing depends on tick rate.
function UI.renderTimers(refs, snapshot)
	if not snapshot then
		return
	end

	local clock = workspace:GetServerTimeNow()

	local remaining = math.max(0, snapshot.shiftEndsAt - clock)
	refs.topBar.time.Text = formatTime(remaining)
	refs.topBar.timeFill.Size = UDim2.fromScale(
		math.clamp(remaining / snapshot.shiftDuration, 0, 1), 1
	)

	for slot = 1, Config.MAX_ORDER_SLOTS do
		local ticket = refs.rail.tickets[slot]
		if ticket.frame.Visible and ticket.orderId then
			local span = ticket.expiresAt - ticket.createdAt
			local left = math.clamp((ticket.expiresAt - clock) / math.max(span, 0.001), 0, 1)
			ticket.patienceFill.Size = UDim2.fromScale(left, 1)
			ticket.patienceFill.BackgroundColor3 = patienceColor(left)
		end
	end
end

-- ----------------------------------------------------------------- juice ---

local GRADE_COLOR = {
	Perfect = COLOR.perfect,
	Good = COLOR.good,
	Sloppy = COLOR.warn,
	Fail = COLOR.bad,
}

function UI.flash(refs, text: string, color: Color3)
	local label = refs.flash
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.Position = UDim2.fromScale(0.5, 0.42)

	TweenService:Create(label, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.37),
	}):Play()
end

function UI.flashGrade(refs, event)
	local color = GRADE_COLOR[event.grade] or COLOR.text
	local text = if event.grade == "Fail"
		then "WRONG ORDER"
		else string.format("%s  +%d", string.upper(event.grade), event.value)
	UI.flash(refs, text, color)
end

-- Brief red pulse on the key that was fumbled.
function UI.flashKey(refs, key: string)
	local entry = refs.keyGrid.buttons[key]
	if not entry then
		return
	end
	entry.stroke.Color = COLOR.bad
	TweenService:Create(entry.stroke, TweenInfo.new(0.35), { Color = COLOR.stroke }):Play()
end

UI.COLOR = COLOR

return UI
