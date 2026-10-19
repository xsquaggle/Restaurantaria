--!strict
-- Tiny instance builder: Ui.new("Frame", { props }, { children }).

local Theme = require(script.Parent.Theme)

local Ui = {}

function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(radius: number?): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function Ui.round(): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Ui.stroke(colour: Color3?, thickness: number?): UIStroke
	return Ui.new("UIStroke", {
		Color = colour or Theme.Colour.ink,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		FontFace = Theme.Font.body,
		TextColor3 = Theme.Colour.ink,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		defaults[k] = v
	end
	return Ui.new("TextLabel", defaults)
end

function Ui.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIBase") then
			child:Destroy()
		end
	end
end

return Ui
