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
	topping_pepper_red_1 = "",
	topping_pepper_red_2 = "",
	topping_pepper_red_3 = "",
	tray_pepper_mixed = "",
	-- Bake and Cut stations: gameplay art (Claude, Higgsfield; visual-pass G6, G8, G9).
	pizza_bake_light = "",
	pizza_bake_regular = "",
	pizza_bake_well = "",
	pizza_bake_burnt = "",
	board_cut = "",
	prop_oven = "",
	prop_oven_needle = "",
	prop_cutter_wheel = "",
	prop_cutter_handle = "",
	fx_oven_glow = "",
	fx_cut_groove = "",
	fx_cut_groove_b = "",
	fx_oven_glass = "",
	chr_marta_happy = "",
	chr_marta_neutral = "",
	chr_marta_impatient = "",
	chr_marta_grumpy = "",
	chr_bo_happy = "",
	chr_bo_neutral = "",
	chr_bo_impatient = "",
	chr_bo_grumpy = "",
	chr_ines_happy = "",
	chr_ines_neutral = "",
	chr_ines_impatient = "",
	chr_ines_grumpy = "",
	-- Interface (Astra, UI V2 complete pack, 2026-10-19).
	fx_select_ring = "",
	icon_bake_extra_well = "",
	icon_bake_light = "",
	icon_bake_regular = "",
	icon_bake_well_done = "",
	icon_coin = "",
	icon_day = "",
	icon_nav_bake_idle = "",
	icon_nav_bake_selected = "",
	icon_nav_cut_idle = "",
	icon_nav_cut_selected = "",
	icon_nav_order_idle = "",
	icon_nav_order_selected = "",
	icon_nav_topping_idle = "",
	icon_nav_topping_selected = "",
	icon_oven_white = "",
	icon_slices_4 = "",
	icon_slices_6 = "",
	icon_slices_8 = "",
	icon_undo = "",
	ui_badge_alert = "",
	ui_badge_info = "",
	ui_button_secondary_disabled = "",
	ui_button_secondary_idle = "",
	ui_button_secondary_pressed = "",
	ui_card_result = "",
	ui_hud_bar = "",
	ui_nav_bar = "",
	ui_nav_divider = "",
	ui_nav_tab_selected = "",
	ui_oven_badge_burnt = "",
	ui_oven_badge_cooking = "",
	ui_oven_badge_idle = "",
	ui_oven_badge_ready = "",
	ui_oven_pill = "",
	ui_panel_summary = "",
	ui_patience_fill_amber = "",
	ui_patience_fill_green = "",
	ui_patience_fill_red = "",
	ui_patience_track = "",
	ui_rail_panel = "",
	ui_ring_fill_burnt = "",
	ui_ring_fill_cooking = "",
	ui_ring_fill_ready = "",
	ui_scrim = "",
	ui_ticket_clip_rail = "",
	ui_ticket_divider = "",
	ui_ticket_tab_idle = "",
	ui_ticket_tab_selected = "",
	ui_timer_fill = "",
	ui_timer_track = "",
	ui_tutorial_hand = "",
	ui_tutorial_target_halo = "",
	-- Interface (Astra, UI V2 integration proof 01).
	ui_button_primary_idle = "",
	ui_button_primary_pressed = "",
	ui_button_primary_disabled = "",
	ui_button_primary_highlighted = "",
	ui_hud_pill = "",
	ui_ticket_top = "",
	ui_ticket_mid = "",
	ui_ticket_bottom = "",
	-- Interface proofs (Astra, UI Proof V1), still used where V2 art is pending.
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
	-- V2 primary button (896x240) and HUD pill (640x152): slice centres from Astra's manifest;
	-- SliceScale is the rendered height over the source height.
	buttonPrimary = { slice = Rect.new(128, 112, 768, 128), height = 240 },
	hudPill = { slice = Rect.new(88, 70, 552, 82), height = 152, inset = 96 },
	-- V2 ticket: three pieces cut from one 840 px wide master; caps 96 px tall, only the
	-- middle stretches.
	ticket = { width = 840, cap = 96 },
	-- UI V2 complete pack: slice centres in delivered pixels (right/bottom exclusive in the
	-- manifest, so Rect.new takes them as is) and the source height SliceScale divides by.
	buttonSecondary = { slice = Rect.new(88, 72, 424, 88), height = 160 },
	navBar = { slice = Rect.new(72, 70, 952, 74), height = 144 },
	navSelected = { slice = Rect.new(72, 70, 440, 74), height = 144 },
	railTab = { slice = Rect.new(40, 40, 472, 104), height = 144 },
	railPanel = { slice = Rect.new(32, 32, 416, 736), width = 448 },
	hudBar = { slice = Rect.new(32, 32, 992, 96), height = 128 },
	ovenPill = { slice = Rect.new(100, 94, 700, 106), height = 200, inset = 112 },
	-- Patience track and fills share one 512x64 canvas; the fill shows inside x 14-498.
	meter = { slice = Rect.new(40, 28, 472, 36), height = 64, width = 512, fillLeft = 14, fillRight = 498 },
	panel = { slice = Rect.new(40, 40, 800, 560) },
	clipRail = { aspect = 768 / 96 },
	-- Oven badge (128 canvas, body 6-122) and ring fills (256 canvas, body 8-248).
	ovenBadge = { body = 116 / 128 },
	ringFill = { body = 240 / 256 },
	-- Tutorial glove: fingertip in its 256 px canvas.
	tutorialHand = { tip = Vector2.new(0.44336, 0.05078) },
	-- V1 button (secondary actions until V2 secondary art arrives): 640x207 export.
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
	-- Hollow badge sockets baked into the V1 tab bar (centres as fractions of the bar, outer
	-- ring diameter as a fraction of its height), measured from the 1024x130 export.
	tabBarSockets = { x = { 235 / 1024, 480 / 1024, 725 / 1024, 975 / 1024 }, y = 37 / 130, d = 45 / 130 },
	-- Full-screen backgrounds: virtual size and how they are tiled (each tile <= 1024 px).
	backgrounds = {
		counter_topping = { width = 1920, height = 1080, cols = 2, rows = 2 },
	},
	-- Sprite sizes for art whose proportions drive layout.
	trayAspect = 384 / 313,
	-- The board is drawn this much wider than the pizza that sits on it.
	boardOverPizza = 1 / 0.9,
	-- Oven unit (trimmed 1727x1938): the window, gauge dial centre and radius, number
	-- medallion and the empty lower panel as fractions of the oven image.
	oven = {
		aspect = 1727 / 1938,
		window = { x = 0.035, y = 0.237, w = 0.922, h = 0.512 },
		dial = { x = 0.5, y = 0.122, r = 0.117 },
		plate = { x = 0.5, y = 0.205, w = 0.27, h = 0.05 },
		medallion = { x = 0.2, y = 0.136, d = 0.12 },
		panel = { x = 0.05, y = 0.8, w = 0.9, h = 0.17 },
	},
	needle = { aspect = 263 / 895, hub = 0.873 },
	cutBoard = { aspect = 2227 / 1476 },
	cutterHandle = { aspect = 414 / 1061, axle = 0.097 },
}

function Assets.get(name: string): string?
	local id = (Assets :: any)[name]
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

return Assets
