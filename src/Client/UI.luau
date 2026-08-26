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
local ChoreDefs = require(Shared.ChoreDefs)
local DailyDefs = require(Shared.DailyDefs)
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

-- Side rail icons are square and measured in pixels, so they stay the same
-- physical size whatever the screen is.
local RAIL_ICON = 74

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

-- How busy the counter is right now, and which third of the day it belongs to.
--
-- Hype was until now completely invisible during service: it decided how often
-- anyone walked in, and the player had no way to tell a quiet counter apart
-- from a broken one. The bar reads against a FULL house rather than against
-- the player's own base, so a new player sees a mostly empty track. That is
-- the honest picture, and the empty part is what a better menu buys.
--
-- Hype is recomputed per phase, so this changes at the two phase boundaries;
-- the delta label calls out which way it went, because a menu that earns its
-- keep only in the morning is otherwise impossible to notice.
local function buildHypeMeter(parent: Instance)
	local frame = make("Frame", {
		Name = "HypeMeter",
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.098),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.24, 0.05),
		Visible = false,
	}, parent)
	corner(frame, 8)

	local phase = make("TextLabel", {
		Name = "Phase",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.5, 0.5),
		Font = Enum.Font.GothamBold,
		Text = "MORNING",
		TextColor3 = COLOR.dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)
	make("UITextSizeConstraint", { MaxTextSize = 15 }, phase)

	local value = make("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.45, 0.06),
		Size = UDim2.fromScale(0.5, 0.5),
		Font = Enum.Font.GothamBold,
		Text = "HYPE 25%",
		TextColor3 = COLOR.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, frame)
	make("UITextSizeConstraint", { MaxTextSize = 15 }, value)

	local track = make("Frame", {
		Name = "Track",
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.05, 0.66),
		Size = UDim2.fromScale(0.9, 0.16),
	}, frame)
	corner(track, 3)

	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.3, 1),
	}, track)
	corner(fill, 3)

	-- Sits just under the meter and only appears at a phase boundary.
	local delta = make("TextLabel", {
		Name = "Delta",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 1.05),
		Size = UDim2.fromScale(1, 0.7),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.good,
		TextScaled = true,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, frame)
	make("UITextSizeConstraint", { MaxTextSize = 15 }, delta)

	return {
		frame = frame,
		phase = phase,
		value = value,
		fill = fill,
		delta = delta,
		-- Last rendered values, so a phase boundary can be spotted and named.
		-- Declared here rather than assigned on first use so the shape of this
		-- table is honest under --!strict.
		lastPhase = nil :: string?,
		lastHype = nil :: number?,
	}
end

local function buildPlateReadout(parent: Instance)
	local label = make("TextLabel", {
		Name = "PlateReadout",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.16),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.7, 0.1),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.dim,
		TextScaled = true,
	}, parent)
	make("UITextSizeConstraint", { MaxTextSize = 20 }, label)
	return label
end

-- The sear meter: a bar that fills while the key is held, with the target band
-- drawn on it. The band has to be visible before you start holding, otherwise
-- the first steak of every session is a guess.
local function buildSearMeter(parent: Instance)
	local track = make("Frame", {
		Name = "SearMeter",
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.155),
		Size = UDim2.fromScale(0.8, 0.1),
		Visible = false,
	}, parent)
	corner(track, 6)

	-- Drawn under the fill so the fill visibly crosses into it.
	local band = make("Frame", {
		Name = "Band",
		BackgroundColor3 = COLOR.good,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.25, 1),
		Position = UDim2.fromScale(0.6, 0),
	}, track)

	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLOR.warn,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}, track)
	corner(fill, 6)

	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.text,
		TextScaled = true,
		ZIndex = 3,
	}, track)
	make("UITextSizeConstraint", { MaxTextSize = 16 }, label)

	return { track = track, band = band, fill = fill, label = label }
end

