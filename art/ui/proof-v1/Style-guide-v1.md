# Pizzeria — style guide v1

Date: October 18, 2026. Status: **working direction for review**, not Lawson-approved final art direction. Companion files: `Asset-briefs.md`, `asset-manifest.json`, `QA-report.md`, and the transparent PNGs in `assets/`.

## 1. Direction and scope

An illustrated neighborhood pizzeria: warm paper and painted enamel, readable silhouettes, expressive cut-out characters, and food that remains the visual focus. Cozy surroundings with simultaneous cooking demands; forgiving early tuning. This adopts Claude's proposed direction provisionally. It does not establish player-tested difficulty or final visual approval.

The First Shift build is an **internal integration milestone**: four stations, two oven slots, up to three tickets, five toppings, three customer characters, 4/6/8 cuts, four-part grading, tips, one rank-up and one upgrade. A customer roster is not the same as a shift's customer count; define those separately in tuning. The delivered prototype still requires **12 pizza-related recipes unlocked progressively from cheese pizza**. Additional owned restaurants can wait; appliance-shopping destinations remain a finished-game requirement.

## 2. Palette

These are exact values for live UI and production cleanup. Generated painted pixels are visual approximations; never sample them to define gameplay or theme constants.

| Token | Hex | Rule |
|---|---|---|
| Ink | #482C24 | All outlines and primary text on light surfaces; no pure-black outlines. |
| Paper | #FFF2D7 | Tickets and main neutral panels. |
| Dough | #E7CE9F | Neutral inset surfaces and warm edge shading. |
| Muted ink | #7D6254 | Secondary text on paper only, subject to contrast checks. |
| Tomato | #C6513D | Contextual food/red accents; not the default action-button color. |
| Basil | #5B7D48 | Food and positive-status accents. |
| Oven | #E6A143 | Heat and attention accents, supplemented by icon/text. |
| Action | #1D6B70 | Primary interactive emphasis; darkened after proof contrast checks. |
| Action pressed | #175A60 | Pressed action state. |
| Action edge | #69B6B3 | Small edge highlight; not a text background. |
| Disabled | #C7B79C | Disabled button face with ink text. |
| White text | #FFFFFF | Button text on Action/Action pressed. |

Food can contain natural colors that resemble UI colors. Teal is reserved for intentional interaction emphasis in interface decoration, not prohibited in the depicted world. Clickability also requires a recognizable control shape, label, and state response. Noninteractive timer progress uses context colors, not action teal by default.

Project text-contrast target: at least 4.5:1 for normal functional text. Check the actual background behind the text, including highlights; do not assume a token guarantees contrast over artwork. Numerical token checks are recorded in QA.

## 3. Linework, shapes, shading, materials, lighting

- At the 1920×1080 reference, major silhouette outlines are 6 px; interior details are 3 px. Scale to the visible object, keeping useful details at least 1.5 rendered viewport pixels on the smallest supported layout. Avoid thick outlines consuming small ingredients.
- Rounded rectangles and soft silhouettes dominate. Use a 24 px reference radius on ordinary controls; large cards may use 32 px. Do not round every piece of food into the same shape.
- Use one base tone, one shadow tone, and one restrained upper-left highlight. Avoid heavy airbrush gradients, neon glows, sparkles, and glossy plastic UI. Food alone may use a small additional gloss highlight.
- Paper has low-contrast surface variation only; no distressed marks behind functional text. Enamel uses clean edges. Wood appears mainly in scenery, not behind tiny labels. Metal is simplified and never photorealistic against cartoon food.
- Warm key light comes from upper left. Cast shadows fall lower right. No conflicting rim lights. Top-down food highlights also come from screen upper left.
- Background decorative saturation should generally stay below the food's saturation. Compare in the actual scene; do not make a pale cheese pizza artificially neon to satisfy a numeric rule.

## 4. Characters and animation parts

Use a shared cast template at 2.75 heads tall (allowed deliberate variation 2.5–3). Lock eye line, neck pivot, hand scale, and common facing angle across the starter cast. A per-character parts sheet prevents pose drift but does not itself ensure cast-wide consistency.

Each starter customer needs neutral, happy, pleased/surprised, impatient, grumpy, and disappointed expressions. Brows, eyes and mouth swap independently; test all intended combinations. Provide at least neutral hands, waiting pose, receiving pose and celebratory pose. Keep reactions readable without speech.

