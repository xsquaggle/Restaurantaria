--!strict
-- Prep geometry: the one coordinate map between the scored dough oval, the drawn body and food
-- positions (cooking plan rev 6 with Astra's response 9 corrections), the per-view transform
-- and the layout envelope. Pure functions shared by server, client and tests.
--
-- Pizza-local p: centre (0, 0), x right, y down, radius 1 at the pizza frame's edge (F / 2 px).
-- The dough is a symmetric positive-definite 2 x 2 matrix S: its outline is S applied to the
-- unit circle, so its semi-axes a >= b and their angle are S's eigenvalues and eigenvectors. A
-- fully rolled round dough is S = 0.95 I, the drawn crust edge.
-- Dough-local q: the stored coordinate for sauce, cheese and toppings. q = 0.95 S^-1 p and
-- p = S q / 0.95, so dough-local radius 0.95 IS the dough outline for every shape, and a full
-- round dough has q = p. One map only: never apply S to a 0.95 radius (that is the 5 % mixed
-- convention Astra found, which puts the crust at 0.9025).
-- Left and right are what the player sees: classify a stored q by its physical p.x, never by
-- q.x (a rotated anisotropic S can flip the sign).
-- Roll stretch constants here are a provisional proof model (plan 3.1, proposals), not tuning.

local PrepGeometry = {}

PrepGeometry.CRUST = 0.95 -- dough-local radius of the outline; also the full-size semi-axis
PrepGeometry.SAUCE_EDGE = 0.84 -- dough-local sauce, cheese and topping limit (proposal)
PrepGeometry.CAP = 1.1 -- largest semi-axis (proposal)
PrepGeometry.BALL = 0.35 -- the ball's radius (proposal); body 0.35 F across
PrepGeometry.STRETCH = 0.35 -- largest stretch of one full-length stroke (proposal)
PrepGeometry.MAT_OVER_FRAME = 1 / 0.9 -- boardOverPizza (Assets.Meta)
PrepGeometry.BAKE_FLATTEN = 0.58 -- PIZZA_FLATTEN (Bake.luau)
PrepGeometry.PHONE_FRAME = 190 -- ceil(180 / 0.95): at least 180 px of visible crust
PrepGeometry.STATE_RADII = { 0.35, 0.47, 0.59, 0.71, 0.83, 0.95 } -- P4 nominal mean radii (proposal)

-- [a b; c d]
export type Mat2 = { a: number, b: number, c: number, d: number }
export type Vec = { x: number, y: number }
export type Ellipse = { major: number, minor: number, angle: number } -- angle in radians, y down

local function mat(a: number, b: number, c: number, d: number): Mat2
	return { a = a, b = b, c = c, d = d }
end
PrepGeometry.mat = mat

function PrepGeometry.mul(m: Mat2, n: Mat2): Mat2
	return mat(m.a * n.a + m.b * n.c, m.a * n.b + m.b * n.d, m.c * n.a + m.d * n.c, m.c * n.b + m.d * n.d)
end

function PrepGeometry.apply(m: Mat2, v: Vec): Vec
	return { x = m.a * v.x + m.b * v.y, y = m.c * v.x + m.d * v.y }
end

function PrepGeometry.inverse(m: Mat2): Mat2
	local det = m.a * m.d - m.b * m.c
	return mat(m.d / det, -m.b / det, -m.c / det, m.a / det)
end

local function transpose(m: Mat2): Mat2
	return mat(m.a, m.c, m.b, m.d)
end

-- Eigenvalues (largest first) and the largest one's angle for a symmetric matrix.
local function symEigen(m: Mat2): (number, number, number)
	local mean = (m.a + m.d) / 2
	local half = (m.a - m.d) / 2
	local r = math.sqrt(half * half + m.b * m.b)
	local angle = 0.5 * math.atan2(2 * m.b, m.a - m.d)
	return mean + r, mean - r, angle
end

-- Symmetric matrix with eigenvalues l1, l2 and l1's eigenvector at angle.
local function fromEigen(l1: number, l2: number, angle: number): Mat2
	local c, s = math.cos(angle), math.sin(angle)
	return mat(l1 * c * c + l2 * s * s, (l1 - l2) * c * s, (l1 - l2) * c * s, l1 * s * s + l2 * c * c)
end

-- The dough from its semi-axes and the major axis's angle (radians; y down, so positive turns
-- clockwise on screen).
function PrepGeometry.shape(a: number, b: number, angle: number?): Mat2
	return fromEigen(a, b, angle or 0)