local function buildKeyGrid(parent: Instance, onKey: (string) -> ())
	local grid = make("Frame", {
		Name = "KeyGrid",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.9, 0.44),
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
		Position = UDim2.fromScale(0.5, 0.97),
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromScale(0.9, 0.17),
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
		Text = "PLAN THE DAY  [E]",
		TextColor3 = COLOR.bg,
		TextScaled = true,
		ZIndex = 11,
	}, overlay)
	corner(start, 8)
	make("UITextSizeConstraint", { MaxTextSize = 22 }, start)
	start.Activated:Connect(onStart)

	-- Only reachable between shifts, which is also the only time the server
	-- accepts a purchase. Spending mid-service would change the loadout under
	-- a running shift.
	local shop = make("TextButton", {
		Name = "Shop",
		BackgroundColor3 = COLOR.panelHi,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.5, 0.82),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.26, 0.07),
		Font = Enum.Font.GothamBold,
		Text = "SUPPLY DEPOT",
		TextColor3 = COLOR.text,
		TextScaled = true,
		ZIndex = 11,
	}, overlay)
	corner(shop, 8)
	make("UITextSizeConstraint", { MaxTextSize = 18 }, shop)

	-- Anchored to its own BOTTOM against a point above the screen edge, so the
	-- label can never run off the bottom the way a top-anchored one did.
	local cash = make("TextLabel", {
		Name = "Cash",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.955),
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromScale(0.4, 0.05),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.perfect,
		TextScaled = true,
		ZIndex = 11,
	}, overlay)
	make("UITextSizeConstraint", { MaxTextSize = 20 }, cash)

	return {
		frame = overlay,
		title = title,
		body = body,
		start = start,
		shop = shop,
		cash = cash,
	}
end

-- The side rail: the strip of round buttons down the left edge, which is where
-- a Roblox player's hand already goes looking for this sort of thing.
--
-- Parented to the root rather than to the overlay so it stays reachable during
-- a shift as well as between them. It holds one button today; anything else
-- that wants a permanent home on screen goes in the same column.
local function buildSideRail(parent: Instance)
	-- Sized in PIXELS, not scale. A scale width plus a UIAspectRatioConstraint
	-- resolved to zero height inside the list layout and the whole rail
	-- rendered as nothing. An icon rail wants to be the same physical size on
	-- every screen anyway, which is what offset gives.
	local rail = make("Frame", {
		Name = "SideRail",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0.28, 0),
		Size = UDim2.new(0, RAIL_ICON, 0, 420),
		ZIndex = 12,
	}, parent)

	local layout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	}, rail)
	layout.Name = "Layout"

	return rail
end

-- One button on the side rail, drawn as a clipboard.
--
-- Built out of frames rather than an uploaded image: an image asset has to be
-- moderated before it renders, and a button that is invisible for a day is
-- worse than one drawn in primitives. The shape is a pale sheet with a darker
-- header strip and three ruled lines.
local function buildRailButton(parent: Instance, label: string, order: number)
	local button = make("TextButton", {
		Name = label,
		BackgroundColor3 = COLOR.panel,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Size = UDim2.fromOffset(RAIL_ICON, RAIL_ICON),
		ZIndex = 12,
	}, parent)
	corner(button, 12)
	stroke(button, COLOR.stroke, 2)

	local sheet = make("Frame", {
		Name = "Sheet",
		BackgroundColor3 = Color3.fromRGB(238, 241, 248),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.22, 0.14),
		Size = UDim2.fromScale(0.56, 0.5),
		ZIndex = 13,
	}, button)
	corner(sheet, 4)

	local clip = make("Frame", {
		Name = "Clip",
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.3, -0.12),
		Size = UDim2.fromScale(0.4, 0.2),
		ZIndex = 14,
	}, sheet)
	corner(clip, 3)

	for line = 1, 3 do
		local ruled = make("Frame", {
			Name = "Line" .. line,
			BackgroundColor3 = Color3.fromRGB(150, 158, 176),
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.16, 0.26 + (line - 1) * 0.22),
			Size = UDim2.fromScale(if line == 3 then 0.42 else 0.68, 0.1),
			ZIndex = 14,
		}, sheet)
		corner(ruled, 2)
	end

	local caption = make("TextLabel", {
		Name = "Caption",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.68),
		Size = UDim2.fromScale(1, 0.24),
		Font = Enum.Font.GothamBold,
		Text = label,
		TextColor3 = COLOR.text,
		TextScaled = true,
		ZIndex = 14,
	}, button)
	make("UITextSizeConstraint", { MaxTextSize = 15 }, caption)

	-- The count of things waiting to be claimed. Hidden at zero, because a
	-- badge that is always there stops meaning anything.
	local badge = make("TextLabel", {
		Name = "Badge",
		BackgroundColor3 = COLOR.bad,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.72, -0.08),
		Size = UDim2.fromScale(0.42, 0.42),
		Font = Enum.Font.GothamBold,
		Text = "0",
		TextColor3 = COLOR.text,
		TextScaled = true,
		Visible = false,
		ZIndex = 15,
	}, button)
	corner(badge, 999)
	make("UITextSizeConstraint", { MaxTextSize = 16 }, badge)

	return {
		button = button,
		badge = badge,
		caption = caption,
		-- Set by UI.render. Declared here so the shape of this table is honest
		-- under --!strict, and true by default so the button works before the
		-- first snapshot lands.
		enabled = true,
	}
end

