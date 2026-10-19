--!strict
-- Client side of the action channel. Calls are async so a pending request never freezes the
-- interface; callers mark the one order as pending instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local folder = Net.folder()
local actionRemote = folder:WaitForChild(Net.ACTION) :: RemoteFunction
local stateRemote = folder:WaitForChild(Net.STATE) :: RemoteEvent

local Remote = {}
Remote.seq = 0
Remote.onSnapshot = nil :: ((any) -> ())?
Remote.onRejected = nil :: ((string, string) -> ())?

function Remote.send(action: string, args: { [string]: any }, done: ((boolean, string?) -> ())?)
	Remote.seq += 1
	local seq = Remote.seq
	task.spawn(function()
		local ok, reason, snapshot = actionRemote:InvokeServer(seq, action, args)
		if snapshot and Remote.onSnapshot then
			Remote.onSnapshot(snapshot)
		end
		if not ok and Remote.onRejected then
			Remote.onRejected(action, reason or "rejected")
		end
		if done then
			done(ok, reason)
		end
	end)
end

stateRemote.OnClientEvent:Connect(function(snapshot)
	if Remote.onSnapshot then
		Remote.onSnapshot(snapshot)
	end
end)

return Remote
