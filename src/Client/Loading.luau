--!strict
-- Boot screen. Holds the game shut until the customer rigs exist and their
-- meshes and textures are actually in memory.
--
-- Without this the first customers spawn before the server has finished
-- building the avatar pool, so they come out as the procedural fallback
-- blobs -- and any rig that does arrive pops in untextured while Roblox
-- streams it.
--
-- Its own ScreenGui with a high DisplayOrder, so it covers the HUD without
-- having to co-ordinate ZIndex with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Loading = {}

local COLOR = {
	bg      = Color3.fromRGB(12, 13, 19),
	text    = Color3.fromRGB(234, 238, 246),
	dim     = Color3.fromRGB(122, 130, 150),
	accent  = Color3.fromRGB(88, 198, 255),
	track   = Color3.fromRGB(32, 35, 47),
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

function Loading.show(playerGui: Instance)
	local screen = make("ScreenGui", {
		Name = "AFC_Loading",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 100,
	}, playerGui)

	local root = make("Frame", {
		Name = "Root",
		BackgroundColor3 = COLOR.bg,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, screen)

	local title = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.8, 0.1),
		Font = Enum.Font.GothamBold,
		Text = "SECTOR 7 FOOD COURT",
		TextColor3 = COLOR.text,
		TextScaled = true,
	}, root)
	make("UITextSizeConstraint", { MaxTextSize = 46 }, title)

	local flavour = make("TextLabel", {
		Name = "Flavour",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.05),
		Font = Enum.Font.GothamMedium,
		Text = "you have been abducted. the locals are hungry.",
		TextColor3 = COLOR.dim,
		TextScaled = true,
	}, root)
	make("UITextSizeConstraint", { MaxTextSize = 18 }, flavour)

	local track = make("Frame", {
		Name = "Track",
		BackgroundColor3 = COLOR.track,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromScale(0.34, 0.012),
	}, root)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}, track)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

	local status = make("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.645),
		Size = UDim2.fromScale(0.5, 0.04),
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = COLOR.dim,
		TextScaled = true,
	}, root)
	make("UITextSizeConstraint", { MaxTextSize = 15 }, status)

	-- Build stamp. If this does not match what you expect, Studio is running a
	-- stale copy and no amount of editing files will change what you see.
	make("TextLabel", {
		Name = "Build",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.99, 0.985),
		Size = UDim2.fromScale(0.3, 0.03),
		Font = Enum.Font.Code,
		Text = "build " .. tostring(Config.BUILD),
		TextColor3 = COLOR.dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, root)

	return { screen = screen, root = root, fill = fill, status = status, flavour = flavour }
end

-- `progress` is 0..1. The bar tweens rather than snapping so a long step does
-- not look frozen.
function Loading.setStatus(handle, text: string, progress: number)
	handle.status.Text = text
	TweenService:Create(
		handle.fill,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1) }
	):Play()
end

function Loading.setFlavour(handle, text: string)
	handle.flavour.Text = text
end

function Loading.finish(handle)
	local fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(handle.root, fade, { BackgroundTransparency = 1 }):Play()
	for _, descendant in handle.root:GetDescendants() do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, fade, { TextTransparency = 1 }):Play()
		elseif descendant:IsA("Frame") then
			TweenService:Create(descendant, fade, { BackgroundTransparency = 1 }):Play()
		end
	end

	task.delay(0.5, function()
		handle.screen:Destroy()
	end)
end

return Loading