-- What is running right now and how long is left on it. Sits under the side
-- rail, on the left edge, where the daily panel that granted it also lives.
--
-- Boosts are the one thing in the game with a clock the player did not start,
-- so they need to be visible without opening anything -- otherwise a fifteen
-- minute prize quietly expires unnoticed and reads as never having worked.
local BOOST_ROWS = {
	{ key = "earnings", label = "EARNINGS", color = COLOR.perfect },
	{ key = "tips",     label = "TIPS",     color = COLOR.good },
}

local function buildBoostStrip(parent: Instance)
	-- Pinned in pixels under the rail, for the same reason the rail is.
	local frame = make("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0.28, RAIL_ICON + 14),
		Size = UDim2.new(0, 190, 0, 62),
		ZIndex = 12,
	}, parent)

	local rows = {}
	for index, spec in BOOST_ROWS do
		local row = make("Frame", {
			Name = spec.label,
			BackgroundColor3 = COLOR.panel,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, (index - 1) * 0.54),
			Size = UDim2.fromScale(1, 0.46),
			Visible = false,
			ZIndex = 12,
		}, frame)
		corner(row, 6)

		local pip = make("Frame", {
			Name = "Pip",
			BackgroundColor3 = spec.color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.04, 0.3),
			Size = UDim2.fromScale(0.05, 0.4),
			ZIndex = 13,
		}, row)
		corner(pip, 999)

		local label = make("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.13, 0.15),
			Size = UDim2.fromScale(0.55, 0.7),
			Font = Enum.Font.GothamBold,
			Text = spec.label,
			TextColor3 = spec.color,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 13,
		}, row)
		make("UITextSizeConstraint", { MaxTextSize = 14 }, label)

		local clock = make("TextLabel", {
			Name = "Clock",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.6, 0.15),
			Size = UDim2.fromScale(0.36, 0.7),
			Font = Enum.Font.GothamBold,
			Text = "",
			TextColor3 = COLOR.text,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 13,
		}, row)
		make("UITextSizeConstraint", { MaxTextSize = 14 }, clock)

		rows[spec.key] = { frame = row, label = label, clock = clock }
	end

	return { frame = frame, rows = rows }
end

local function renderBoosts(strip, profile)
	local boosts = profile and profile.boosts

	for _, spec in BOOST_ROWS do
		local row = strip.rows[spec.key]
		local slot = boosts and boosts[spec.key]
		local remaining = (slot and slot.remaining) or 0

		row.frame.Visible = remaining > 0
		if remaining > 0 then
			row.clock.Text = formatTime(remaining)

			-- The earnings boost rolls its strength when it is won, so the
			-- label has to carry the number: two players with this prize are
			-- not on the same rate.
			row.label.Text = if spec.key == "earnings" and slot.value
				then string.format("+%d%% CASH", math.floor((slot.value or 0) * 100 + 0.5))
				else spec.label
		end
	end
end

-- Forward declared. The daily button's click handler is built here but runs
-- much later, and renderDaily is defined further down the file next to the
-- other render functions. Without this declaration that reference would
-- resolve to a nil GLOBAL at runtime rather than failing to compile.
local renderDaily

