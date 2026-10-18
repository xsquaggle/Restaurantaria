--!strict
-- Authoritative shift state, one per player. The client only sends intents; every
-- timestamp, legality check, grade and reward is decided here.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Scoring = require(Shared.Scoring)
local SaveService = require(script.Parent.SaveService)

type Order = { recipe: string, bake: string, slices: number }
type Customer = {
	id: number,
	cast: number,
	order: Order,
	arrivedAt: number,
	status: string, -- "waiting" | "ordered" | "served"
	pizzaId: number?,
	result: any?,
}
type Pizza = {
	id: number,
	ticketId: number,
	stage: string, -- "topping" | "oven" | "cutting" | "served"
	toppings: { Scoring.Piece },
	slot: number?,
	bakeStart: number?,
	bakeSeconds: number?,
	cuts: { Scoring.Line },
}
type Shift = {
	id: string,
	startedAt: number,
	nextArrival: number,
	nextId: number,
	customers: { Customer },
	pizzas: { [number]: Pizza },
	ovens: { [number]: number | false },
	tips: number,
	xp: number,
	finished: boolean,
	saved: boolean?,
	saveMessage: string?,
}
type Session = {
	player: Player,
	lastSeq: number,
	tokens: number,
	tokenTime: number,
	shift: Shift,
	rejected: number,
	version: number,
}

local ShiftService = {}
ShiftService.sessions = {} :: { [Player]: Session }
-- Called when state changes outside a client request (a save finishing), so Main can push.
ShiftService.changed = nil :: ((Player) -> ())?

local function now(): number
	return workspace:GetServerTimeNow()
end

local function newShift(): Shift
	return {
		id = HttpService:GenerateGUID(false),
		startedAt = now(),
		nextArrival = 1,
		nextId = 1,
		customers = {},
		pizzas = {},
		ovens = { false, false },
		tips = 0,
		xp = 0,
		finished = false,
	}
end

function ShiftService.start(player: Player): Session
	local session: Session = {
		player = player,
		lastSeq = 0,
		tokens = Config.Net.maxActionsPerSecond,
		tokenTime = os.clock(),
		shift = newShift(),
		rejected = 0,
		version = 0,
	}
	ShiftService.sessions[player] = session
	return session
end

function ShiftService.stop(player: Player)
	-- Leaving mid-shift abandons it: no reward, no penalty.
	ShiftService.sessions[player] = nil
end

local function activeTickets(shift: Shift): number
	local n = 0
	for _, c in shift.customers do
		if c.status == "ordered" then
			n += 1
		end
	end
	return n
end

local function customerById(shift: Shift, id: number): Customer?
	for _, c in shift.customers do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- Spawns due customers. Returns true when something changed.
