--!strict
-- Uploaded image ids for runtime art. An empty id means "not uploaded yet": the client draws a
-- styled stand-in using the same layout, so art can be dropped in without layout changes.
-- Source files: art/ui/runtime/*.png (exported from art/ui/proof-v1).

local Assets = {
	ui_orderTicket_blank = "",
	ui_tabBar_idle = "",
	ui_ovenRing_idle = "",
	ui_primary_idle = "",
	ui_primary_pressed = "",
	ui_primary_disabled = "",
	ui_primary_highlighted = "",
	ui_patience_happy = "",
	ui_patience_neutral = "",
	ui_patience_impatient = "",
	ui_patience_grumpy = "",
}

-- Layout metadata measured from the runtime exports (fractions of the exported image).
Assets.Meta = {
	-- Primary button: 640x207 export, candidate nine-slice margins scaled from the proof manifest.
	primarySlice = Rect.new(73, 61, 566, 149),
	primaryAspect = 640 / 207,
	-- Patience: live fill safe region inside the 768x216 export.
	patienceFill = { x = 0.290, y = 0.385, w = 0.628, h = 0.283 },
	patienceAspect = 768 / 216,
	-- Oven ring: band centre radius and band width as fractions of the image size.
	ringBandRadius = 0.433,
	ringBandWidth = 0.092,
	ticketAspect = 344 / 512,
	tabBarAspect = 1024 / 130,
}

function Assets.get(name: string): string?
	local id = (Assets :: any)[name]
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

return Assets