Store pivots in metadata, never as visible crosses in deliverable images. Head pivots at the neck; arms at the shoulder; each face part has a fixed face-relative anchor. Parts must retain enough overlap to avoid transparent joint gaps at the tested motion limits. Start with subtle head tilt ±4°, torso bob 2–4 reference pixels and hand motion; larger motions need explicit tests.

## 5. Food scale, perspective, and baking

- Order view: side/front view. Topping and cutting: true top-down, circular pizzas remain circles. Oven: front view. Document camera/blockout references so new station assets match.
- Standard pizza diameter: 600 reference pixels within the preparation area; topping sprites typically 42–64 px, with their actual size relative to the pizza stored in recipe/ingredient data. This is an initial visual target, not a limit on other recipe shapes.
- Position ingredients in normalized pizza-local coordinates. Visual radius, legal placement boundary and scoring region must agree. A sprite's transparent padding is not its edible footprint.
- Crust, sauce, cheese, ingredient instances and cooking overlays are separate layers. Avoid a separate generated composite for every topping combination.
- Show distinct raw, target-cooked and burnt food states. Tint can interpolate, but final quality needs selective crust browning, cheese blistering/gloss and appropriate topping changes. Do not tint green herbs and red sauce uniformly brown.
- Food retains a clear silhouette at phone scale. Cutting lines sit above the pizza, with an unmistakable stroke preview and finger-friendly feedback. Cut scoring and visual lines must share the same geometry.

## 6. Typography and live content

Use two Roblox built-in families: **Fredoka One** for short display headings and occasional emphatic labels; **Source Sans Pro** for tickets, tabs, instructions, timers and numeric values. Use the Font/FontFace interface for new implementation. Family resources: `rbxasset://fonts/families/FredokaOne.json` and `rbxasset://fonts/families/SourceSansPro.json`. Verify rendering in Studio, including localization glyphs.

| Role | Reference size | Mobile floor (rendered viewport px) |
|---|---:|---:|
| Main heading, Fredoka One | 52 | 24 |
| Section title, Fredoka One | 36 | 20 |
| Main button/tab, Source Sans Pro semibold | 32 | 16 |
| Ticket/body, Source Sans Pro | 28 | 16 |
| Secondary metadata, Source Sans Pro | 24 | 14 |
| Critical countdown, Source Sans Pro semibold | 32 | 18 |

These are project targets, not Roblox-mandated accessibility values. Use a responsive layout rather than shrinking every reference font linearly. Allow text expansion; labels must not rely on one exact English word width. Do not bake functional text, numbers, prices, timers, item IDs, grade percentages or badge counts into images. No all-caps paragraphs or decorative outline fonts on tickets.

## 7. Interface hierarchy, spacing, and mobile behavior

Priority: active cooking surface → active ticket and urgent oven state → station navigation → other tickets → nonurgent economy/status. During a shift, shop and progression management should not compete with cooking.

The 1920×1080 landscape canvas is an art/composition reference, not an assumed runtime resolution. Reference spacing uses an 8 px grid: 16 px tight separation, 24 px internal padding, 32 px between controls, 48 px outer gutters. Reference navigation band is approximately 144 px high. Final positions respond to the safe rectangle, not the raw screen edges.

Project mobile targets: interactive hit areas at least 48×48 rendered viewport pixels, at least 8 px clear separation, ordinary text at least 16 px, secondary text at least 14 px. Use larger targets for time-critical controls. Validate physical size and thumb reach on real phones; viewport pixels alone are not proof of usability.

At a small landscape viewport such as 844×390, reserve a 64 px navigation row within safe insets. Show an active-ticket detail view plus compact selectable ticket summaries; keep both oven slot states visible. Do not fit three full desktop ticket cards into the preparation area. At still narrower widths, reduce decorative margins and collapse nonessential status before reducing text or hit-target floors. Initially support landscape cooking explicitly; portrait must have a deliberate rotation prompt or a designed alternative, never a crushed layout.

Use live control regions above the art. The four-tab bar composite is a proof backplate, not four functioning buttons. Provide four independent hit regions, labels, selected-state indicators and badge counts. Render the Send button separately. Selected navigation uses a persistent indicator plus label weight; tutorial/focus highlighting is a different state. Keep oven rings and ticket access available at every station.

Interactive UI should respect Roblox/device safe areas; noninteractive backgrounds may extend underneath. Test Roblox menu areas, phone cutouts and text expansion. No swipe navigation in this iteration because it competes with preparation gestures.

## 8. Buttons and status