end

function PrepGeometry.ball(): Mat2
	return PrepGeometry.shape(PrepGeometry.BALL, PrepGeometry.BALL, 0)
end

-- Semi-axes and angle of the dough's own outline.
function PrepGeometry.axes(S: Mat2): Ellipse
	local l1, l2, angle = symEigen(S)
	return { major = l1, minor = l2, angle = angle }
end

function PrepGeometry.meanRadius(S: Mat2): number
	local e = PrepGeometry.axes(S)
	return (e.major + e.minor) / 2
end

-- The one map. Pizza-local p to dough-local q and back.
function PrepGeometry.toDough(S: Mat2, p: Vec): Vec
	local q = PrepGeometry.apply(PrepGeometry.inverse(S), p)
	return { x = q.x * PrepGeometry.CRUST, y = q.y * PrepGeometry.CRUST }
end

function PrepGeometry.toPizza(S: Mat2, q: Vec): Vec
	return PrepGeometry.apply(S, { x = q.x / PrepGeometry.CRUST, y = q.y / PrepGeometry.CRUST })
end

-- Visible half of a stored dough-local point, by its physical x (Astra r9 item 1).
function PrepGeometry.visibleHalf(S: Mat2, q: Vec): string
	return if PrepGeometry.toPizza(S, q).x < 0 then "left" else "right"
end

-- The view's screen matrix K = (F / 2) D S: the unit circle's point to px offsets from the view
-- centre, so K applied to the unit circle is the drawn dough outline. It already includes the
-- dough S; apply it to q / 0.95, not to a pizza-local p. D's flatten scales y (0.58 in Bake, 1
-- elsewhere).
function PrepGeometry.viewMatrix(S: Mat2, frame: number, flatten: number?): Mat2
	local k = frame / 2
	local f = flatten or 1
	return mat(k * S.a, k * S.b, k * f * S.c, k * f * S.d)
end

-- Displayed ellipse of K applied to the unit circle: the semi-axes are K's singular values and
-- the angle is the first left singular vector's, read from the full composed transform (not
-- the old vertical-radius shortcut, which is wrong for a rotated oval).
function PrepGeometry.ellipseOf(K: Mat2): Ellipse
	local l1, l2, angle = symEigen(PrepGeometry.mul(K, transpose(K)))
	return { major = math.sqrt(math.max(l1, 0)), minor = math.sqrt(math.max(l2, 0)), angle = angle }
end

-- Screen offset (px from the view centre) of a stored dough-local point in a view. The view
-- matrix already holds S, so it takes q / 0.95 (the unit-circle point), never toPizza(S, q),
-- which would apply S a second time (Astra r13 item 2).
function PrepGeometry.screenOf(S: Mat2, frame: number, flatten: number?, q: Vec): Vec
	return PrepGeometry.apply(PrepGeometry.viewMatrix(S, frame, flatten), { x = q.x / PrepGeometry.CRUST, y = q.y / PrepGeometry.CRUST })
end

-- How to draw a registered full-canvas body image (P3, P4, P13) so its measured body lands on
-- the displayed ellipse with its measured body centre on the view's pivot.
-- body = { alphaX, alphaY, centreX, centreY }: the body's alpha diameter as a share of the
-- canvas on each axis, and its alpha centre's offset from the canvas centre as a share of the
-- canvas (x right, y down), from the delivery manifest (stand-ins declare theirs).
-- Returns the image's size (px), Rotation (degrees) and the image centre's offset from the pivot
-- (px), so the GUI draws R(angle) diag(size) with no shear.
export type Body = { alphaX: number, alphaY: number, centreX: number, centreY: number }
export type Placement = { width: number, height: number, rotation: number, offset: Vec }

function PrepGeometry.bodyPlacement(e: Ellipse, body: Body): Placement
	local w = 2 * e.major / body.alphaX
	local h = 2 * e.minor / body.alphaY
	local c, s = math.cos(e.angle), math.sin(e.angle)
	-- The body centre sits at (centreX w, centreY h) in the image's own frame; turn it with the
	-- image and move the image the other way so the body centre stays on the pivot.
	local bx, by = body.centreX * w, body.centreY * h
	return { width = w, height = h, rotation = math.deg(e.angle), offset = { x = -(c * bx - s * by), y = -(s * bx + c * by) } }
