--!strict
-- Remote plumbing. The server creates the folder and events; the client waits
-- for them. Deliberately few remotes: one channel in, two channels out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Transient feedback (grades, fumbles) rides inside the snapshot rather than
-- on its own remote: separate remotes have no ordering guarantee between them,
-- and "the plate emptied" arriving before "you served it" picks the wrong
-- animation.
local NAMES = {
	"StationAction",  -- client -> server : {action = "...", ...}
	"StartShift",     -- client -> server : no payload
	"ShiftUpdate",    -- server -> client : full snapshot, with .events attached
}

local folder: Folder

if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local Remotes = {}
for _, name in NAMES do
	Remotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
