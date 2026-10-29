--!strict
-- Which pizza a Serve press serves (Astra r17 R17-02 / r19 D1, wrong-ticket Serve). Serve acts
-- on the pizza the board shows, never on one the player has not seen there:
--  * the board's pizza is bound only once it is drawn (show), so a refresh that fails part way
--    never leaves Serve pointing at a pizza the board does not show;
--  * a press that began on one pizza and is released after the board changed serves nothing
--    (a tap held across a serve reply, a ticket switch or a pizza taken out of the oven);
--  * for SETTLE seconds after the board changes, Serve is off, so a second tap aimed at the
--    pizza just served cannot land on the next one (the impatient double tap: the first serve's
--    reply swaps the board between the taps, after the button's 0.35 s repeat guard).
-- The request carries the ticket the board showed, and the server refuses a pizza that is not
-- that ticket's. Pure state, no instances: the offline checks drive it (tests/serve_gate_check).

local ServeGate = {}

-- Seconds Serve stays off after the board's pizza changes: longer than the button's repeat
-- guard (Theme.Motion.repeatGuard 0.35), shorter than a deliberate second look. A proposal.
ServeGate.SETTLE = 0.45
-- A press older than this no longer binds a release to it (a press that never activated).
ServeGate.PRESS_LIFE = 2

export type Gate = {
	shown: number?, -- the pizza the board shows (drawn)
	ticket: number?, -- its ticket
	changedAt: number, -- when the board's pizza last changed
	pressOn: number?, -- the pizza shown when the current press began
	pressAt: number,
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

-- A press began on Serve.
function ServeGate.press(g: Gate, now: number)
	g.pressOn = g.shown
	g.pressAt = now
end

-- Seconds until Serve may be pressed again after a change (0 when settled).
function ServeGate.wait(g: Gate, now: number): number
	return math.max(0, g.changedAt + ServeGate.SETTLE - now)
end

-- Serve may be pressed: a pizza is shown, settled, and not already being served.
function ServeGate.ready(g: Gate, now: number, pending: boolean): boolean
	return g.shown ~= nil and not pending and ServeGate.wait(g, now) <= 0
end

-- What an activation of Serve serves now: (pizzaId, ticketId) or (nil, nil, reason). Ends the
-- press either way.
function ServeGate.intent(g: Gate, now: number, pending: boolean): (number?, number?, string?)
	local pressed = now - g.pressAt <= ServeGate.PRESS_LIFE
	local pressOn = g.pressOn
	g.pressOn = nil
	g.pressAt = -math.huge
	if g.shown == nil then
		return nil, nil, "nothing shown"
	elseif pending then
		return nil, nil, "already serving"
	elseif pressed and pressOn ~= g.shown then
		return nil, nil, "board changed during the press"
	elseif ServeGate.wait(g, now) > 0 then
		return nil, nil, "board just changed"
	end
	return g.shown, g.ticket, nil
end

return ServeGate
