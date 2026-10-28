--!strict
-- What the shift summary shows, worked out from the snapshot alone: the completed day, coins,
-- experience against the real rank threshold, the save state and the continuation action.
-- Kept apart from the layout (SummaryCard) so the values and wording can be checked without
-- a client.

local SummaryLines = {}

-- True once this shift's rewards are settled: saved, or kept for this session by design.
function SummaryLines.settled(snap: any): boolean
	return snap.settlement == "saved" or snap.settlement == "session"
end

function SummaryLines.build(snap: any): { string }
	local profile = snap.profile or {}
	local count = profile.shiftsCompleted or 0
	return {
		string.format("Experience: +%d", snap.xp),
		-- The lifetime count comes from the save, which doesn't hold this shift until it
		-- settles, so it is left out while saving or after a failed save.
		if SummaryLines.settled(snap)
			then string.format("Rank %d · %d shift%s completed", profile.rank or 1, count, if count == 1 then "" else "s")
			else string.format("Rank %d", profile.rank or 1),
		if snap.settlement == "saved" then "Progress saved"
			elseif snap.settlement == "retry" then "Save not confirmed. Please retry."
			elseif snap.settlement == "session" then "Progress not saved"
			else "Saving...",
	}
end

export type XpBar = {
	rank: number, -- rank at the shown endpoint (the server's rule: 1 + xp // xpPerRank)
	into: number, -- XP inside that rank
	need: number, -- XP per rank (Config.Rewards.xpPerRank), never a decorative number
	fraction: number, -- into / need, 0..1
	-- counted: the save has this shift's XP (snap.recorded), so the profile already holds it.
	-- Before that the bar still shows where the award takes the player, as a labelled
	-- projection (projected), from the profile as it stands (Astra r15 brief, r17 R17-06):
	-- the confirmed part solid (solidFraction), the earned part lighter.
	counted: boolean,
	projected: boolean,
	fromXp: number, -- XP total before this shift
	toXp: number, -- XP total with this shift's award (accepted or projected)
	baseRank: number, -- rank at fromXp
	baseFraction: number, -- progress inside baseRank at fromXp
	solidFraction: number, -- the confirmed part of the shown fill
	rankUp: boolean, -- the award crosses a threshold (definitive only once counted)
}

export type Model = {
	day: number?,
	served: number,
	coins: number,
	bonus: number,
	xpEarned: number,
	-- The earned-XP label: "+30 XP", or "+30 XP · save pending" while the save does not have
	-- the award yet (Astra r15 QA 3), "+30 XP · not saved" in session-only play.
	xpLabel: string,
	rank: number?,
	bar: XpBar?, -- nil: XP and rank show as text only (no threshold or profile XP to hand)
	xpCaption: string?,
	status: string,
	tone: string, -- "saved" | "pending" | "warn"
	action: { label: string, mode: string }, -- mode "ready" | "standby" | "retry"
}

function SummaryLines.bar(xp: number?, earned: number, counted: boolean, xpPerRank: number?): XpBar?
	if type(xp) ~= "number" or type(xpPerRank) ~= "number" or xpPerRank <= 0 then
		return nil
	end
	local fromXp = if counted then math.max(0, xp - earned) else xp
	local toXp = if counted then xp else xp + math.max(earned, 0)
	local rank = 1 + toXp // xpPerRank
	local into = toXp - (rank - 1) * xpPerRank
	local fraction = math.clamp(into / xpPerRank, 0, 1)
	local baseRank = 1 + fromXp // xpPerRank
	local baseFraction = math.clamp((fromXp - (baseRank - 1) * xpPerRank) / xpPerRank, 0, 1)
	local projected = not counted and toXp > fromXp
	return {
		rank = rank,
		into = into,
		need = xpPerRank,
		fraction = fraction,
		counted = counted,
		projected = projected,
		fromXp = fromXp,
		toXp = toXp,
		baseRank = baseRank,
		baseFraction = baseFraction,
		solidFraction = if not projected then fraction elseif rank == baseRank then baseFraction else 0,
		rankUp = rank > baseRank,
	}
end

-- The bar's caption at `rank` and `fraction` (any point of its fill). The XP inside the rank
-- rounds down like the counting award label, so the two always add up. A projection says so.
function SummaryLines.caption(bar: XpBar, rank: number, fraction: number): string
	local text = string.format("%d / %d XP to Rank %d", math.floor(fraction * bar.need + 1e-6), bar.need, rank + 1)
	return if bar.projected then "Projected: " .. text else text
end

-- The rank words beside the bar at `rank`, and whether they are the small qualifier style.
-- A projected rank above the confirmed one is labelled as projected; so is any projected
-- rank when the layout has no caption to say it (tight, Astra r17 R17-08). "Rank up!" only
-- for an accepted award, on the final value.
function SummaryLines.rankText(bar: XpBar, rank: number, final: boolean, tight: boolean): (string, boolean)
	if bar.projected and (rank > bar.baseRank or tight) then
		return string.format("Projected Rank %d", rank), true
	end
	if final and bar.counted and bar.rankUp then
		return string.format("Rank %d · Rank up!", rank), false
	end
	return string.format("Rank %d", rank), false
end

function SummaryLines.model(snap: any, xpPerRank: number?): Model
	local profile = snap.profile or {}
	local served = 0
	for _, c in snap.customers or {} do
		if c.status == "served" then
			served += 1
		end
	end
	local settled = SummaryLines.settled(snap)
	-- The completed day comes from the receipt; older snapshots fall back to the shift's day,
	-- then to the save's count (which already holds this shift once it is recorded).
	local day = snap.completedShiftDay or snap.day
	if not day and type(profile.shiftsCompleted) == "number" then
		day = profile.shiftsCompleted + (if snap.recorded then 0 else 1)
	end
	local earned = snap.xp or 0
	local bar = SummaryLines.bar(profile.xp, earned, snap.recorded == true, xpPerRank)
	local caption = if bar then SummaryLines.caption(bar, bar.rank, bar.fraction) else nil
	local xpLabel = string.format("+%d XP", earned)
	if earned > 0 and not (bar and bar.counted) and snap.recorded ~= true then
		xpLabel ..= if snap.settlement == "session" then " · not saved" else " · save pending"
	end
	local tone = if snap.settlement == "saved" then "saved" elseif settled or snap.settlement == "retry" then "warn" else "pending"
	return {
		day = day,
		served = served,
		coins = snap.tips or 0,
		bonus = snap.tutorialBonus or 0,
		xpEarned = earned,
		xpLabel = xpLabel,
		rank = if bar then bar.rank else profile.rank,
		bar = bar,
		xpCaption = caption,
		status = SummaryLines.build(snap)[3],
		tone = tone,
		action = if snap.settlement == "retry" then { label = "Retry save", mode = "retry" }
			elseif settled then { label = "Next shift", mode = "ready" }
			-- Astra r15 QA 2: the standby says it is a wait while the status line says Saving.
			else { label = "Please wait", mode = "standby" },
	}
end

-- Everything the card shows from a finished shift's snapshot. A newer snapshot that changes
-- any of it (a corrected bonus or award, a save result) refreshes the card, even when the
-- save wording stays the same (Astra r17 R17-06); SummaryLines.presentation decides on its
-- own whether anything moves, so a correction never replays a reward.
function SummaryLines.receiptKey(snap: any): string
	local profile = snap.profile or {}
	return table.concat({
		tostring(snap.shiftId),
		tostring(snap.settlement),
		tostring(snap.saveMessage),
		tostring(snap.recorded),
		tostring(snap.tips),
		tostring(snap.tutorialBonus),
		tostring(snap.xp),
		tostring(profile.xp),
		tostring(profile.rank),
		tostring(profile.shiftsCompleted),
		tostring(snap.completedShiftDay or snap.day),
	}, "|")
end

-- Play-once presentation state (Astra r15 motion brief, rule 1). Main keeps one `state`
-- table outside the rebuilt UI and asks here, on every summary build or refresh, why: "first"
-- (this shift's summary appears for the first time: the coins are revealed, then the earned
-- XP, whose bar moves now whether the save has accepted it or shows it as a projection;
-- neither waits for the save), "settled" (the save has just accepted XP shown earlier: it
-- locks in once and a real rank-up may now be celebrated; nothing counts again) or "rebuild"
-- (anything else: a resize, a correction, a repeated or late notification: final values).
-- Keyed by shift id, so a retry, reopen or duplicate never replays a reward.
export type Cue = { reason: string, revealEarnings: boolean, advanceXp: boolean, confirmXp: boolean }

function SummaryLines.presentation(state: { [string]: any }, snap: any, xpPerRank: number?): Cue
	local key = tostring(snap.shiftId)
	local seen = state[key]
	local bar = SummaryLines.bar((snap.profile or {}).xp, snap.xp or 0, snap.recorded == true, xpPerRank)
	local counted = bar ~= nil and bar.counted
	if not seen then
		state[key] = { xpCounted = counted }
		return { reason = "first", revealEarnings = true, advanceXp = bar ~= nil, confirmXp = false }
	end
	if counted and not seen.xpCounted then
		seen.xpCounted = true
		return { reason = "settled", revealEarnings = false, advanceXp = false, confirmXp = true }
	end
	return { reason = "rebuild", revealEarnings = false, advanceXp = false, confirmXp = false }
end

return SummaryLines
