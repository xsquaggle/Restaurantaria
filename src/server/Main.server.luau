--!strict
-- Server bootstrap: remotes, player lifecycle, the arrival tick and snapshot pushes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Recipes = require(ReplicatedStorage.Shared.Recipes)
local CustomerLooks = require(script.Parent.CustomerLooks)
local SaveService = require(script.Parent.SaveService)
local ShiftService = require(script.Parent.ShiftService)
local TestStore = require(script.Parent.TestStore)

-- The game is played entirely in screen-space 2D; no avatar, so no touch thumbstick.
Players.CharacterAutoLoads = false

local folder = Net.folder()
local actionRemote = folder:WaitForChild(Net.ACTION) :: RemoteFunction
local stateRemote = folder:WaitForChild(Net.STATE) :: RemoteEvent

local function push(player: Player)
	local snap = ShiftService.snapshot(player)
	-- A leaving player's session lasts until their save settles; nothing to send them then.
	if snap and player.Parent then
		stateRemote:FireClient(player, snap)
	end
end

ShiftService.changed = push

actionRemote.OnServerInvoke = function(player: Player, seq: any, action: any, args: any)
	local ok, reason = ShiftService.handle(player, seq, action, args)
	return ok, reason, ShiftService.snapshot(player)
end

CustomerLooks.start()

local function onPlayerAdded(player: Player)
	task.spawn(CustomerLooks.loadFriends, player)
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

-- Leaving settles a finished shift's save (waits for the attempt in flight, retries a failed
-- one) before the profile is released.
Players.PlayerRemoving:Connect(function(player)
	CustomerLooks.forget(player)
	ShiftService.leave(player)
end)

