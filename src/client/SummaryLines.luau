--!strict
-- The shift summary's secondary lines: experience, rank and the save state. Kept apart from
-- the layout so the wording can be checked without a client.

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

return SummaryLines
