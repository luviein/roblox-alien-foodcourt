--!strict
-- The 2D layer. Tickets now ride above the customers' heads in 3D and the
-- order is built on a real plate, so this is down to the HUD: score, clock,
-- combo, the key grid, and the between-shift screens.
--
-- Every on-screen button fires the same callback as its keyboard key, so
-- touch works without a separate code path.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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

-- ---------------------------------------------------------------- helpers --

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

-- ------------------------------------------------------------------ build --

local function buildTopBar(parent: Instance)
	local bar = make("Frame", {
		Name = "TopBar",
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.015),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.5, 0.075),
	}, parent)
	corner(bar, 10)

	local score = make("TextLabel", {
		Name = "Score",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.03, 0),
		Size = UDim2.fromScale(0.3, 1),
		Font = Enum.Font.GothamBold,
		Text = "0 c",
		TextColor3 = COLOR.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, bar)
	make("UITextSizeConstraint", { MaxTextSize = 34 }, score)

	local timeLabel = make("TextLabel", {
		Name = "Time",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.35, 0.1),
		Size = UDim2.fromScale(0.3, 0.5),
		Font = Enum.Font.GothamBold,
		Text = "3:00",
		TextColor3 = COLOR.text,
		TextScaled = true,
	}, bar)
	make("UITextSizeConstraint", { MaxTextSize = 30 }, timeLabel)

	local timeTrack = make("Frame", {
		Name = "TimeTrack",
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.35, 0.68),
		Size = UDim2.fromScale(0.3, 0.14),
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
		Position = UDim2.fromScale(0.67, 0),
		Size = UDim2.fromScale(0.3, 1),
		Font = Enum.Font.GothamBold,
		Text = "x1.00",
		TextColor3 = COLOR.dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, bar)
	make("UITextSizeConstraint", { MaxTextSize = 34 }, combo)

	return { frame = bar, score = score, time = timeLabel, timeFill = timeFill, combo = combo }
end

local function buildPlateReadout(parent: Instance)
	local label = make("TextLabel", {
		Name = "PlateReadout",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.585),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.4, 0.045),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.dim,
		TextScaled = true,
	}, parent)
	make("UITextSizeConstraint", { MaxTextSize = 20 }, label)
	return label
end

local function buildKeyGrid(parent: Instance, onKey: (string) -> ())
	local grid = make("Frame", {
		Name = "KeyGrid",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.645),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.56, 0.2),
	}, parent)

	make("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, grid)

	local buttons = {}

	for rowIndex, keys in KEY_ROWS do
		local row = make("Frame", {
			Name = "Row" .. rowIndex,
			BackgroundTransparency = 1,
			LayoutOrder = rowIndex,
			Size = UDim2.new(1, 0, 0.5, -4),
		}, grid)

		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, row)

		for keyIndex, key in keys do
			local button = make("TextButton", {
				Name = key,
				BackgroundColor3 = COLOR.panel,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				LayoutOrder = keyIndex,
				Size = UDim2.fromScale(0.188, 1),
				Text = "",
			}, row)
			corner(button, 8)
			local buttonStroke = stroke(button, COLOR.stroke, 2)

			local swatch = make("Frame", {
				Name = "Swatch",
				BackgroundColor3 = COLOR.stroke,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.1),
				AnchorPoint = Vector2.new(0.5, 0),
				Size = UDim2.fromScale(0.5, 0.16),
			}, button)
			corner(swatch, 3)

			local letter = make("TextLabel", {
				Name = "Letter",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0, 0.28),
				Size = UDim2.fromScale(1, 0.4),
				Font = Enum.Font.GothamBold,
				Text = key,
				TextColor3 = COLOR.text,
				TextScaled = true,
			}, button)
			make("UITextSizeConstraint", { MaxTextSize = 26 }, letter)

			local name = make("TextLabel", {
				Name = "Ingredient",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.05, 0.69),
				Size = UDim2.fromScale(0.9, 0.24),
				Font = Enum.Font.GothamMedium,
				Text = "",
				TextColor3 = COLOR.dim,
				TextScaled = true,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, button)
			make("UITextSizeConstraint", { MaxTextSize = 12 }, name)

			button.Activated:Connect(function()
				onKey(key)
			end)

			buttons[key] = {
				button = button,
				stroke = buttonStroke,
				letter = letter,
				name = name,
				swatch = swatch,
			}
		end
	end

	return { frame = grid, buttons = buttons }
