--!strict
-- The three cheese deposits of the slice 8a picture proofs (Lawson 2026-10-29 15:40; Astra r21):
-- an even application, a large miss and a heavy pile, each exactly 24 pinches (the same
-- deposited quantity: one full layer by the grade's count), all on the edible area so no crust
-- pinch changes a result. Placed pinch lists standing in for a player's pours (the held-pour
-- proofs, whose counts differ, stay in tests/cheese_pour_check.luau). Dough-local positions.
-- Read by the checks (tests/cheese_map_check.luau), the Studio comparison sheet and the
-- Studio-only debug command that makes a proof pizza through the real actions. Test fixture
-- only: nothing in play reads it.

local CheeseProofs = {}

export type Vec = { x: number, y: number }

local function P(x: number, y: number): Vec
	return { x = x, y = y }
end

-- A fixed small jitter (golden-ratio sequence), so the even layout is not a perfect lattice.
local function jitter(n: number, size: number): (number, number)
	local jx = (((n * 0.6180339887) % 1) - 0.5) * size
	local jy = (((n * 0.7548776662) % 1) - 0.5) * size
	return jx, jy
end

-- Even: a careful player's layer, one in the middle, eight around it, fifteen further out.
local function even(): { Vec }
	local out = { P(0, 0) }
	for i = 0, 7 do
		local a = i / 8 * 2 * math.pi
		table.insert(out, P(0.32 * math.cos(a), 0.32 * math.sin(a)))
	end
	for i = 0, 14 do
		local a = (i + 0.5) / 15 * 2 * math.pi
		table.insert(out, P(0.66 * math.cos(a), 0.66 * math.sin(a)))
	end
	for n, p in out do
		local jx, jy = jitter(n, 0.1)
		p.x += jx
		p.y += jy
	end
	return out
end

-- Large miss: the same 24 pinches all on the left half, the right half left bare.
local function miss(): { Vec }
	local out = {}
	local function arc(r: number, from: number, to: number, n: number)
		for i = 0, n - 1 do
			local a = math.rad(if n == 1 then from else from + (to - from) * i / (n - 1))
			table.insert(out, P(r * math.cos(a), r * math.sin(a)))
		end
	end
	arc(0.2, 120, 240, 3)
	arc(0.42, 100, 260, 6)
	arc(0.62, 95, 265, 9)
	arc(0.76, 110, 250, 6)
	return out
end

-- Heavy pile: half the cheese (12 pinches) dropped on one spot, the other half spread thinly
-- around the pizza.
local function pile(): { Vec }
	local out = {}
	for n = 1, 12 do
		local jx, jy = jitter(n, 0.06)
		table.insert(out, P(0.3 + jx, 0.1 + jy))
	end
	for i = 0, 11 do
		local a = (i + 0.5) / 12 * 2 * math.pi
		table.insert(out, P(0.55 * math.cos(a), 0.55 * math.sin(a)))
	end
	return out
end

CheeseProofs.names = { "even", "miss", "pile" }
CheeseProofs.labels = { even = "Even", miss = "Large miss", pile = "Heavy pile" }

-- A fresh copy of a proof's pinches, in placement order.
function CheeseProofs.pinches(name: string): { Vec }
	if name == "even" then
		return even()
	elseif name == "miss" then
		return miss()
	elseif name == "pile" then
		return pile()
	end
	error("no cheese proof " .. tostring(name))
end

return CheeseProofs