-- The daily tasks panel.
--
-- A TextButton with no text rather than a Frame, because a plain Frame does not
-- absorb clicks and every one of them would land on the shade behind it.
local function buildDailyPanel(parent: Instance, onClaim: (number) -> (), onClose: () -> ())
	local shade = make("TextButton", {
		Name = "DailyShade",
		BackgroundColor3 = COLOR.bg,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
	}, parent)
	shade.Activated:Connect(onClose)

	local panel = make("TextButton", {
		Name = "Panel",
		BackgroundColor3 = COLOR.panel,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.56),
		ZIndex = 21,
	}, shade)
	corner(panel, 12)
	stroke(panel, COLOR.stroke, 2)

	local title = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.06, 0.05),
		Size = UDim2.fromScale(0.88, 0.1),
		Font = Enum.Font.GothamBold,
		Text = "DAILY TASKS",
		TextColor3 = COLOR.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, panel)
	make("UITextSizeConstraint", { MaxTextSize = 28 }, title)

	local date = make("TextLabel", {
		Name = "Date",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.06, 0.15),
		Size = UDim2.fromScale(0.88, 0.06),
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = COLOR.dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, panel)
	make("UITextSizeConstraint", { MaxTextSize = 16 }, date)

	-- One row per task. Built up front rather than on demand: three rows is a
	-- fixed number, and rebuilding instances every render is how you get a
	-- panel that flickers.
	local rows = {}
	for index = 1, DailyDefs.TASK_COUNT do
		local row = make("Frame", {
			Name = "Task" .. index,
			BackgroundColor3 = COLOR.panelHi,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.06, 0.23 + (index - 1) * 0.185),
			Size = UDim2.fromScale(0.88, 0.165),
			ZIndex = 22,
		}, panel)
		corner(row, 8)

		local goal = make("TextLabel", {
			Name = "Goal",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.04, 0.08),
			Size = UDim2.fromScale(0.62, 0.36),
			Font = Enum.Font.GothamBold,
			Text = "",
			TextColor3 = COLOR.text,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
		}, row)
		make("UITextSizeConstraint", { MaxTextSize = 17 }, goal)

		local count = make("TextLabel", {
			Name = "Count",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.04, 0.46),
			Size = UDim2.fromScale(0.4, 0.3),
			Font = Enum.Font.GothamMedium,
			Text = "",
			TextColor3 = COLOR.dim,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
		}, row)
		make("UITextSizeConstraint", { MaxTextSize = 14 }, count)

		local track = make("Frame", {
			Name = "Track",
			BackgroundColor3 = COLOR.bg,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.04, 0.8),
			Size = UDim2.fromScale(0.62, 0.1),
			ZIndex = 23,
		}, row)
		corner(track, 3)

		local fill = make("Frame", {
			Name = "Fill",
			BackgroundColor3 = COLOR.accent,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			ZIndex = 24,
		}, track)
		corner(fill, 3)

		local claim = make("TextButton", {
			Name = "Claim",
			BackgroundColor3 = COLOR.panel,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Position = UDim2.fromScale(0.7, 0.2),
			Size = UDim2.fromScale(0.26, 0.6),
			Font = Enum.Font.GothamBold,
			Text = "LOCKED",
			TextColor3 = COLOR.dim,
			TextScaled = true,
			ZIndex = 23,
		}, row)
		corner(claim, 6)
		make("UITextSizeConstraint", { MaxTextSize = 16 }, claim)
		claim.Activated:Connect(function()
			onClaim(index)
		end)

		rows[index] = {
			frame = row, goal = goal, count = count, fill = fill, claim = claim,
		}
	end

	-- Announces what the last claim rolled. Sits in the footer so it does not
	-- push the rows around when it appears.
	local prize = make("TextLabel", {
		Name = "Prize",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.06, 0.79),
		Size = UDim2.fromScale(0.88, 0.08),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.perfect,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, panel)
	make("UITextSizeConstraint", { MaxTextSize = 17 }, prize)

	local footer = make("TextLabel", {
		Name = "Footer",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.06, 0.87),
		Size = UDim2.fromScale(0.6, 0.07),
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = COLOR.dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, panel)
	make("UITextSizeConstraint", { MaxTextSize = 14 }, footer)

	local close = make("TextButton", {
		Name = "Close",
		BackgroundColor3 = COLOR.panelHi,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.7, 0.86),
		Size = UDim2.fromScale(0.24, 0.09),
		Font = Enum.Font.GothamBold,
		Text = "BACK",
		TextColor3 = COLOR.text,
		TextScaled = true,
		ZIndex = 22,
	}, panel)
	corner(close, 8)
	make("UITextSizeConstraint", { MaxTextSize = 18 }, close)
	close.Activated:Connect(onClose)

	return {
		shade = shade,
		panel = panel,
		title = title,
		date = date,
		rows = rows,
		prize = prize,
		footer = footer,
		close = close,

		-- Declared up front rather than assigned on first use, so the shape of
		-- this table is honest under --!strict. lastProfile lets the panel
		-- render the instant it opens; shownPrizeSerial stops the snapshot
		-- re-announcing the same win ten times a second.
		lastProfile = nil :: any,
		shownPrizeSerial = nil :: number?,
	}
end

