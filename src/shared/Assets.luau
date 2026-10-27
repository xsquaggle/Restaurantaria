--!strict
-- Uploaded image ids for runtime art. An empty id means "not uploaded yet"; src/shared/Art.luau
-- then shows the Studio-only copy if one exists, or nothing. Code never draws a stand-in.
-- Sources: art/manifest.json (generated art and Astra's UI proofs).

local Assets = {
	-- Topping station: gameplay and environment art (Claude, Higgsfield). The counter_topping
	-- tiles are the earlier preparation background, kept for comparison; bg_topping_clean_v2
	-- (below) replaced them (QA-005).
	counter_topping_1 = "rbxassetid://105850371985802",
	counter_topping_2 = "rbxassetid://130737619585739",
	counter_topping_3 = "rbxassetid://110291528763744",
	counter_topping_4 = "rbxassetid://102567501331121",
	bg_order_1 = "rbxassetid://116441805154909",
	bg_order_2 = "rbxassetid://122235780643550",
	bg_order_3 = "rbxassetid://87431958474283",
	bg_order_4 = "rbxassetid://121403115830833",
	bg_bake_1 = "rbxassetid://82545400701497",
	bg_bake_2 = "rbxassetid://102516831793624",
	bg_bake_3 = "rbxassetid://86658731448716",
	bg_bake_4 = "rbxassetid://82970868106959",
	bg_cut_1 = "rbxassetid://96941810897970",
	bg_cut_2 = "rbxassetid://112265532593094",
	bg_cut_3 = "rbxassetid://73842185036961",
	bg_cut_4 = "rbxassetid://120629532085322",
	prop_order_counter = "rbxassetid://138765202295007",
	board_round = "rbxassetid://124267780319901",
	pizza_raw = "rbxassetid://77621266809939",
	tray_pepperoni = "rbxassetid://117405149652956",
	tray_mushroom = "rbxassetid://105885809091140",
	tray_basil = "rbxassetid://108230873916778",
	tray_olive = "rbxassetid://129039618092298",
	tray_pepper = "rbxassetid://122487317800730",
	topping_pepperoni_1 = "rbxassetid://137351333814618",
	topping_pepperoni_2 = "rbxassetid://101499603272931",
	topping_pepperoni_3 = "rbxassetid://125375904797645",
	topping_mushroom_1 = "rbxassetid://85329037619802",
	topping_mushroom_2 = "rbxassetid://91019578771625",
	topping_mushroom_3 = "rbxassetid://104921629646727",
	topping_basil_1 = "rbxassetid://104132444003148",
	topping_basil_2 = "rbxassetid://132430438255092",
	topping_basil_3 = "rbxassetid://84273788064077",
	topping_olive_1 = "rbxassetid://118241233698348",
	topping_olive_2 = "rbxassetid://105507791446697",
	topping_olive_3 = "rbxassetid://90446214172955",
	topping_pepper_1 = "rbxassetid://92032777538620",
	topping_pepper_2 = "rbxassetid://121691973675764",
	topping_pepper_3 = "rbxassetid://127306191661308",
	topping_pepper_red_1 = "rbxassetid://137858382773556",
	topping_pepper_red_2 = "rbxassetid://131442470200973",
	topping_pepper_red_3 = "rbxassetid://83317701894143",
	-- Baked look of each raw drawing above, piece for piece (G7 v2).
	topping_pepperoni_1_baked = "rbxassetid://70894347040218",
	topping_pepperoni_2_baked = "rbxassetid://73689333787459",
	topping_pepperoni_3_baked = "rbxassetid://103261257161162",
	topping_mushroom_1_baked = "rbxassetid://73256190090318",
	topping_mushroom_2_baked = "rbxassetid://80337212091581",
	topping_mushroom_3_baked = "rbxassetid://136382825546581",
	topping_basil_1_baked = "rbxassetid://125875406526625",
	topping_basil_2_baked = "rbxassetid://87185476775572",
	topping_basil_3_baked = "rbxassetid://78674678524003",
	topping_olive_1_baked = "rbxassetid://110428426890561",
	topping_olive_2_baked = "rbxassetid://119479109008121",
	topping_olive_3_baked = "rbxassetid://123290751363838",
	topping_pepper_1_baked = "rbxassetid://76529637914750",
	topping_pepper_2_baked = "rbxassetid://101560703089393",
	topping_pepper_3_baked = "rbxassetid://98066649170226",
	topping_pepper_red_1_baked = "rbxassetid://138255611280669",
	topping_pepper_red_2_baked = "rbxassetid://96955490508772",
	topping_pepper_red_3_baked = "rbxassetid://135477474010550",
	tray_pepper_mixed = "rbxassetid://99222038556437",
	-- Bake and Cut stations: gameplay art (Claude, Higgsfield; visual-pass G6, G8, G9).
	pizza_bake_light = "rbxassetid://130032931357725",
	pizza_bake_regular = "rbxassetid://113300339318595",
	pizza_bake_well = "rbxassetid://129223295945025",
	pizza_bake_burnt = "rbxassetid://99624513174352",
	board_cut = "rbxassetid://110022152558585",
	prop_oven = "rbxassetid://124148390317976",
	prop_oven_needle = "rbxassetid://102643169053798",
	prop_cutter_wheel = "rbxassetid://129647007261424",
	prop_cutter_handle = "rbxassetid://139244006561835",
	fx_oven_glow = "rbxassetid://117084060181969",
	fx_cut_groove = "rbxassetid://121852099381236",
	fx_cut_groove_b = "rbxassetid://132328692773389",
	fx_cut_groove_c = "rbxassetid://88577604876364",
	fx_oven_glass = "rbxassetid://90898132202673",
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
	fx_select_ring = "rbxassetid://118144973507287",
	icon_bake_extra_well = "rbxassetid://109068803535429",
	icon_bake_light = "rbxassetid://73209880948536",
	icon_bake_regular = "rbxassetid://121680315477451",
	icon_bake_well_done = "rbxassetid://97645537878707",
	icon_coin = "rbxassetid://100817279504730",
	icon_day = "rbxassetid://84448955004136",
	icon_nav_bake_idle = "rbxassetid://113262099913582",
	icon_nav_bake_selected = "rbxassetid://114640656046068",
	icon_nav_cut_idle = "rbxassetid://88191481883731",
	icon_nav_cut_selected = "rbxassetid://123059077852515",
	icon_nav_order_idle = "rbxassetid://87613164021732",
	icon_nav_order_selected = "rbxassetid://104587797480629",
	-- Dough subject (Astra response 6) in place of the tomato.
	icon_nav_topping_idle = "rbxassetid://87487309691466",
	icon_nav_topping_selected = "rbxassetid://112384285693498",
	icon_oven_white = "rbxassetid://81918378805088",
	icon_slices_4 = "rbxassetid://90427064086595",
	icon_slices_6 = "rbxassetid://137097938639592",
	icon_slices_8 = "rbxassetid://111393636185257",
	icon_undo = "rbxassetid://78261471309314",
	ui_badge_alert = "rbxassetid://72328643440159",
	ui_badge_info = "rbxassetid://125176631276872",
	ui_button_secondary_disabled = "rbxassetid://105327834078706",
	ui_button_secondary_idle = "rbxassetid://137808224917951",
	ui_button_secondary_pressed = "rbxassetid://123154939620952",
	ui_card_result = "rbxassetid://119342059119853",
	ui_hud_bar = "rbxassetid://83988221440047",
	ui_nav_bar = "rbxassetid://82052741437024",
	ui_nav_divider = "rbxassetid://112394230744192",
	ui_nav_tab_selected = "rbxassetid://131297783221634",
	ui_oven_badge_burnt = "rbxassetid://92404839408634",
	ui_oven_badge_cooking = "rbxassetid://136105238417686",
	ui_oven_badge_idle = "rbxassetid://137748826195686",
	ui_oven_badge_ready = "rbxassetid://85761367519533",
	ui_oven_pill = "rbxassetid://106749683303455",
	ui_panel_summary = "rbxassetid://71530660753865",
	ui_patience_fill_amber = "rbxassetid://117454301163762",
	ui_patience_fill_green = "rbxassetid://106398314775209",
	ui_patience_fill_red = "rbxassetid://70821799007467",
	ui_patience_track = "rbxassetid://87092227192472",
	ui_rail_panel = "rbxassetid://74480611927153",
	ui_ring_fill_burnt = "rbxassetid://93031353879972",
	ui_ring_fill_cooking = "rbxassetid://116438937854594",
	ui_ring_fill_ready = "rbxassetid://75035447328555",
	ui_scrim = "rbxassetid://81442375649859",
	-- Shift summary pieces (Astra, pizzeria-shift-feedback-v1 = astra-response-7), uploaded
	-- 2026-10-27 from byte-exact originals (the signed copies' C2PA chunk removed; sha256 as
	-- in her manifest).
	icon_shift_complete = "rbxassetid://80363246997143",
	icon_xp_star = "rbxassetid://95841601277453",
	ui_xp_track = "rbxassetid://132100199672261",
	ui_xp_fill = "rbxassetid://136312048271102",
	ui_ticket_clip_rail = "rbxassetid://81682398993051",
	ui_ticket_divider = "rbxassetid://77501679237130",
	ui_ticket_tab_idle = "rbxassetid://75739257591420",
	ui_ticket_tab_selected = "rbxassetid://80463041302408",
	ui_timer_fill = "rbxassetid://86980522024378",
	ui_timer_track = "rbxassetid://110311316826751",
	ui_tutorial_hand = "rbxassetid://85949058675409",
	ui_tutorial_target_halo = "rbxassetid://131302856190575",
	-- Interface (Astra, UI V2 integration proof 01).
	ui_button_primary_idle = "rbxassetid://120560215781468",
	ui_button_primary_pressed = "rbxassetid://85109296223960",
	ui_button_primary_disabled = "rbxassetid://100032197525521",
	ui_button_primary_highlighted = "rbxassetid://90052051986078",
	ui_hud_pill = "rbxassetid://71601253006901",
	ui_ticket_top = "rbxassetid://93052828453368",
	ui_ticket_mid = "rbxassetid://135334526342166",
	ui_ticket_bottom = "rbxassetid://134541196617635",
	-- Interface proofs (Astra, UI Proof V1), still used where V2 art is pending.
	ui_orderTicket_blank = "rbxassetid://123450503236796",
	ui_tabBar_idle = "rbxassetid://136048753168015",
	ui_ovenRing_idle = "rbxassetid://95813852347994",
	ui_primary_idle = "rbxassetid://88120177823410",
	ui_primary_pressed = "rbxassetid://75346389083382",
	ui_primary_disabled = "rbxassetid://112864128331424",
	ui_primary_highlighted = "rbxassetid://119412398495780",
	ui_patience_happy = "rbxassetid://102186875157149",
	ui_patience_neutral = "rbxassetid://122474786748509",
	ui_patience_impatient = "rbxassetid://84095838030339",
	ui_patience_grumpy = "rbxassetid://131536348161735",
	-- Interface extension (Astra, response 6, 2026-10-20): Overdone state, standby button, hint
	-- chip, dialogue bubble and tail, pressed glove and arrow, action icons, clean Topping surface.
	ui_oven_badge_overdone = "rbxassetid://85347697967002",
	ui_ring_fill_overdone = "rbxassetid://102194194928020",
	ui_button_primary_standby = "rbxassetid://123279775014466",
	ui_hint_chip = "rbxassetid://118093426619889",
	ui_speech_bubble = "rbxassetid://102241835390356",
	ui_speech_tail = "rbxassetid://109572663907288",
	ui_tutorial_hand_pressed = "rbxassetid://125934640701576",
	ui_tutorial_arrow = "rbxassetid://97501261652583",
	icon_take_order_white = "rbxassetid://111662746013650",
	icon_serve_white = "rbxassetid://76831607027353",
	bg_topping_clean_v2 = "rbxassetid://72607256484344",
	-- Astra r13 (art/astra-r13), uploaded 2026-10-26: Cut worktop and optional Topping props.
	bg_cut_clean_ivory = "rbxassetid://88281494803877",
	deco_basil_pot = "rbxassetid://129133759821938",
	deco_shaker_pair = "rbxassetid://82029622934688",
	deco_gingham_cloth = "rbxassetid://81389727068805",
	-- Astra r13 Prep kit, uploaded 2026-10-26 byte-exact (sha256 = the kit manifest's): the Make
	-- tab's board, flour, dough and rolling pin.
	surface_prep_board = "rbxassetid://104278477689375",
	tool_flour_crock = "rbxassetid://91804425451106",
	tool_flour_scoop = "rbxassetid://86137927326439",
	fx_flour_dust = "rbxassetid://116675054243626",
	fx_flour_clump = "rbxassetid://121074614630671",
	tool_dough_tub = "rbxassetid://83613747162655",
	food_dough_ball = "rbxassetid://107550522847792",
	food_dough_roll_01 = "rbxassetid://123075374455535",
	food_dough_roll_02 = "rbxassetid://104573045440090",
	food_dough_roll_03 = "rbxassetid://86706561631768",
	food_dough_roll_04 = "rbxassetid://128168621384471",
	food_dough_roll_05 = "rbxassetid://94822809031954",
	food_dough_roll_06 = "rbxassetid://74281857814960",
	tool_rolling_pin = "rbxassetid://87000234822762",
	-- The same kit, uploaded 2026-10-27 byte-exact: the Make tab's sauce and cheese steps.
	tool_sauce_pot = "rbxassetid://117862564891343",
	tool_ladle_loaded = "rbxassetid://123643808874441",
	tool_ladle_empty = "rbxassetid://85718758566468",
	food_sauce_raw = "rbxassetid://99141428549445",
	food_sauce_dollop = "rbxassetid://121541372225849",
	tool_cheese_bowl = "rbxassetid://72993269606607",
	food_cheese_raw = "rbxassetid://83704168156179",
	-- The same kit, uploaded 2026-10-27 byte-exact (manifest sha256): the baked states that carry
	-- the player's own pizza through Bake, Cut and the result (P13 bare crusts, P15, P14).
	food_crust_light = "rbxassetid://135966052112911",
	food_crust_regular = "rbxassetid://118516807780052",
	food_crust_well = "rbxassetid://116244074109839",
	food_crust_burnt = "rbxassetid://130620142435420",
	food_sauce_cooked = "rbxassetid://97657862155105",
	food_cheese_melted = "rbxassetid://74313384211353",
	food_cheese_golden = "rbxassetid://118860189516118",
	food_cheese_burnt = "rbxassetid://135522129771732",
	-- Uploaded 2026-10-19 with the rest; no earlier entry.
	topping_basil_baked = "rbxassetid://76051026541638",
	topping_mushroom_baked = "rbxassetid://130710605399267",
	topping_olive_baked = "rbxassetid://87651552393192",
	topping_pepper_baked = "rbxassetid://75899040861071",
	topping_pepperoni_baked = "rbxassetid://93061253255306",
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
	-- The panel's rounded corners run about 53 px in from each edge, past the manifest's 32 px
	-- slice, so the corners are sliced at 64 px: with 32, the curve's tail sat in the stretched
	-- edges and drew as steps on phones (QA-003).
	railPanel = { slice = Rect.new(64, 64, 384, 704), width = 448 },
	hudBar = { slice = Rect.new(32, 32, 992, 96), height = 128 },
	ovenPill = { slice = Rect.new(100, 94, 700, 106), height = 200, inset = 112 },
	-- Patience track and fills share one 512x64 canvas; the fill shows inside x 14-498.
	meter = { slice = Rect.new(40, 28, 472, 36), height = 64, width = 512, fillLeft = 14, fillRight = 498 },
	panel = { slice = Rect.new(40, 40, 800, 560) },
	-- Cream result card (880x400): its corner curves run 48 px in from the sides and 56 px in
	-- from the top and bottom, so the slice margins are 64 px (with 40 the curve's tail sat in
	-- the stretched edges and drew as a step at the lower corners, QA-010a). SliceScale must
	-- stay at or under height / (2 * corner) so both corners fit.
	card = { slice = Rect.new(64, 64, 816, 336), corner = 64 },
	clipRail = { aspect = 768 / 96 },
	-- Order counter front (trimmed 2683x681); its top edge is the first 9% of the image.
	orderCounter = { aspect = 2683 / 681, top = 0.09 },
	-- Oven badge (128 canvas, body 6-122) and ring fills (256 canvas, body 8-248).
	ovenBadge = { body = 116 / 128 },
	ringFill = { body = 240 / 256 },
	-- Tutorial glove: fingertip in its 256 px canvas (the pressed glove shares it), and the
	-- arrow's tip in its own 256 px canvas (it points up).
	tutorialHand = { tip = Vector2.new(0.44336, 0.05078) },
	tutorialArrow = { tip = Vector2.new(0.49609, 0.0625) },
	-- Summary panel (840x600): the manifest's corrected slice, scaled by the smaller axis.
	panelSummary = { slice = Rect.new(80, 80, 760, 520), width = 840, height = 600 },
	-- XP track (1024x128) and fill (1024x104), from Astra's manifest: SliceScale = shown height
	-- over source height; the fill sits in the track's interior (40 px in from each side, 30 px
	-- from top and bottom) and is revealed by clipping, never squeezed.
	xpTrack = { slice = Rect.new(88, 60, 936, 68), height = 128, insetX = 40, insetY = 30 },
	xpFill = { slice = Rect.new(64, 48, 960, 56), height = 104 },
	-- Hint chip (512x128, body 8-504 x 8-120) and the dialogue bubble (512x256, body 8-504 x
	-- 8-248), both scaled by min(width / source width, height / source height). The tail
	-- (128x64) is its own image: it scales with the bubble and overlaps its bottom by 26 px.
	hintChip = { slice = Rect.new(64, 60, 448, 68), width = 512, height = 128 },
	speechBubble = { slice = Rect.new(80, 80, 432, 176), width = 512, height = 256 },
	speechTail = { width = 128, height = 64, overlap = 26 },
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
		-- One image, centred: the surface is plain, so either axis may crop (QA-005).
		bg_topping_clean_v2 = { width = 1024, height = 576, cols = 1, rows = 1, align = Vector2.new(0.5, 0.5) },
		bg_order = { width = 1920, height = 1080, cols = 2, rows = 2 },
		bg_bake = { width = 1920, height = 1080, cols = 2, rows = 2 },
		bg_cut = { width = 1920, height = 1080, cols = 2, rows = 2 },
		-- Astra r13: one plain image, centred, so either axis may crop.
		bg_cut_clean_ivory = { width = 1024, height = 576, cols = 1, rows = 1, align = Vector2.new(0.5, 0.5) },
	},
	-- Sprite sizes for art whose proportions drive layout.
	trayAspect = 384 / 313,
	-- The board is drawn this much wider than the pizza that sits on it.
	boardOverPizza = 1 / 0.9,
	-- Oven unit v2 (trimmed 1608x1865; v1's layout fractions hold within about 0.5%): the window, gauge dial centre and radius, number
	-- medallion and the empty lower panel as fractions of the oven image.
	oven = {
		aspect = 1612 / 1857,
		window = { x = 0.035, y = 0.237, w = 0.922, h = 0.512 },
		-- Gauge arc centre, measured on v3 (band edges agree within 1 degree at three radii).
		dial = { x = 0.5, y = 0.144, r = 0.117 },
		-- Angles (degrees from straight up) of the v3 arc's band edges: cold start, teal,
		-- green, amber, red, and the needle's stop at the red end.
		gaugeEdges = { -88, -46, -17, 12, 48.5, 88 },
		plate = { x = 0.5, y = 0.205, w = 0.27, h = 0.05 },
		medallion = { x = 0.2, y = 0.136, d = 0.12 },
		panel = { x = 0.05, y = 0.8, w = 0.9, h = 0.17 },
	},
	needle = { aspect = 263 / 895, hub = 0.873 },
	cutBoard = { aspect = 2227 / 1476 },
	cutterHandle = { aspect = 414 / 1061, axle = 0.097 },
}

-- The pack's two aliases (asset-manifest.json): same art under a second name.
Assets.Alias = { icon_bake = "icon_bake_regular", icon_cut = "icon_nav_cut_idle" }

function Assets.get(name: string): string?
	local id = (Assets :: any)[Assets.Alias[name] or name]
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

return Assets
