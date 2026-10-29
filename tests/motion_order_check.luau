-- The motion driver under a long frame (slice 7b-1, found in Studio). When one frame covers
-- several of a presentation's phase times (a hitch, or the app resuming), the phases must
-- still start in their own order: the shift card's timeline ends with a finish, and a finish
-- that runs before the XP count's phase leaves the bar and the rank on the old values while
-- the award shows the new one (Studio: "+30 XP", "Rank 1", "70 / 100" with the profile at
-- 100). Drives Motion with a stand-in Heartbeat on the mock's virtual clock. Mock only: run
-- it with tests/offline/run.py or inside Studio.

local RunService = game:GetService("RunService")
local beats: { () -> () } = {}
if RunService.Heartbeat == nil then
	-- The mock has no engine loop: one frame is one call of every connected function.
	RunService.Heartbeat = {
		Connect = function(_self: any, f: () -> ())
			table.insert(beats, f)
			local connection = {}
			function connection.Disconnect()
				local i = table.find(beats, f)
				if i then
					table.remove(beats, i)
				end
			end
			return connection
		end,
	}
end
local Motion = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Motion)

local failures = {}
local passed = 0
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

local function frame()
	for _, f in table.clone(beats) do
		f()
	end
end

-- A timeline like the card's: twelve phases, a motion owned by the eighth (the bar's fill,
-- with its final value), and an end that finishes the presentation.
local function timeline(log: { string }, bar: { value: number })
	local pr = Motion.presentation()
	for i = 1, 12 do
		pr:at(i * 0.25, function()
			table.insert(log, tostring(i))
			if i == 8 then
				local key = {}
				pr:own(key, function()
					bar.value = 100
				end)
				Motion.run(key, 0.9, function(p)
					bar.value = 70 + 30 * p
				end)
			end
		end)
	end
	pr:at(3.5, function()
		table.insert(log, "end")
		pr:finish()
	end)
	return pr
end

-- 1. At 60 frames a second: every phase once, in order, the bar on its final value.
do
	local log, bar = {}, { value = 70 }
	local pr = timeline(log, bar)
	for _ = 1, 4 * 60 do
		task.wait(1 / 60)
		frame()
	end
	check("60 fps: phases in order", table.concat(log, ","), "1,2,3,4,5,6,7,8,9,10,11,12,end")
	check("60 fps: finished", pr.alive, false)
	check("60 fps: bar final", bar.value, 100)
end

-- 2. One frame covering the whole timeline (a 5 s hitch right after it starts).
do
	local log, bar = {}, { value = 70 }
	local pr = timeline(log, bar)
	task.wait(1 / 60)
	frame()
	task.wait(5)
	frame()
	check("one long frame: phases in order before the end", table.concat(log, ","), "1,2,3,4,5,6,7,8,9,10,11,12,end")
	check("one long frame: finished", pr.alive, false)
	check("one long frame: bar on its final value", bar.value, 100)
end

-- 3. A 0.6 s hitch late in the timeline: the phases it covers start in order.
do
	local log, bar = {}, { value = 70 }
	timeline(log, bar)
	for _ = 1, 2.6 * 60 do
		task.wait(1 / 60)
		frame()
	end
	task.wait(0.6)
	frame()
	for _ = 1, 60 do
		task.wait(1 / 60)
		frame()
	end
	check("late hitch: phases in order", table.concat(log, ","), "1,2,3,4,5,6,7,8,9,10,11,12,end")
	check("late hitch: bar final", bar.value, 100)
end

-- 4. Two motions due in the same frame start in the order they were asked for.
do
	local log = {}
	Motion.run("a", 0.5, function() end, function()
		table.insert(log, "a")
	end)
	Motion.run("b", 0.5, function() end, function()
		table.insert(log, "b")
	end)
	Motion.run("c", 0.2, function() end, function()
		table.insert(log, "c")
	end)
	task.wait(2)
	frame()
	check("same frame: earliest due first, then the order asked", table.concat(log, ","), "c,a,b")
end

local summary = string.format("motion order checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
print("  " .. summary)