-- The interrupt. Deliberately loud and deliberately in the middle of the
-- screen: a chore you can politely ignore is not an interruption, it is
-- decoration.
local function buildChoreBanner(parent: Instance, onClear: () -> ())
	local banner = make("TextButton", {
		Name = "Chore",
		BackgroundColor3 = COLOR.bad,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.115),
		Size = UDim2.fromScale(0.34, 0.1),
		Visible = false,
		ZIndex = 8,
	}, parent)
	corner(banner, 10)

	local title = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.04, 0.08),
		Size = UDim2.fromScale(0.92, 0.44),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.bg,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
	}, banner)
	make("UITextSizeConstraint", { MaxTextSize = 20 }, title)

	local prompt = make("TextLabel", {
		Name = "Prompt",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.04, 0.5),
		Size = UDim2.fromScale(0.92, 0.28),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.bg,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
	}, banner)
	make("UITextSizeConstraint", { MaxTextSize = 14 }, prompt)

	local track = make("Frame", {
		Name = "Track",
		BackgroundColor3 = COLOR.bg,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.94),
		Size = UDim2.fromScale(0.92, 0.1),
		ZIndex = 9,
	}, banner)
	corner(track, 3)

	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
	}, track)
	corner(fill, 3)

	banner.Activated:Connect(onClear)

	return { frame = banner, title = title, prompt = prompt, fill = fill }
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

	-- The prep panel is a modal: nothing to press until you have picked up an
	-- order. An empty key grid sitting there permanently invited pressing keys
	-- that were not attached to anything.
	local prep = make("Frame", {
		Name = "PrepPanel",
		BackgroundColor3 = COLOR.bg,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.985),
		Size = UDim2.fromScale(0.62, 0.42),
		Visible = false,
	}, root)
	corner(prep, 12)
	stroke(prep, COLOR.stroke, 2)

	local prepTitle = make("TextLabel", {
		Name = "PrepTitle",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.03),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.9, 0.11),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.text,
		TextScaled = true,
	}, prep)
	make("UITextSizeConstraint", { MaxTextSize = 22 }, prepTitle)

	-- Shown instead of the panel when nothing is in hand.
	local hint = make("TextLabel", {
		Name = "Hint",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.6, 0.06),
		Font = Enum.Font.GothamMedium,
		Text = "click a customer's order to start it",
		TextColor3 = COLOR.dim,
		TextScaled = true,
		Visible = false,
	}, root)
	make("UITextSizeConstraint", { MaxTextSize = 18 }, hint)

	local overlay = buildOverlay(root, callbacks.onStart)
	overlay.shop.Activated:Connect(callbacks.onOpenShop)

	local dailyPanel
	dailyPanel = buildDailyPanel(root, function(index)
		callbacks.onClaimDaily(index)
	end, function()
		dailyPanel.shade.Visible = false
	end)

	local rail = buildSideRail(root)
	local dailyButton = buildRailButton(rail, "DAILY", 1)
	local boostStrip = buildBoostStrip(root)

	-- Rendered on open rather than waiting for the next snapshot, so the panel
	-- never appears holding stale numbers for a tenth of a second.
	--
	-- Refuses to open mid-shift: the rail stays on screen during service so
	-- boost timers remain readable, but stopping to read task progress with
	-- four tickets going is not a thing to offer.
	dailyButton.button.Activated:Connect(function()
		if not dailyButton.enabled then
			return
		end
		renderDaily(dailyPanel, dailyPanel.lastProfile)
		dailyPanel.shade.Visible = true
	end)

	return {
		screen = screen,
		root = root,
		prep = prep,
		prepTitle = prepTitle,
		hint = hint,
		topBar = buildTopBar(root),
		hypeMeter = buildHypeMeter(root),
		rail = rail,
		dailyButton = dailyButton,
		dailyPanel = dailyPanel,
		boostStrip = boostStrip,
		plateReadout = buildPlateReadout(prep),
		searMeter = buildSearMeter(prep),
		keyGrid = buildKeyGrid(prep, callbacks.onKey),
		actionBar = buildActionBar(prep, callbacks.onServe, callbacks.onScrap),
		overlay = overlay,
		chore = buildChoreBanner(root, callbacks.onChore),
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

-- Today's challenge, drawn from DailyDefs rather than from a remote: the
-- challenge is a pure function of the date, so the client can work out what it
-- is on its own. Only the player's own record has to come from the server.
--
-- Whether the daily panel is up. The keyboard needs to ask, because E means
-- "start the day" outside a shift and must not fire straight through an open
-- panel -- matching how the draft and the shop already behave.
function UI.isDailyOpen(refs): boolean
	return refs.dailyPanel.shade.Visible
end

function UI.setDailyOpen(refs, open: boolean)
	refs.dailyPanel.shade.Visible = open
end

-- Assigned to the local forward declared near buildDailyPanel, above.
function renderDaily(panel, profile)
	if not profile then
		return
	end

	local status = profile.daily
	if not status then
		return
	end

	-- The date comes from the day number the SERVER sent, never from the
	-- client's own clock: a machine set a day fast would otherwise show a task
	-- list the server is not tracking.
	panel.date.Text = string.format(
		"%s  .  new tasks at midnight UTC",
		DailyDefs.dateString(status.day * 86400))

	for index, row in panel.rows do
		local task = status.tasks[index]
		if not task then
			row.frame.Visible = false
		else
			row.frame.Visible = true

			local goal = DailyDefs.describe(task)
			row.goal.Text = goal
			row.count.Text = string.format("%d / %d", task.progress, task.target)
			row.fill.Size = UDim2.fromScale(
				math.clamp(task.progress / math.max(task.target, 1), 0, 1), 1)

			-- Three states, and the button says which: nothing to do yet, a
			-- prize waiting, or already taken.
			if task.claimed then
				row.claim.Text = "CLAIMED"
				row.claim.BackgroundColor3 = COLOR.panel
				row.claim.TextColor3 = COLOR.dim
				row.fill.BackgroundColor3 = COLOR.dim
			elseif task.complete then
				row.claim.Text = "CLAIM"
				row.claim.BackgroundColor3 = COLOR.good
				row.claim.TextColor3 = COLOR.bg
				row.fill.BackgroundColor3 = COLOR.good
			else
				row.claim.Text = "LOCKED"
				row.claim.BackgroundColor3 = COLOR.panel
				row.claim.TextColor3 = COLOR.dim
				row.fill.BackgroundColor3 = COLOR.accent
			end
		end
	end

	local streak = status.streak or 0
	panel.footer.Text = if streak > 0
		then string.format("Progress counts from every shift.   Streak %d days", streak)
		else "Progress counts from every shift you play."

	-- Only announce a prize the player has not been shown yet. The snapshot
	-- repeats the last one ten times a second, so without the serial check
	-- this line would never clear.
	local won = profile.lastPrize
	if won and won.serial and won.serial ~= panel.shownPrizeSerial then
		panel.shownPrizeSerial = won.serial

		local minutes = math.floor((won.seconds or 0) / 60 + 0.5)
		if won.kind == "cash" then
			panel.prize.Text = string.format("%s  .  +%d c", won.name, won.amount)
		elseif won.effect == "earnings" then
			panel.prize.Text = string.format(
				"%s  .  +%d%% cash for %d min",
				won.name, math.floor((won.value or 0) * 100 + 0.5), minutes)
		elseif won.effect == "tips" then
			panel.prize.Text = string.format(
				"%s  .  customers tip for %d min", won.name, minutes)
		else
			panel.prize.Text = won.name
		end
	end
end

-- Declared above UI.render because that is the only thing that calls it, and a
-- local declared below its caller resolves to nil at runtime.
local function renderHype(meter, snapshot)
	-- Between shifts there is no live counter to describe, and the draft screen
	-- already shows the day's hype phase by phase.
	if snapshot.state ~= "Service" or snapshot.hype == nil then
		meter.frame.Visible = false
		meter.lastPhase = nil
		meter.lastHype = nil
		return
	end

	meter.frame.Visible = true

	local hype = snapshot.hype
	local phase = snapshot.phase or ""

	meter.phase.Text = string.upper(phase)
	meter.value.Text = string.format("HYPE %d%%", math.floor(hype * 100 + 0.5))
	meter.fill.Size = UDim2.fromScale(math.clamp(hype, 0, 1), 1)

	-- Hype only moves at a phase boundary, so this fires twice a shift at most.
	if meter.lastPhase and meter.lastPhase ~= phase and meter.lastHype then
		local change = hype - meter.lastHype
		if math.abs(change) >= 0.005 then
			local up = change > 0
			meter.delta.Text = string.format(
				"%s%d%% %s",
				(if up then "+" else "-"),
				math.floor(math.abs(change) * 100 + 0.5),
				(if up then "busier" else "quieter"))
			meter.delta.TextColor3 = if up then COLOR.good else COLOR.warn
			meter.delta.TextTransparency = 0

			TweenService:Create(
				meter.delta,
				TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2.2),
				{ TextTransparency = 1 }
			):Play()
		end
	end

	meter.lastPhase = phase
	meter.lastHype = hype
