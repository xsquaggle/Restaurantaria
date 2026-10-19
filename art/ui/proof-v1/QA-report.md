# Proof QA — October 18, 2026

Status: **11 image proofs delivered; production integration and Lawson approval remain open.**

## Checks performed

- Visually inspected every generated asset and state. No functional text or numeric progress is baked into the images.
- All 11 files decode as RGBA PNG, have alpha extrema 0–255, and have fully transparent corner pixels.
- The oven ring has a fully transparent center pixel and visible open center.
- All four primary states share a 1774×887 canvas; all four patience states share a 2172×724 canvas.
- Actual dimensions, nontrivial-alpha bounds and checksums were measured. Files are byte-for-byte copies of generated masters.
- Color-token contrast and a sample grid in each generated button label region were checked numerically.

## State registration

Button silhouette bounds differ from idle by at most 2 source pixels per edge: approximately 0.52 reference pixels at a 432px visible width. Patience bounds differ from happy by at most 10 source pixels per edge (grumpy): approximately 1.89 reference pixels at a 320px visible width. These are **bounding-box measurements**, not proof of pixel-identical contours or animation stability. Use shared source windows and fixed label/fill anchors. Normalize or separate the common housing if live state swaps reveal jitter.

## Color checks

| Token pairing | Contrast ratio |
|---|---:|
| ink_on_paper | 11.4:1 |
| muted_on_paper | 5.05:1 |
| white_on_action | 6.2:1 |
| white_on_pressed | 7.87:1 |
| ink_on_disabled | 6.43:1 |

| Generated button central-region sample | White text minimum | Ink text minimum |
|---|---:|---:|
| ui_primary_idle | 6.03:1 | 1.99:1 |
| ui_primary_pressed | 7.28:1 | 1.62:1 |
| ui_primary_disabled | 2.04:1 | 5.83:1 |
| ui_primary_highlighted | 5.85:1 | 2.07:1 |

The exact live theme tokens pass the proposed 4.5:1 normal-text target for their stated pairings. The selected v2 idle/highlighted images, pressed image (white text) and disabled image (ink text) also pass the sampled central-label-region check. Earlier idle/highlighted candidates failed and were replaced by darker generated refinements. Generated pixel colors still do not exactly match the tokens. A finite sampling grid is not a certification of every background pixel.

## Limitations that must remain visible

- The generated images retain soft surface shading; their palette and geometry are not exact production specifications.
- No Roblox upload, Studio layout, nine-slice test, gameplay test, phone playtest, or device-memory profile was performed here.
- The bar has four blank badge sockets; it still needs independent controls and live selected/focus states.
- Ring and patience progress are empty art shells. Live fills, arcs, labels, sound and interactions are not implemented in this package.
- The ticket bottom notches, fixed dividers, circular ring and composite patience housing should not be blindly nine-sliced.
- Full masters represent approximately 66.0 MiB as one uncompressed RGBA copy, excluding engine overhead/mipmaps. This is a size estimate, not measured Roblox runtime memory. Prepare smaller runtime exports and shared components before shipping.

## Integration acceptance still required

1. Inspect artwork on light/dark scene backgrounds and check edges after upload/downsampling.
2. Verify fixed hitboxes, label anchors, source regions, slice settings and state changes in Studio.
3. Test the composition on desktop and small landscape phones with safe insets; read every label and manipulate food with fingers.
4. Place the UI with the actual customer, ingredient and station art before approving the style.
5. Validate the four-station game independently: order identity, timestamp authority, forged/replayed requests, transitions and save/rejoin behavior.

## Provenance

Generation: built-in image_gen, transparency requested on every call. Exact prompts are in Generation-prompts.json. The initial glossy button was refined; only the selected refined master and its states are included. Originals remain in the image-generation output location. No paid Higgsfield generation, live Studio mutation or publishing was performed.
