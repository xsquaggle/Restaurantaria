--!strict
-- Which pizza a Serve press serves (Astra r17 R17-02 / r19 D1, wrong-ticket Serve). Serve acts
-- on the pizza the board shows, never on one the player has not seen there:
--  * the board's pizza is bound only once it is drawn (show), so a refresh that fails part way
--    never leaves Serve pointing at a pizza the board does not show;
--  * a press that began on one pizza and is released after the board changed serves nothing
--    (a tap held across a serve reply, a ticket switch or a pizza taken out of the oven),
--    however long it was held, and neither does a press that began inside the settle;
--  * for SETTLE seconds after the board changes, a Serve press is ignored, so a second tap aimed
--    at the pizza just served cannot land on the next one (the impatient double tap: the first
--    serve's reply swaps the board between the taps, after the button's 0.35 s repeat guard).
-- The settle is invisible: Serve keeps its normal look (Lawson, slice 7b-1: a Serve that greyed
-- out after every serve felt dead), and a press inside it gets the button's press-down and
-- nothing else. The request carries the ticket the board showed, and the server refuses a pizza
-- that is not that ticket's. Pure state, no instances: the offline checks drive it
-- (tests/serve_gate_check).

local ServeGate = {}

-- Seconds a press is ignored after the board's pizza changes: longer than the button's repeat
-- guard (Theme.Motion.repeatGuard 0.35). Not shorter: 0.45 let an injected second tap 0.565 s
-- after the swap through in Studio. A deliberate serve that soon is rare, since the next pizza
-- usually needs cutting first.
ServeGate.SETTLE = 0.6
export type Gate = {
	shown: number?, -- the pizza the board shows (drawn)
	ticket: number?, -- its ticket
	changedAt: number, -- when the board's pizza last changed
	pressOn: number?, -- the pizza shown when the current press began
	pressAt: number, -- when it began (-math.huge: no press since the last activation)
}

function ServeGate.new(): Gate
	return { shown = nil, ticket = nil, changedAt = -math.huge, pressOn = nil, pressAt = -math.huge }
end

-- The board now shows `pizzaId` (nil: nothing to cut). Call after it is drawn.
function ServeGate.show(g: Gate, pizzaId: number?, ticketId: number?, now: number)
	if pizzaId ~= g.shown then
		g.changedAt = now
	end
	g.shown = pizzaId
	g.ticket = if pizzaId then ticketId else nil
end

-- A press began on Serve. A press that begins inside the settle (the board changed under it
-- moments ago) is bound to nothing, so its release serves nothing: it was aimed at the pizza
-- before (first Studio run: a second press 70 ms after the swap, released once settled).
function ServeGate.press(g: Gate, now: number)
	g.pressOn = if ServeGate.wait(g, now) <= 0 then g.shown else nil
	g.pressAt = now
end

-- Seconds until a press is no longer ignored after a change (0 when settled).
function ServeGate.wait(g: Gate, now: number): number
	return math.max(0, g.changedAt + ServeGate.SETTLE - now)
end

-- Serve looks enabled: a pizza is shown. Not while settling or serving: those presses are
-- ignored without a look of their own.
function ServeGate.enabled(g: Gate): boolean
	return g.shown ~= nil
end

-- What an activation of Serve serves now: (pizzaId, ticketId) or (nil, nil, reason). Ends the
-- press either way. A press binds its activation whatever its age (a long hold across a board
-- change serves nothing); one that never activated (dragged off) binds only the next activation,
-- and only refuses it if the board changed since.
function ServeGate.intent(g: Gate, now: number, pending: boolean): (number?, number?, string?)
	local pressAt = g.pressAt
	local pressed = pressAt > -math.huge
	local pressOn = g.pressOn
	g.pressOn = nil
	g.pressAt = -math.huge
	if g.shown == nil then
		return nil, nil, "nothing shown"
	elseif pending then
		return nil, nil, "already serving"
	elseif pressed and pressOn == nil then
		return nil, nil, "pressed while the board was changing"
	elseif pressed and (pressOn ~= g.shown or g.changedAt > pressAt) then
		return nil, nil, "board changed during the press"
	elseif ServeGate.wait(g, now) > 0 then
		return nil, nil, "board just changed"
	end
	return g.shown, g.ticket, nil
end

return ServeGate
