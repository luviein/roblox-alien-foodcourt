--!strict
-- The settings panel and the gear that opens it.
--
-- Sliders are -/+ steppers rather than drag handles: no pointer-capture edge
-- cases, works identically on touch, and 10% steps are finer than anyone
-- actually needs for a volume control.

local Settings = require(script.Parent.Settings)

local SettingsUI = {}

local COLOR = {
	bg      = Color3.fromRGB(16, 17, 24),
	panel   = Color3.fromRGB(30, 32, 43),
	panelHi = Color3.fromRGB(46, 50, 66),
	stroke  = Color3.fromRGB(60, 65, 84),
	accent  = Color3.fromRGB(88, 198, 255),
	text    = Color3.fromRGB(234, 238, 246),
	dim     = Color3.fromRGB(122, 130, 150),
	good    = Color3.fromRGB(108, 220, 140),
}

local STEP = 0.1

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

-- A labelled row with -/+ buttons and a fill bar showing the value.
local function sliderRow(parent: Instance, order: number, label: string, key: string)
	local row = make("Frame", {
		Name = key,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 54),
	}, parent)

	make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.45, 0.55),
		Font = Enum.Font.GothamMedium,
		Text = label,
		TextColor3 = COLOR.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local readout = make("TextLabel", {
		Name = "Readout",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.62, 0),
		Size = UDim2.fromScale(0.2, 0.55),
		Font = Enum.Font.GothamBold,
		Text = "70%",
		TextColor3 = COLOR.accent,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)

	local track = make("Frame", {
		Name = "Track",
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0.68),
		Size = UDim2.fromScale(0.62, 0.16),
	}, row)
	corner(track, 4)

	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.7, 1),
	}, track)
	corner(fill, 4)

	local function button(text: string, x: number, delta: number)
		local btn = make("TextButton", {
			BackgroundColor3 = COLOR.panelHi,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(x, 0.4),
			Size = UDim2.fromOffset(38, 32),
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = COLOR.text,
			TextSize = 20,
		}, row)
		corner(btn, 6)
		btn.Activated:Connect(function()
			Settings.nudge(key, delta)
		end)
	end

	button("-", 0.88, -STEP)
	button("+", 1.0, STEP)

	local function refresh()
		local value = Settings.get(key) :: number
		readout.Text = string.format("%d%%", math.round(value * 100))
		fill.Size = UDim2.fromScale(value, 1)
	end

	refresh()
	return refresh
end

-- A labelled row with an ON/OFF button.
local function toggleRow(parent: Instance, order: number, label: string, key: string)
	local row = make("Frame", {
		Name = key,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 44),
	}, parent)

	make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.7, 1),
		Font = Enum.Font.GothamMedium,
		Text = label,
		TextColor3 = COLOR.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local btn = make("TextButton", {
		BackgroundColor3 = COLOR.panelHi,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(76, 32),
		Font = Enum.Font.GothamBold,
		Text = "ON",
		TextColor3 = COLOR.bg,
		TextSize = 14,
	}, row)
	corner(btn, 6)

	local function refresh()
		local on = Settings.get(key) == true
		btn.Text = if on then "ON" else "OFF"
		btn.BackgroundColor3 = if on then COLOR.good else COLOR.panelHi
		btn.TextColor3 = if on then COLOR.bg else COLOR.dim
	end

	btn.Activated:Connect(function()
		Settings.toggle(key)
	end)

	refresh()
	return refresh
end

function SettingsUI.build(playerGui: Instance)
	local screen = make("ScreenGui", {
		Name = "AFC_Settings",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 50,
	}, playerGui)

	-- Gear. Top-right, clear of the Roblox chrome in the top-left.
	local gear = make("TextButton", {
		Name = "Gear",
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(40, 40),
		Font = Enum.Font.GothamBold,
		Text = "⚙",
		TextColor3 = COLOR.text,
		TextSize = 22,
	}, screen)
	corner(gear, 8)

	local shade = make("TextButton", {
		Name = "Shade",
		BackgroundColor3 = COLOR.bg,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, screen)

	local panel = make("Frame", {
		Name = "Panel",
		BackgroundColor3 = COLOR.panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 380),
	}, shade)
	corner(panel, 12)
	make("UIStroke", { Color = COLOR.stroke, Thickness = 2 }, panel)

	make("UIPadding", {
		PaddingTop = UDim.new(0, 22),
		PaddingBottom = UDim.new(0, 22),
		PaddingLeft = UDim.new(0, 26),
		PaddingRight = UDim.new(0, 26),
	}, panel)

	make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Font = Enum.Font.GothamBold,
		Text = "SETTINGS",
		TextColor3 = COLOR.text,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	local rows = make("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -104),
	}, panel)

	make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, rows)

	local refreshers = {
		sliderRow(rows, 1, "Music volume", "musicVolume"),
		sliderRow(rows, 2, "Sound effects", "sfxVolume"),
		toggleRow(rows, 3, "Reaction bubbles", "reactionBubbles"),
		toggleRow(rows, 4, "Screen shake", "screenShake"),
	}

	local close = make("TextButton", {
		Name = "Close",
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 42),
		Font = Enum.Font.GothamBold,
		Text = "CLOSE",
		TextColor3 = COLOR.bg,
		TextSize = 16,
	}, panel)
	corner(close, 8)

	local function refreshAll()
		for _, refresh in refreshers do
			refresh()
		end
	end

	Settings.changed.Event:Connect(refreshAll)

	local function setOpen(open: boolean)
		shade.Visible = open
		if open then
			refreshAll()
		end
	end

	gear.Activated:Connect(function()
		setOpen(not shade.Visible)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	-- Clicking the dimmed backdrop closes too, but clicks on the panel itself
	-- must not bubble up to it.
	shade.Activated:Connect(function()
		setOpen(false)
	end)
	panel.InputBegan:Connect(function() end)

	return {
		screen = screen,
		toggle = function()
			setOpen(not shade.Visible)
		end,
		isOpen = function()
			return shade.Visible
		end,
	}
end

return SettingsUI