All primary-button states share one logical hitbox and label anchor. Idle: teal and raised. Pressed: darker teal, shallower lip, live label displaced at most 2 rendered pixels. Disabled: opaque muted face, ink text, no hover/press action; explain why when useful. Highlighted: visible cream inset edge or live focus outline, not a hover-only effect. Do not animate the hitbox.

Oven progress is live, not baked into the PNG. Display slot identity and done/overcooked state with text/icon as well as hue. Do not confuse a full ring with an exact readiness threshold unless those meanings are intentionally identical.

Patience combines a continuous meter with four expressions and an optional live state label: happy, neutral, impatient, grumpy. Proposed starting bands for a linear display are >70%, >40%, >15%, and ≤15%; keep these configurable and do not equate grumpy automatically with leaving. Early-rank walk-outs remain disabled under the working gameplay recommendation. Expressions and bar length must communicate state without color.

## 9. Animation and timers

Press feedback 80 ms; release 110 ms; station visual transition 140 ms; small status change 160 ms; customer reaction 250–450 ms; unhurried between-shift reward flourish up to 650 ms. These are working targets. Input responds immediately; do not wait for a flourish or tween to complete before accepting legal actions. Reduced motion removes overshoot and repeated pulses.

Station switching does not pause oven/patience clocks. Server state determines legal steps, deadlines, grades and payouts; the client renders a smooth timestamp-based estimate. App backgrounding, disconnects and rejoining require an explicit separate policy. Sending a pizza may show a per-order pending acknowledgement, but must not freeze unrelated stations. Repeated taps and retried requests cannot duplicate orders or rewards.

## 10. Asset files and integration

Use transparent PNG with genuine alpha; no baked checkerboard, text, annotations or pivot crosses. Names follow `ui_<element>_<state>.png` for UI, and `chr_<name>_<part>_<state>`, `ing_<name>_<variant>`, `stn_<station>_<layer>` for other categories. Prefer underscores over concatenation for unambiguous parsing.

Master export dimensions are recorded separately from reference display sizes. The image generator may return a different canvas than requested. The manifest records measured dimensions and alpha bounds; never infer dimensions from a prompt. Retain originals non-destructively.

Button nine-slice margins and SliceCenter are **candidate settings**, not certified in-engine values. Store source-pixel L/T/R/B margins and Rect(L,T,W−R,H−B) separately. Preserve corners and validate actual uploaded image dimensions. The ticket's repeated bottom notches, fixed tab dividers, face medallions and circular oven ring are not freely nine-sliceable. Use uniform aspect-preserving sizing or separate components.

Do not upload every high-resolution master and call it optimized. First select runtime sizes appropriate to observed use, preserve alpha and edge quality, then pack approved small assets into atlases if measurement supports it. Document atlas image, region, source size, trimmed offset and pivot. Allow padding/extrusion to avoid neighboring sprite bleed. Packing is not a guarantee of memory reduction. Generated masters in this package are deliberately unmodified proofs, not final runtime atlases.

## 11. Review gate

Accept a style only after seeing one complete micro-scene: the same customer with several expressions, five ingredients assembled on a pizza, one station and the interface together. Compare generator pipelines at identical displayed sizes and motions. Judge consistency, legibility, transparency, animation suitability and correction effort, not isolated prettiness.

For this proof package: inspect all images, validate alpha and canvas dimensions, and report state alignment. For integration: test light/dark backdrops, scaling, labels, hitboxes, selected states, timer visibility, and multiple phone layouts. For gameplay: finish two pizzas out of order against the right tickets; reject forged/replayed calls; interrupt every station transition; save/rejoin without duplicated rewards. Add real-device profiling before claiming optimization.

## Official implementation references

- [Built-in Font families](https://create.roblox.com/docs/reference/engine/enums/Font) and [Font datatype](https://create.roblox.com/docs/reference/engine/datatypes/Font).
- [Roblox nine-slice design](https://create.roblox.com/docs/ui/9-slice).
- [ImageLabel API](https://create.roblox.com/docs/reference/engine/classes/ImageLabel).
- [Position and size](https://create.roblox.com/docs/ui/position-and-size) and [ScreenGui](https://create.roblox.com/docs/reference/engine/classes/ScreenGui).
- [Workspace server-time API](https://create.roblox.com/docs/reference/engine/classes/Workspace/GetServerTimeNow).
- [Studio device emulation](https://create.roblox.com/docs/tutorials/curriculums/user-interface-design/implement-designs-in-studio).

The art direction, timings, touch targets, palette, thresholds and layout decisions above are project recommendations. The linked documentation supports the platform mechanics, not those design judgments.
