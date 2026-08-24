--!strict
-- Client entry point: input in, snapshots out to the UI.
--
-- The client is deliberately dumb. It never decides whether a key was correct,
-- never grades a dish, never runs a timer that matters. It sends intents and
-- draws whatever the server last told it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.UI)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local snapshot = nil

-- ------------------------------------------------------------- intents -----

local function sendAction(payload)
	Remotes.StationAction:FireServer(payload)
end

local function onKey(key: string)
	if not snapshot or snapshot.state ~= "Service" then
		return
	end
	sendAction({ action = "ingredient", key = key })
end

local function onServe()
	sendAction({ action = "serve" })
end

local function onScrap()
	sendAction({ action = "scrap" })
end

local function onSelect(slot: number)
	sendAction({ action = "select", slot = slot })
end

local function onStart()
	Remotes.StartShift:FireServer()
end

local refs = UI.build(playerGui, {
	onKey = onKey,
	onServe = onServe,
	onScrap = onScrap,
	onSelect = onSelect,
	onStart = onStart,
})

-- --------------------------------------------------------------- input -----

local INGREDIENT_KEYS = {
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.T] = "T",
	[Enum.KeyCode.A] = "A",
	[Enum.KeyCode.S] = "S",
	[Enum.KeyCode.D] = "D",
	[Enum.KeyCode.F] = "F",
	[Enum.KeyCode.G] = "G",
}

local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

local function handleInput(_actionName: string, inputState: Enum.UserInputState, input: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end

	local keyCode = input.KeyCode
	local inService = snapshot ~= nil and snapshot.state == "Service"

	-- E doubles as an ingredient key during service and as the start/continue
	-- key outside it. Gating on state keeps both bindings clean.
	if not inService then
		if keyCode == Enum.KeyCode.E then
			onStart()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Sink
	end

	if keyCode == Enum.KeyCode.Space then
		onServe()
	elseif keyCode == Enum.KeyCode.X then
		onScrap()
	elseif SLOT_KEYS[keyCode] then
		onSelect(SLOT_KEYS[keyCode])
	elseif INGREDIENT_KEYS[keyCode] then
		onKey(INGREDIENT_KEYS[keyCode])
	end

	return Enum.ContextActionResult.Sink
end

local BOUND_KEYS = {
	Enum.KeyCode.Q, Enum.KeyCode.W, Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.T,
	Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.F, Enum.KeyCode.G,
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
	Enum.KeyCode.Space, Enum.KeyCode.X,
}

-- Sinking Space also stops the character jumping under the UI, which is what
-- we want -- this is a fixed-camera screen, not a platformer.
ContextActionService:BindAction("AFC_Input", handleInput, false, table.unpack(BOUND_KEYS))

-- --------------------------------------------------------------- events ----

local function handleEvent(event)
	if event.type == "graded" then
		UI.flashGrade(refs, event)
	elseif event.type == "fumble" then
		UI.flashKey(refs, event.key)
	elseif event.type == "expired" then
		UI.flash(refs, "WALKED OUT", UI.COLOR.bad)
	end
end

Remotes.ShiftUpdate.OnClientEvent:Connect(function(newSnapshot)
	snapshot = newSnapshot
	UI.render(refs, snapshot)
end)

Remotes.ShiftEvent.OnClientEvent:Connect(function(events)
	for _, event in events do
		handleEvent(event)
	end
end)

RunService.RenderStepped:Connect(function()
	UI.renderTimers(refs, snapshot)
end)

-- Ask for current state now that the handlers above are connected.
sendAction({ action = "sync" })

-- Full-screen game: get the default Roblox chrome out of the way.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

print("[AlienFoodCourt] client ready")
