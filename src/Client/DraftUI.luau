--!strict
-- The draft: today's conditions, and the menu you take into them.
--
-- The hype figures are shown BEFORE you commit, per phase, with the reasons
-- spelled out. A rule you cannot see is not strategy, it is a guess -- and
-- these rules only become interesting once you can plan against them.
--
-- Hype is computed here with the same HypeDefs the server uses, so the preview
-- cannot disagree with the shift. The client is not trusted with it: the
-- server recomputes from the menu it receives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DishDefs = require(Shared.DishDefs)
local HypeDefs = require(Shared.HypeDefs)
local ShopDefs = require(Shared.ShopDefs)

local DraftUI = {}

local COLOR = {
	bg      = Color3.fromRGB(14, 15, 21),
	panel   = Color3.fromRGB(28, 30, 41),
	panelHi = Color3.fromRGB(44, 48, 63),
	stroke  = Color3.fromRGB(58, 63, 82),
	accent  = Color3.fromRGB(88, 198, 255),
	text    = Color3.fromRGB(234, 238, 246),
	dim     = Color3.fromRGB(120, 128, 148),
	good    = Color3.fromRGB(108, 220, 140),
	warn    = Color3.fromRGB(246, 184, 72),
	bad     = Color3.fromRGB(242, 92, 92),
	gold    = Color3.fromRGB(255, 214, 92),
}

-- Short enough to sit in a row without wrapping, plain enough to guess at.
local TAG_CHIPS = {
	{ key = "healthy",     label = "HEALTHY",  color = COLOR.good },
	{ key = "fatty",       label = "FATTY",    color = COLOR.warn },
	{ key = "breakfast",   label = "MORNING",  color = COLOR.accent },
	{ key = "lateNight",   label = "NIGHT",    color = COLOR.accent },
	{ key = "smelly",      label = "SMELLY",   color = COLOR.bad },
	{ key = "alwaysHyped", label = "POPULAR",  color = COLOR.gold },
	{ key = "trash",       label = "TRASH",    color = COLOR.dim },
	{ key = "dishes",      label = "WASHING",  color = COLOR.dim },
}

local WEATHER_CHIP = {
	sunny = "SUITS SUN",
	rain  = "SUITS RAIN",
	cold  = "SUITS COLD",
}

local MAX_CHIPS = 4
local MAX_REASONS = 6

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

-- One selectable dish.
local function buildDishRow(parent: Instance, order: number, onToggle: () -> ())
	local row = make("TextButton", {
		BackgroundColor3 = COLOR.panel,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 52),
	}, parent)
	corner(row, 8)
	local stroke = make("UIStroke", { Color = COLOR.stroke, Thickness = 2 }, row)

	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, row)

	local title = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.1),
		Size = UDim2.fromScale(0.62, 0.44),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local value = make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0.1),
		Size = UDim2.fromScale(0.3, 0.44),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.gold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)

	local chipRow = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.56),
		Size = UDim2.fromScale(1, 0.38),
	}, row)

	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, chipRow)

	local chips = {}
	for index = 1, MAX_CHIPS do
		local chip = make("TextLabel", {
			BackgroundColor3 = COLOR.panelHi,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.fromOffset(74, 17),
			Font = Enum.Font.GothamBold,
			Text = "",
			TextColor3 = COLOR.bg,
			TextSize = 10,
			Visible = false,
		}, chipRow)
		corner(chip, 4)
		chips[index] = chip
	end

	row.Activated:Connect(onToggle)

	return { frame = row, stroke = stroke, title = title, value = value, chips = chips }
end

-- One phase's projected hype.
local function buildPhaseRow(parent: Instance, order: number, phase: string)
	local row = make("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 46),
	}, parent)

	make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.5, 0.42),
		Font = Enum.Font.GothamBold,
		Text = string.upper(HypeDefs.PhaseName[phase] or phase),
		TextColor3 = COLOR.dim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local readout = make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.5, 0.42),
		Font = Enum.Font.GothamBold,
		Text = "100%",
		TextColor3 = COLOR.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)

	local track = make("Frame", {
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0.56),
		Size = UDim2.fromScale(1, 0.24),
	}, row)
	corner(track, 4)

	-- The 100% mark, so above and below the line are visible at a glance
	-- rather than requiring you to read the number.
	make("Frame", {
		BackgroundColor3 = COLOR.stroke,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale((1 - HypeDefs.MIN) / (HypeDefs.MAX - HypeDefs.MIN), 0),
		Size = UDim2.new(0, 2, 1, 0),
		ZIndex = 3,
	}, track)

	local fill = make("Frame", {
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.5, 1),
	}, track)
	corner(fill, 4)

	return { frame = row, readout = readout, fill = fill }
