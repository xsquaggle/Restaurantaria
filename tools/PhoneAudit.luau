-- Studio check for QA-007 (phone layout and text floors). Paste into the Studio MCP in the
-- Client datamodel during play, on the station to audit, with the device simulator at the
-- phone size. Reports what is drawn, not nominal values: every visible text with its
-- effective on-screen size (TextScaled labels are solved for the size that fits, inside
-- their UITextSizeConstraint; fixed sizes are multiplied by any UIScale above them), every
-- input region with its AbsoluteSize, and the main ScreenGui's insets. Covers every screen
-- gui under PlayerGui (world SurfaceGuis, such as planning labels, are left out). Read-only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("Restaurantaria") :: ScreenGui
local viewport = workspace.CurrentCamera.ViewportSize

local function shown(o: GuiObject): boolean
	local p: Instance? = o
	while p and p ~= playerGui do
		if (p:IsA("GuiObject") and not p.Visible) or (p:IsA("LayerCollector") and not p.Enabled) then
			return false
		end
		p = p.Parent
	end
	-- AbsolutePosition is measured below the top-bar inset, also for guis that ignore it.
	local a, s = o.AbsolutePosition + GuiService:GetGuiInset(), o.AbsoluteSize
	return s.X > 0 and s.Y > 0 and a.X < viewport.X and a.Y < viewport.Y and a.X + s.X > 0 and a.Y + s.Y > 0
end

local function scaleAbove(o: Instance): number
	local k = 1
	local p: Instance? = o
	while p and p ~= playerGui do
		local s = p:FindFirstChildOfClass("UIScale")
		if s then
			k *= s.Scale
		end
		p = p.Parent
	end
	return k
end

local function fits(label: TextLabel | TextButton, size: number): boolean
	local params = Instance.new("GetTextBoundsParams")
	params.Text = label.Text
	params.Font = label.FontFace
	params.Size = size
	params.Width = if label.TextWrapped then label.AbsoluteSize.X else math.huge
	local b = TextService:GetTextBoundsAsync(params)
	return b.X <= label.AbsoluteSize.X + 0.5 and b.Y <= label.AbsoluteSize.Y + 0.5
end

local function effectiveSize(label: TextLabel | TextButton): (number, string)
	if not label.TextScaled then
		return label.TextSize * scaleAbove(label), "fixed"
	end
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	local lo, hi = if c then c.MinTextSize else 1, if c then c.MaxTextSize else 100
	-- Largest whole size in [lo, hi] that fits; Roblox draws lo even when nothing fits.
	local best = lo
	local a, b = lo, hi
	while a <= b do
		local m = (a + b) // 2
		if fits(label, m) then
			best = m
			a = m + 1
		else
			b = m - 1
		end
	end
	return best, if fits(label, best) then "scaled" else "scaled, overflows at min"
end

local function path(o: Instance): string
	return (o:GetFullName():gsub("^.-PlayerGui%.", ""))
end

local texts, inputs = {}, {}
-- Every enabled screen gui under PlayerGui: HUD, rail, nav, hints, name cards, overlays.
for _, d in playerGui:GetDescendants() do
	if d:FindFirstAncestorWhichIsA("SurfaceGui") or d:FindFirstAncestorWhichIsA("BillboardGui") then
		continue
	end
	if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.TextTransparency < 1 and shown(d) then
		local size, how = effectiveSize(d)
		table.insert(texts, { size = size, row = string.format("%5.1f px %-24s %q at %dx%d  %s", size, how, d.Text:sub(1, 40), d.AbsoluteSize.X, d.AbsoluteSize.Y, path(d)) })
	end
	if d:IsA("GuiButton") and d.Active and shown(d) then
		local s = d.AbsoluteSize
		table.insert(inputs, { min = math.min(s.X, s.Y), row = string.format("%4dx%-4d %s", s.X, s.Y, path(d)) })
	end
end
table.sort(texts, function(x, y) return x.size < y.size end)
table.sort(inputs, function(x, y) return x.min < y.min end)

local under16, under14, under48 = 0, 0, 0
for _, t in texts do
	if t.size < 16 then under16 += 1 end
	if t.size < 14 then under14 += 1 end
end
for _, i in inputs do
	if i.min < 48 then under48 += 1 end
end

local inset = GuiService:GetGuiInset()
local root = gui:FindFirstChild("Root") :: GuiObject?
local lines = {
	string.format("viewport %dx%d; ScreenGui %dx%d at (%d,%d); ScreenInsets %s; IgnoreGuiInset %s; GuiInset %s",
		viewport.X, viewport.Y, gui.AbsoluteSize.X, gui.AbsoluteSize.Y, gui.AbsolutePosition.X, gui.AbsolutePosition.Y,
		gui.ScreenInsets.Name, tostring(gui.IgnoreGuiInset), tostring(inset)),
	if root then string.format("Root %dx%d at (%d,%d)", root.AbsoluteSize.X, root.AbsoluteSize.Y, root.AbsolutePosition.X, root.AbsolutePosition.Y) else "no Root",
	string.format("texts %d: under 16 px %d, under 14 px %d; input regions %d: under 48 px on a side %d", #texts, under16, under14, #inputs, under48),
	"-- texts, smallest first",
}
for _, t in texts do
	table.insert(lines, t.row)
end
table.insert(lines, "-- input regions, smallest side first")
for _, i in inputs do
	table.insert(lines, i.row)
end
return table.concat(lines, "\n")
