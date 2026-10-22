--!strict
-- Authoritative shift state, one per player. The client only sends intents; every
-- timestamp, legality check, grade and reward is decided here.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Scoring = require(Shared.Scoring)
local CustomerLooks = require(script.Parent.CustomerLooks)
local SaveService = require(script.Parent.SaveService)

type Order = { recipe: string, bake: string, slices: number }
type Customer = {
	id: number,
	-- Personality pool (Recipes.Cast), the appearance (a CustomerLooks key) and the name
	-- shown for it; label is the name, or @username when two share one this shift.
	cast: number,
	look: string,
	name: string,
	username: string?,
	label: string,
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
	-- Recipes this shift's orders use and the ingredients those need (the topping trays),
	-- fixed when the shift starts.
	menu: { string },
	ingredients: { string },
	-- Customers this shift serves, fixed when it starts.
	customerCount: number,
	startedAt: number,
	nextArrival: number,
	nextId: number,
	customers: { Customer },
	pizzas: { [number]: Pizza },
	ovens: { [number]: number | false },
	tips: number,
	xp: number,
	-- The save's first shift. Its first served order may earn the one-time tutorial bonus,
	-- kept apart from tips.
	tutorial: boolean,
	tutorialBonus: number?,
	finished: boolean,
	-- Set when the shift ends: the rewards to commit, unchanged on every attempt.
	receipt: SaveService.Receipt?,
	-- nil while running, then "pending" (being saved), "saved", "session" (kept for this
	-- session only, by design) or "retry" (the save failed; the receipt waits for another
	-- attempt). The next shift can't start until it is "saved" or "session".
	settlement: string?,
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

-- The save's unlocked recipes, or every recipe while the development setting for mixed
-- orders is on.
local function menuFor(player: Player): { string }
	if Config.Dev.mixedOrders then
		return Recipes.all()
	end
	local profile = SaveService.profiles[player]
	return table.clone(if profile then profile.data.unlockedRecipes else Recipes.Starting)
end

local function isTutorial(player: Player): boolean
	local profile = SaveService.profiles[player]
	return profile ~= nil and profile.data.shiftsCompleted == 0
end

-- One customer on a save's first shift (the tutorial), the full count after it.
local function customerCountFor(player: Player): number
	if isTutorial(player) then
		return Config.Shift.tutorialCustomers
	end
	return Config.Shift.customerCount
end

-- Coins that top the tutorial's first completed order up to the guarantee.
function ShiftService.tutorialBonusFor(tip: number): number
	return math.max(0, Config.Rewards.tutorialGuarantee - tip)
end

-- Studio test hook: when set, each served order's coins are forced to this value, so the
-- tutorial bonus can be seen firing (it never fires under today's grade formula).
ShiftService.devForcedTip = nil :: number?

function ShiftService.newShift(player: Player): Shift
	local menu = menuFor(player)
	return {
		id = HttpService:GenerateGUID(false),
		menu = menu,
		ingredients = Recipes.ingredientsFor(menu),
		customerCount = customerCountFor(player),
		startedAt = now(),
		nextArrival = 1,
		nextId = 1,
		customers = {},
		pizzas = {},
		ovens = { false, false },
		tips = 0,
		xp = 0,
		tutorial = isTutorial(player),
		tutorialBonus = nil,
		finished = false,
	}
end

function ShiftService.start(player: Player): Session
	local session: Session = {
		player = player,
		lastSeq = 0,
		tokens = Config.Net.maxActionsPerSecond,
		tokenTime = os.clock(),
		shift = ShiftService.newShift(player),
		rejected = 0,
		version = 0,
	}
	ShiftService.sessions[player] = session
	return session
end

function ShiftService.stop(player: Player)
	-- Leaving mid-shift abandons it: no reward, no penalty. A finished shift whose save
	-- failed gets one last attempt with its receipt before the profile is released.
	local session = ShiftService.sessions[player]
	ShiftService.sessions[player] = nil
	if session and session.shift.settlement == "retry" and session.shift.receipt then
		SaveService.commitShift(player, session.shift.receipt)
	end
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

-- Two customers with the same display name in one shift both show their @username.
local function relabel(shift: Shift)
	local count = {}
	for _, c in shift.customers do
		count[c.name:lower()] = (count[c.name:lower()] or 0) + 1
	end
	for _, c in shift.customers do
		c.label = if count[c.name:lower()] > 1 and c.username then "@" .. c.username else c.name
	end
end

-- Spawns due customers. Returns true when something changed.
-- Each appearance is one person: someone who is waiting or has an open ticket is not in the
-- shop twice. A due customer is admitted only once a look is ready for them (CustomerLooks
-- prepares them offstage); until then, or while every look is in the shop, the arrival waits,
-- and patience starts from the moment they actually walk in.
function ShiftService.tick(session: Session): boolean
	local shift = session.shift
	if shift.finished then
		return false
	end
	local changed = false
	local t = now()
	local elapsed = t - shift.startedAt
	while shift.nextArrival <= shift.customerCount and elapsed >= Config.Shift.arrivals[shift.nextArrival] do
		local i = shift.nextArrival
		local present, visits, names = {}, {}, {}
		for _, c in shift.customers do
			if c.status ~= "served" then
				present[c.look] = true
			end
			visits[c.look] = (visits[c.look] or 0) + 1
			if c.username then
				names[c.name:lower()] = true
			end
		end
		local look = CustomerLooks.pick(session.player, present, visits, names, i)
		if not look then
			break
		end
		local order = Recipes.menuOrder(shift.menu, i)
		table.insert(shift.customers, {
			id = shift.nextId,
			cast = look.pool,
			look = look.key,
			name = look.name,
			username = look.username,
			label = look.name,
			order = order,
			arrivedAt = math.max(shift.startedAt + Config.Shift.arrivals[i], t - 1),
			status = "waiting",
		})
		shift.nextId += 1
		shift.nextArrival += 1
		relabel(shift)
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
	if not table.find(shift.ingredients, args.ingredient) then
		return false, "ingredient not unlocked"
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

-- Commits the finished shift's receipt in the background (the save can retry for several
-- seconds; don't hold the reply for it). One attempt at a time.
local function settle(session: Session, shift: Shift)
	if shift.settlement == "pending" or not shift.receipt then
		return
	end
	shift.settlement = "pending"
	shift.saveMessage = "Saving..."
	task.spawn(function()
		local outcome = SaveService.commitShift(session.player, shift.receipt :: SaveService.Receipt)
		if outcome.bonusPaid ~= nil and shift.tutorialBonus ~= nil then
			-- What the save actually paid: 0 if this save had already used its bonus. A failed
			-- save leaves the requested amount in place.
			shift.tutorialBonus = outcome.bonusPaid
		end
		shift.settlement = outcome.state
		shift.saveMessage = outcome.message
		if ShiftService.changed then
			ShiftService.changed(session.player)
		end
	end)
end

local function finishIfDone(session: Session)
	local shift = session.shift
	if shift.finished or shift.nextArrival <= shift.customerCount then
		return
	end
	for _, c in shift.customers do
		if c.status ~= "served" then
			return
		end
	end
	shift.finished = true
	shift.receipt = table.freeze({ shiftId = shift.id, tips = shift.tips, xp = shift.xp, tutorialBonus = shift.tutorialBonus })
	settle(session, shift)
end
-- For tests.
ShiftService.finishIfDone = finishIfDone

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
	if ShiftService.devForcedTip and RunService:IsStudio() then
		tip = ShiftService.devForcedTip :: number
	end
	-- The tutorial's first completed order is topped up to the guarantee by a separate bonus;
	-- the grade and the order's own coins stay as earned. Paid by commitShift, once per save.
	local tutorialBonus = nil
	if shift.tutorial and shift.tutorialBonus == nil then
		tutorialBonus = ShiftService.tutorialBonusFor(tip)
		shift.tutorialBonus = tutorialBonus
	end

	pizza.stage = "served"
	customer.status = "served"
	customer.result = { wait = wait, topping = topping, bake = bake, cut = cut, overall = overall, tip = tip, tutorialBonus = tutorialBonus }
	shift.tips += tip
	shift.xp += math.floor(Config.Rewards.xpPerOrder * overall / 100 + 0.5)
	finishIfDone(session)
	return true, nil
end

function Actions.newShift(shift: Shift, _args: any, session: Session): (boolean, string?)
	if not shift.finished then
		return false, "shift still running"
	end
	-- The next shift starts from the saved profile, so this one's rewards must be settled
	-- first: never replaced while saving or after a failed save.
	if shift.settlement == "pending" then
		return false, "progress still saving"
	elseif shift.settlement ~= "saved" and shift.settlement ~= "session" then
		return false, "progress not saved yet"
	end
	session.shift = ShiftService.newShift(session.player)
	return true, nil
end

-- Commits a finished shift's receipt again after a failed save.
function Actions.retrySave(shift: Shift, _args: any, session: Session): (boolean, string?)
	if not shift.finished then
		return false, "shift still running"
	end
	if shift.settlement ~= "retry" then
		return false, if shift.settlement == "pending" then "progress still saving" else "nothing to retry"
	end
	settle(session, shift)
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
	if session.shift.finished and action ~= "newShift" and action ~= "retrySave" then
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
		menu = shift.menu,
		ingredients = shift.ingredients,
		customerCount = shift.customerCount,
		startedAt = shift.startedAt,
		customers = shift.customers,
		pizzas = pizzas,
		ovens = shift.ovens,
		tips = shift.tips,
		-- Shown on its own line; never part of tips.
		tutorialBonus = shift.tutorialBonus or 0,
		xp = shift.xp,
		finished = shift.finished,
		settlement = shift.settlement,
		-- True once this shift's tips are inside profile.tips (saved, or kept in memory after
		-- a failed load), so the HUD never counts them twice.
		recorded = profile ~= nil and table.find(profile.data.recentShiftIds, shift.id) ~= nil,
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