function ShiftService.tick(session: Session): boolean
	local shift = session.shift
	if shift.finished then
		return false
	end
	local changed = false
	local elapsed = now() - shift.startedAt
	while shift.nextArrival <= Config.Shift.customerCount and elapsed >= Config.Shift.arrivals[shift.nextArrival] do
		local i = shift.nextArrival
		local orderDef = Recipes.ShiftOrders[((i - 1) % #Recipes.ShiftOrders) + 1]
		table.insert(shift.customers, {
			id = shift.nextId,
			cast = ((i - 1) % #Recipes.Cast) + 1,
			order = { recipe = orderDef.recipe, bake = orderDef.bake, slices = orderDef.slices },
			arrivedAt = shift.startedAt + Config.Shift.arrivals[i],
			status = "waiting",
		})
		shift.nextId += 1
		shift.nextArrival += 1
		changed = true
	end
	return changed
end

------------------------------------------------------------------------------------------
-- Argument validation

local function isFiniteNumber(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v >= lo and v <= hi
end

local function isId(v: any): boolean
	return type(v) == "number" and v == v and v >= 1 and v <= 1e6 and v % 1 == 0
end

local function getPizza(shift: Shift, id: any, stage: string): (Pizza?, string?)
	if not isId(id) then
		return nil, "bad pizza id"
	end
	local pizza = shift.pizzas[id]
	if not pizza then
		return nil, "no such pizza"
	end
	if pizza.stage ~= stage then
		return nil, "pizza is not at " .. stage
	end
	return pizza, nil
end

------------------------------------------------------------------------------------------
-- Actions. Each returns (ok, reason).

local Actions = {}

function Actions.takeOrder(shift: Shift, args: any): (boolean, string?)
	if not isId(args.customerId) then
		return false, "bad customer id"
	end
	local customer = customerById(shift, args.customerId)
	if not customer or customer.status ~= "waiting" then
		return false, "customer is not waiting"
	end
	if activeTickets(shift) >= Config.Shift.maxActiveTickets then
		return false, "ticket rail is full"
	end
	customer.status = "ordered"
	local pizza: Pizza = { id = shift.nextId, ticketId = customer.id, stage = "topping", toppings = {}, cuts = {} }
	shift.nextId += 1
	shift.pizzas[pizza.id] = pizza
	customer.pizzaId = pizza.id
	return true, nil
end

function Actions.placeTopping(shift: Shift, args: any): (boolean, string?)
	local pizza, err = getPizza(shift, args.pizzaId, "topping")
	if not pizza then
		return false, err
	end
	if type(args.ingredient) ~= "string" or not Recipes.Ingredients[args.ingredient] then
		return false, "unknown ingredient"
	end
	if not isFiniteNumber(args.x, -1, 1) or not isFiniteNumber(args.y, -1, 1) then
		return false, "position out of range"
	end
	if args.x * args.x + args.y * args.y > Config.Topping.placeRadius ^ 2 then
		return false, "off the pizza"
	end
	if #pizza.toppings >= Config.Topping.maxPieces then
		return false, "too many toppings"
	end
	table.insert(pizza.toppings, { ingredient = args.ingredient, x = args.x, y = args.y })
	return true, nil
end

function Actions.undoTopping(shift: Shift, args: any): (boolean, string?)
	local pizza, err = getPizza(shift, args.pizzaId, "topping")
	if not pizza then
		return false, err
	end
	if #pizza.toppings == 0 then
		return false, "nothing to undo"
	end
	table.remove(pizza.toppings)
	return true, nil
end

function Actions.sendToOven(shift: Shift, args: any): (boolean, string?)
	local pizza, err = getPizza(shift, args.pizzaId, "topping")
	if not pizza then
		return false, err
	end
	for slot = 1, Config.Oven.slots do
		if shift.ovens[slot] == false then
			shift.ovens[slot] = pizza.id
			pizza.stage = "oven"
			pizza.slot = slot
			pizza.bakeStart = now()
			return true, nil
		end
	end
	return false, "both oven slots are full"
end

function Actions.takeOut(shift: Shift, args: any): (boolean, string?)
	local pizza, err = getPizza(shift, args.pizzaId, "oven")
	if not pizza then
		return false, err
	end
	pizza.bakeSeconds = now() - (pizza.bakeStart :: number)
	shift.ovens[pizza.slot :: number] = false
	pizza.slot = nil
	pizza.stage = "cutting"
	return true, nil
end

function Actions.cut(shift: Shift, args: any): (boolean, string?)
	local pizza, err = getPizza(shift, args.pizzaId, "cutting")
	if not pizza then
		return false, err
	end
	for _, k in { "x1", "y1", "x2", "y2" } do
		if not isFiniteNumber(args[k], -1.6, 1.6) then
			return false, "cut out of range"
		end
	end
	local dx, dy = args.x2 - args.x1, args.y2 - args.y1
	if math.sqrt(dx * dx + dy * dy) < Config.Cut.minDragLength then
		return false, "cut too short"
	end
	if #pizza.cuts >= Config.Cut.maxLines then
		return false, "already cut " .. Config.Cut.maxLines .. " times"
	end
	table.insert(pizza.cuts, { x1 = args.x1, y1 = args.y1, x2 = args.x2, y2 = args.y2 })
	return true, nil
end

function Actions.undoCut(shift: Shift, args: any): (boolean, string?)
	local pizza, err = getPizza(shift, args.pizzaId, "cutting")
	if not pizza then
		return false, err
	end
	if #pizza.cuts == 0 then
		return false, "nothing to undo"
	end
	table.remove(pizza.cuts)
	return true, nil
end

local function finishIfDone(session: Session)
	local shift = session.shift
	if shift.nextArrival <= Config.Shift.customerCount then
		return
	end
	for _, c in shift.customers do
		if c.status ~= "served" then
			return
		end
	end
	shift.finished = true
	shift.saveMessage = "Saving..."
	-- The save can retry for several seconds; don't hold the Serve reply for it.
	task.spawn(function()
		local saved, message = SaveService.commitShift(session.player, shift.id, shift.tips, shift.xp)
		shift.saved = saved
		shift.saveMessage = if saved then nil else message
		if ShiftService.changed then
			ShiftService.changed(session.player)
		end
	end)
end

function Actions.serve(shift: Shift, args: any, session: Session): (boolean, string?)
	local pizza, err = getPizza(shift, args.pizzaId, "cutting")
	if not pizza then
		return false, err
	end
	local customer = customerById(shift, pizza.ticketId)
	if not customer or customer.status ~= "ordered" then
		return false, "ticket is not open"
	end
	local order = customer.order
	local recipe = Recipes.ById[order.recipe]
	local wait = Scoring.wait(Scoring.patienceFraction(customer.arrivedAt, now()))
	local topping = Scoring.toppings(recipe, pizza.toppings)
	local bake = Scoring.bake(order.bake, pizza.bakeSeconds :: number)
	local cut = Scoring.cut(order.slices, pizza.cuts)
	local overall = math.floor((wait.score + topping.score + bake.score + cut.score) / 4 + 0.5)
	local tip = math.floor(Config.Rewards.baseTip * overall / 100 + 0.5)

	pizza.stage = "served"
	customer.status = "served"
	customer.result = { wait = wait, topping = topping, bake = bake, cut = cut, overall = overall, tip = tip }
	shift.tips += tip
	shift.xp += math.floor(Config.Rewards.xpPerOrder * overall / 100 + 0.5)
	finishIfDone(session)
	return true, nil
end

function Actions.newShift(shift: Shift, _args: any, session: Session): (boolean, string?)
	if not shift.finished then
		return false, "shift still running"
	end
	session.shift = newShift()
	return true, nil
end

-- Runs one action without the sequence and rate checks. Only for trusted server code
-- (the Studio test hook); client intents always go through handle().
function ShiftService.apply(session: Session, action: string, args: any): (boolean, string?)
	return Actions[action](session.shift, args, session)
end

------------------------------------------------------------------------------------------

local function takeToken(session: Session): boolean
	local t = os.clock()
	local rate = Config.Net.maxActionsPerSecond
	session.tokens = math.min(rate, session.tokens + (t - session.tokenTime) * rate)
	session.tokenTime = t
	if session.tokens < 1 then
		return false
	end
	session.tokens -= 1
	return true
end

-- Entry point for every client intent. seq must strictly increase per session, which
-- rejects replayed or duplicated requests.
function ShiftService.handle(player: Player, seq: any, action: any, args: any): (boolean, string?)
	local session = ShiftService.sessions[player]
	if not session then
		return false, "no session"
	end
	local function reject(reason: string): (boolean, string?)
		session.rejected += 1
		return false, reason
	end
	if not isId(seq) then
		return reject("bad sequence")
	end
	if seq <= session.lastSeq then
		return reject("replayed request")
	end
	session.lastSeq = seq
	if not takeToken(session) then
		return reject("too many requests")
	end
	if type(action) ~= "string" or not Actions[action] then
		return reject("unknown action")
	end
	if type(args) ~= "table" then
		return reject("bad arguments")
	end
	if session.shift.finished and action ~= "newShift" then
		return reject("shift is over")
	end
	local ok, reason = Actions[action](session.shift, args, session)
	if not ok then
		return reject(reason or "rejected")
	end
	return true, nil
end

function ShiftService.snapshot(player: Player): any
	local session = ShiftService.sessions[player]
	if not session then
		return nil
	end
	local shift = session.shift
	local profile = SaveService.profiles[player]
	-- Snapshots can arrive out of order (pushes vs. call replies); clients keep the newest.
	session.version += 1
	local pizzas = {}
	for _, p in shift.pizzas do
		table.insert(pizzas, p)
	end
	table.sort(pizzas, function(a, b)
		return a.id < b.id
	end)
	return {
		version = session.version,
		shiftId = shift.id,
		startedAt = shift.startedAt,
		customers = shift.customers,
		pizzas = pizzas,
		ovens = shift.ovens,
		tips = shift.tips,
		xp = shift.xp,
		finished = shift.finished,
		saved = shift.saved,
		saveMessage = shift.saveMessage,
		lastSeq = session.lastSeq,
		rejected = session.rejected,
		profile = if profile
			then {
				status = profile.status,
				message = profile.message,
				tips = profile.data.tips,
				xp = profile.data.xp,
				rank = SaveService.rank(profile.data.xp),
				shiftsCompleted = profile.data.shiftsCompleted,
			}
			else nil,
	}
end

return ShiftService
