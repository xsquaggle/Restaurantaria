--!strict
-- Authoritative shift state, one per player. The client only sends intents; every
-- timestamp, legality check, grade and reward is decided here.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local MakeCheese = require(Shared.MakeCheese)
local MakeDough = require(Shared.MakeDough)
local MakeSauce = require(Shared.MakeSauce)
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
	stage: string, -- "topping" (the Make tab) | "oven" | "cutting" | "served"
	-- The Make tab's steps (MakeDough's record: dough, then sauce, cheese and toppings); toppings
	-- and Send to oven only once make.step is "toppings".
	make: MakeDough.Make,
	toppings: { Scoring.Piece },
	slot: number?,
	bakeStart: number?,
	bakeSeconds: number?,
	cuts: { Scoring.Cut },
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
	-- The day this shift is (the save's completed shifts + 1 when it began). The summary names
	-- it as the completed day and the HUD keeps it until the next shift starts (QA-013).
	day: number,
	-- The save's first shift. Its first served order may earn the one-time tutorial bonus,
	-- kept apart from tips.
	tutorial: boolean,
	tutorialBonus: number?,
	finished: boolean,
	-- The save store of the profile this shift began on; its receipt is only written there.
	store: any?,
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
	-- Set once the player is leaving (or the server closing): no more intents are accepted.
	leaving: boolean?,
	-- Studio test hook (TestStore.forceTip): each served order's coins are forced to this, so
	-- the tutorial bonus can be seen firing. Ignored on a shift bound to the production store.
	devForcedTip: number?,
}

-- How long leaving waits for a finished shift's save, inside Roblox's 30 s shutdown window.
local LEAVE_SECONDS = 25

local ShiftService = {}
ShiftService.sessions = {} :: { [Player]: Session }
-- Called when state changes outside a client request (a save finishing), so Main can push.
ShiftService.changed = nil :: ((Player) -> ())?

local function now(): number
	return workspace:GetServerTimeNow()
end

-- The save's unlocked recipes, or every recipe while the development setting for mixed
-- orders is on. A shift on the production store always uses the save's recipes.
local function menuFor(player: Player): { string }
	local profile = SaveService.profiles[player]
	if Config.Dev.mixedOrders and not (profile and SaveService.kindOf(profile.store) == "production") then
		return Recipes.all()
	end
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

function ShiftService.newShift(player: Player): Shift
	local menu = menuFor(player)
	local profile = SaveService.profiles[player]
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
		day = (if profile then profile.data.shiftsCompleted else 0) + 1,
		tutorial = isTutorial(player),
		tutorialBonus = nil,
		finished = false,
		store = if profile then profile.store else nil,
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
	local pizza: Pizza = { id = shift.nextId, ticketId = customer.id, stage = "topping", make = MakeDough.new(), toppings = {}, cuts = {} }
	shift.nextId += 1
	shift.pizzas[pizza.id] = pizza
	customer.pizzaId = pizza.id
	return true, nil
end

local STEP_ORDER = { dough = 1, sauce = 2, cheese = 3, toppings = 4 }

-- A pizza on the Make tab at its given step ("dough", "sauce", "cheese" or "toppings").
local function makePizza(shift: Shift, id: any, step: string): (Pizza?, string?)
	local pizza, err = getPizza(shift, id, "topping")
	if not pizza then
		return nil, err
	end
	local at = pizza.make.step
	if at ~= step then
		if (STEP_ORDER[at] or 0) > STEP_ORDER[step] then
			return nil, step .. " is done"
		end
		return nil, if at == "dough" and step == "toppings" then "dough not finished" else "not at the " .. step .. " step"
	end
	return pizza, nil
end

-- Make, dough step: one flour stroke (its dust stamps), sent whole on release.
function Actions.flour(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "dough")
	if not pizza then
		return false, err
	end
	local stroke, reason = MakeDough.validateFlour(pizza.make, args.points)
	if not stroke then
		return false, reason
	end
	table.insert(pizza.make.flour, stroke)
	return true, nil
end

-- Make, dough step: pull the dough ball onto the board (it lands in the centre). The board is
-- floured first.
function Actions.placeDough(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "dough")
	if not pizza then
		return false, err
	end
	if pizza.make.placed then
		return false, "the dough is already on the board"
	end
	if #pizza.make.flour == 0 then
		return false, "flour the board first"
	end
	pizza.make.placed = true
	return true, nil
end

