--!strict
-- Server bootstrap: remotes, player lifecycle, the arrival tick and snapshot pushes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

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

-- Studio-only test hook so automated playtests can inspect authoritative state.
if RunService:IsStudio() then
	local debug = Instance.new("BindableFunction")
	debug.Name = "RestaurantariaDebug"
	debug.OnInvoke = function(command: string, value: any)
		local player = Players:GetPlayers()[1]
		local session = player and ShiftService.sessions[player]
		if not session then
			return "no session"
		end
		if command == "state" then
			local lines = { string.format("lastSeq=%d rejected=%d tips=%d finished=%s", session.lastSeq, session.rejected, session.shift.tips, tostring(session.shift.finished)) }
			for _, c in session.shift.customers do
				local r = c.result
				table.insert(lines, string.format("customer %d %s %s/%s/%d pizza=%s%s", c.id, c.status, c.order.recipe, c.order.bake, c.order.slices, tostring(c.pizzaId),
					if r then string.format(" grade=%d (wait %d top %d bake %d cut %d) tip=%d", r.overall, r.wait.score, r.topping.score, r.bake.score, r.cut.score, r.tip) else ""))
			end
			for id, pz in session.shift.pizzas do
				table.insert(lines, string.format("pizza %d ticket=%d stage=%s toppings=%d cuts=%d slot=%s baked=%s", id, pz.ticketId, pz.stage, #pz.toppings, #pz.cuts, tostring(pz.slot), tostring(pz.bakeSeconds)))
			end
			local profile = SaveService.profiles[player]
			if profile then
				table.insert(lines, string.format("profile %s tips=%d xp=%d shifts=%d", profile.status, profile.data.tips, profile.data.xp, profile.data.shiftsCompleted))
			end
			return table.concat(lines, "\n")
		elseif command == "simulateLoadFailure" then
			SaveService.simulateLoadFailure = value == true
			return "ok"
		elseif command == "reloadProfile" then
			local profile = SaveService.load(player)
			push(player)
			return profile.status
		elseif command == "skipArrivals" then
			-- Shift the clock so the next customer arrives now.
			session.shift.startedAt -= (value or 10)
			return "ok"
		elseif command == "resetPatience" then
			-- Tool-driven playtests are slow; refill every unserved customer's patience.
			for _, c in session.shift.customers do
				if c.status ~= "served" then
					c.arrivedAt = workspace:GetServerTimeNow()
				end
			end
			push(player)
			return "ok"
		elseif command == "setBake" then
			-- value = { slot, seconds }: make the pizza in that slot read as baked for `seconds`.
			local id = session.shift.ovens[value[1]]
			local pizza = id and session.shift.pizzas[id]
			if not pizza then
				return "empty slot"
			end
			pizza.bakeStart = workspace:GetServerTimeNow() - value[2]
			push(player)
			return "ok"
		end
		return "unknown command"
	end
	debug.Parent = ServerStorage
end
