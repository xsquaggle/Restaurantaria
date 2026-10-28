--!strict
-- What a served order's result card says, from the server's result alone: the grade, its
-- parts as short rows, pay apart from the grade, and up to three notes with the food problem
-- first. Kept apart from the card's layout (Main's showResult) so the wording can be checked
-- without a client. Nothing here grades: every number is the server's.

local ResultLines = {}

ResultLines.MAX_NOTES = 3

export type Part = { name: string, score: number }
export type Model = {
	title: string, -- "Bo · 100%"
	grade: number,
	parts: { Part }, -- the grade's components, in order
	pay: string, -- coins, and Service when it moves the coins only (split join)
	payLines: { string }, -- the same as separate lines, for a narrow card
	notes: { string },
}

-- A held grade's note reads "<problem>: grade held to N" (or "Make held to N"). Astra r14:
-- say the food problem first and the hold after it, never only a formula.
function ResultLines.splitHeld(note: string): (string, string?)
	local problem, what, value = string.match(note, "^(.-): (%a+) held to (%d+)$")
	if not problem or problem == "" then
		return note, nil
	end
	return problem, string.format("That held %s to %s", if what == "grade" then "the grade" else what, value)
end

local function has(list: { string }, text: string): boolean
	return table.find(list, text) ~= nil
end

function ResultLines.model(result: any, label: string): Model
	local r = result
	local split = r.join == "split"
	local parts: { Part } = {}
	if not split then
		-- The earlier average join counts the wait in the grade, so it stays a grade part.
		table.insert(parts, { name = "Wait", score = r.wait.score })
	end
	table.insert(parts, { name = "Make", score = r.make.score })
	table.insert(parts, { name = "Bake", score = r.bake.score })
	table.insert(parts, { name = "Cut", score = r.cut.score })
	local coins = string.format("+%d coin%s", r.tip, if r.tip == 1 then "" else "s")

	-- One note at a time from each part (each part's first, then its second...), so a Make
	-- with several notes never hides "Burnt" or a cut note.
	local raw = {}
	local round = 1
	while true do
		local added = false
		for _, part in { r.make, r.bake, r.cut, r.wait } do
			local n = part.notes[round]
			if n then
				table.insert(raw, n)
				added = true
			end
		end
		if not added then
			break
		end
		round += 1
	end
	-- The note of the hold that set the grade (it leads its part's notes) goes first, as its
	-- food problem and then the hold; the other notes follow in turn.
	local notes = {}
	for i, n in raw do
		local problem, hold = ResultLines.splitHeld(n)
		if hold then
			table.remove(raw, i)
			table.insert(notes, problem)
			table.insert(notes, hold)
			break
		end
	end
	for _, n in raw do
		if not has(notes, n) then
			table.insert(notes, n)
		end
	end
	-- At result size a crust spill cannot be seen on the thumbnail (Astra r14 QA 4), so the
	-- sauce's own note is named whenever the sauce step recorded it.
	local sauce = r.make.detail and r.make.detail.sauce
	if sauce and sauce.notes and has(sauce.notes, "Sauce on the crust") and not has(notes, "Sauce on the crust") then
		table.insert(notes, math.min(#notes + 1, if notes[2] and string.find(notes[2], "^That held") then 3 else 2), "Sauce on the crust")
	end
	while #notes > ResultLines.MAX_NOTES do
		table.remove(notes)
	end
	return {
		title = string.format("%s · %d%%", label, r.overall),
		grade = r.overall,
		parts = parts,
		pay = if split then string.format("%s · Service %d", coins, r.wait.score) else coins,
		payLines = if split then { coins, string.format("Service %d", r.wait.score) } else { coins },
		notes = notes,
	}
end

return ResultLines
