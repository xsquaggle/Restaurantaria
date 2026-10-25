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

`ServerStorage.RestaurantariaDebug` (a BindableFunction, created only in Studio). Call it as
`Invoke(command, value, userId?)`; without a userId it acts on the first player. Everything is
decided by that player's own loaded store. Test mutators (`skipArrivals`, `resetPatience`,
`setBake`, `age`, `stage`, `act`, `playOut`, `forceTip`) are refused while the player is still
on the real save: run `fakeStore` first.

| Command | Effect |
|---------|--------|
| `state` | Authoritative shift, pizza and profile state as text |
| `skipArrivals`, n | Moves the shift clock n seconds forward |
| `resetPatience` | Refills every unserved customer's patience |
| `setBake`, {slot, s} | Makes the pizza in that oven read as baked for s seconds |
| `playOut` | Finishes the shift with clean pizzas through the real actions |
| `simulateLoadFailure`, bool | Next profile load fails (pair with `reloadProfile`) |
| `reloadProfile` | Reloads the player's profile from the store it is already on |
| `forceTip`, n or nil | Every order this player serves earns n coins (test store only) |
| `fakeStore`, {failNext, loseAckNext, delay, fresh} | For a player on the real save: a new in-memory store is selected first (later joins load from it too), the profile reloads from it and a new shift starts; refused while that player's real save is still pending or waiting for a retry. For a player already on a fake store it only changes that store's faults (`fresh = true` starts a new empty one). Other players are not touched. One way: the real store comes back only with a new play session |

`tests/scoring_check.luau` holds table-driven grading checks; paste it into the command bar
after a sync.

### Offline checks (mock)

`python3 -I tests/offline/run.py` runs the save and summary checks without Studio, using the
[Luau CLI](https://github.com/luau-lang/luau/releases) (on PATH or named by `$LUAU`) and a
mock of the few Roblox APIs they use, on a virtual clock. Mock evidence only: it says nothing
about the real DataStore, a real rejoin or overlapping servers.

## Order counter (3D, hybrid proof)
The Order station's counter is the only 3D model. It must exist in the place as a MeshPart named `prop3d_order_counter` in `ReplicatedStorage.Models3D`, brought in with Studio's File > Import 3D from `counter_v1.fbx` (or the source GLB), with a `Yaw` attribute of -90 so the cupboard side faces the camera. Without it the Order station falls back to the 2D view.
- Current upload: MeshId `rbxassetid://88229031650519`; SurfaceAppearance ColorMap 111229975630862, NormalMap 130883249966364, RoughnessMap 136996353373536, MetalnessMap 99549641244814. 16,462 tris, 5.68 x 5.51 x 18 studs.
- `src/client/OrderRoom.luau` applies its own Lighting while Order shows (Ambient 150,132,118; OutdoorAmbient 160,145,130; Brightness 1.2; ClockTime 13.5) and restores the previous values afterwards.
