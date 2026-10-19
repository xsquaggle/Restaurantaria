# Interface proof briefs — v1

All 11 PNGs were generated with the built-in image tool and copied without altering their pixel data. Exact master dimensions, alpha bounds, and checksums are in `asset-manifest.json`. The master canvas and the visible artwork rectangle are different. Reference display sizes below describe the **visible artwork**, not its transparent padding.

Status: review-ready visual proofs. Generated colors and geometry are approximate. These are not uploaded Roblox assets, packed runtime atlases, or certified mobile UI. Functional overlays and hit regions must be assembled in Studio.

## Shared requirements

- Genuine RGBA transparency outside each silhouette; no functional text, prices, timers, counts, or progress baked in.
- Artwork uses the palette, warm outlines and upper-left lighting in `Style-guide-v1.md`.
- Center anchors for proof placement. Bind live text/hitboxes to the UI container, not to a per-state alpha bounding box.
- Use one shared source window for each state family; do not automatically trim each state independently, which would cause jitter.
- Start with aspect-preserving placement. Padding can be excluded using a documented source region or normalized during a later production export. Verify the uploaded dimensions before using source-pixel coordinates.
- Any 9-slice settings below are source-pixel candidates for the full delivered master. They require Studio verification, including SliceScale. Never interpret edge margins as the SliceCenter rectangle itself.

## 1. Blank order ticket

File: `ui_orderTicket_blank.png`

Use: live customer/ticket identity, recipe requirements and order state. One neutral paper state; selection and urgency are live overlays.

Master: 1122×1402. Measured visible rectangle: (175,139)–(951,1293), or 776×1154. Reference visible display: **320×476**. Keep approximately 28 reference pixels of text padding inside the side edges, 40 below the red top strip, and 32 above the bottom notches.

Transparency: outside paper is alpha-transparent; central paper is opaque. The red top strip is decoration and contains no text.

9-slice: **not recommended for this composite** because the three repeated bottom notches would stretch unevenly. Use aspect-preserving sizing. For a variable-height production ticket, separate a plain center, header and notched footer instead of distorting this image.

Acceptance: legible live ticket content without overlap; no baked wording; notches stay proportional; selected ticket clearly differs via live indicator; use a compact ticket design on phones rather than shrinking this full card below text minima.

## 2. Four-tab station navigation backplate

File: `ui_tabBar_idle.png`

Use: the Order / Topping / Bake / Cut navigation row. This file contains no labels or icons. Four independent controls and badge counts must be placed above it.

Master: 1983×793. Visible rectangle: (48,275)–(1935,515), 1887×240. Reference visible display: **1120×142**. Approximate source divider x positions: 540, 992, 1444. Badge centers: (482,345), (934,345), (1386,345), (1848,345). Badge socket outer diameter approximately 82 source pixels. These are visual guide positions, not measured interaction boundaries.

Use four equal-width hit regions within the logical row; the painted dividers have slight optical variation. At runtime keep the navigation row at least 64 viewport pixels high and tab hit areas at least 48×48. If the painted dividers visibly conflict with equal live controls, split/rebuild the backplate before final acceptance rather than shrinking targets.

States: neutral image supplied; selected tab, pressed feedback, unavailable state and focus/tutorial outline are live overlays on each control. Badge sockets remain blank when unused.

Transparency: exterior transparent, compartment faces opaque.

9-slice: **none for the composite**, because the dividers and badge circles must not stretch independently. Scale uniformly for this proof. Production can use four separate cells to adapt to wider aspect ratios.

Acceptance: exactly four distinguishable controls; no baked functional text; badges map to the right station; live labels remain readable; navigation does not conflict with food dragging; selected state remains obvious without color.

## 3. Primary action button — four states

Files: `ui_primary_v2_idle.png`, `ui_primary_pressed.png`, `ui_primary_disabled.png`, `ui_primary_v2_highlighted.png`. The v2 files are the selected contrast-refined states; use the manifest rather than assuming every filename is identical apart from its state suffix.

Use: actions such as Send or Start day, with live text chosen by context. One logical button and one label anchor across all states.

