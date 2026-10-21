-- Studio check for the dialogue bubble (A23, Widgets.speechBubble). Paste into the Studio MCP
-- in the Client datamodel during play. It lays the bubble over ivory, teal and the live
-- station (transparent) with the longest filled lines from the dialogue plan (rev 4, worst
-- case "Pepperoni Basil" / "Well done" / "8"), a 60-character line at the plan's limit and a
-- short line, with the tail at the left, middle and right of the straight bottom edge.
-- Returns each bubble's measured size, slice scale, line count and tail point. Remove the
-- "SpeechBubbleTest" screen gui afterwards.

local Players = game:GetService("Players")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Widgets = require(client:WaitForChild("Widgets"))
local Theme = require(client:WaitForChild("Theme"))

local LINES = {
	{ text = "Pepperoni Basil, Well done. I'll take it to the ward.", along = 0.5 },
	{ text = "Pepperoni Basil, Well done, 8 slices. Big night for us all!!", along = 0.15 },
	{ text = "Cheese, please.", along = 0.85 },
}

local old = playerGui:FindFirstChild("SpeechBubbleTest")
if old then
	old:Destroy()
end
local gui = Instance.new("ScreenGui")
gui.Name = "SpeechBubbleTest"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = playerGui
local size = gui.AbsoluteSize
local compact = size.Y < 520
local bubbleW = if compact then 210 else 360
local columns = {
	{ name = "Ivory", colour = Theme.Colour.paper, transparency = 0 },
	{ name = "Teal", colour = Theme.Colour.action, transparency = 0 },
	{ name = "Live", colour = Color3.new(), transparency = 1 },
}
local report = {}
local colW = math.floor(size.X / #columns)
local bubbles = {}
for c, col in columns do
	local panel = Instance.new("Frame")
	panel.Name = col.name
	panel.BackgroundColor3 = col.colour
	panel.BackgroundTransparency = col.transparency
	panel.BorderSizePixel = 0
	panel.Position = UDim2.fromOffset((c - 1) * colW, 0)
	panel.Size = UDim2.fromOffset(colW, size.Y)
	panel.Parent = gui
	for i, line in LINES do
		local b = Widgets.speechBubble(math.min(bubbleW, colW - 16), compact)
		b.frame.Name = "Bubble" .. i
		b.frame.Parent = panel
		b:set(line.text, line.along)
		table.insert(bubbles, { b = b, panel = panel, i = i, col = col.name })
	end
end
task.wait(0.5)
local TextService = game:GetService("TextService")
local function lineCount(label: TextLabel): number
	local params = Instance.new("GetTextBoundsParams")
	params.Text = "Ag"
	params.Font = label.FontFace
	params.Size = label.TextSize
	local one = TextService:GetTextBoundsAsync(params)
	return math.round(label.TextBounds.Y / one.Y)
end
local y = {}
for _, e in bubbles do
	local f = e.b.frame
	local top = y[e.col] or 8
	f.Position = UDim2.fromOffset(math.floor((colW - f.AbsoluteSize.X) / 2), top)
	y[e.col] = top + f.AbsoluteSize.Y + (if compact then 10 else 24)
	local body = f:FindFirstChild("Body") :: ImageLabel
	local tail = f:FindFirstChild("Tail") :: ImageLabel
	local label = body:FindFirstChildOfClass("TextLabel") :: TextLabel
	local tip = e.b:tip()
	table.insert(report, string.format(
		"%s #%d body %dx%d scale %.4f text %dx%d (~%d lines at %d px) tail %dx%d at (%.1f, %.1f) tip (%.1f, %.1f) frame %dx%d",
		e.col, e.i, body.AbsoluteSize.X, body.AbsoluteSize.Y, body.SliceScale, label.TextBounds.X, label.TextBounds.Y,
		lineCount(label), label.TextSize, tail.AbsoluteSize.X, tail.AbsoluteSize.Y, tail.Position.X.Offset, tail.Position.Y.Offset,
		tip.X, tip.Y, f.AbsoluteSize.X, f.AbsoluteSize.Y
	))
end
return string.format("viewport %dx%d compact %s bubble max %d\n", size.X, size.Y, tostring(compact), bubbleW) .. table.concat(report, "\n")
