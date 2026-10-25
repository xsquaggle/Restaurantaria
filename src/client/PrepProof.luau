--!strict
-- Studio-only Prep contract proof (cooking plan rev 6, build step 2's measurements, with Astra's
-- response 9 corrections). Declared engineering STAND-INs, never art: flat ovals drawn into an
-- EditableImage, plain bars and text buttons, every view labelled "STAND-IN". Nothing requires
-- this module; a Studio play test calls it from the command bar or the Studio MCP:
--   require(LocalPlayer.PlayerScripts.Client.PrepProof).run(mode, opts)
-- It refuses to run outside Studio. It places fixtures over the live station area, measures
-- them and returns a report; unmount() removes them and restores any layout it changed.

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Art = require(Shared.Art)
local G = require(Shared.PrepGeometry)
local Food = require(Shared.PrepFood)

local PrepProof = {}

local CANVAS = 512
-- Declared stand-in bodies: alpha diameter share and a deliberate centre offset (canvas share)
-- so registration is exercised, as a manifest would declare them.
PrepProof.BODIES = {
	P3 = { alphaX = 0.35, alphaY = 0.35, centreX = 0.005, centreY = -0.004 },
	P4 = { alphaX = 0.95, alphaY = 0.95, centreX = -0.004, centreY = 0.005 },
}
local MEASURE = Color3.fromRGB(0, 255, 0) -- measurement colour for pixel captures
local DOUGH = Color3.fromRGB(236, 212, 168) -- beige stand-in dough

local state: any = { parts = {}, restore = {} }
local images: { [string]: EditableImage } = {}

local function guiRoot(): (Frame, Frame, Frame)
	local gui = (Players.LocalPlayer :: Player).PlayerGui:WaitForChild("Restaurantaria")
	local root = gui:WaitForChild("Root") :: Frame
	return root, root:WaitForChild("Stations") :: Frame, root:WaitForChild("Hints") :: Frame
end

local function new(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

-- A white disc of the declared body on a transparent canvas (2 x 2 supersampled edge). Tinted
-- by ImageColor3. The body is a circle; the oval comes from the draw transform only.
local function bodyImage(key: string): EditableImage
	if images[key] then
		return images[key]
	end
	local body = PrepProof.BODIES[key]
	local image = AssetService:CreateEditableImage({ Size = Vector2.new(CANVAS, CANVAS) })
	local buf = buffer.create(CANVAS * CANVAS * 4)
	local r = body.alphaX * CANVAS / 2
	local cx, cy = CANVAS / 2 + body.centreX * CANVAS, CANVAS / 2 + body.centreY * CANVAS
	for y = 0, CANVAS - 1 do
		for x = 0, CANVAS - 1 do
			local cover = 0
			for sy = 0, 1 do
				for sx = 0, 1 do
					local dx, dy = x + 0.25 + sx * 0.5 - cx, y + 0.25 + sy * 0.5 - cy
					if dx * dx + dy * dy <= r * r then
						cover += 0.25
					end
				end
			end
			local o = (y * CANVAS + x) * 4
			buffer.writeu8(buf, o, 255)
			buffer.writeu8(buf, o + 1, 255)
			buffer.writeu8(buf, o + 2, 255)
			buffer.writeu8(buf, o + 3, math.round(cover * 255))
		end
		if y % 64 == 63 then
			task.wait()
		end
	end
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(CANVAS, CANVAS), buf)
	images[key] = image
	return image
end

local function label(text: string, size: number, parent: Instance, pos: UDim2, anchor: Vector2?): TextLabel
	local l = new("TextLabel", {
		Text = text,
		TextSize = size,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Color3.fromRGB(150, 20, 40),
		BackgroundTransparency = 0.1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = pos,
		AnchorPoint = anchor or Vector2.zero,
		ZIndex = 60,
		Parent = parent,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = l })
	return l
end

function PrepProof.unmount()
	for _, p in state.parts do
		p:Destroy()
	end
	state.parts = {}
	for inst, props in state.restore do
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	state.restore = {}
	if state.conn then
		state.conn:Disconnect()
		state.conn = nil
	end
end

local function remember(inst: Instance, props: { [string]: any })
	state.restore[inst] = state.restore[inst] or {}
	for k in props do
		if state.restore[inst][k] == nil then
			state.restore[inst][k] = (inst :: any)[k]
		end
		(inst :: any)[k] = props[k]
	end