end

local function buildActionBar(parent: Instance, onServe: () -> (), onScrap: () -> ())
	local bar = make("Frame", {
		Name = "ActionBar",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.865),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.56, 0.075),
	}, parent)

	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
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
		make("UITextSizeConstraint", { MaxTextSize = 20 }, button)
		button.Activated:Connect(callback)
		return button
	end

	return {
		frame = bar,
		serve = actionButton("Serve", "SERVE  [space]", COLOR.good, 1, onServe),
		scrap = actionButton("Scrap", "SCRAP  [x]", COLOR.bad, 2, onScrap),
	}
end

local function buildOverlay(parent: Instance, onStart: () -> ())
	local overlay = make("Frame", {
		Name = "Overlay",
		BackgroundColor3 = COLOR.bg,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = true,
		ZIndex = 10,
	}, parent)

	local title = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.22),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.8, 0.12),
		Font = Enum.Font.GothamBold,
		Text = "SECTOR 7 FOOD COURT",
		TextColor3 = COLOR.text,
		TextScaled = true,
		ZIndex = 11,
	}, overlay)
	make("UITextSizeConstraint", { MaxTextSize = 46 }, title)

	local body = make("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.37),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.7, 0.28),
		Font = Enum.Font.GothamMedium,
		Text = "connecting to the station...",
		TextColor3 = COLOR.dim,
		TextSize = 17,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 11,
	}, overlay)

	local start = make("TextButton", {
		Name = "Start",
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.5, 0.72),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.26, 0.085),
		Font = Enum.Font.GothamBold,
		Text = "START SHIFT  [E]",
		TextColor3 = COLOR.bg,
		TextScaled = true,
		ZIndex = 11,
	}, overlay)
	corner(start, 8)
	make("UITextSizeConstraint", { MaxTextSize = 22 }, start)
	start.Activated:Connect(onStart)

	return { frame = overlay, title = title, body = body, start = start }
end

local function buildFlash(parent: Instance)
	local flash = make("TextLabel", {
		Name = "Flash",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.46),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.1),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.perfect,
		TextScaled = true,
		TextStrokeColor3 = COLOR.bg,
		TextStrokeTransparency = 0.2,
		TextTransparency = 1,
		ZIndex = 9,
	}, parent)
	make("UITextSizeConstraint", { MaxTextSize = 52 }, flash)
	return flash
end

