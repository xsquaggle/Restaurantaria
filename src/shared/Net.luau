--!strict
-- Remote names and lookup. The server creates the remotes; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.FOLDER = "Remotes"
Net.ACTION = "Action" -- RemoteFunction: client -> server (seq, action, args) -> (ok, reason, snapshot)
Net.STATE = "State" -- RemoteEvent: server -> client snapshot pushes

function Net.folder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(Net.FOLDER)
		if existing then
			return existing :: Folder
		end
		local folder = Instance.new("Folder")
		folder.Name = Net.FOLDER
		local action = Instance.new("RemoteFunction")
		action.Name = Net.ACTION
		action.Parent = folder
		local state = Instance.new("RemoteEvent")
		state.Name = Net.STATE
		state.Parent = folder
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(Net.FOLDER) :: Folder
end

return Net
