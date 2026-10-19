-- Studio-only check sheet for supplied UI components, run in the Client datamodel during a
-- playtest (Studio MCP execute_luau). It shows the real widgets at the sizes Astra names,
-- each on dark teal (left half) and on ivory (right half), so edges, caps, slicing and
-- label placement can be judged at native scale. The two backgrounds are test backdrops
-- only; nothing here ships. Set SHEET to "controls", "tickets" or "tall", or "off" to remove.

local SHEET = "controls"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = Players.LocalPlayer.PlayerScripts:WaitForChild("Client")
local Widgets = require(Client.Widgets)
local Ui = require(Client.Ui)
local Theme = require(Client.Theme)
local Art = require(ReplicatedStorage.Shared.Art)
local Assets = require(ReplicatedStorage.Shared.Assets)

local pg = Players.LocalPlayer.PlayerGui
local old = pg:FindFirstChild("ComponentSheet")
if old then
	old:Destroy()
end
if SHEET == "off" then
	return "removed"
end

local TEAL, IVORY = Color3.fromHex("#1D6B70"), Color3.fromHex("#FFF8E8")
local gui = Ui.new("ScreenGui", {
	Name = "ComponentSheet",
	IgnoreGuiInset = true,
	DisplayOrder = 100,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = pg,
})
local W = gui.AbsoluteSize.X
local half = math.floor(W / 2)
for i, colour in { TEAL, IVORY } do
	Ui.new("Frame", {
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset((i - 1) * half, 0),
		Size = UDim2.new(0, if i == 1 then half else W - half, 1, 0),
		Parent = gui,
	})
end

local report = {}
local function place(inst: GuiObject, x: number, y: number, caption: string, dark: boolean)
	inst.AnchorPoint = Vector2.zero
	inst.Position = UDim2.fromOffset(x, y)
	inst.Parent = gui
	Ui.text({
		Text = caption,
		TextSize = 14,
		TextColor3 = if dark then IVORY else Theme.Colour.ink,
		TextWrapped = false,
		Position = UDim2.fromOffset(x, y - 18),
		Size = UDim2.fromOffset(300, 16),
		Parent = gui,
	})
	task.defer(function()
		table.insert(report, string.format("%s at %d,%d size %dx%d", caption, inst.AbsolutePosition.X, inst.AbsolutePosition.Y, inst.AbsoluteSize.X, inst.AbsoluteSize.Y))
	end)
end

local function button(state: string, w: number, h: number): Frame
	local b = Widgets.button("Send to oven", function() end)
	b.frame.Size = UDim2.fromOffset(w, h)
	if state == "disabled" then
		b:setEnabled(false)
	elseif state == "highlighted" then
		b:setHighlighted(true)
	elseif state == "pressed" then
		-- Pressed art at full scale, so its outline can be compared with the others; in play
		-- the shared body also eases to 96 %.
		Art.apply(b.frame:FindFirstChild("Body"):FindFirstChild("Art") :: ImageLabel, "ui_button_primary_pressed")
	end
	return b.frame
end

-- Same construction as the HUD pill in Main.client.luau.
local function pill(text: string, compact: boolean): ImageLabel
	local h = if compact then 36 else 44
	local scale = h / Assets.Meta.hudPill.height
	local holder = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Assets.Meta.hudPill.slice,
		SliceScale = scale,
		Size = UDim2.fromOffset(if compact then 120 else 240, h),
	})
	Art.apply(holder, "ui_hud_pill")
	Ui.text({
		Text = text,
		FontFace = Theme.Font.display,
		TextSize = if compact then 16 else 22,
		TextColor3 = Theme.Colour.labelStroke,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	return holder
end

local function ticket(w: number, h: number): Frame
	local t = Widgets.railTicket(Vector2.new(w, h), w < 200)
	t:set({ id = 2, cast = 2, order = { recipe = "garden", bake = "light", slices = 6 } })
	t:setPatience(0.8, "happy")
	return t.frame
end

for side = 0, 1 do
	local x0, dark = side * half, side == 0
	local bg = if dark then "teal" else "ivory"
	if SHEET == "controls" then
		for i, state in { "idle", "pressed", "disabled", "highlighted" } do
			place(button(state, 420, 110), x0 + 40, 90 + (i - 1) * 132, string.format("%s 420x110 on %s", state, bg), dark)
			place(button(state, 168, 48), x0 + 500, 90 + (i - 1) * 72, string.format("%s 168x48", state), dark)
		end
		place(pill("Day 12", false), x0 + 40, 640, "pill 240x44", dark)
		place(pill("120 coins", false), x0 + 300, 640, "pill 240x44", dark)
		place(pill("Day 12", true), x0 + 40, 720, "pill 120x36", dark)
		place(pill("120 coins", true), x0 + 180, 720, "pill 120x36", dark)
	elseif SHEET == "tickets" then
		place(ticket(420, 460), x0 + 40, 90, "ticket 420x460 on " .. bg, dark)
		place(ticket(168, 174), x0 + 500, 90, "ticket 168x174", dark)
		place(ticket(168, 220), x0 + 500, 300, "ticket 168x220", dark)
	elseif SHEET == "tall" then
		place(ticket(420, 580), x0 + 40, 90, "ticket 420x580 on " .. bg, dark)
	end
end
task.wait(0.2)
table.sort(report)
return string.format("sheet %s, screen %dx%d\n", SHEET, gui.AbsoluteSize.X, gui.AbsoluteSize.Y) .. table.concat(report, "\n")