end

-- Proposed station allocation. Phone: the mat is 212 (190 / 0.9 rounded outward) and the
-- station today is 209, so the compact hint strip gives 3 px (34 -> 31) and the mat meets the
-- station's top and bottom. HD: unchanged. Returns the layout numbers.
local function layout(stations: Frame, hints: Frame): any
	local compact = stations.AbsoluteSize.Y < 300
	local W, H = stations.AbsoluteSize.X, stations.AbsoluteSize.Y
	local frame
	if compact then
		frame = G.PHONE_FRAME
		local need = G.envelope(frame, H).mat
		if H < need then
			local give = need - H
			remember(stations, { Size = UDim2.fromOffset(W, need) })
			remember(hints, { Position = hints.Position + UDim2.fromOffset(0, give), Size = hints.Size - UDim2.fromOffset(0, give) })
			H = need
		end
	end
	local margin = if compact then 6 else math.clamp(math.round(H * 0.03), 6, 24)
	local gap = if compact then 4 else math.max(4, math.round(W * 0.01))
	-- The tool column keeps Topping's side layout: two across, three rows (Undo in the sixth).
	local trayAspect = 76 / 62
	local cellH = (H - margin * 2 - gap * 2) / 3
	local cellW = cellH * trayAspect
	local gridW = cellW * 2 + gap
	if not compact then
		local boardD = math.min(H - margin * 2, W - gridW - margin * 3)
		frame = math.floor(boardD * 0.9)
	end
	local env = G.envelope(frame, H)
	local left = margin * 2 + gridW
	local cx = left + (W - margin - left) / 2
	return { compact = compact, W = W, H = H, margin = margin, gap = gap, cellW = cellW, cellH = cellH, gridW = gridW, env = env, cx = cx, cy = H / 2 }
end

local function placeBody(parent: Instance, key: string, e: G.Ellipse, cx: number, cy: number, colour: Color3, z: number): ImageLabel
	local pl = G.bodyPlacement(e, PrepProof.BODIES[key])
	local img = new("ImageLabel", {
		Name = "StandIn_" .. key,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(pl.width, pl.height),
		Rotation = pl.rotation,
		Position = UDim2.fromOffset(cx + pl.offset.x, cy + pl.offset.y),
		ImageColor3 = colour,
		ZIndex = z,
		Parent = parent,
	})
	img.ImageContent = Content.fromObject(bodyImage(key))
	return img
end

local function clipChain(inst: GuiObject): { string }
	local out = {}
	local p: Instance? = inst.Parent
	while p and p:IsA("GuiObject") do
		if (p :: GuiObject).ClipsDescendants then
			table.insert(out, string.format("%s clips at %s size %s", p.Name, tostring((p :: GuiObject).AbsolutePosition), tostring((p :: GuiObject).AbsoluteSize)))
		end
		p = p.Parent
	end
	return out
end

local function r2(v: number): string
	return string.format("%.2f", v)
end

