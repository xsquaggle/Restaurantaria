--!strict
-- Hybrid proof: the Order station's counter as a generated 3D model behind a fixed camera.
-- Customers stay the 2D waist-up art; Order.luau draws them above the counter line this
-- module reports, so the 3D counter hides their waists as the drawn counter did. The
-- existing Order background art hangs on a plane behind them.
--
-- Studio only while models cannot be uploaded (see shared/Model3D.luau). Everything here
-- is local to this client.

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Model3D = require(Shared.Model3D)

local OrderRoom = {}

local COUNTER = "prop3d_order_counter"
-- Far from the baseplate and spawn so nothing else is in shot.
local ORIGIN = Vector3.new(0, 400, 0)
-- Camera height above the counter top and distance in front of its staff-side edge, in
-- studs; the field of view and aim are solved from the screen layout.
local EYE_RISE = 1.6
local EYE_BACK = 22
-- Share of the work surface's height above the counter's far top edge (the drawn
-- counter's COUNTER_TOP).
local LINE = 0.72
-- The counter runs a little past both sides of the work surface, as the drawn one did.
local BLEED = 1.04
-- Gap between the counter's customer side and the background plane, in studs.
local BACKDROP_GAP = 14

function OrderRoom.available(): boolean
	return Model3D.has(COUNTER)
end

-- ctx: the station context; container: the station's frame (its absolute rect is the work
-- surface). Returns nil when the model is missing.
function OrderRoom.new(ctx: any, container: GuiObject): any
	local size = Model3D.size(COUNTER) :: Vector3
	local folder = Instance.new("Folder")
	folder.Name = "OrderRoom"
	local counter = Model3D.build(COUNTER)
	if not counter then
		return nil
	end
	counter.CFrame = CFrame.new(ORIGIN + Vector3.new(0, size.Y / 2, 0)) * counter.CFrame.Rotation
	counter.Parent = folder
	local top = ORIGIN.Y + size.Y
	local front = ORIGIN.Z - size.Z / 2
	local back = ORIGIN.Z + size.Z / 2

	-- Warm key light from the upper left, the direction the painted stations are lit from
	-- (the camera looks along +Z, so screen left is +X). The sun comes from the same side.
	local lamp = Instance.new("Part")
	lamp.Name = "Lamp"
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.Transparency = 1
	lamp.Size = Vector3.one
	lamp.Position = ORIGIN + Vector3.new(size.X * 0.4, size.Y + 8, -6)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 236, 205)
	light.Brightness = 0.6
	light.Range = 28
	light.Shadows = true
	light.Parent = lamp
	lamp.Parent = folder

	-- Background plane: the existing Order background tiles, unlit so they keep their colours.
	local meta = Assets.Meta.backgrounds.bg_order
	local plane = Instance.new("Part")
	plane.Name = "Backdrop"
	plane.Anchored = true
	plane.CanCollide = false
	plane.Transparency = 1
	plane.CastShadow = false
	local planeW = size.X * 4
	local planeH = planeW * meta.height / meta.width
	plane.Size = Vector3.new(planeW, planeH, 0.1)
	plane.CFrame = CFrame.new(ORIGIN + Vector3.new(0, planeH * 0.3, size.Z / 2 + BACKDROP_GAP))
	plane.Parent = folder
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.LightInfluence = 0
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(meta.width, meta.height)
	surface.Adornee = plane
	surface.Parent = plane
	local tiles = {}
	for r = 0, meta.rows - 1 do
		for c = 0, meta.cols - 1 do
			local tile = Instance.new("ImageLabel")
			tile.BackgroundTransparency = 1
			tile.Position = UDim2.fromScale(c / meta.cols, r / meta.rows)
			tile.Size = UDim2.new(1 / meta.cols, 1, 1 / meta.rows, 1)
			tile:SetAttribute("Art", string.format("bg_order_%d", r * meta.cols + c + 1))
			tile.Parent = surface
			table.insert(tiles, tile)
		end
	end

	folder.Parent = workspace

	local camera = workspace.CurrentCamera
	local room = { line = 0 }

	-- Solve the camera so the counter spans the work surface (plus bleed) and its far top
	-- edge lands on LINE of the work surface's height.
	local function solve(): CFrame
		local inset = GuiService:GetGuiInset()
		local rectPos = container.AbsolutePosition + inset
		local rectSize = container.AbsoluteSize
		local wantSpan = rectSize.X * BLEED
		local wantMidX = rectPos.X + rectSize.X / 2
		local wantLine = rectPos.Y + rectSize.Y * LINE
		local eyeY = top + EYE_RISE
		local eyeZ = front - EYE_BACK
		local x, pitch, fov = 0, math.rad(-8), 40
		local left = Vector3.new(ORIGIN.X - size.X / 2, top, front)
		local right = Vector3.new(ORIGIN.X + size.X / 2, top, front)
		local far = Vector3.new(ORIGIN.X, top, back)
		local cf = CFrame.new()
		for _ = 1, 6 do
			cf = CFrame.new(x, eyeY, eyeZ) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(pitch, 0, 0)
			camera.CFrame = cf
			camera.FieldOfView = fov
			local l = camera:WorldToViewportPoint(left)
			local r = camera:WorldToViewportPoint(right)
			local f = camera:WorldToViewportPoint(far)
			local span = math.abs(r.X - l.X)
			-- Wider span wants a narrower view: scale tan(fov / 2).
			local t = math.tan(math.rad(fov) / 2) * span / wantSpan
			fov = math.clamp(math.deg(2 * math.atan(t)), 8, 90)
			-- Studs per pixel at the counter front, to move the eye sideways (looking along +Z,
			-- screen right is world -X).
			local perPx = size.X / math.max(span, 1)
			x += (wantMidX - (l.X + r.X) / 2) * perPx
			-- Radians per pixel vertically: tilting down lifts the scene on screen.
			local radPerPx = math.rad(fov) / camera.ViewportSize.Y
			pitch -= (f.Y - wantLine) * radPerPx
		end
		cf = CFrame.new(x, eyeY, eyeZ) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(pitch, 0, 0)
		camera.CFrame = cf
		camera.FieldOfView = fov
		local f = camera:WorldToViewportPoint(far)
		room.line = f.Y - rectPos.Y
		-- The background plane fills the view at its depth, so the painted room keeps the
		-- framing it had as a full-screen backdrop (cover-fit, centred on the view).
		local depth = plane.Position.Z - cf.Position.Z
		local viewH = 2 * depth * math.tan(math.rad(fov) / 2) / math.cos(pitch)
		local viewW = viewH * camera.ViewportSize.X / camera.ViewportSize.Y
		local k = math.max(viewW / meta.width, viewH / meta.height) * 1.02
		plane.Size = Vector3.new(meta.width * k, meta.height * k, 0.1)
		local hit = cf.Position + cf.LookVector * (depth / cf.LookVector.Z)
		plane.CFrame = CFrame.new(hit.X, hit.Y, plane.Position.Z)
		return cf
	end

	local active = false
	local fixed: CFrame? = nil
	local saved: { [string]: any } = {}

	function room.setActive(on: boolean)
		if on == active then
			return
		end
		active = on
		if on then
			for _, tile in tiles do
				Art.apply(tile, tile:GetAttribute("Art") :: string)
			end
			saved = {
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
				Brightness = Lighting.Brightness,
				ExposureCompensation = Lighting.ExposureCompensation,
				ClockTime = Lighting.ClockTime,
			}
			Lighting.Ambient = Color3.fromRGB(150, 132, 118)
			Lighting.OutdoorAmbient = Color3.fromRGB(160, 145, 130)
			-- Brightness 1.2 pushed the wood top past full red into yellow (QA-001); 0.5 keeps
			-- its highlight to a thin band. ClockTime 10.5 puts the sun at the upper left.
			Lighting.Brightness = 0.5
			Lighting.ExposureCompensation = 0
			Lighting.ClockTime = 10.5
			camera.CameraType = Enum.CameraType.Scriptable
			fixed = solve()
			RunService:BindToRenderStep("OrderRoomCamera", Enum.RenderPriority.Camera.Value + 1, function()
				camera.CameraType = Enum.CameraType.Scriptable
				camera.CFrame = fixed :: CFrame
			end)
		else
			RunService:UnbindFromRenderStep("OrderRoomCamera")
			for _, tile in tiles do
				Art.release(tile)
			end
			for k, v in saved do
				(Lighting :: any)[k] = v
			end
		end
	end

	-- Work-surface y (pixels from its top) of the counter's far top edge, for clipping the
	-- customers. Valid after the first solve; computed now so layout can use it.
	camera.CameraType = Enum.CameraType.Scriptable
	fixed = solve()

	function room.destroy()
		room.setActive(false)
		folder:Destroy()
	end

	return room
end

return OrderRoom