end

function DraftUI.build(playerGui: Instance, onConfirm: ({ string }) -> ())
	local screen = make("ScreenGui", {
		Name = "AFC_Draft",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 70,
	}, playerGui)

	-- A TextButton, not a Frame: plain Frames do not absorb clicks in Roblox,
	-- so a Frame panel would let every click fall through to the shade behind
	-- it and close the screen mid-draft.
	local shade = make("TextButton", {
		BackgroundColor3 = COLOR.bg,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, screen)

	local panel = make("TextButton", {
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 580),
	}, shade)
	corner(panel, 14)
	make("UIStroke", { Color = COLOR.stroke, Thickness = 2 }, panel)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 20),
		PaddingBottom = UDim.new(0, 20),
		PaddingLeft = UDim.new(0, 24),
		PaddingRight = UDim.new(0, 24),
	}, panel)

	local dayLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, 0, 0, 28),
		Font = Enum.Font.GothamBold,
		Text = "DAY 1",
		TextColor3 = COLOR.text,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	local weatherLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 0, 28),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.accent,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, panel)

	local weatherBlurb = make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = COLOR.dim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, panel)

	-- Left: what you own. Right: what it would do to you.
	local dishList = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(0.58, -10, 1, -122),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = COLOR.stroke,
	}, panel)

	make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, dishList)

	local side = make("Frame", {
		BackgroundColor3 = COLOR.panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 56),
		Size = UDim2.new(0.42, 0, 1, -122),
	}, panel)
	corner(side, 10)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
	}, side)

	make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.GothamBold,
		Text = "EXPECTED HYPE",
		TextColor3 = COLOR.dim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, side)

	local phaseHolder = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 150),
	}, side)

	make("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, phaseHolder)

	local phaseRows = {}
	for index, phase in HypeDefs.Phases do
		phaseRows[phase] = buildPhaseRow(phaseHolder, index, phase)
	end

	make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 186),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.GothamBold,
		Text = "WHY",   -- the reasons behind the numbers above
		TextColor3 = COLOR.dim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, side)

	local reasons = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 206),
		Size = UDim2.new(1, 0, 1, -206),
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = COLOR.text,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, side)

	local slotLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.4, 0, 0, 44),
		Font = Enum.Font.GothamBold,
		Text = "0 / 3",
		TextColor3 = COLOR.dim,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	local confirm = make("TextButton", {
		BackgroundColor3 = COLOR.good,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.42, 0, 0, 44),
		Font = Enum.Font.GothamBold,
		Text = "OPEN UP",
		TextColor3 = COLOR.bg,
		TextSize = 16,
	}, panel)
	corner(confirm, 8)

	local refs = {
		screen = screen,
		shade = shade,
		dayLabel = dayLabel,
		weatherLabel = weatherLabel,
		weatherBlurb = weatherBlurb,
		dishList = dishList,
		dishRows = {},
		phaseRows = phaseRows,
		reasons = reasons,
		slotLabel = slotLabel,
		confirm = confirm,
		selected = {},          -- dishId -> true
	}

	-- Backing out without opening up: the draft is a decision, and a decision
	-- you cannot reconsider is just a prompt.
	shade.Activated:Connect(function()
		DraftUI.setOpen(refs, false)
	end)

	confirm.Activated:Connect(function()
		local menu = {}
		for _, dishId in DishDefs.ActiveMenu do
			if refs.selected[dishId] then
				table.insert(menu, dishId)
			end
		end
		onConfirm(menu)
	end)

	return refs
end

function DraftUI.setOpen(refs, open: boolean)
	refs.shade.Visible = open
end

function DraftUI.isOpen(refs): boolean
	return refs.shade.Visible
end

-- Fills the selection with the first few unlocked dishes, so a player who
-- never touches this screen still gets a working menu.
function DraftUI.seed(refs, profile)
	if next(refs.selected) ~= nil or not profile then
		return
	end
	local slots = profile.menuSlots or 3
	for _, dishId in DishDefs.ActiveMenu do
		if profile.unlocked[dishId] and DraftUI.count(refs) < slots then
			refs.selected[dishId] = true
		end
	end
end

function DraftUI.count(refs): number
	local count = 0
	for _ in refs.selected do
		count += 1
	end
	return count
end

