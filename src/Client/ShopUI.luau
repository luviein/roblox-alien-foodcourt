--!strict
-- The between-shifts shop: unlock dishes, buy upgrades.
--
-- Purely a view. It sends "buy this id" and redraws from whatever the server
-- says the profile is afterwards -- it never decides affordability or
-- ownership itself, so a client that lies about either gets nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DishDefs = require(Shared.DishDefs)
local ShopDefs = require(Shared.ShopDefs)

local ShopUI = {}

local COLOR = {
	bg      = Color3.fromRGB(16, 17, 24),
	panel   = Color3.fromRGB(30, 32, 43),
	panelHi = Color3.fromRGB(46, 50, 66),
	stroke  = Color3.fromRGB(60, 65, 84),
	accent  = Color3.fromRGB(88, 198, 255),
	text    = Color3.fromRGB(234, 238, 246),
	dim     = Color3.fromRGB(122, 130, 150),
	good    = Color3.fromRGB(108, 220, 140),
	gold    = Color3.fromRGB(255, 214, 92),
}

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

-- One purchasable row: name, what it does, price, and a buy button whose state
-- says why you cannot have it yet.
local function buildRow(parent: Instance, order: number, onBuy: () -> ())
	local row = make("Frame", {
		BackgroundColor3 = COLOR.panel,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 62),
	}, parent)
	corner(row, 8)

	make("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
	}, row)

	local title = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.14),
		Size = UDim2.fromScale(0.62, 0.4),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local blurb = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.54),
		Size = UDim2.fromScale(0.62, 0.34),
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = COLOR.dim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)

	local button = make("TextButton", {
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(132, 38),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.bg,
		TextSize = 15,
	}, row)
	corner(button, 7)

	button.Activated:Connect(onBuy)

	return { frame = row, title = title, blurb = blurb, button = button }
end

function ShopUI.build(playerGui: Instance, onBuy: (string, string) -> ())
	local screen = make("ScreenGui", {
		Name = "AFC_Shop",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 60,
	}, playerGui)

	local shade = make("TextButton", {
		Name = "Shade",
		BackgroundColor3 = COLOR.bg,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, screen)

	-- A button so clicks inside are absorbed rather than falling through to
	-- the backdrop and closing the thing you are trying to use.
	local panel = make("TextButton", {
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 560),
	}, shade)
	corner(panel, 14)
	make("UIStroke", { Color = COLOR.stroke, Thickness = 2 }, panel)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 20),
		PaddingBottom = UDim.new(0, 20),
		PaddingLeft = UDim.new(0, 22),
		PaddingRight = UDim.new(0, 22),
	}, panel)

	make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, 0, 0, 30),
		Font = Enum.Font.GothamBold,
		Text = "SUPPLY DEPOT",
		TextColor3 = COLOR.text,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	local cash = make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 0, 30),
		Font = Enum.Font.GothamBold,
		Text = "0 c",
		TextColor3 = COLOR.gold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, panel)

	local list = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -104),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = COLOR.stroke,
	}, panel)

	make("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	local function heading(text: string, order: number)
		local label = make("TextLabel", {
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 26),
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = COLOR.dim,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, list)
		return label
	end

	heading("MENU", 1)

	local dishRows = {}
	for index, dishId in ShopDefs.DishOrder do
		dishRows[dishId] = buildRow(list, 1 + index, function()
			onBuy("dish", dishId)
		end)
	end

	heading("UPGRADES", 100)

	local upgradeRows = {}
	for index, upgradeId in ShopDefs.UpgradeOrder do
		upgradeRows[upgradeId] = buildRow(list, 100 + index, function()
			onBuy("upgrade", upgradeId)
		end)
	end

	local close = make("TextButton", {
		BackgroundColor3 = COLOR.panelHi,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 42),
		Font = Enum.Font.GothamBold,
		Text = "BACK",
		TextColor3 = COLOR.text,
		TextSize = 15,
	}, panel)
	corner(close, 8)

	local refs = {
		screen = screen,
		shade = shade,
		cash = cash,
		dishRows = dishRows,
		upgradeRows = upgradeRows,
	}

	close.Activated:Connect(function()
		shade.Visible = false
	end)
	shade.Activated:Connect(function()
		shade.Visible = false
	end)

	return refs
end

function ShopUI.setOpen(refs, open: boolean)
	refs.shade.Visible = open
end

function ShopUI.isOpen(refs): boolean
	return refs.shade.Visible
end

-- Redrawn from the profile every snapshot, so a purchase updates as soon as
-- the server acknowledges it.
function ShopUI.render(refs, profile)
	if not profile then
		return
	end

	refs.cash.Text = string.format("%d c", profile.cash)

	for dishId, row in refs.dishRows do
		local dish = DishDefs.get(dishId)
		local cost = ShopDefs.dishCost(dishId) or 0
		local owned = profile.unlocked[dishId] == true

		row.title.Text = dish and dish.displayName or dishId
		row.blurb.Text = dish and dish.alienName or ""

		if owned then
			row.button.Text = "ON MENU"
			row.button.BackgroundColor3 = COLOR.good
			row.button.Active = false
		else
			row.button.Text = string.format("%d c", cost)
			-- Affordability is shown, not enforced -- the server decides. This
			-- only stops the button looking available when it is not.
			row.button.BackgroundColor3 = if profile.cash >= cost then COLOR.accent else COLOR.panelHi
			row.button.Active = true
		end
	end

	for upgradeId, row in refs.upgradeRows do
		local upgrade = ShopDefs.Upgrades[upgradeId]
		local owned = (profile.upgrades and profile.upgrades[upgradeId]) or 0
		local maxLevel = ShopDefs.maxLevel(upgradeId)
		local cost = ShopDefs.upgradeCost(upgradeId, owned)

		row.title.Text = string.format("%s  %d/%d", upgrade.name, owned, maxLevel)
		row.blurb.Text = upgrade.blurb

		if not cost then
			row.button.Text = "MAXED"
			row.button.BackgroundColor3 = COLOR.good
			row.button.Active = false
		else
			row.button.Text = string.format("%d c", cost)
			row.button.BackgroundColor3 = if profile.cash >= cost then COLOR.accent else COLOR.panelHi
			row.button.Active = true
		end
	end
end

return ShopUI
