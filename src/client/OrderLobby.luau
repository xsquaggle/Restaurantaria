--!strict
-- The Order room's lobby shell (lobby batch 1a): Blender-built wall, window-wall, corner-post,
-- wainscot, floor and ceiling modules, placed on the layout sheet's grid
-- (qa-r1/lobby-layout-sheet.md rev 3) around the counter. Code only places the modules; their
-- geometry, UVs and colour maps come from the Blender files as built.
--
-- Each module slot has a fixed place. The inherited (worn) and restored finishes are separate
-- models that share that place, so a later upgrade can swap one slot without moving anything.
-- The door modules (batch 1b) are not built yet, so side-wall modules 3 and 4 stay open, and
-- the window opening has no frame or glazing yet.
--
-- Shown only when ReplicatedStorage's "LobbyShell" attribute is "inherited" or "restored";
-- otherwise the painted backdrop stays. In Studio the declared planning geometry (window
-- view reserve and the customer route) is laid out with it, in yellow and labelled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Model3D = require(ReplicatedStorage.Shared.Model3D)

local OrderLobby = {}

-- Room interior, in studs from the sheet origin (the counter's centre on the floor):
-- X -20..20 (screen left is +X), Z -2..22 into the room, floor at 0, ceiling at 12.
local HALF_W = 20
local BACK = 22
local FRONT = -2
local HEIGHT = 12
local MODULE = 4
-- Back-wall modules 5 to 7 are one window module; side modules 3 and 4 are the door modules.
local WINDOW = { [5] = true, [6] = true, [7] = true }
local DOORS = { [3] = true, [4] = true }
-- The leak replaces one ceiling panel: column 8 from X +20, row 3 from the back wall
-- (X -12..-8, Z 10..14).
local LEAK = { col = 8, row = 3 }

-- Inherited finishes vary by slot so no two neighbours repeat the same wear.
local WALL_WEAR = {
	back = { "a", "c", "b", "a", "", "", "", "b", "c", "a" },
	left = { "b", "a", "", "", "c", "b" },
	right = { "c", "b", "", "", "a", "c" },
}
local WAINSCOT_WEAR = {
	back = { "a", "b", "b", "a", "b", "a", "a", "b", "a", "b" },
	left = { "b", "a", "", "", "b", "a" },
	right = { "a", "b", "", "", "a", "b" },
}

type Slot = { kind: string, wear: string?, cf: CFrame }

-- Turns a module's front (-Z in its own frame) to face into the room from each wall.
local FACING = {
	back = CFrame.identity,
	left = CFrame.Angles(0, math.pi / 2, 0),
	right = CFrame.Angles(0, -math.pi / 2, 0),
}

-- Every slot of the shell with the centre of the module's box, relative to the sheet origin.
local function slots(): { Slot }
	local out: { Slot } = {}
	local function add(kind: string, wear: string?, pos: Vector3, facing: CFrame)
		table.insert(out, { kind = kind, wear = wear, cf = CFrame.new(pos) * facing })
	end
	-- Back wall: modules 1 to 10 from X +20; the inner face is at Z 22, the wall runs to 23.
	for i = 1, 10 do
		local x = HALF_W + MODULE / 2 - MODULE * i
		if not WINDOW[i] then
			add("wall", WALL_WEAR.back[i], Vector3.new(x, HEIGHT / 2, BACK + 0.5), FACING.back)
		end
		-- Wainscot boards (0.5 to 3.3 high, 0.2 deep) run under the window too.
		add("wainscot", WAINSCOT_WEAR.back[i], Vector3.new(x, 1.9, BACK - 0.1), FACING.back)
	end
	add("window", nil, Vector3.new(-2, HEIGHT / 2, BACK + 0.5), FACING.back)
	-- Side walls: modules 1 to 6 from the back; the left wall's inner face is X +20.
	for _, side in { "left", "right" } do
		local sign = if side == "left" then 1 else -1
		for j = 1, 6 do
			if not DOORS[j] then
				local z = BACK + MODULE / 2 - MODULE * j
				add("wall", WALL_WEAR[side][j], Vector3.new(sign * (HALF_W + 0.5), HEIGHT / 2, z), FACING[side])
				add("wainscot", WAINSCOT_WEAR[side][j], Vector3.new(sign * (HALF_W - 0.1), 1.9, z), FACING[side])
			end
		end
		-- Corner post in the outside corner square, where the back and side walls butt.
		add("post", nil, Vector3.new(sign * (HALF_W + 0.5), HEIGHT / 2, BACK + 0.5), FACING.back)
	end
	-- Floor tiles (top at 0) and ceiling panels (underside at 12): ten columns by six rows.
	for col = 1, 10 do
		for row = 1, 6 do
			local x = HALF_W + MODULE / 2 - MODULE * col
			local z = BACK + MODULE / 2 - MODULE * row
			local turn = CFrame.Angles(0, math.rad(90 * ((col * 13 + row * 7) % 4)), 0)
			local wear = if (col * 31 + row * 17) % 5 < 2 then "b" else "a"
			add("floor", wear, Vector3.new(x, -0.1, z), turn)
			local leak = col == LEAK.col and row == LEAK.row
			add(if leak then "leak" else "ceiling", nil, Vector3.new(x, HEIGHT + 0.25, z), CFrame.identity)
		end
	end
	return out
end

-- Model for a slot in a finish state.
local function modelName(slot: Slot, state: string): string
	local kind = slot.kind
	if kind == "post" then
		return "lobby_corner_post"
	elseif kind == "window" then
		return "lobby_window_wall_" .. state
	elseif kind == "leak" then
		return if state == "restored" then "lobby_ceiling_restored" else "lobby_ceiling_leak_inherited"
	elseif kind == "ceiling" then
		return "lobby_ceiling_" .. state
	elseif state == "restored" then
		return "lobby_" .. kind .. "_restored"
	end
	return "lobby_" .. kind .. "_inherited_" .. (slot.wear :: string)
end

-- One built part per model, cloned for every slot (the clones share its mesh and texture).
local templates: { [string]: MeshPart } = {}

local function template(name: string): MeshPart?
	local t = templates[name]
	if t == nil then
		-- The Studio dev path needs EditableMesh, which errors when the place does not allow
		-- the mesh APIs; the room then keeps the painted backdrop instead of failing.
		local ok, built = pcall(Model3D.build, name)
		if not ok then
			warn("[OrderLobby] " .. name .. ": " .. tostring(built))
			return nil
		end
		t = built
		if t then
			templates[name] = t
		end
	end
	return t
end

function OrderLobby.state(): string?
	local s = ReplicatedStorage:GetAttribute("LobbyShell")
	return if s == "inherited" or s == "restored" then s else nil
end

-- Planning geometry: flat yellow or grey blocks with a label, never art. Studio only.
local PLANNING = Color3.fromRGB(255, 205, 50)

local function label(part: BasePart, face: Enum.NormalId, text: string, px: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = px
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = Color3.fromRGB(60, 45, 0)
	t.Text = text
	t.Parent = gui
	gui.Parent = part
end

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

local function planning(origin: CFrame): Folder
	local f = Instance.new("Folder")
	f.Name = "PlanningGeometry"
	local at = function(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	-- Window view reserve behind the back wall: sidewalk Z 23..29, road Z 29..41, and the
	-- facing building line at Z 45. Nothing on it is art; the street set comes later.
	local walk = block(f, "ViewReserveSidewalk", Vector3.new(80, 0.1, 6), at(0, -0.05, 26), Color3.fromRGB(205, 200, 185), 0)
	label(walk, Enum.NormalId.Top, "PLANNING: sidewalk Z 23-29", 4)
	local road = block(f, "ViewReserveRoad", Vector3.new(80, 0.1, 12), at(0, -0.05, 35), Color3.fromRGB(130, 132, 140), 0)
	label(road, Enum.NormalId.Top, "PLANNING: road Z 29-41", 4)
	local line = block(f, "ViewReserveBuildingLine", Vector3.new(40, 24, 0.2), at(-2, 12, 45), Color3.fromRGB(196, 210, 220), 0)
	local band = block(f, "ViewReserveLabel", Vector3.new(16, 2.4, 0.05), at(-2, 10.2, 44.85), PLANNING, 0)
	label(band, Enum.NormalId.Front, "PLANNING GEOMETRY: window view reserve, building line Z 45", 24)
	band.Parent = line
	-- Customer route, sheet "Route and queue points": in by the left door, out by the right.
	local function route(points: { Vector2 }, name: string, text: string)
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local mid = (a + b) / 2
			local d = b - a
			local seg = block(
				f,
				name .. i,
				Vector3.new(0.6, 0.06, d.Magnitude + 0.6),
				at(mid.X, 0.03, mid.Y) * CFrame.Angles(0, math.atan2(d.X, d.Y), 0),
				PLANNING,
				0.15
			)
			if i == 1 then
				label(seg, Enum.NormalId.Top, text, 8)
			end
		end
	end
	route({
		Vector2.new(26, 26), Vector2.new(26, 10), Vector2.new(17, 10), Vector2.new(12, 9),
		Vector2.new(8, 6), Vector2.new(4.2, 2.9),
	}, "RouteIn", "PLANNING: entrance route")
	route({
		Vector2.new(-4.2, 2.9), Vector2.new(-10, 9), Vector2.new(-17, 10), Vector2.new(-26, 10),
		Vector2.new(-26, 26),
	}, "RouteOut", "PLANNING: exit route")
	return f
end

-- Builds the shell around the sheet origin (world position of the counter's centre on the
-- floor). Returns nil when the shell is off or a model is missing.
function OrderLobby.build(originPos: Vector3): Folder?
	local state = OrderLobby.state()
	if state == nil then
		return nil
	end
	local origin = CFrame.new(originPos)
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder:SetAttribute("State", state)
	for _, slot in slots() do
		local name = modelName(slot, state)
		local t = template(name)
		if t == nil then
			folder:Destroy()
			warn("[OrderLobby] missing model " .. name .. "; showing the painted backdrop")
			return nil
		end
		local part = t:Clone()
		part.CFrame = origin * slot.cf * t.CFrame.Rotation
		-- The shell neither casts shadows into the room nor blocks the sun, so the approved
		-- counter keeps the lighting it was approved under.
		part.CastShadow = false
		part.Parent = folder
	end
	if RunService:IsStudio() then
		planning(origin).Parent = folder
	end
	return folder
end

return OrderLobby