end

function UI.render(refs, snapshot)
	local state = snapshot.state

	refs.overlay.frame.Visible = state ~= "Service"

	if state == "Idle" then
		refs.overlay.title.Text = "SECTOR 7 FOOD COURT"
		refs.overlay.body.Text = IDLE_BODY
		refs.overlay.start.Text = "PLAN THE DAY  [E]"
	elseif state == "Results" then
		local stats = snapshot.stats
		refs.overlay.title.Text = string.format("SHIFT OVER . %d c", snapshot.score)
		if snapshot.profile and snapshot.profile.lastEarned then
			refs.overlay.title.Text = string.format(
				"SHIFT OVER . %d pts . +%d c",
				snapshot.score, snapshot.profile.lastEarned)
		end
		refs.overlay.body.Text = table.concat({
			string.format("Perfect %d      Good %d      Sloppy %d", stats.perfect, stats.good, stats.sloppy),
			string.format("Wrong order %d      Walked out %d", stats.failed, stats.expired),
			"",
			string.format("Best combo  x%d", snapshot.bestCombo),
		}, "\n")
		refs.overlay.start.Text = "CONTINUE  [E]"
	end

	-- Cash and the shop live on the between-shifts screen only: purchases
	-- change the loadout, and the server refuses them mid-service anyway.
	if snapshot.profile then
		refs.overlay.cash.Text = if snapshot.profile.temporary
			then "PROGRESS NOT SAVING - see Output"
			else string.format("%d c", snapshot.profile.cash)
		refs.overlay.cash.TextColor3 = if snapshot.profile.temporary
			then COLOR.bad
			else COLOR.perfect
	end

	refs.topBar.score.Text = string.format("%d c", snapshot.score)
	refs.topBar.combo.Text = string.format("x%.2f", snapshot.comboMult)
	refs.topBar.combo.TextColor3 = if snapshot.combo > 0 then COLOR.perfect else COLOR.dim

	renderHype(refs.hypeMeter, snapshot)

	-- Kept current so the panel can render the instant it is opened.
	refs.dailyPanel.lastProfile = snapshot.profile

	-- The rail stays up during service so a running boost is still readable,
	-- but the panel behind it closes: reading task progress mid-shift is not
	-- something to offer with four tickets going.
	local daily = snapshot.profile and snapshot.profile.daily
	refs.dailyButton.enabled = state ~= "Service"
	refs.dailyButton.button.BackgroundColor3 =
		if state == "Service" then COLOR.bg else COLOR.panel

	if state == "Service" then
		refs.dailyPanel.shade.Visible = false
	elseif refs.dailyPanel.shade.Visible then
		renderDaily(refs.dailyPanel, snapshot.profile)
	end

	-- The badge is on the rail rather than in the panel, so a finished task is
	-- visible without opening anything.
	local claimable = (daily and daily.claimable) or 0
	refs.dailyButton.badge.Visible = claimable > 0
	refs.dailyButton.badge.Text = tostring(claimable)

	renderBoosts(refs.boostStrip, snapshot.profile)

	-- Which order is selected drives the key labels and the plate readout.
	local activeOrder = nil
	for _, order in snapshot.orders do
		if order.id == snapshot.activeOrderId then
			activeOrder = order
			break
		end
	end

	-- Chores sit above everything else. They are the only thing in the game
	-- with its own clock that you did not start.
	local chore = snapshot.chore
	refs.chore.frame.Visible = chore ~= nil and state == "Service"
	if chore then
		local def = ChoreDefs.get(chore.id)
		refs.chore.title.Text = string.upper(def and def.name or chore.id)
		refs.chore.prompt.Text = ("press %s   %s"):format(ChoreDefs.KEY, def and def.blurb or "")
	end

	-- The prep panel is only up while you actually have an order in hand. A
	-- cooking order is not in hand -- the server drops it the moment the basket
	-- goes down, and the countdown lives on the customer's ticket from there.
	local inHand = state == "Service" and activeOrder ~= nil
	refs.prep.Visible = inHand
	refs.hint.Visible = state == "Service" and not inHand

	if inHand then
		local dish = DishDefs.get(activeOrder.dishId)
		refs.prepTitle.Text = string.upper(dish and dish.displayName or activeOrder.dishId)
	end

	-- SPACE is the commit key for every dish, but it commits different things:
	-- lower the basket, hand over the plate, collect what is ready.
	if activeOrder and activeOrder.searState and activeOrder.searState ~= "done" then
		refs.actionBar.serve.Text = "SERVE  [space]"
	elseif cookState == "raw" then
		refs.actionBar.serve.Text = "FRY  [space]"
	elseif cookState == "ready" then
		refs.actionBar.serve.Text = "COLLECT  [space]"
	elseif cookState == "burnt" then
		refs.actionBar.serve.Text = "BIN IT  [space]"
	else
		refs.actionBar.serve.Text = "SERVE  [space]"
	end

	-- Fried orders have no plate. The readout carries the cook prompt instead,
	-- and while it is counting down renderTimers owns the text -- writing it
	-- from both places is what made it flicker.
	local cookState = activeOrder and activeOrder.cookState

	-- Sear meter: shown once the prep steps are done, so the band is on screen
	-- before the first hold rather than discovered by ruining a steak.
	local searDish = if activeOrder then DishDefs.get(activeOrder.dishId) else nil
	local sear = searDish and searDish.sear
	local showSear = sear ~= nil
		and activeOrder.searState ~= nil
		and activeOrder.searState ~= "done"
		and #snapshot.build >= #activeOrder.required

	refs.searMeter.track.Visible = showSear == true
	if showSear then
		refs.searMeter.band.Position = UDim2.fromScale(sear.perfectFrom, 0)
		refs.searMeter.band.Size = UDim2.fromScale(sear.perfectTo - sear.perfectFrom, 1)

		-- Empty the bar until this order is actually on the heat. renderTimers
		-- only writes the fill while searing, so without this the meter opened
		-- still holding the last steak's value.
		if activeOrder.searState ~= "searing" then
			refs.searMeter.fill.Size = UDim2.fromScale(0, 1)
			refs.searMeter.fill.BackgroundColor3 = COLOR.warn
		end
		refs.searMeter.label.Text = if activeOrder.searState == "searing"
			then "let go in the green"
			else ("hold %s to %s"):format(sear.key, string.lower(sear.label:gsub(" %(hold%)", "")))
	end

	local steps = if activeOrder then #activeOrder.required else 0
	local doneSteps = #snapshot.build

	if cookState == "raw" then
		refs.plateReadout.Text = if doneSteps >= steps
			then "SPACE to fry"
			else string.format("STEP  %d / %d", doneSteps, steps)
	elseif cookState == "burnt" then
		refs.plateReadout.Text = "BURNT   SPACE to bin it"
	elseif showSear then
		-- The meter carries the instruction; the readout would only repeat it.
		refs.plateReadout.Text = ""
	elseif activeOrder and activeOrder.searState == "done" then
		refs.plateReadout.Text = ("SEARED  %s   SPACE to serve"):format(
			string.upper(activeOrder.searGrade or "?"))
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

	-- Which key comes next, and which are already done. Without this the panel
	-- showed a row of identical buttons and gave no clue why pressing an
	-- already-used one did nothing.
	local nextKey = nil
	local doneKeys = {}
	if activeOrder then
		for index = 1, #snapshot.build do
			doneKeys[activeOrder.keys[index]] = true
		end
		nextKey = activeOrder.keys[#snapshot.build + 1]
	end

	for key, entry in refs.keyGrid.buttons do
		local ingredientId = keyToIngredient[key]

		if not ingredientId then
			-- Not part of this dish at all.
			entry.name.Text = ""
			entry.swatch.BackgroundTransparency = 1
			entry.letter.TextColor3 = COLOR.stroke
			entry.button.BackgroundTransparency = 0.55
			entry.stroke.Color = COLOR.panel
			entry.stroke.Thickness = 2
			continue
		end

		entry.name.Text = DishDefs.ingredientName(ingredientId)
		entry.swatch.BackgroundColor3 = DishDefs.ingredientColor(ingredientId)
		entry.swatch.BackgroundTransparency = 0

		if key == nextKey then
			-- Do this one.
			entry.letter.TextColor3 = COLOR.text
			entry.button.BackgroundTransparency = 0.05
			entry.stroke.Color = COLOR.accent
			entry.stroke.Thickness = 3
		elseif doneKeys[key] then
			-- Already done: still legible, clearly spent.
			entry.letter.TextColor3 = COLOR.dim
			entry.button.BackgroundTransparency = 0.45
			entry.stroke.Color = COLOR.good
			entry.stroke.Thickness = 2
			entry.swatch.BackgroundTransparency = 0.6
		else
			entry.letter.TextColor3 = COLOR.text
			entry.button.BackgroundTransparency = 0.15
			entry.stroke.Color = COLOR.stroke
			entry.stroke.Thickness = 2
		end
	end
end

function UI.renderTimers(refs, snapshot)
	if not snapshot then
		return
	end

	local clock = workspace:GetServerTimeNow()
	local remaining = math.max(0, snapshot.shiftEndsAt - clock)

	-- The chore bar drains per frame. Five seconds is short enough that a
	-- ten-times-a-second bar would visibly stutter through it.
	if snapshot.chore then
		local span = math.max(snapshot.chore.expiresAt - snapshot.chore.startedAt, 0.001)
		local left = math.clamp((snapshot.chore.expiresAt - clock) / span, 0, 1)
		refs.chore.fill.Size = UDim2.fromScale(left, 1)
	end

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

	-- Sear meter fills per frame. This one genuinely has to: the whole
	-- interaction is releasing at the right moment, and a bar that only moves
	-- ten times a second is not something you can time against.
	if active and active.searState == "searing" and refs.searMeter.track.Visible then
		local dish = DishDefs.get(active.dishId)
		local sear = dish and dish.sear
		if sear then
			local fraction = (clock - active.searStartedAt) / sear.duration
			refs.searMeter.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			refs.searMeter.fill.BackgroundColor3 = if fraction > 1
				then COLOR.bad
				elseif fraction >= sear.perfectFrom and fraction <= sear.perfectTo then COLOR.good
				else COLOR.warn
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
