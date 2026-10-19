# Restaurantaria

A 2D cooking and restaurant-progression game for Roblox, inspired by Papa's Pizzeria's
hands-on multitasking. The first playable is one pizzeria with four stations (Order,
Topping, Bake, Cut) that the player switches between while ovens and customers keep running.

## Layout

Rojo project (`default.project.json`):

| Path | Studio location | What |
|------|-----------------|------|
| `src/shared` | `ReplicatedStorage.Shared` | Config, recipes, pure scoring, remotes, asset ids |
| `src/server` | `ServerScriptService.Server` | Shift state, action validation, saving |
| `src/client` | `StarterPlayerScripts.Client` | Layout, stations, widgets |
| `art/ui` | not synced | UI proof package and runtime-sized PNG exports |
| `tests` | not synced | Checks to run from the Studio command bar |
| `tools` | not synced | Studio helpers |

The server owns all game state. The client sends intents (`seq`, action, args) through
`Remotes.Action`; the server checks the sequence number (replays), a rate limit, argument
types and ranges, and stage legality, then grades and pays out itself.

## Working in Studio without Rojo

`tools/studio_sync.luau` pulls `src/` from a commit into the open place (it switches
`HttpService.HttpEnabled` on for the fetch and restores it). Set `SHA` and run it from the
command bar.

## Test hooks (Studio only)

`ServerStorage.RestaurantariaDebug` (a BindableFunction, created only in Studio):

| Command | Effect |
|---------|--------|
| `state` | Authoritative shift, pizza and profile state as text |
| `skipArrivals`, n | Moves the shift clock n seconds forward |
| `resetPatience` | Refills every unserved customer's patience |
| `setBake`, {slot, s} | Makes the pizza in that oven read as baked for s seconds |
| `playOut` | Finishes the shift with clean pizzas through the real actions |
| `simulateLoadFailure`, bool | Next profile load fails (pair with `reloadProfile`) |
| `reloadProfile` | Reloads the player's profile |

`tests/scoring_check.luau` holds table-driven grading checks; paste it into the command bar
after a sync.

## Order counter (3D, hybrid proof)
The Order station's counter is the only 3D model. It must exist in the place as a MeshPart named `prop3d_order_counter` in `ReplicatedStorage.Models3D`, brought in with Studio's File > Import 3D from `counter_v1.fbx` (or the source GLB), with a `Yaw` attribute of -90 so the cupboard side faces the camera. Without it the Order station falls back to the 2D view.
- Current upload: MeshId `rbxassetid://88229031650519`; SurfaceAppearance ColorMap 111229975630862, NormalMap 130883249966364, RoughnessMap 136996353373536, MetalnessMap 99549641244814. 16,462 tris, 5.68 x 5.51 x 18 studs.
- `src/client/OrderRoom.luau` applies its own Lighting while Order shows (Ambient 150,132,118; OutdoorAmbient 160,145,130; Brightness 1.2; ClockTime 13.5) and restores the previous values afterwards.
