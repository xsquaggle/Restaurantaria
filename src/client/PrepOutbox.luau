--!strict
-- The client's ordered outbox for Prep's cheese and step actions (cooking plan rev 6, 3.3, with
-- Astra's response 9 correction: queued cheese is bound to its pizza and stroke, and Next,
-- Undo and ticket switching are ordered so a batch can never vanish, come back after Undo or
-- land on another pizza). Pure: the caller passes the clock and a send function.
--
-- Every entry carries its own pizzaId. Pinches wait in one FIFO with the step actions and go
-- out at most PINCH_BATCH at a time, one batch every BATCH_GAP seconds; a batch never mixes
-- pizzas or strokes. A step action (Next, Undo) waits behind everything queued before it.
-- - Undo removes the pizza's most recent stroke at once on screen. Its unsent pinches are
--   dropped from the queue; only when part of it was already sent does an undoCheese go out,
--   queued behind what was sent, and the server removes that whole stroke.
-- - Next (advancePrep) ends a held stroke and goes behind the pizza's queued pinches, so every
--   pinch reaches the server first. Afterwards the pizza takes no more cheese or Undo here.
-- - Switching tickets ends the held stroke; queued entries keep their pizza.
-- - A refusal drops that pizza's queued entries; the caller redraws it from the snapshot.

local PrepOutbox = {}

PrepOutbox.PINCH_BATCH = 8
PrepOutbox.BATCH_GAP = 0.1
PrepOutbox.MAX_PINCHES = 48

export type Point = { x: number, y: number }
type Entry = { kind: string, pizzaId: number, stroke: number?, point: Point?, from: string? }
type Stroke = { id: number, pinches: { Point }, sent: number }
type Pizza = { strokes: { Stroke }, nextStroke: number, done: boolean }

export type Message = { action: string, args: any }

function PrepOutbox.new(send: (Message) -> ())
	local self = {}
	local queue: { Entry } = {}
	local pizzas: { [number]: Pizza } = {}
	local held: { pizzaId: number, stroke: number }? = nil
	local lastBatch = -math.huge

	local function pizza(id: number): Pizza
		local p = pizzas[id]
		if not p then
			p = { strokes = {}, nextStroke = 1, done = false }
			pizzas[id] = p
		end
		return p
	end

	local function strokeOf(p: Pizza, id: number): Stroke?
		for _, s in p.strokes do
			if s.id == id then
				return s
			end
		end
		return nil
	end

	local function count(p: Pizza): number
		local n = 0
		for _, s in p.strokes do
			n += #s.pinches
		end
		return n
	end

	-- Starts a held sprinkle on a pizza; returns false once its cheese step is over.
	function self.begin(pizzaId: number): boolean
		local p = pizza(pizzaId)
		if p.done then
			return false
		end
		self.release()
		table.insert(p.strokes, { id = p.nextStroke, pinches = {}, sent = 0 })
		held = { pizzaId = pizzaId, stroke = p.nextStroke }
		p.nextStroke += 1
		return true
	end

	-- Places one pinch on the held stroke (drawn at once by the caller). Refused past the cap.
	function self.place(point: Point): boolean
		local h = held
		if not h then
			return false
		end
		local p = pizza(h.pizzaId)
		if count(p) >= PrepOutbox.MAX_PINCHES then
			return false
		end
		local s = strokeOf(p, h.stroke) :: Stroke
		table.insert(s.pinches, point)
		table.insert(queue, { kind = "pinch", pizzaId = h.pizzaId, stroke = h.stroke, point = point })
		return true
	end

	-- Ends the held stroke (release, or before any switch, Undo or Next). Empty strokes vanish.
	function self.release()
		local h = held
		held = nil
		if h then
			local p = pizza(h.pizzaId)
			local s = strokeOf(p, h.stroke)
			if s and #s.pinches == 0 then
				table.remove(p.strokes, table.find(p.strokes, s))
			end
		end
	end

	-- Ticket switch: queued entries keep their pizza.
	function self.focus(_pizzaId: number)
		self.release()
	end

	function self.undo(pizzaId: number): boolean
		self.release()
		local p = pizza(pizzaId)
		if p.done or #p.strokes == 0 then
			return false
		end
		local s = table.remove(p.strokes) :: Stroke
		for i = #queue, 1, -1 do
			local e = queue[i]
			if e.kind == "pinch" and e.pizzaId == pizzaId and e.stroke == s.id then
				table.remove(queue, i)
			end
		end
		if s.sent > 0 then
			table.insert(queue, { kind = "undo", pizzaId = pizzaId })
		end
		return true
	end

	function self.advance(pizzaId: number, from: string): boolean
		self.release()
		local p = pizza(pizzaId)
		if p.done then
			return false
		end
		p.done = true
		table.insert(queue, { kind = "advance", pizzaId = pizzaId, from = from })
		return true
	end

	-- Sends what is due at clock time now, in queue order.
	function self.tick(now: number)
		while #queue > 0 do
			local e = queue[1]
			if e.kind == "undo" then
				table.remove(queue, 1)
				send({ action = "undoCheese", args = { pizzaId = e.pizzaId } })
			elseif e.kind == "advance" then
				table.remove(queue, 1)
				send({ action = "advancePrep", args = { pizzaId = e.pizzaId, from = e.from } })
			else
				if now - lastBatch < PrepOutbox.BATCH_GAP - 1e-9 then
					return
				end
				local points = {}
				local s = strokeOf(pizza(e.pizzaId), e.stroke :: number) :: Stroke
				local first = s.sent == 0
				while #queue > 0 and #points < PrepOutbox.PINCH_BATCH do
					local n = queue[1]
					if n.kind ~= "pinch" or n.pizzaId ~= e.pizzaId or n.stroke ~= e.stroke then
						break
					end
					table.remove(queue, 1)
					table.insert(points, n.point)
				end
				s.sent += #points
				lastBatch = now
				send({ action = "addCheese", args = { pizzaId = e.pizzaId, newStroke = first, points = points } })
			end
		end
	end

	-- The server refused one of this pizza's actions: drop what is still queued for it.
	function self.refused(pizzaId: number)
		if held and (held :: any).pizzaId == pizzaId then
			held = nil
		end
		for i = #queue, 1, -1 do
			if queue[i].pizzaId == pizzaId then
				table.remove(queue, i)
			end
		end
		pizzas[pizzaId] = nil
	end

	-- What the player sees: this pizza's pinches in placement order.
	function self.visible(pizzaId: number): { Point }
		local out = {}
		for _, s in pizza(pizzaId).strokes do
			for _, pt in s.pinches do
				table.insert(out, pt)
			end
		end
		return out
	end

	function self.pending(): number
		return #queue
	end

	return self
end

return PrepOutbox
