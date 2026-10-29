-- Wrong-ticket Serve (Astra r17 R17-02, r19 D1). Slice 4's capture a15 showed Serve acting on
-- Bo's uncut pizza while a cut pizza sat on the board; the cause was not established. Reading
-- the client: the Serve button fires on release (Activated) and checks only that some pizza is
-- on the board and not being served, so a press held across the board changing serves the new
-- pizza, and so does an impatient second tap once the first serve's reply has swapped the board
-- (the button's repeat guard is 0.35 s; a reply takes longer). The "before" rows replay the old
-- rule (Stations/Cut at the slice 7a build, replicated below) on those timelines and are
-- expected to show the fault; the "after" rows run ServeGate and must not. Then the server:
-- a pizza that is not the shown ticket's is refused and nothing changes. Mock only: run it with
-- tests/offline/run.py or inside Studio.

local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local ServeGate = require(Client.ServeGate)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local ShiftService = require(game:GetService("ServerScriptService").Server.ShiftService)

local failures = {}
local passed = 0
local report = {}
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

local REPEAT = 0.35 -- Theme.Motion.repeatGuard
local A = { id = 81, ticket = 80 } -- the cut pizza on the board
local B = { id = 83, ticket = 82 } -- Bo's uncut pizza, next in line

-- The old rule: enabled = a pizza on the board and not pending, checked at release; the
-- activation serves whatever the board's pizza is at that moment.
local function oldRun(events: { any }): { number }
	local shown, pending, lastFired, served = nil :: any, {}, -math.huge, {}
	for _, e in events do
		if e.kind == "board" then
			shown = e.pizza
		elseif e.kind == "reply" then
			pending[e.pizza.id] = nil
		elseif e.kind == "release" then
			local enabled = shown ~= nil and not pending[shown.id]
			if enabled and e.t - lastFired >= REPEAT then
				lastFired = e.t
				pending[shown.id] = true
				table.insert(served, shown.id)
			end
		end
	end
	return served
end

-- The new rule, as Stations/Cut drives the gate: show on every refresh, press on the press,
-- the button enabled whenever a pizza is shown (the settle is invisible), and the activation's
-- intent.
local function newRun(events: { any }): ({ number }, { string })
	local g = ServeGate.new()
	local pending, lastFired, served, why = {}, -math.huge, {}, {}
	for _, e in events do
		if e.kind == "board" then
			ServeGate.show(g, e.pizza and e.pizza.id, e.pizza and e.pizza.ticket, e.t)
		elseif e.kind == "reply" then
			pending[e.pizza.id] = nil
		elseif e.kind == "press" then
			ServeGate.press(g, e.t)
		elseif e.kind == "release" then
			local isPending = g.shown ~= nil and pending[g.shown] == true
			local enabled = ServeGate.enabled(g)
			if enabled and e.t - lastFired >= REPEAT then
				lastFired = e.t
				local id, ticket, reason = ServeGate.intent(g, e.t, isPending)
				if id then
					check("intent ticket matches the shown pizza", ticket, if id == A.id then A.ticket else B.ticket)
					pending[id] = true
					table.insert(served, id)
				else
					table.insert(why, reason :: string)
				end
			elseif not enabled then
				-- Nothing on the board: the button is off and does not activate; the press ends.
				ServeGate.intent(g, e.t, isPending)
				table.insert(why, "off: nothing shown")
			end
		end
	end
	return served, why
end

local function list(t: { any }): string
	local out = {}
	for _, v in t do
		table.insert(out, tostring(v))
	end
	return "{" .. table.concat(out, ",") .. "}"
end

-- 1. Impatient double tap, reply 0.6 s late: the second press begins while the first serve is
-- pending and is released after the reply has put B on the board.
local held = {
	{ t = -5, kind = "board", pizza = A },
	{ t = 0, kind = "press" },
	{ t = 0.08, kind = "release" },
	{ t = 0.55, kind = "press" },
	{ t = 0.6, kind = "reply", pizza = A },
	{ t = 0.6, kind = "board", pizza = B },
	{ t = 0.66, kind = "release" },
}
check("before: held second tap serves Bo's pizza too", list(oldRun(held)), "{81,83}")
local s1, w1 = newRun(held)
check("after: held second tap serves only the cut pizza", list(s1), "{81}")
table.insert(report, "held second tap: before " .. list(oldRun(held)) .. ", after " .. list(s1) .. " " .. list(w1))

-- 2. Second tap just after the board changed (the reply came between the taps).
local quick = {
	{ t = -5, kind = "board", pizza = A },
	{ t = 0, kind = "press" },
	{ t = 0.08, kind = "release" },
	{ t = 0.5, kind = "reply", pizza = A },
	{ t = 0.5, kind = "board", pizza = B },
	{ t = 0.7, kind = "press" },
	{ t = 0.78, kind = "release" },
}
check("before: quick second tap serves Bo's pizza", list(oldRun(quick)), "{81,83}")
local s2, w2 = newRun(quick)
check("after: quick second tap is ignored while the board settles", list(s2), "{81}")
check("after: why", w2[1], "pressed while the board was changing")
table.insert(report, "quick second tap: before " .. list(oldRun(quick)) .. ", after " .. list(s2) .. " " .. list(w2))

-- 3. A deliberate serve of B once it has been on the board past the settle time.
local deliberate = table.clone(quick)
table.insert(deliberate, { t = 0.5 + ServeGate.SETTLE + 0.05, kind = "press" })
table.insert(deliberate, { t = 0.5 + ServeGate.SETTLE + 0.13, kind = "release" })
local s3 = newRun(deliberate)
check("after: a deliberate serve of the next pizza works", list(s3), "{81,83}")

-- 4. A ticket switch from the rail during a press (no serve pending).
local switch = {
	{ t = -5, kind = "board", pizza = A },
	{ t = 0, kind = "press" },
	{ t = 0.1, kind = "board", pizza = B },
	{ t = 0.8, kind = "release" },
}
check("before: a press held across a ticket switch serves the new ticket", list(oldRun(switch)), "{83}")
local s4, w4 = newRun(switch)
check("after: it serves nothing", list(s4), "{}")
check("after: why", w4[1], "board changed during the press")

-- 4b. Studio's first run (slice 7b-1): the second press began 70 ms after the reply swapped
-- the board and was released once the board had settled. Aimed at the pizza before: nothing.
local studio = {
	{ t = -5, kind = "board", pizza = A },
	{ t = 0, kind = "press" },
	{ t = 0.054, kind = "release" },
	{ t = 0.108, kind = "reply", pizza = A },
	{ t = 0.108, kind = "board", pizza = B },
	{ t = 0.18, kind = "press" },
	{ t = 1.15, kind = "release" },
}
check("before: Studio run serves Bo's pizza", list(oldRun(studio)), "{81,83}")
local s4b, w4b = newRun(studio)
check("after: Studio run serves only the cut pizza", list(s4b), "{81}")
check("after: why", w4b[1], "pressed while the board was changing")
table.insert(report, "press begun during the swap, released settled: before " .. list(oldRun(studio)) .. ", after " .. list(s4b) .. " " .. list(w4b))

-- 4c. Studio, second run: a second click 0.618 s after the first, the reply having swapped the
-- board at 0.053 s (0.565 s before it). It got through with a 0.45 s settle; not with 0.6.
local injected = {
	{ t = -5, kind = "board", pizza = A },
	{ t = 0, kind = "press" },
	{ t = 0, kind = "release" },
	{ t = 0.053, kind = "reply", pizza = A },
	{ t = 0.053, kind = "board", pizza = B },
	{ t = 0.6, kind = "press" },
	{ t = 0.618, kind = "release" },
}
check("before: injected second click serves Bo's pizza", list(oldRun(injected)), "{81,83}")
check("after: injected second click 0.565 s after the swap is off", list((newRun(injected))), "{81}")

-- 5. Gate edges. Serve looks enabled whenever a pizza is shown; what a press does is intent's.
local g = ServeGate.new()
check("nothing shown: looks off", ServeGate.enabled(g), false)
check("nothing shown: no intent", select(3, ServeGate.intent(g, 0, false)), "nothing shown")
ServeGate.show(g, 81, 80, 0)
check("just shown: looks enabled (no grey-out)", ServeGate.enabled(g), true)
check("just shown: a key press is ignored", select(3, ServeGate.intent(g, 0.1, false)), "board just changed")
check("just shown: a mouse press is ignored", (function()
	ServeGate.press(g, 0.1)
	return select(3, ServeGate.intent(g, 0.18, false))
end)(), "pressed while the board was changing")
check("settled: serves", (ServeGate.intent(g, ServeGate.SETTLE, false)), 81)
check("pending: looks enabled", ServeGate.enabled(g), true)
check("pending: no intent", select(3, ServeGate.intent(g, 5, true)), "already serving")
ServeGate.show(g, 81, 80, 6)
check("same pizza redrawn: still settled", (ServeGate.intent(g, 6, false)), 81)
check("activation without a press (keyboard or gamepad) serves the shown pizza", (ServeGate.intent(g, 6, false)), 81)
ServeGate.press(g, 7)
ServeGate.show(g, 83, 82, 7.1)
check("stale press past its life does not bind", (ServeGate.intent(g, 7 + ServeGate.PRESS_LIFE + 1, false)), 83)
check("SETTLE above the repeat guard", ServeGate.SETTLE > REPEAT, true)

-- 6. The server: the pizza must be the shown ticket's.
local function cutPizza(id: number, ticket: number, cuts: number): any
	local list_ = {}
	for i = 1, cuts do
		local a = math.rad((i - 1) * 180 / cuts)
		table.insert(list_, { x1 = -math.cos(a), y1 = -math.sin(a), x2 = math.cos(a), y2 = math.sin(a) })
	end
	return { id = id, ticketId = ticket, stage = "cutting", make = { step = "toppings", flour = {}, placed = false, strokes = {} }, toppings = {}, cuts = list_, bakeSeconds = Config.Oven.targets.regular }
end
local function newSession(): any
	local now = workspace:GetServerTimeNow()
	return {
		shift = {
			customers = {
				{ id = 80, status = "ordered", order = { recipe = "cheese", bake = "regular", slices = 8 }, arrivedAt = now },
				{ id = 82, status = "ordered", order = { recipe = "cheese", bake = "regular", slices = 8 }, arrivedAt = now },
			},
			pizzas = { [81] = cutPizza(81, 80, 4), [83] = cutPizza(83, 82, 0) },
			ovens = { false, false },
			ingredients = {},
			nextArrival = 1,
			customerCount = 5,
			tips = 0,
			xp = 0,
			tutorial = false,
		},
	}
end
local session = newSession()
local ok, why = ShiftService.apply(session, "serve", { pizzaId = 83, ticketId = 80 })
check("server: Bo's pizza for the shown ticket refused", ok, false)
check("server: why", why, "pizza is not that ticket's")
check("server: Bo's pizza still on the board", session.shift.pizzas[83].stage, "cutting")
check("server: Bo still waiting", session.shift.customers[2].status, "ordered")
check("server: nothing paid", session.shift.tips, 0)
ok, why = ShiftService.apply(session, "serve", { pizzaId = 81 })
check("server: no ticket refused", why, "bad ticket id")
check("server: the shown pizza for its ticket accepted", (ShiftService.apply(session, "serve", { pizzaId = 81, ticketId = 80 })), true)
check("server: its customer served", session.shift.customers[1].status, "served")
check("server: Bo untouched", session.shift.customers[2].status, "ordered")
check("server: Bo's pizza untouched", session.shift.pizzas[83].stage, "cutting")
check("server: an uncut pizza can still be served (no cut gate)", (ShiftService.apply(session, "serve", { pizzaId = 83, ticketId = 82 })), true)
check("server: Bo served with Cut 0", session.shift.customers[2].result.cut.score, 0)

for _, l in report do
	print("  " .. l)
end
local summary = string.format("serve gate checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
print("  " .. summary)
