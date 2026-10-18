--!strict
-- Uploaded image ids for runtime art. An empty id means "not uploaded yet"; src/shared/Art.luau
-- then shows the Studio-only copy if one exists, or nothing. Code never draws a stand-in.
-- Sources: art/manifest.json (generated art and Astra's UI proofs).

local Assets = {
	-- Topping station: gameplay and environment art (Claude, Higgsfield).
	counter_topping_1 = "",
	counter_topping_2 = "",
	counter_topping_3 = "",
	counter_topping_4 = "",
	board_round = "",
	pizza_raw = "",
	tray_pepperoni = "",
	tray_mushroom = "",
	tray_basil = "",
	tray_olive = "",
	tray_pepper = "",
	topping_pepperoni_1 = "",
	topping_pepperoni_2 = "",
	topping_pepperoni_3 = "",
	topping_mushroom_1 = "",
	topping_mushroom_2 = "",
	topping_mushroom_3 = "",
	topping_basil_1 = "",
	topping_basil_2 = "",
	topping_basil_3 = "",
	topping_olive_1 = "",
	topping_olive_2 = "",
	topping_olive_3 = "",
	topping_pepper_1 = "",
	topping_pepper_2 = "",
	topping_pepper_3 = "",
	-- Interface proofs (Astra, UI Proof V1).
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
	-- Full-screen backgrounds: virtual size and how they are tiled (each tile <= 1024 px).
	backgrounds = {
		counter_topping = { width = 1920, height = 1080, cols = 2, rows = 2 },
	},
	-- Sprite sizes for art whose proportions drive layout.
	trayAspect = 384 / 313,
	-- The board is drawn this much wider than the pizza that sits on it.
	boardOverPizza = 1 / 0.9,
}

function Assets.get(name: string): string?
	local id = (Assets :: any)[name]
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

return Assets
