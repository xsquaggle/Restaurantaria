--!strict
-- Native avatar customers in the 3D Order room (QA-002). Each waiting customer is a clone of
-- their look from the server's CustomerLooks folder (LooksFolder: the one the server stamped,
-- never a stale saved folder of the same name), which the server builds offstage. They walk
-- in from the left along a lane behind the counter, step up to a free spot, idle there and
-- walk out to the right once their order is taken. Only the root is anchored and moved; the
-- walk and idle animations drive the limbs, and the walk plays at the speed its planted foot
-- travels, so the feet keep pace with the floor. Labels are not drawn here: head() gives each figure's
-- projected head box so the station can place its name tag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LooksFolder = require(ReplicatedStorage.Shared.LooksFolder)

local OrderCrowd = {}

-- Roblox's default R15 idle and walk (the ids its Animate script uses).
local IDLE = "rbxassetid://507766388"
local WALK = "rbxassetid://913402848"
-- How fast the walk animation's planted foot moves back, in hip heights per second at speed
-- 1 (measured on the three fallbacks: 2.769 to 2.773).
local STANCE = 2.77
-- Walking speed in hip heights per second, about 5 studs a second for an average avatar.
local PACE = 2.4
-- Turning rate in radians per second, and the largest change of heading taken while walking.
local TURN = 9
local FACE = 1
-- From the measured layout (lobby-layout-sheet rev 3): counter spots as shares of the
-- counter's width (screen left is +X), the stand line behind its back edge, the lane that
-- walkers use behind the waiting customers, and the off-screen start and finish.
local SPOTS = { 0.3, 0, -0.3 }
local STAND = 1.2
local LANE = 3.9
local ENTER_X = 18
local EXIT_X = -22
-- Parts more than this far above the head are left out of the head box: some accessories
-- carry stray invisible parts far above the avatar.
local HEAD_REACH = 3
-- Hair can show a little above its part's box (Marta's by 5 px at HD), so the box's top is
-- raised by this much, in studs.
local HEAD_PAD = 0.15
-- A look that has not replicated by then is stood in for by any other look.
local LOOK_WAIT = 5

type Figure = {
	id: number,
	model: Model,
	root: BasePart,
	lift: number,
	idle: AnimationTrack,
	walk: AnimationTrack,
	walking: boolean,
	pos: Vector3,
	yaw: number,
	path: { Vector3 },
	spot: number?,
	leaving: boolean,
	headParts: { BasePart },
	headTop: number,
}