end

-- The ball (P3) is never scaled by the oval except during the 0.1 s hand-off, when it follows
-- the moving preview oval with state 1 (moving-stroke rule, Astra r9 item 2): pass the current
-- displayed ellipse. At rest, frame 0, the ellipse is the round ball's.
function PrepGeometry.ballEllipse(frame: number, flatten: number?): Ellipse
	return PrepGeometry.ellipseOf(PrepGeometry.viewMatrix(PrepGeometry.ball(), frame, flatten))
end

-- Fitting an unsheared sprite (sauce patch, pinch, topping) of local size w x h turned theta
-- (radians) to the local stretch J of the view at its point. Returns the drawn size, Rotation
-- and the shear the GUI cannot show: the angle (degrees) by which the exact transformed sprite
-- axes miss 90 degrees. Zero shear means the unsheared draw is exact.
export type SpriteFit = { width: number, height: number, rotation: number, shear: number }

function PrepGeometry.spriteFit(J: Mat2, w: number, h: number, theta: number): SpriteFit
	local c, s = math.cos(theta), math.sin(theta)
	local G = PrepGeometry.mul(J, mat(c * w / 2, -s * h / 2, s * w / 2, c * h / 2))
	local e = PrepGeometry.ellipseOf(G)
	local ux = PrepGeometry.apply(G, { x = 1, y = 0 })
	local uy = PrepGeometry.apply(G, { x = 0, y = 1 })
	local cosA = (ux.x * uy.x + ux.y * uy.y) / (math.sqrt(ux.x ^ 2 + ux.y ^ 2) * math.sqrt(uy.x ^ 2 + uy.y ^ 2))
	return { width = 2 * e.major, height = 2 * e.minor, rotation = math.deg(e.angle), shear = math.abs(90 - math.deg(math.acos(math.clamp(cosA, -1, 1)))) }
end

-- The local stretch of dough-local units on screen: J = K / 0.95, the derivative of screenOf
-- (K already holds S once).
function PrepGeometry.localStretch(S: Mat2, frame: number, flatten: number?): Mat2
	local K = PrepGeometry.viewMatrix(S, frame, flatten)
	return mat(K.a / PrepGeometry.CRUST, K.b / PrepGeometry.CRUST, K.c / PrepGeometry.CRUST, K.d / PrepGeometry.CRUST)
end

