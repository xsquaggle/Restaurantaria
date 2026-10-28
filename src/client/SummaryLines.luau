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
	rank: number, -- rank at the shown XP (the server's rule: 1 + xp // xpPerRank)
	into: number, -- XP inside that rank
	need: number, -- XP per rank (Config.Rewards.xpPerRank), never a decorative number
	fraction: number, -- into / need, 0..1
	-- The shift's XP is only in the bar once the save has it (snap.recorded); before that
	-- the bar shows the profile as it stands. fromXp/toXp are for a fill animation.
	counted: boolean,
	fromXp: number,
	toXp: number,
	rankUp: boolean,
}

export type Model = {
	day: number?,
	served: number,
	coins: number,
	bonus: number,
	xpEarned: number,
	-- The earned-XP label: "+30 XP", or "+30 XP · save pending" while the bar still shows the
	-- profile from before this shift (Astra r15 QA 3), "+30 XP · not saved" in session-only play.
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
	local rank = 1 + xp // xpPerRank
	local into = xp - (rank - 1) * xpPerRank
	local fromXp = if counted then math.max(0, xp - earned) else xp
	return {
		rank = rank,
		into = into,
		need = xpPerRank,
		fraction = math.clamp(into / xpPerRank, 0, 1),
		counted = counted,
		fromXp = fromXp,
		toXp = xp,
		rankUp = counted and 1 + fromXp // xpPerRank < rank,
	}
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
	local caption = nil
	if bar then
		caption = string.format("%d / %d XP to Rank %d", bar.into, bar.need, bar.rank + 1)
		if not bar.counted and earned > 0 then
			caption = "Before this shift: " .. caption
		end
	end
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

-- Play-once presentation state (Astra r15 motion brief, rule 1). Main keeps one `state`
-- table outside the rebuilt UI and asks here, on every summary build, why the card is being
-- built: "first" (this shift's summary appears for the first time: earnings may be revealed),
-- "settled" (the save has just confirmed this shift's XP: the XP may advance, once) or
-- "rebuild" (anything else: a resize, a repeated or late notification). Keyed by shift id,
-- so a retry, reopen or duplicate never replays a reward. Motion is not built yet: today the
-- card shows final values for every reason.
export type Cue = { reason: string, revealEarnings: boolean, advanceXp: boolean }

function SummaryLines.presentation(state: { [string]: any }, snap: any, xpPerRank: number?): Cue
	local key = tostring(snap.shiftId)
	local seen = state[key]
	local bar = SummaryLines.bar((snap.profile or {}).xp, snap.xp or 0, snap.recorded == true, xpPerRank)
	local counted = bar ~= nil and bar.counted
	if not seen then
		state[key] = { xpCounted = counted }
		return { reason = "first", revealEarnings = true, advanceXp = counted }
	end
	if counted and not seen.xpCounted then
		seen.xpCounted = true
		return { reason = "settled", revealEarnings = false, advanceXp = true }
	end
	return { reason = "rebuild", revealEarnings = false, advanceXp = false }
end

return SummaryLines