-- Make, dough step: one roll, press to release.
function Actions.rollDough(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "dough")
	if not pizza then
		return false, err
	end
	local line, reason = MakeDough.validateRoll(pizza.make, args)
	if not line then
		return false, reason
	end
	table.insert(pizza.make.strokes, line)
	return true, nil
end

-- Make, dough step: takes back the last roll; with none, lifts the ball off the board; with the
-- ball off, removes the last flour stroke.
function Actions.undoDough(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "dough")
	if not pizza then
		return false, err
	end
	local make = pizza.make
	if #make.strokes > 0 then
		table.remove(make.strokes)
	elseif make.placed then
		make.placed = false
	elseif #make.flour > 0 then
		table.remove(make.flour)
	else
		return false, "nothing to undo"
	end
	return true, nil
end

-- Make: the dough is done and the pizza moves on to the sauce. `from` guards a double tap.
function Actions.finishDough(shift: Shift, args: any): (boolean, string?)
	if args.from ~= "dough" then
		return false, "bad step"
	end
	local pizza, err = makePizza(shift, args.pizzaId, "dough")
	if not pizza then
		return false, err
	end
	if not MakeDough.canFinish(pizza.make) then
		return false, "roll the dough first"
	end
	pizza.make.step = "sauce"
	return true, nil
end

-- Make, sauce step: one ladle at a dough-local point on the dough.
function Actions.pourSauce(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "sauce")
	if not pizza then
		return false, err
	end
	local action, reason = MakeSauce.validatePour(pizza.make.sauce, args)
	if not action then
		return false, reason
	end
	table.insert(pizza.make.sauce.actions, action)
	return true, nil
end

-- Make, sauce step: one spread stroke, its dragged path (dough-local), sent whole on release.
-- It must cross sauce.
function Actions.spreadSauce(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "sauce")
	if not pizza then
		return false, err
	end
	local action, reason = MakeSauce.validateSpread(pizza.make.sauce, args)
	if not action then
		return false, reason
	end
	table.insert(pizza.make.sauce.actions, action)
	return true, nil
end

-- Make, sauce step: takes back the last pour or spread.
function Actions.undoSauce(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "sauce")
	if not pizza then
		return false, err
	end
	if #pizza.make.sauce.actions == 0 then
		return false, "nothing to undo"
	end
	table.remove(pizza.make.sauce.actions)
	return true, nil
end

-- Make: the sauce is done (a pour and a spread that moved sauce, at least) and the pizza moves
-- on to the cheese.
function Actions.finishSauce(shift: Shift, args: any): (boolean, string?)
	if args.from ~= "sauce" then
		return false, "bad step"
	end
	local pizza, err = makePizza(shift, args.pizzaId, "sauce")
	if not pizza then
		return false, err
	end
	if not MakeSauce.canFinish(pizza.make.sauce) then
		return false, "pour and spread the sauce first"
	end
	pizza.make.step = "cheese"
	return true, nil
end

-- Make, cheese step: one batch of a held sprinkle's pinches. The whole batch is checked first
-- (MakeCheese.validate); a refused batch changes nothing, not even an empty stroke.
function Actions.addCheese(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "cheese")
	if not pizza then
		return false, err
	end
	local points, newStroke, reason = MakeCheese.validate(pizza.make.cheese, args)
	if not points then
		return false, reason
	end
	MakeCheese.add(pizza.make.cheese, points, newStroke)
	return true, nil
end

-- Make, cheese step: takes back the last sprinkle (every pinch of it).
function Actions.undoCheese(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "cheese")
	if not pizza then
		return false, err
	end
	if #pizza.make.cheese.strokes == 0 then
		return false, "nothing to undo"
	end
	table.remove(pizza.make.cheese.strokes)
	return true, nil
end

-- Make: the cheese is done (one pinch at least) and the pizza moves on to its toppings, or
-- straight to Send to oven on a ticket without any.
function Actions.finishCheese(shift: Shift, args: any): (boolean, string?)
	if args.from ~= "cheese" then
		return false, "bad step"
	end
	local pizza, err = makePizza(shift, args.pizzaId, "cheese")
	if not pizza then
		return false, err
	end
	if not MakeCheese.canFinish(pizza.make.cheese) then
		return false, "sprinkle some cheese first"
	end
	pizza.make.step = "toppings"
	return true, nil
end

