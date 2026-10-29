-- OrderCrowd.make hardening (Astra r19 residual risk: make assumed a fully built model, so a
-- partial look or a failed build could leave a customer missing until the next sync). The
-- crowd now builds only from a complete look (root, head, Humanoid), keeps the customer pending
-- when a build fails, marks that look and stands in another one, and stands a figure in its
-- rest pose if its animations fail. These rows check the look choice; the build itself needs
-- real avatars and is checked in Studio. Mock only: run it with tests/offline/run.py.

local OrderCrowd = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.OrderCrowd)

local failures = {}
local passed = 0
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

-- The mock's IsA is exact, so the parts are made as the base class the code asks for.
local function look(name: string, parts: { string }, parent: Instance): Instance
	local m = Instance.new("Model")
	m.Name = name
	for _, p in parts do
		if p == "Humanoid" then
			Instance.new("Humanoid").Parent = m
		else
			local part = Instance.new("BasePart")
			part.Name = p
			part.Parent = m
		end
	end
	m.Parent = parent
	return m
end

local FULL = { "HumanoidRootPart", "Head", "Humanoid" }
local looks = Instance.new("Folder")
local marta = look("marta", FULL, looks)
local bo = look("bo", { "Head", "Humanoid" }, looks) -- still arriving: no root yet
local ines = look("ines", FULL, looks)

check("complete: full look", OrderCrowd.complete(marta), true)
check("complete: no root", OrderCrowd.complete(bo), false)
check("complete: no Humanoid", OrderCrowd.complete(look("x", { "HumanoidRootPart", "Head" }, Instance.new("Folder"))), false)
check("complete: no head", OrderCrowd.complete(look("y", { "HumanoidRootPart", "Humanoid" }, Instance.new("Folder"))), false)
check("complete: nil", OrderCrowd.complete(nil), false)
check("complete: a folder", OrderCrowd.complete(Instance.new("Folder")), false)

local none = {}
check("pick: own complete look", OrderCrowd.pick(looks, "marta", 0, none), marta)
check("pick: partial own look waits", OrderCrowd.pick(looks, "bo", 1, none), nil)
check("pick: partial own look past the wait stands in a complete one", OrderCrowd.pick(looks, "bo", 6, none) ~= nil, true)
check("pick: the stand-in is complete", OrderCrowd.complete(OrderCrowd.pick(looks, "bo", 6, none)), true)
check("pick: missing look waits", OrderCrowd.pick(looks, "nobody", 1, none), nil)
check("pick: missing look past the wait", OrderCrowd.pick(looks, "nobody", 6, none) ~= nil, true)
check("pick: no folder yet", OrderCrowd.pick(nil, "marta", 9, none), nil)
-- A build from marta failed: marta's customer gets another look at once, never marta again.
local failed = { [marta] = true }
check("pick: failed own look stands in another at once", OrderCrowd.pick(looks, "marta", 0, failed), ines)
failed[ines] = true
check("pick: every complete look failed: keep waiting", OrderCrowd.pick(looks, "marta", 9, failed), nil)
-- bo's look completes: bo is built from it.
local root = Instance.new("BasePart")
root.Name = "HumanoidRootPart"
root.Parent = bo
check("pick: bo complete now", OrderCrowd.pick(looks, "bo", 1, none), bo)

local summary = string.format("order crowd checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
print("  " .. summary)