-- Modes:
--  layout {colour?}: the Prep layout at this size: mat, target ring, a full-size round dough,
--    tool cells, Undo, pin; reports every size, the clip chain and the fit.
--  body {key = "P3" | "P4", a, b, turn, flatten?, colour?}: one registered body at the mat
--    centre for pixel measurement (MEASURE colour by default).
--  pin {x, y}: the pin stand-in anchored at a station point (sweep captures).
--  views {a, b, turn}: Prep, Bake (0.58), Cut and result-card views of one dough with sauce and
--    cheese stamps at stored dough-local positions, for the extreme-oval captures.
--  stroke {}: a 0.5 s scripted roll on real frames, P3 -> P4 hand-off included; logs every
--    frame's drawn body against the expected oval and the crossfade alphas.
function PrepProof.run(mode: string, opts: any?): string
	if not RunService:IsStudio() then
		return "refused: Studio only"
	end
	local o = opts or {}
	PrepProof.unmount()
	local root, stations, hints = guiRoot()
	for _, holder in stations:GetChildren() do
		if holder:IsA("GuiObject") and holder.Visible then
			remember(holder, { Visible = false })
		end
	end
	local L = layout(stations, hints)
	local fx = new("Frame", { Name = "PrepProof", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = stations })
	table.insert(state.parts, fx)
	local out = {}
	local function add(line: string)
		table.insert(out, line)
	end
	label("STAND-IN fixtures (Studio only, not art)", if L.compact then 14 else 18, fx, UDim2.fromOffset(4, 2))
	add(string.format("viewport %s station %dx%d hints %s+%s nav %s rail %s", tostring(workspace.CurrentCamera.ViewportSize), L.W, L.H, tostring(hints.AbsolutePosition), tostring(hints.AbsoluteSize), tostring((root:FindFirstChild("Nav") :: GuiObject).AbsolutePosition), tostring((root:FindFirstChild("Rail") :: GuiObject).AbsolutePosition)))
	local env = L.env
	add(string.format("frame %d crust %s over-roll %s mat exact %s -> %d fits=%s shortfall=%d", env.frame, r2(env.crust), r2(env.overRoll), r2(env.matExact), env.mat, tostring(env.fits), env.shortfall))

	local function mat()
		local board = new("ImageLabel", { Name = "MatStandIn", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(L.cx, L.cy), Size = UDim2.fromOffset(env.mat, env.mat), ZIndex = 2, Parent = fx })
		Art.apply(board, "board_round")
		local ring = new("Frame", { Name = "TargetRing", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(L.cx, L.cy), Size = UDim2.fromOffset(env.crust, env.crust), ZIndex = 3, Parent = fx })
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
		new("UIStroke", { Color = Color3.fromRGB(120, 90, 60), Thickness = 1, Transparency = 0.3, Parent = ring })
		return board
	end

	if mode == "layout" then
		local board = mat()
		local dough = placeBody(fx, "P4", G.ellipseOf(G.viewMatrix(G.shape(0.95, 0.95, 0), env.frame)), L.cx, L.cy, o.colour or DOUGH, 4)
		local names = { "Dough", "Ladle", "Cheese", "", "", "Undo" }
		local undo
		for i, name in names do
			if name ~= "" then
				local col, row = (i - 1) % 2, (i - 1) // 2
				local b = new("TextButton", {
					Name = "Tool_" .. name,
					Text = name .. (if name ~= "Undo" then "\nSTAND-IN" else ""),
					TextSize = if L.compact then 14 else 22,
					Font = Enum.Font.GothamBold,
					BackgroundColor3 = Color3.fromRGB(250, 244, 230),
					Position = UDim2.fromOffset(L.margin + col * (L.cellW + L.gap), L.margin + row * (L.cellH + L.gap)),
					Size = UDim2.fromOffset(L.cellW, L.cellH),
					ZIndex = 5,
					Parent = fx,
				})
				if name == "Undo" then
					undo = b
					-- Undo floor 86 x 48 on phone, even where the cell is narrower.
					if L.compact and L.cellW < 86 then
						b.Size = UDim2.fromOffset(86, L.cellH)
					end
				end
			end
		end
		local pin = new("Frame", { Name = "PinStandIn", BackgroundColor3 = Color3.fromRGB(110, 80, 50), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(env.frame * 0.6, if L.compact then 14 else 40), Position = UDim2.fromOffset(L.cx + env.frame * 0.3, L.cy + env.frame * 0.36), ZIndex = 30, Parent = fx })
		label("pin STAND-IN", if L.compact then 14 else 16, pin, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		task.wait(0.2)
		local bodyD = dough.AbsoluteSize.X * PrepProof.BODIES.P4.alphaX
		add(string.format("mat %s at %s; dough image %s body %s px (crust floor 180 on phone)", tostring(board.AbsoluteSize), tostring(board.AbsolutePosition), tostring(dough.AbsoluteSize), r2(bodyD)))
		add(string.format("mat top %s bottom %s vs station 0..%d; mat right edge %s vs station width %d", r2(board.AbsolutePosition.Y - stations.AbsolutePosition.Y), r2(board.AbsolutePosition.Y - stations.AbsolutePosition.Y + board.AbsoluteSize.Y), L.H, r2(board.AbsolutePosition.X + board.AbsoluteSize.X), L.W))
		add(string.format("tool cell %sx%s grid width %s; Undo %s", r2(L.cellW), r2(L.cellH), r2(L.gridW), tostring(undo.AbsoluteSize)))
		add(string.format("pin %s", tostring(pin.AbsoluteSize)))
		local canvas = env.overRoll / PrepProof.BODIES.P4.alphaX
		add(string.format("over-roll image canvas %s px vs mat %d; dough clip chain: %s", r2(canvas), env.mat, table.concat(clipChain(dough), "; ")))
		add(string.format("the over-roll body (%s) fits inside the clipping station %dx%d: %s", r2(env.overRoll), L.W, L.H, tostring(env.overRoll <= L.H and env.overRoll <= L.W)))
	elseif mode == "body" then
		mat()
		local S = G.shape(o.a or 0.35, o.b or o.a or 0.35, math.rad(o.turn or 0))
		local e = G.ellipseOf(G.viewMatrix(S, env.frame, o.flatten))
		local img = placeBody(fx, o.key or "P4", e, L.cx, L.cy, o.colour or MEASURE, 4)
		task.wait(0.2)
		local pivot = stations.AbsolutePosition + Vector2.new(L.cx, L.cy)
		add(string.format("body %s expected %sx%s px at %s deg; pivot (gui) %s; image %s rotation %s", o.key or "P4", r2(2 * e.major), r2(2 * e.minor), r2(math.deg(e.angle)), tostring(pivot), tostring(img.AbsoluteSize), r2(img.AbsoluteRotation)))
	elseif mode == "pin" then
		mat()
		placeBody(fx, "P4", G.ellipseOf(G.viewMatrix(G.shape(0.95, 0.95, 0), env.frame)), L.cx, L.cy, DOUGH, 4)
		for _, at in o.points or { { L.cx, L.cy } } do
			local pin = new("Frame", { Name = "PinStandIn", BackgroundColor3 = Color3.fromRGB(110, 80, 50), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(env.frame * 0.6, if L.compact then 14 else 40), Position = UDim2.fromOffset(at[1], at[2]), ZIndex = 30, Parent = fx })
			new("Frame", { Name = "Pointer", BackgroundColor3 = Color3.fromRGB(255, 0, 255), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 4), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 31, Parent = pin })
		end
		add("pins drawn in the station frame, which clips; anchor = pointer (magenta dot), never clamped")
		add(string.format("mat centre %s,%s mat %d; mat edges x %s..%s y %s..%s", r2(L.cx), r2(L.cy), env.mat, r2(L.cx - env.mat / 2), r2(L.cx + env.mat / 2), r2(L.cy - env.mat / 2), r2(L.cy + env.mat / 2)))
	elseif mode == "views" then
		-- Four views side by side at their sizes: Prep (frame), Bake flatten 0.58 (same frame),
		-- Cut (same frame) and the result-card thumbnail (72 HD / 56 phone).
		local S = G.shape(o.a or 1.1, o.b or 0.35, math.rad(o.turn or 45))
		local thumb = if L.compact then 56 else 72
		local scale = if L.compact then 0.55 else 0.42 -- views shrunk to sit side by side; stated in the report
		local F = math.floor(env.frame * scale)
		local specs = { { "Prep", F, 1 }, { "Bake 0.58", F, G.BAKE_FLATTEN }, { "Cut", F, 1 }, { "Result", thumb, 1 } }
		local cells, _ = Food.sauce({ { kind = "pour", x = -0.3, y = -0.2 }, { kind = "pour", x = 0.35, y = 0.1 }, { kind = "pour", x = 0, y = 0.45 }, { kind = "spread", x = -0.7, y = 0, x2 = 0.7, y2 = 0 } })
		local pinches = {}
		for i = 0, 11 do
			local a = i * math.pi / 6
			table.insert(pinches, { x = 0.55 * math.cos(a), y = 0.55 * math.sin(a) })
		end
		table.insert(pinches, { x = 0.9, y = 0 }) -- one on the crust
		local x = L.margin + 4
		for _, spec in specs do
			local name, frame, flatten = spec[1], spec[2], spec[3]
			local cx, cy = x + frame * 1.1 / 2, L.cy + 8
			local e = G.ellipseOf(G.viewMatrix(S, frame, flatten))
			placeBody(fx, "P4", e, cx, cy, DOUGH, 4)
			local J = G.localStretch(S, frame, flatten)
			for i = 1, Food.SAUCE_CELLS + 8 do
				local amount = cells[i]
				if amount > 0.005 then
					local c = Food.centroids[i]
					local off = G.screenOf(S, frame, flatten, c)
					local fit = G.spriteFit(J, 0.3, 0.3, 0)
					local stamp = new("Frame", { BackgroundColor3 = Color3.fromRGB(200, 40, 30), BackgroundTransparency = 1 - math.min(0.75, amount * 4), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(fit.width, fit.height), Rotation = fit.rotation, Position = UDim2.fromOffset(cx + off.x, cy + off.y), ZIndex = 5, Parent = fx })
					new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = stamp })
				end
			end
			for _, p in pinches do
				local off = G.screenOf(S, frame, flatten, p)
				local fit = G.spriteFit(J, 2 * Food.PINCH_RADIUS, 2 * Food.PINCH_RADIUS, 0)
				local pin = new("Frame", { BackgroundColor3 = Color3.fromRGB(255, 236, 140), BackgroundTransparency = 0.25, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(fit.width, fit.height), Rotation = fit.rotation, Position = UDim2.fromOffset(cx + off.x, cy + off.y), ZIndex = 6, Parent = fx })
				new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = pin })
			end
			label(name .. " STAND-IN", 14, fx, UDim2.fromOffset(x, L.cy + 8 + frame * 0.62), nil)
			add(string.format("%s: frame %d flatten %.2f drawn dough %sx%s at %s deg", name, frame, flatten, r2(2 * e.major), r2(2 * e.minor), r2(math.deg(e.angle))))
			x += frame * 1.1 + 14
		end
		add(string.format("views drawn at %.2f of the work frame to sit side by side (result card at its own %d px); measured axes from the transform", scale, thumb))
	elseif mode == "stroke" then
		mat()
		local S0 = G.ball()
		local base = env.frame
		local p3 = placeBody(fx, "P3", G.ellipseOf(G.viewMatrix(S0, base)), L.cx, L.cy, DOUGH, 4)
		local p4 = placeBody(fx, "P4", G.ellipseOf(G.viewMatrix(S0, base)), L.cx, L.cy, DOUGH, 5)
		p4.ImageTransparency = 1
		local log = {}
		local t0 = os.clock()
		local p1, p2 = { x = -1, y = 0.1 }, { x = 1, y = -0.1 }
		local worst, prevD = 0, nil :: number?
		local worstJump = 0
		while true do
			local t = os.clock() - t0
			local u = math.clamp(t / 0.5, 0, 1)
			local S = G.roll(S0, p1, { x = p1.x + (p2.x - p1.x) * u, y = p1.y + (p2.y - p1.y) * u }) or S0
			local e = G.ellipseOf(G.viewMatrix(S, base))
			local fade = math.clamp(t / 0.1, 0, 1) -- 0.1 s hand-off: P3 out, state 1 in, same oval
			for _, pair in { { p3, "P3" }, { p4, "P4" } } do
				local img, key = pair[1], pair[2]
				local pl = G.bodyPlacement(e, PrepProof.BODIES[key])
				img.Size = UDim2.fromOffset(pl.width, pl.height)
				img.Rotation = pl.rotation
				img.Position = UDim2.fromOffset(L.cx + pl.offset.x, L.cy + pl.offset.y)
			end
			p3.ImageTransparency = fade
			p4.ImageTransparency = 1 - fade
			RunService.RenderStepped:Wait()
			-- After the frame: the drawn bodies against the expected oval.
			local d3 = p3.AbsoluteSize.X * PrepProof.BODIES.P3.alphaX
			local d4 = p4.AbsoluteSize.X * PrepProof.BODIES.P4.alphaX
			worst = math.max(worst, math.abs(d3 - 2 * e.major), math.abs(d4 - 2 * e.major))
			if prevD then
				worstJump = math.max(worstJump, math.abs(d4 - prevD))
			end
			prevD = d4
			table.insert(log, string.format("t=%.3f expected %.2f P3 %.2f (a=%.2f) P4 %.2f (a=%.2f)", t, 2 * e.major, d3, 1 - p3.ImageTransparency, d4, 1 - p4.ImageTransparency))
			if u >= 1 and t > 0.55 then
				break
			end
		end
		add(string.format("frames %d; worst drawn-body error vs expected oval %.3f px; largest frame-to-frame body change %.3f px", #log, worst, worstJump))
		for _, l in log do
			add(l)
		end
	end
	return table.concat(out, "\n")
end

return PrepProof