function DraftUI.render(refs, profile)
	if not profile then
		-- Better to say so than to present an empty panel as though it were an
		-- answer. Should be momentary: the server pushes again on profile load.
		refs.reasons.Text = "Still loading your profile..."
		return
	end

	local conditions = profile.conditions or {}
	local slots = profile.menuSlots or 3

	refs.dayLabel.Text = string.format("DAY %d", conditions.day or profile.day or 1)
	refs.weatherLabel.Text = string.upper(conditions.weatherName or "")
	refs.weatherBlurb.Text = conditions.weatherBlurb or ""

	local yesterday = {}
	for _, dishId in (profile.lastMenu or {}) do
		yesterday[dishId] = true
	end

	-- Rows are built once, on first render, since the unlocked set only grows
	-- between shifts and never during this screen.
	local order = 0
	for _, dishId in DishDefs.ActiveMenu do
		if not profile.unlocked[dishId] then
			continue
		end
		order += 1

		local row = refs.dishRows[dishId]
		if not row then
			row = buildDishRow(refs.dishList, order, function()
				if refs.selected[dishId] then
					refs.selected[dishId] = nil
				elseif DraftUI.count(refs) < slots then
					refs.selected[dishId] = true
				end
				DraftUI.render(refs, profile)
			end)
			refs.dishRows[dishId] = row
		end

		local dish = DishDefs.get(dishId)
		local tags = dish.hype or {}
		local picked = refs.selected[dishId] == true

		row.title.Text = dish.displayName
		row.value.Text = string.format("%d pts", dish.baseValue)

		if picked then
			row.stroke.Color = COLOR.good
			row.stroke.Thickness = 3
			row.frame.BackgroundColor3 = COLOR.panelHi
		else
			row.stroke.Color = COLOR.stroke
			row.stroke.Thickness = 2
			row.frame.BackgroundColor3 = COLOR.panel
		end

		-- Chips, most decision-relevant first. Repeats matter more than
		-- anything intrinsic, so they lead.
		local chipIndex = 0
		local function chip(label: string, colour: Color3)
			chipIndex += 1
			local slot = row.chips[chipIndex]
			if slot then
				slot.Visible = true
				slot.Text = label
				slot.BackgroundColor3 = colour
			end
		end

		if yesterday[dishId] then
			chip("YESTERDAY", COLOR.bad)
		end
		if tags.weather and tags.weather == conditions.weather then
			chip(WEATHER_CHIP[tags.weather] or "IN SEASON", COLOR.good)
		end
		for _, entry in TAG_CHIPS do
			if tags[entry.key] and chipIndex < MAX_CHIPS then
				chip(entry.label, entry.color)
			end
		end
		for index = chipIndex + 1, MAX_CHIPS do
			row.chips[index].Visible = false
		end
	end

	-- Projected hype, using the same code the server will run.
	local defs = {}
	for _, dishId in DishDefs.ActiveMenu do
		if refs.selected[dishId] then
			table.insert(defs, DishDefs.get(dishId))
		end
	end

	local allReasons = {}
	for _, phase in HypeDefs.Phases do
		local hype, why = HypeDefs.evaluate(defs, phase, conditions.weather or "clear", yesterday)
		local row = refs.phaseRows[phase]

		row.readout.Text = string.format("%d%%", math.round(hype * 100))
		row.readout.TextColor3 = if hype > 1.02 then COLOR.good
			elseif hype < 0.98 then COLOR.bad
			else COLOR.text
		row.fill.Size = UDim2.fromScale(
			(hype - HypeDefs.MIN) / (HypeDefs.MAX - HypeDefs.MIN), 1)
		row.fill.BackgroundColor3 = if hype > 1.02 then COLOR.good
			elseif hype < 0.98 then COLOR.bad
			else COLOR.accent

		for _, reason in why do
			-- The same reason fires in all three phases for anything
			-- unconditional; list it once.
			if not table.find(allReasons, reason) then
				table.insert(allReasons, reason)
			end
		end
	end

	-- Show a bounded list rather than a wall of text. Morning reasons include
	-- every unconditional one, so trimming from the end keeps the useful half.
	local trimmed = #allReasons - MAX_REASONS
	while #allReasons > MAX_REASONS do
		table.remove(allReasons)
	end
	if trimmed > 0 then
		table.insert(allReasons, ("...and %d more"):format(trimmed))
	end

	local count = DraftUI.count(refs)

	-- An empty WHY column is ambiguous: it could mean "this menu has no
	-- effects" or "nothing rendered". Say which.
	refs.reasons.Text = if #allReasons > 0
		then table.concat(allReasons, "\n")
		elseif count == 0 then "Pick some dishes to see how the day reacts."
		else "Nothing on this menu stands out today."

	refs.slotLabel.Text = string.format("%d / %d chosen", count, slots)
	refs.confirm.BackgroundColor3 = if count > 0 then COLOR.good else COLOR.panelHi
end

return DraftUI