function OrderCrowd.new(room: any)
	-- The server's container (QA18-01): never just the first folder of the name, which a saved
	-- place can leave empty.
	local container = LooksFolder.binder(ReplicatedStorage)
	local warned = false
	local origin = room.origin :: Vector3
	local size = room.size :: Vector3
	local back = size.Z / 2
	local function floor(x: number, z: number): Vector3
		return Vector3.new(origin.X + x, origin.Y, origin.Z + z)
	end
	local standZ, laneZ = back + STAND, back + LANE

	local figures: { [number]: Figure } = {}
	local pending: { [number]: { look: string, since: number, instant: boolean } } = {}
	local spots: { [number]: number } = {}
	local clock = 0

	local function make(id: number, template: Model): Figure
		local model = template:Clone()
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		root.Anchored = true
		humanoid.EvaluateStateMachine = false
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local function track(id: string): AnimationTrack
			local a = Instance.new("Animation")
			a.AnimationId = id
			local t = (animator :: Animator):LoadAnimation(a)
			t.Looped = true
			return t
		end
		local idle, walk = track(IDLE), track(WALK)
		idle:Play(0, 1, 1)
		-- Out of step with each other, so a row of customers does not breathe in unison.
		idle.TimePosition = math.random() * math.max(idle.Length, 1)
		walk:Play(0, 0.001, PACE / STANCE)
		local head = model:FindFirstChild("Head") :: BasePart
		local headParts = { head }
		for _, a in model:GetChildren() do
			local handle = if a:IsA("Accessory") then a:FindFirstChild("Handle") else nil
			if handle and handle:IsA("BasePart") and handle.Transparency < 1 then
				table.insert(headParts, handle)
			end
		end
		local figure: Figure = {
			id = id,
			model = model,
			root = root,
			lift = humanoid.HipHeight + root.Size.Y / 2,
			idle = idle,
			walk = walk,
			walking = false,
			pos = floor(ENTER_X, laneZ),
			yaw = math.pi / 2,
			path = {},
			spot = nil,
			leaving = false,
			headParts = headParts,
			headTop = 0,
		}
		model.Parent = room.folder
		return figure
	end

	-- Sends a figure to the leftmost free spot, along the lane behind the others.
	local function seat(f: Figure)
		for i = 1, #SPOTS do
			if spots[i] == nil then
				spots[i] = f.id
				f.spot = i
				local x = size.X * SPOTS[i]
				f.path = { floor(x, laneZ), floor(x, standZ) }
				return
			end
		end
	end

	local function leave(f: Figure)
		f.leaving = true
		local x = f.pos.X - origin.X
		f.path = { floor(x, laneZ), floor(EXIT_X, laneZ) }
	end

	local crowd = {}

	-- waiting: the customers waiting at the counter now; instant: new figures start at their
	-- spot (customers already there when the room is built).
	function crowd.sync(waiting: { any }, instant: boolean?)
		local here = {}
		for _, customer in waiting do
			here[customer.id] = true
			if not figures[customer.id] and not pending[customer.id] then
				pending[customer.id] = { look = customer.look, since = clock, instant = instant == true }
			end
		end
		for id in pending do
			if not here[id] then
				pending[id] = nil
			end
		end
		for id, f in figures do
			if not here[id] and not f.leaving then
				leave(f)
			end
		end
	end

	function crowd.tick(dt: number)
		clock += dt
		-- Anyone without a spot waits off-screen by the entrance until one frees, longest
		-- waiting first.
		local queue = {}
		for id, f in figures do
			if f.spot == nil and not f.leaving then
				table.insert(queue, id)
			end
		end
		table.sort(queue)
		for _, id in queue do
			seat(figures[id])
		end
		-- New arrivals, in arrival order so the longest-waiting stands furthest left.
		local ids = {}
		for id in pending do
			table.insert(ids, id)
		end
		table.sort(ids)
		local looks = if #ids > 0 then container() else nil
		for _, id in ids do
			local p = pending[id]
			local template = if looks then looks:FindFirstChild(p.look) else nil
			if looks and not template and clock - p.since > LOOK_WAIT then
				template = looks:FindFirstChildOfClass("Model")
			end
			if not looks and not warned and clock - p.since > LOOK_WAIT then
				warned = true
				warn("[OrderCrowd] the server's CustomerLooks folder has not arrived; customers show once it does")
			end
			if template then
				pending[id] = nil
				local f = make(id, template :: Model)
				figures[id] = f
				seat(f)
				if p.instant and f.spot then
					f.pos = f.path[#f.path]
					f.yaw = 0
					table.clear(f.path)
				end
			end
		end
		for id, f in figures do
			local moving = false
			local target = f.path[1]
			if target then
				local gap = target - f.pos
				local dist = gap.Magnitude
				local turn = if dist > 1e-3 then (math.atan2(-gap.X, -gap.Z) - f.yaw + math.pi) % (2 * math.pi) - math.pi else 0
				f.yaw += math.clamp(turn, -TURN * dt, TURN * dt)
				-- A sharp change of direction is turned on the spot first, so nobody walks
				-- sideways or backwards.
				if math.abs(turn) <= FACE then
					moving = dist > 1e-3
					local speed = PACE * (f.lift - f.root.Size.Y / 2)
					if dist <= speed * dt then
						f.pos = target
						table.remove(f.path, 1)
						-- A leaver frees their spot once back in the lane, so the next customer
						-- never walks into them.
						if f.leaving and f.spot then
							spots[f.spot] = nil
							f.spot = nil
						end
					else
						f.pos += gap.Unit * speed * dt
					end
				end
			elseif f.leaving then
				f.model:Destroy()
				figures[id] = nil
				continue
			else
				-- At the counter: face the player.
				local turn = (0 - f.yaw + math.pi) % (2 * math.pi) - math.pi
				f.yaw += math.clamp(turn, -TURN * dt, TURN * dt)
			end
			if moving ~= f.walking then
				f.walking = moving
				f.walk:AdjustWeight(if moving then 1 else 0.001, 0.2)
				f.idle:AdjustWeight(if moving then 0.001 else 1, 0.2)
			end
			local at = f.pos + Vector3.new(0, f.lift, 0)
			f.root.CFrame = CFrame.new(at) * CFrame.Angles(0, f.yaw, 0)
		end
	end

	-- Pixels between neighbouring spots on the stand line, at head height.
	function crowd.spacing(): number
		local a = room.project(floor(size.X * SPOTS[1], standZ) + Vector3.new(0, 5, 0))
		local b = room.project(floor(size.X * SPOTS[2], standZ) + Vector3.new(0, 5, 0))
		return math.abs(a.X - b.X)
	end

	-- True once the customer stands at their spot.
	function crowd.standing(id: number): boolean
		local f = figures[id]
		return f ~= nil and not f.leaving and f.spot ~= nil and #f.path == 0
	end

	-- The projected box around a figure's head and its accessories, in station pixels:
	-- x0, y0, x1, y1. Nil when the customer has no figure.
	function crowd.head(id: number): (number?, number?, number?, number?)
		local f = figures[id]
		if not f then
			return nil
		end
		local head = f.headParts[1]
		local limit = head.Position.Y + head.Size.Y / 2 + HEAD_REACH
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		local top = -math.huge
		for _, part in f.headParts do
			local cf, half = part.CFrame, part.Size / 2
			if cf.Position.Y - half.Y > limit then
				continue
			end
			for _, c in { Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, 1, -1), Vector3.new(1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(1, -1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, 1, 1) } do
				local w = cf:PointToWorldSpace(half * c)
				local p = room.project(w)
				top = math.max(top, w.Y)
				x0, y0 = math.min(x0, p.X), math.min(y0, p.Y)
				x1, y1 = math.max(x1, p.X), math.max(y1, p.Y)
			end
		end
		local crown = room.project(Vector3.new(head.Position.X, top + HEAD_PAD, head.Position.Z))
		return x0, math.min(y0, crown.Y), x1, y1
	end

	function crowd.destroy()
		for _, f in figures do
			f.model:Destroy()
		end
		table.clear(figures)
		table.clear(pending)
	end

	return crowd
end

return OrderCrowd