-- Roll model (provisional, plan 3.1; the taper revised 2026-10-26). A stroke p1 -> p2 must
-- cross the dough. It stretches the dough along its own direction u by up to 35 % x (the share
-- of the dough's longest chord along u the stroke covers). The stretch is applied in ROLL_STEPS
-- equal parts, and each part is tapered by the dough's radius along u at that moment: 1 until
-- TAPER_FROM, falling to 0 at the 1.1 cap. So thin dough resists more as the stroke goes on and
-- a full stroke on a nearly full-size dough lands near full size instead of jumping to the cap
-- (the first model tapered once, by the radius before the stroke: 0.861 -> 1.1 in one stroke).
-- Semi-axes stop at 1.1. Judged on the two end points only, so equal physical strokes give
-- equal shapes whatever the event rate.
PrepGeometry.TAPER_FROM = 0.85 -- proposal
PrepGeometry.ROLL_STEPS = 16

-- The dough's radius along direction u (half its longest chord in that direction).
local function radiusAlong(S: Mat2, u: Vec): number
	local v = PrepGeometry.apply(PrepGeometry.inverse(S), u)
	return 1 / math.sqrt(v.x * v.x + v.y * v.y)
end

-- Length of the part of segment p1 -> p2 inside the dough, or 0.
function PrepGeometry.chordInside(S: Mat2, p1: Vec, p2: Vec): number
	-- In the unit-circle frame of S the dough is the unit disc.
	local Si = PrepGeometry.inverse(S)
	local a, b = PrepGeometry.apply(Si, p1), PrepGeometry.apply(Si, p2)
	local dx, dy = b.x - a.x, b.y - a.y
	local A = dx * dx + dy * dy
	if A < 1e-12 then
		return 0
	end
	local B = 2 * (a.x * dx + a.y * dy)
	local C = a.x * a.x + a.y * a.y - 1
	local disc = B * B - 4 * A * C
	if disc <= 0 then
		return 0
	end
	local r = math.sqrt(disc)
	local t1 = math.clamp((-B - r) / (2 * A), 0, 1)
	local t2 = math.clamp((-B + r) / (2 * A), 0, 1)
	local len = math.sqrt((p2.x - p1.x) ^ 2 + (p2.y - p1.y) ^ 2)
	return (t2 - t1) * len
end

function PrepGeometry.roll(S: Mat2, p1: Vec, p2: Vec): Mat2?
	local dx, dy = p2.x - p1.x, p2.y - p1.y
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1e-9 then
		return nil
	end
	local chord = PrepGeometry.chordInside(S, p1, p2)
	if chord <= 0 then
		return nil
	end
	local u = { x = dx / len, y = dy / len }
	local cover = math.clamp(chord / (2 * radiusAlong(S, u)), 0, 1)
	-- Untapered, the parts multiply to exactly 1 + 0.35 x cover, as one undivided stretch would.
	local part = (1 + PrepGeometry.STRETCH * cover) ^ (1 / PrepGeometry.ROLL_STEPS) - 1
	for _ = 1, PrepGeometry.ROLL_STEPS do
		local half = radiusAlong(S, u)
		local taper = math.clamp((PrepGeometry.CAP - half) / (PrepGeometry.CAP - PrepGeometry.TAPER_FROM), 0, 1)
		local k = part * taper
		-- New outline = (I + k u u^T) applied to the old one; keep the symmetric factor of A S^2 A^T.
		local A = mat(1 + k * u.x * u.x, k * u.x * u.y, k * u.x * u.y, 1 + k * u.y * u.y)
		local AS = PrepGeometry.mul(A, S)
		local l1, l2, angle = symEigen(PrepGeometry.mul(AS, transpose(AS)))
		local a = math.min(math.sqrt(l1), PrepGeometry.CAP)
		local b = math.min(math.sqrt(math.max(l2, 0)), PrepGeometry.CAP)
		S = fromEigen(a, b, angle)
	end
	return S
end

-- The dough after a list of committed strokes ({ x1, y1, x2, y2 }); strokes that miss are skipped.
function PrepGeometry.doughShape(strokes: { { x1: number, y1: number, x2: number, y2: number } }): Mat2
	local S = PrepGeometry.ball()
	for _, l in strokes do
		S = PrepGeometry.roll(S, { x = l.x1, y = l.y1 }, { x = l.x2, y = l.y2 }) or S
	end
	return S
end

-- Which two P4 states to show and the crossfade weight of the second, by mean radius.
function PrepGeometry.stateBlend(meanRadius: number): (number, number, number)
	local r = PrepGeometry.STATE_RADII
	if meanRadius <= r[1] then
		return 1, 1, 0
	end
	for i = 1, #r - 1 do
		if meanRadius <= r[i + 1] then
			return i, i + 1, (meanRadius - r[i]) / (r[i + 1] - r[i])
		end
	end
	return #r, #r, 0
end

-- Layout envelope. The frame comes first; the mat is the frame / 0.9 rounded OUTWARD (phone:
-- 190 / 0.9 = 211.111 -> 212), so the 1.1 over-roll envelope (209 on phone) has 1.5 px each
-- side. Returns every size the station needs and whether the station height holds the mat.
export type Envelope = { frame: number, crust: number, overRoll: number, matExact: number, mat: number, ball: number, fits: boolean, shortfall: number }

function PrepGeometry.envelope(frame: number, stationHeight: number): Envelope
	local matExact = frame * PrepGeometry.MAT_OVER_FRAME
	local m = math.ceil(matExact - 1e-9)
	return {
		frame = frame,
		crust = frame * PrepGeometry.CRUST,
		overRoll = frame * PrepGeometry.CAP,
		matExact = matExact,
		mat = m,
		ball = frame * PrepGeometry.BALL,
		fits = stationHeight >= m,
		shortfall = math.max(0, m - stationHeight),
	}
end

return PrepGeometry