function UI.build(playerGui: Instance, callbacks): any
	local screen = make("ScreenGui", {
		Name = "AlienFoodCourt",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	-- Transparent: the 3D stall shows through everything below.
	local root = make("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, screen)

	return {
		screen = screen,
		root = root,
		topBar = buildTopBar(root),
		plateReadout = buildPlateReadout(root),
		keyGrid = buildKeyGrid(root, callbacks.onKey),
		actionBar = buildActionBar(root, callbacks.onServe, callbacks.onScrap),
		overlay = buildOverlay(root, callbacks.onStart),
		flash = buildFlash(root),
	}
end

-- ----------------------------------------------------------------- render --

local IDLE_BODY = table.concat({
	"You have been abducted. The locals are curious about Earth food.",
	"",
	"1-4 . select a customer        Q W E R T / A S D F G . add ingredient",
	"SPACE . serve                  X . scrap the plate",
	"",
	"Build each order top to bottom, in the order listed on their ticket.",
}, "\n")

function UI.render(refs, snapshot)
	local state = snapshot.state

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

	refs.topBar.score.Text = string.format("%d c", snapshot.score)
	refs.topBar.combo.Text = string.format("x%.2f", snapshot.comboMult)
	refs.topBar.combo.TextColor3 = if snapshot.combo > 0 then COLOR.perfect else COLOR.dim

	-- Which order is selected drives the key labels and the plate readout.
	local activeOrder = nil
	for _, order in snapshot.orders do
		if order.id == snapshot.activeOrderId then
			activeOrder = order
			break
		end
	end

	-- Fried orders have no plate. The readout carries the cook prompt instead,
	-- and while it is counting down renderTimers owns the text -- writing it
	-- from both places is what made it flicker.
	local cookState = activeOrder and activeOrder.cookState

	if cookState == "raw" then
		refs.plateReadout.Text = "SPACE to start frying"
	elseif cookState == "burnt" then
		refs.plateReadout.Text = "BURNT   SPACE to bin it"
	elseif cookState ~= "cooking" and cookState ~= "ready" then
		local total = if activeOrder then #activeOrder.required else 0
		refs.plateReadout.Text = if state == "Service" and total > 0
			then string.format("PLATE  %d / %d", #snapshot.build, total)
			else ""
	end

	local dish = if activeOrder then DishDefs.get(activeOrder.dishId) else nil
	local keyToIngredient = {}
	if dish and dish.components then
		for _, component in dish.components do
			keyToIngredient[component.key] = component.id
		end
	end

	for key, entry in refs.keyGrid.buttons do
		local ingredientId = keyToIngredient[key]
		if ingredientId then
			entry.name.Text = DishDefs.ingredientName(ingredientId)
			entry.swatch.BackgroundColor3 = DishDefs.ingredientColor(ingredientId)
			entry.swatch.BackgroundTransparency = 0
			entry.letter.TextColor3 = COLOR.text
			entry.button.BackgroundTransparency = 0.15
			entry.stroke.Color = COLOR.stroke
		else
			entry.name.Text = ""
			entry.swatch.BackgroundTransparency = 1
			entry.letter.TextColor3 = COLOR.stroke
			entry.button.BackgroundTransparency = 0.55
			entry.stroke.Color = COLOR.panel
		end
	end
end

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

	-- The fry prompt counts down every frame rather than every snapshot: a
	-- timer that visibly stutters is worse than no timer. render() leaves this
	-- label alone while cooking so the two never fight over it -- them both
	-- writing it is what made the text flicker.
	local active = nil
	for _, order in snapshot.orders do
		if order.id == snapshot.activeOrderId then
			active = order
			break
		end
	end

	if not active or not active.cookState then
		return
	end

	if active.cookState == "cooking" then
		refs.plateReadout.Text = string.format("FRYING   %.1fs", math.max(0, active.readyAt - clock))
	elseif active.cookState == "ready" then
		-- Counts down to burning, so the number on screen is the danger.
		refs.plateReadout.Text = string.format("READY   SPACE to serve   %.1fs", math.max(0, active.burnAt - clock))
	end
end

-- ------------------------------------------------------------------ juice --

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
	label.Position = UDim2.fromScale(0.5, 0.46)

	TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.40),
	}):Play()
end

function UI.flashGrade(refs, event)
	local color = GRADE_COLOR[event.grade] or COLOR.text
	local text = if event.grade == "Fail"
		then "WRONG ORDER"
		else string.format("%s  +%d", string.upper(event.grade), event.value)
	UI.flash(refs, text, color)
end

-- Green pulse for a good keypress, red for a fumble.
function UI.pulseKey(refs, key: string, ok: boolean)
	local entry = refs.keyGrid.buttons[key]
	if not entry then
		return
	end

	local hit = if ok then COLOR.good else COLOR.bad
	entry.stroke.Color = hit
	entry.stroke.Thickness = 3

	TweenService:Create(entry.stroke, TweenInfo.new(0.28), {
		Color = COLOR.stroke,
		Thickness = 2,
	}):Play()
end

UI.COLOR = COLOR

return UI
