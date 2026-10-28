--!strict
-- Station layout numbers worked out from sizes alone, kept apart from the stations' drawing
-- so a re-skin or a motion pass can reuse them and the offline checks can measure them
-- without a client. Nothing here changes food, input meaning or grades: these are where
-- things are drawn.

local StationLayout = {}

-- The reserved hint strip between the work surface and the tab bar. Phones use 31 px (34
-- before slice 4): the 3 px go back to the stations so the Make board reaches the agreed
-- 190 px pizza frame on a 667x375 phone. 31 px still holds one 16 px line in Astra's chip.
function StationLayout.hintStripHeight(compact: boolean, screenY: number): number
	return if compact then 31 else math.clamp(math.round(screenY * 0.05), 40, 56)
end

-- The pizza frame F is radius 1 in pizza-local units and the visible mat radius 1 / 0.9.
StationLayout.FRAME_SHARE = 0.9

export type MakeLayout = {
	margin: number,
	gap: number,
	cellW: number,
	cellH: number,
	gridW: number,
	F: number, -- pizza frame, px
	mat: number, -- visible mat (the board's disc), px
	left: number, -- x where the board's column starts
	cx: number,
	cy: number,
}

-- Make's dough, sauce and cheese steps: the tool column (two across, three rows) on the left
-- and the board on the right. The board meets the station's top and bottom on a phone.
function StationLayout.make(W: number, H: number, compact: boolean): MakeLayout
	local margin = if compact then 6 else math.clamp(math.round(H * 0.03), 6, 24)
	local gap = if compact then 4 else math.max(4, math.round(W * 0.01))
	local cellH = (H - margin * 2 - gap * 2) / 3
	local cellW = cellH * 76 / 62
	local gridW = cellW * 2 + gap
	local matMax = math.min(H - (if compact then 0 else margin * 2), W - gridW - margin * 3)
	local F = math.floor(matMax * StationLayout.FRAME_SHARE)
	local mat = math.ceil(F / StationLayout.FRAME_SHARE - 1e-9)
	local left = margin * 2 + gridW
	return {
		margin = margin,
		gap = gap,
		cellW = cellW,
		cellH = cellH,
		gridW = gridW,
		F = F,
		mat = mat,
		left = left,
		cx = left + (W - margin - left) / 2,
		cy = H / 2,
	}
end

-- Where to put the centre of a rotated tool image so that its contact point (a share of
-- the canvas, Astra's anchor) lands on the pointer. Roblox turns an image about its centre,
-- whatever its AnchorPoint, so an anchor away from the centre drifts off the pointer when
-- the tool tips; this keeps the bowl (ladle) or the floury scoop bowl on the evaluated
-- point at any angle and size. Rotation in degrees, clockwise on screen as Roblox draws it.
function StationLayout.toolCentre(px: number, py: number, w: number, h: number, contactX: number, contactY: number, degrees: number): (number, number)
	local dx, dy = (contactX - 0.5) * w, (contactY - 0.5) * h
	local a = math.rad(degrees)
	local c, s = math.cos(a), math.sin(a)
	return px - (dx * c - dy * s), py - (dx * s + dy * c)
end

-- Contact anchors and tilts from Astra's r14 art contract. The ladle's interaction pivot is
-- the bowl's centre; 25 degrees to pour and -10 to spread are her provisional starting
-- values (not motion approval). The scoop's (0.5, 0.35) is her art-directed bowl centre.
StationLayout.LADLE_CONTACT = { x = 0.49963, y = 0.74373 }
StationLayout.LADLE_POUR, StationLayout.LADLE_SPREAD = 25, -10
StationLayout.SCOOP_CONTACT = { x = 0.5, y = 0.35 }
StationLayout.SCOOP_TILT = -20

-- The pizza on an oven rack: the share of the window it spans and how much flatter than round
-- it is drawn for the oven's perspective. Common to every pizza (Astra r14: frame the oven
-- better, never flatten one pizza less than another); stored food geometry is untouched.
-- Before slice 4: span 0.82, flatten 0.58, centre 0.58, glass 0.35 transparent.
StationLayout.OVEN = { span = 0.8, flatten = 0.7, centreY = 0.56, glassTransparency = 0.6 }

-- The drawn pizza's size on the rack for a window of w x h: the width the span allows,
-- unless the flattened height would leave the window, then the height decides.
function StationLayout.ovenPizza(w: number, h: number): (number, number)
	local o = StationLayout.OVEN
	local width = w * o.span
	local room = 2 * math.min(o.centreY, 1 - o.centreY) * h
	if width * o.flatten > room then
		width = room / o.flatten
	end
	return width, width * o.flatten
end

return StationLayout
