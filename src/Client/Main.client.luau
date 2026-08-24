--!strict
-- Client entry point: input in, snapshots out to the scene and the HUD.
--
-- The client is deliberately dumb. It never decides whether a key was correct,
-- never grades a dish, never runs a timer that matters. It sends intents and
-- draws whatever the server last told it.

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Audio = require(script.Parent.Audio)
local Scene = require(script.Parent.Scene)
local Customers = require(script.Parent.Customers)
local FoodStack = require(script.Parent.FoodStack)
local Loading = require(script.Parent.Loading)
local SettingsUI = require(script.Parent.SettingsUI)
local UI = require(script.Parent.UI)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local snapshot: any = nil

-- Nothing accepts input until the avatar pool is built and preloaded.
local ready = false

-- Ceiling on how long we will wait for the server. If the pool never
-- finishes, the game opens anyway with the procedural fallback rather than
-- stranding the player on a loading screen.
local BOOT_TIMEOUT = 30

-- Tracks whether the combo has already topped out this streak, so the max-combo
-- sting fires on the way up and not on every serve afterwards.
local comboWasMaxed = false

-- ----------------------------------------------------------------- scene ---

Scene.applyLighting()
local scene = Scene.build()
Scene.lockCamera()
Scene.parkCharacter()

Customers.init(scene)
FoodStack.init(scene)
Audio.init()

-- --------------------------------------------------------------- intents ---

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
	if not ready then
		return
	end
	Remotes.StartShift:FireServer()
end

local refs = UI.build(playerGui, {
	onKey = onKey,
	onServe = onServe,
	onScrap = onScrap,
	onSelect = onSelect,
	onStart = onStart,
})

SettingsUI.build(playerGui)

-- ----------------------------------------------------------------- input ---

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
	if not ready then
		return Enum.ContextActionResult.Sink
	end

	local keyCode = input.KeyCode
	local inService = snapshot ~= nil and snapshot.state == "Service"

	-- E doubles as an ingredient key during service and as the start/continue
	-- key outside it. Gating on state keeps both bindings clean.
	if not inService then
		if keyCode == Enum.KeyCode.E then
			onStart()
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

-- ---------------------------------------------------------------- events ---

-- Events ride inside the snapshot, so they are guaranteed to be handled before
-- the state they describe is drawn. Order matters: the plate has to know it
-- was SERVED before it sees an empty build list, or it plays the wrong exit.
local function handleEvent(event)
	local kind = event.type

	if kind == "ingredientAdded" then
		UI.pulseKey(refs, event.key, true)
		Audio.play("click")

	elseif kind == "fumble" then
		UI.pulseKey(refs, event.key, false)
		Scene.shake(0.12, 0.18)
		Audio.play("fumble")

	elseif kind == "graded" then
		UI.flashGrade(refs, event)
		-- The grade goes straight through: the customer picks their own
		-- reaction face from it, so Perfect and Sloppy do not look identical.
		Customers.markExit(event.orderId, event.grade)

		if event.grade == "Fail" then
			FoodStack.dump()
			Audio.play("wrongOrder")
		else
			FoodStack.serve()
			Audio.play("serveSuccess")
			if event.grade == "Perfect" then
				Scene.shake(0.35, 0.22)
			end
		end

		-- Only when the streak actually tops out, and only on the way up --
		-- otherwise it retriggers on every serve for the rest of the round.
		local atMax = event.comboMult >= Config.COMBO_MAX
		if atMax and not comboWasMaxed then
			Audio.play("maxCombo")
		end
		comboWasMaxed = atMax

	elseif kind == "expired" then
		UI.flash(refs, "WALKED OUT", UI.COLOR.bad)
		Customers.markExit(event.orderId, "Expired")
		Audio.play("wrongOrder")
		comboWasMaxed = false

	elseif kind == "scrapped" or kind == "selected" then
		-- Switching tickets abandons the plate, same as scrapping it. Showing
		-- the food hit the floor makes that cost legible instead of silent.
		FoodStack.dump()

	elseif kind == "orderArrived" then
		Audio.play("ticketArrive")

	elseif kind == "shiftStarted" then
		Customers.clear()
		FoodStack.clear()
		comboWasMaxed = false
		Audio.startMusic()

	elseif kind == "shiftEnded" then
		Customers.clear()
		FoodStack.clear()
		comboWasMaxed = false
		Audio.stopMusic()
		Audio.play("roundComplete")
	end
end

Remotes.ShiftUpdate.OnClientEvent:Connect(function(newSnapshot)
	if newSnapshot.events then
		for _, event in newSnapshot.events do
			handleEvent(event)
		end
	end

	snapshot = newSnapshot

	UI.render(refs, snapshot)
	Customers.sync(snapshot)
	FoodStack.sync(snapshot.build)
end)

RunService.RenderStepped:Connect(function(dt)
	UI.renderTimers(refs, snapshot)
	Customers.update(dt, snapshot)
end)

-- Full-screen game: get the default Roblox chrome out of the way.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- Ask for current state now that the handlers above are connected.
sendAction({ action = "sync" })

-- ------------------------------------------------------------------ boot ---

-- Holds the game shut until the customer rigs exist AND their meshes and
-- textures are resident. Skipping either half is what made the first
-- customers of a session show up as fallback blobs.
local function boot()
	local loading = Loading.show(playerGui)

	Loading.setStatus(loading, "contacting the station", 0.05)

	local folder = ReplicatedStorage:WaitForChild("CustomerRigs", 15)

	if folder then
		local deadline = os.clock() + BOOT_TIMEOUT

		while not folder:GetAttribute("Ready") and os.clock() < deadline do
			local built = folder:GetAttribute("Built") or 0
			local total = math.max(folder:GetAttribute("Total") or 1, 1)
			Loading.setStatus(
				loading,
				("processing arrivals   %d / %d"):format(built, total),
				0.1 + 0.55 * (built / total)
			)
			task.wait(0.1)
		end

		-- PreloadAsync is the part that actually matters: without it the rigs
		-- exist but stream in grey and untextured on first sight.
		local rigs = folder:GetChildren()
		if #rigs > 0 then
			Loading.setStatus(loading, "loading appearances", 0.7)
			pcall(function()
				ContentProvider:PreloadAsync(rigs)
			end)
		else
			warn("[AlienFoodCourt] no rigs available at boot -- using procedural fallback")
		end
	else
		warn("[AlienFoodCourt] CustomerRigs never appeared -- using procedural fallback")
	end

	Loading.setStatus(loading, "opening the shutters", 1)
	task.wait(0.35)

	ready = true
	Loading.finish(loading)

	print("[AlienFoodCourt] client ready")
end

task.spawn(boot)
