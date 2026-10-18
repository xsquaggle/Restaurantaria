--!strict
-- Server bootstrap: remotes, player lifecycle, the arrival tick and snapshot pushes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SaveService = require(script.Parent.SaveService)
local ShiftService = require(script.Parent.ShiftService)

-- The game is played entirely in screen-space 2D; no avatar, so no touch thumbstick.
Players.CharacterAutoLoads = false

local folder = Net.folder()
local actionRemote = folder:WaitForChild(Net.ACTION) :: RemoteFunction
local stateRemote = folder:WaitForChild(Net.STATE) :: RemoteEvent

local function push(player: Player)
	local snap = ShiftService.snapshot(player)
	if snap then
		stateRemote:FireClient(player, snap)
	end
end

actionRemote.OnServerInvoke = function(player: Player, seq: any, action: any, args: any)
	local ok, reason = ShiftService.handle(player, seq, action, args)
	return ok, reason, ShiftService.snapshot(player)
end

local function onPlayerAdded(player: Player)
	SaveService.load(player)
	if player.Parent == nil then
		SaveService.release(player)
		return
	end
	ShiftService.start(player)
	push(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	ShiftService.stop(player)
	SaveService.release(player)
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		for player, session in ShiftService.sessions do
			if ShiftService.tick(session) then
				push(player)
			end
		end
	end
end)