function Actions.placeTopping(shift: Shift, args: any): (boolean, string?)
	local pizza, err = makePizza(shift, args.pizzaId, "toppings")
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
	local pizza, err = makePizza(shift, args.pizzaId, "toppings")
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
	local pizza, err = makePizza(shift, args.pizzaId, "toppings")
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
	if #pizza.cuts >= Config.Cut.maxLines then
		return false, "already cut " .. Config.Cut.maxLines .. " times"
	end
	-- Freehand: the client sends the dragged path; the server grades and keeps it (the path's
	-- best-fit chord, the path itself and its straightness and completeness).
	local cut, reason = Scoring.cutPath(args.path)
	if not cut then
		return false, reason
	end
	table.insert(pizza.cuts, cut)
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
	shift.receipt = table.freeze({ shiftId = shift.id, tips = shift.tips, xp = shift.xp, tutorialBonus = shift.tutorialBonus, store = shift.store, completedShiftDay = shift.day })
	settle(session, shift)
end
-- For tests.
ShiftService.finishIfDone = finishIfDone

local function waitUntil(done: () -> boolean, deadline: number)
	while not done() and os.clock() < deadline do
		task.wait(0.1)
	end
end

-- The player is leaving, or the server is closing. A running shift is abandoned: no reward,
-- no penalty. A finished shift's save is settled before the caller releases the profile: an
-- attempt in flight is waited for, never raced, and a failed one gets one more attempt with
-- the same receipt. Bounded by deadline (os.clock, default 25 s from now); past it the
-- receipt may stay unsaved, and a warning says so. A second call while the first is still
-- settling waits for it. Returns the shift's settlement (nil for an abandoned shift).
function ShiftService.stop(player: Player, deadline: number?): string?
	local session = ShiftService.sessions[player]
	if not session then
		return nil
	end
	local limit = deadline or os.clock() + LEAVE_SECONDS
	local shift = session.shift
	if session.leaving then
		waitUntil(function()
			return ShiftService.sessions[player] ~= session
		end, limit)
		return shift.settlement
	end
	session.leaving = true
	if shift.finished and shift.receipt then
		local function notPending()
			return shift.settlement ~= "pending"
		end
		waitUntil(notPending, limit)
		if shift.settlement == "retry" and os.clock() < limit then
			settle(session, shift)
			waitUntil(notPending, limit)
		end
		if shift.settlement ~= "saved" and shift.settlement ~= "session" then
			warn(string.format("[Save] %s left before shift %s was saved (%s)", player.Name, shift.id, tostring(shift.settlement)))
		end
	end
	if ShiftService.sessions[player] == session then
		ShiftService.sessions[player] = nil
	end
	return shift.settlement
end

-- stop, then release the player's profile.
function ShiftService.leave(player: Player, deadline: number?): string?
	local settlement = ShiftService.stop(player, deadline)
	SaveService.release(player)
	return settlement
end

-- Server shutdown (BindToClose): every player leaves at once, all within `seconds`.
function ShiftService.closeAll(seconds: number)
	local deadline = os.clock() + seconds
	local open = 0
	for player in ShiftService.sessions do
		open += 1
		task.spawn(function()
			local ok, err = pcall(ShiftService.leave, player, deadline)
			if not ok then
				warn("[Save] closing: " .. tostring(err))
			end
			open -= 1
		end)
	end
	waitUntil(function()
		return open == 0
	end, deadline)
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
	local make = Scoring.make(recipe, pizza.make, pizza.toppings)
	local bake = Scoring.bake(order.bake, pizza.bakeSeconds :: number)
	local cut = Scoring.cut(order.slices, pizza.cuts)
	-- The join (Config.Grade): the grade, its ceiling, the pay and the XP, all from the parts.
	local order_ = Scoring.order(wait, make, bake, cut)
	local overall = order_.grade
	if order_.held then
		table.insert(make.notes, 1, string.format("%s: grade held to %d", order_.held.note, order_.held.value))
	end
	local tip = order_.coins
	if session.devForcedTip and RunService:IsStudio() and SaveService.kindOf(shift.store) ~= "production" then
		tip = session.devForcedTip :: number
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
	customer.result = {
		wait = wait,
		make = make,
		bake = bake,
		cut = cut,
		overall = overall,
		join = order_.join,
		weighted = order_.weighted,
		paid = order_.paid,
		held = order_.held,
		xp = order_.xp,
		tip = tip,
		tutorialBonus = tutorialBonus,
	}
	shift.tips += tip
	shift.xp += order_.xp
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
	if session.leaving then
		return reject("leaving")
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
		day = shift.day,
		-- From the receipt: set once the shift has finished, never moved by the save result.
		completedShiftDay = if shift.receipt then shift.receipt.completedShiftDay else nil,
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