Each master: **1774×887**. Shared recommended proof source window: (48,160)–(1728,704), 1680×544. Reference visible button approximately **432×134** within a 440×144 logical container. On phones prioritize a ≥48px rendered hit height over proportional scaling. Keep text within the central 70% of the face and vertically above the lower lip.

State appearance: idle dark teal, pressed deeper teal/shallow lip, disabled opaque warm gray-beige, highlighted dark teal with cream inset focus outline. The highlighted PNG is intentionally distinguishable from idle; no hover is needed. Use live white text for active states and ink text on disabled. Live text backgrounds should use the final Action token #1D6B70 if any later asset revision fails contrast checks.

Transparency: transparent exterior; keep the inactive image opaque rather than fading the whole control.

Candidate 9-slice margins for the **full master**: L=240, T=320, R=240, B=335 source pixels. Candidate SliceCenter: Rect(240,320,1534,552). These include transparent padding and protect the rounded corners and lower lip; they are not target border widths. For the source window above, subtract its origin and recompute margins rather than copying full-master values. For initial placement use a fixed aspect-preserving window; only adopt Slice after visual testing at every target width and height.

Acceptance: label/hitbox do not move between states; no clipped edge or external shadow; centered live label has sufficient contrast; pressed is visually different; disabled truly rejects action; highlight is usable for keyboard/controller focus and tutorials. Source silhouette differences are quantified in QA, so do not call these pixel-identical exports.

## 4. Oven progress-ring shell

File: `ui_ovenRing_idle.png`

Use: the static frame around a live oven timer. Two instances identify the two oven slots. The file is not a complete timed widget by itself.

Master: 1254×1254. Visible rectangle approximately (104,106)–(1150,1147). Reference visible diameter **112px**. Small-screen visible diameter target **48px**, with an independent slot label and a sufficiently large hitbox if tapping opens that oven.

Both outside and center are transparent. No numbers, ticks or percentage are baked in. Maintain a 1:1 display aspect. Center anchor (0.5,0.5); runtime progress should be a mathematically circular overlay so small hand-painted asymmetry does not affect timing.

9-slice: none. Uniform scaling only.

Runtime states: empty, baking, ready, overcooked. Use live arc/fill, slot identity and a non-color cue. Grade cooking on server-owned timestamps; the ring only displays state. An empty slot must not resemble a completed pizza.

Acceptance: transparent hole verified; frame stays circular; live timer is readable on every station; no baked progress; smoothing does not grant extra cooking time or determine rewards.

## 5. Patience meter — four expressions

Files: `ui_patience_happy.png`, `ui_patience_neutral.png`, `ui_patience_impatient.png`, `ui_patience_grumpy.png`.

Use: a readable customer mood with an independently changing patience bar. Each image contains a face and an empty track. It contains **no baked fill percentage**.

Each master: **2172×724**. Shared recommended source window: (216,112)–(1952,600), 1736×488. Reference visible composite approximately **320×86**. Use an approximately 48px face at mobile display when expression recognition matters; do not scale the full widget until the face becomes a tiny emoji.

Safe approximate live fill area in full-source coordinates: x=720–1810, y=300–438; it stays inside the blank track in all states. Keep the live fill below a live label or put the label adjacent; leave rounded padding at the track's right edge. Tune the final clipped fill region in Studio.

States: smile with happy eyes; neutral eyes/flat mouth; mildly lowered brows/frown; strongly furrowed brows/deeper frown. Add a live state label where needed. Maintain the same logical container and source window across states.

Transparency: transparent exterior; cream face and empty track remain opaque. 9-slice: none for the face/track composite. For production, use one shared housing plus separate expression sprites if whole-widget swapping produces noticeable variation. This also avoids duplicating the same long track four times in memory.

Acceptance: four expressions distinguishable at intended phone size; no reliance on color alone; continuous fill tracks actual patience; early-rank grumpy state does not silently imply walk-out; state changes do not shift the live fill or label. Final geometry normalization remains an integration task, with current drift documented in QA.

## Remaining production gates

1. Lawson's visual direction confirmation.
2. Representative in-game composition with a customer, food and one station.
3. Studio upload/scale checks and normalized state registration.
4. Live label, arc, fill and hitbox implementation.
5. Phone usability and texture-memory measurement.

The images satisfy the requested proof categories. Completion of the PNG set is not completion of these production gates.