-- Server shutdown: settle everyone's saves together within Roblox's 30 s window.
game:BindToClose(function()
	ShiftService.closeAll(25)
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
-- Commands that edit rewards, timing or play are test mutators: refused for a player still on
-- the real save (TestStore.guard), so a test run needs fakeStore first.
local TEST_MUTATORS = { playOut = true, stage = true, act = true, setBake = true, age = true, skipArrivals = true, resetPatience = true }

if RunService:IsStudio() then
	local debug = Instance.new("BindableFunction")
	debug.Name = "RestaurantariaDebug"
	-- userId (optional) picks the player; otherwise the first one.
	debug.OnInvoke = function(command: string, value: any, userId: number?)
		local player = if userId then Players:GetPlayerByUserId(userId) else Players:GetPlayers()[1]
		local session = player and ShiftService.sessions[player]
		if not session then
			return "no session"
		end
		if TEST_MUTATORS[command] then
			local refusal = TestStore.guard(player)
			if refusal then
				return refusal
			end
		end
		if command == "state" then
			local function storeName(store: any): string
				return if store == nil then "none" elseif store == SaveService.realStore then "real" else "fake"
			end
			local lines = { string.format("player=%d lastSeq=%d rejected=%d tips=%d tutorial=%s tutorialBonus=%s finished=%s settlement=%s store=%s shiftStore=%s menu=%s", player.UserId, session.lastSeq, session.rejected, session.shift.tips, tostring(session.shift.tutorial), tostring(session.shift.tutorialBonus), tostring(session.shift.finished), tostring(session.shift.settlement), storeName(SaveService.store), storeName(session.shift.store), table.concat(session.shift.menu, ",")) }
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
				table.insert(lines, string.format("profile %s tips=%d xp=%d shifts=%d tutorialBonusPaid=%s", profile.status, profile.data.tips, profile.data.xp, profile.data.shiftsCompleted, tostring(profile.data.tutorialBonusPaid)))
			end
			return table.concat(lines, "\n")
		elseif command == "mixedOrders" then
			-- value = true/false: the development setting for mixed orders (Config.Dev), for this
			-- server session. Shifts started after it use it; restartShift starts one now.
			Config.Dev.mixedOrders = value == true
			return "ok"
		elseif command == "restartShift" then
			-- Abandons the current shift (no reward, nothing saved) and starts a new one. A real
			-- receipt still saving or waiting for a retry is never abandoned.
			local settlement = session.shift.settlement
			if TestStore.productionBound(player) and (settlement == "pending" or settlement == "retry") then
				return "refused: this shift's real save is not settled yet"
			end
			session.shift = ShiftService.newShift(player)
			push(player)
			return "ok"
		elseif command == "forceTip" then
			-- value = a number of coins every served order earns, or nil to score normally.
			-- Lets a test see the tutorial bonus fire. This player only, on a test store only.
			return TestStore.forceTip(player, value)
		elseif command == "simulateLoadFailure" then
			SaveService.simulateLoadFailure = value == true
			return "ok"
		elseif command == "fakeStore" then
			-- value = { failNext, loseAckNext, delay, fresh }: see TestStore. There is no way back
			-- to the real store within a play session.
			local result = TestStore.command(player, value)
			push(player)
			return result
		elseif command == "reloadProfile" then
			-- Reloads from the store the player is already on, so it never moves a player
			-- between the real and a test store.
			local current = SaveService.profiles[player]
			local profile = SaveService.load(player, current and current.store)
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
		elseif command == "playOut" then
			-- Brings in every remaining customer and makes each one a clean pizza, in order,
			-- through the real actions, so the end-of-shift summary and save can be tested
			-- without a long manual playthrough. Bypasses the client seq so the client keeps
			-- working afterwards.
			local shift = session.shift
			local log = {}
			local function act(action: string, args: any)
				local ok, reason = ShiftService.apply(session, action, args)
				if not ok then
					table.insert(log, action .. ": " .. tostring(reason))
				end
			end
			shift.startedAt -= 1000
			-- A character can only be in the shop once, so later customers walk in as earlier
			-- ones are served: repeat until everyone has come and gone.
			for _round = 1, shift.customerCount + 1 do
				ShiftService.tick(session)
				local clock = workspace:GetServerTimeNow()
				-- Open tickets first so taking new orders never hits the rail limit.
				for _, pass in { "ordered", "waiting" } do
					for _, c in shift.customers do
						if c.status ~= pass then
							continue
						end
						if c.status == "waiting" then
							c.arrivedAt = clock - 20
							act("takeOrder", { customerId = c.id })
						end
						local pizza = shift.pizzas[c.pizzaId]
						if not pizza then
							continue
						end
						if pizza.stage == "topping" then
							for _, req in Recipes.ById[c.order.recipe].toppings do
								for i = 1, req.count do
									local t = (i - 0.5) / req.count
									local a = if req.region == "left" then math.rad(90 + t * 180)
										elseif req.region == "right" then math.rad(-90 + t * 180)
										else math.rad(22.5 + (i - 1) * 360 / req.count)
									act("placeTopping", { pizzaId = pizza.id, ingredient = req.ingredient, x = math.cos(a) * 0.5, y = -math.sin(a) * 0.5 })
								end
							end
							act("sendToOven", { pizzaId = pizza.id })
						end
						if pizza.stage == "oven" then
							pizza.bakeStart = workspace:GetServerTimeNow() - Config.Oven.targets[c.order.bake]
							act("takeOut", { pizzaId = pizza.id })
						end
						if pizza.stage == "cutting" then
							local n = c.order.slices // 2
							for k = 0, n - 1 do
								local a = math.rad(k * 180 / n)
								act("cut", { pizzaId = pizza.id, x1 = math.cos(a) * 1.05, y1 = math.sin(a) * 1.05, x2 = -math.cos(a) * 1.05, y2 = -math.sin(a) * 1.05 })
							end
							act("serve", { pizzaId = pizza.id })
						end
					end
				end
			end
			push(player)
			return if #log == 0 then "ok" else table.concat(log, "\n")
		elseif command == "stage" then
			-- A busy moment for captures, through the real actions: every ticket open, the
			-- first pizza in the oven and the next on the topping station with `value` (0-1) of
			-- its pieces placed.
			local shift = session.shift
			local log = {}
			local function act(action: string, args: any)
				local ok, reason = ShiftService.apply(session, action, args)
				if not ok then
					table.insert(log, action .. ": " .. tostring(reason))
				end
			end
			local function top(pizza: any, recipeId: string, share: number)
				for _, req in Recipes.ById[recipeId].toppings do
					for i = 1, math.round(req.count * share) do
						local t = (i - 0.5) / req.count
						local a = if req.region == "left" then math.rad(90 + t * 180)
							elseif req.region == "right" then math.rad(-90 + t * 180)
							else math.rad(22.5 + (i - 1) * 360 / req.count + (if req.ingredient == "pepper" then 30 else 0))
						local r = if req.ingredient == "pepper" then 0.28 else 0.52
						act("placeTopping", { pizzaId = pizza.id, ingredient = req.ingredient, x = math.cos(a) * r, y = -math.sin(a) * r })
					end
				end
			end
			shift.startedAt -= 1000
			ShiftService.tick(session)
			local clock = workspace:GetServerTimeNow()
			for _, c in shift.customers do
				if c.status == "waiting" then
					c.arrivedAt = clock - 5
					act("takeOrder", { customerId = c.id })
				end
			end
			local open = {}
			for _, c in shift.customers do
				if c.status == "ordered" and c.pizzaId and shift.pizzas[c.pizzaId] then
					table.insert(open, c)
				end
			end
			if open[1] and shift.pizzas[open[1].pizzaId].stage == "topping" then
				top(shift.pizzas[open[1].pizzaId], open[1].order.recipe, 1)
				act("sendToOven", { pizzaId = open[1].pizzaId })
			end
			-- value may be { crowd = true, share = n }: both ovens running and the third pizza on
			-- the topping station (the crowded capture state).
			local crowd = type(value) == "table" and value.crowd
			local share = if type(value) == "table" then value.share or 0.7 else value or 0.7
			if crowd and open[2] and shift.pizzas[open[2].pizzaId].stage == "topping" then
				top(shift.pizzas[open[2].pizzaId], open[2].order.recipe, 1)
				act("sendToOven", { pizzaId = open[2].pizzaId })
				table.remove(open, 2)
			end
			if open[2] and shift.pizzas[open[2].pizzaId].stage == "topping" then
				top(shift.pizzas[open[2].pizzaId], open[2].order.recipe, share)
			end
			push(player)
			return if #log == 0 then "ok" else table.concat(log, "\n")
		elseif command == "act" then
			-- value = { action, args }: one real player action, as if the client sent it.
			local ok, reason = ShiftService.apply(session, value[1], value[2])
			push(player)
			return if ok then "ok" else tostring(reason)
		elseif command == "pieces" then
			-- value = pizzaId: the authoritative piece list (continuity evidence).
			local pizza = session.shift.pizzas[value]
			if not pizza then
				return "no such pizza"
			end
			local rows = { string.format("pizza %d stage=%s pieces=%d cuts=%d", pizza.id, pizza.stage, #pizza.toppings, #pizza.cuts) }
			for i, t in pizza.toppings do
				table.insert(rows, string.format("%02d %s %.3f,%.3f", i, t.ingredient, t.x, t.y))
			end
			return table.concat(rows, "\n")
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
		elseif command == "looks" then
			-- The built customer looks (QA-002 evidence).
			return table.concat(CustomerLooks.describe(), "\n")
		elseif command == "age" then
			-- value = { customerId, seconds }: that customer arrived `seconds` ago (mood captures).
			local customer = nil
			for _, c in session.shift.customers do
				if c.id == value[1] then
					customer = c
				end
			end
			if not customer then
				return "no such customer"
			end
			customer.arrivedAt = workspace:GetServerTimeNow() - value[2]
			push(player)
			return "ok"
		end
		return "unknown command"
	end
	debug.Parent = ServerStorage
end
