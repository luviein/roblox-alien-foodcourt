# Alien Food Court — P0.5

You were abducted. The locals are curious about Earth food. Get to work.

**Still a feel test, not a game.** One station, assembly dishes only — but now in
3D, with customers who walk in and food that physically stacks on the plate.

P0 answered "do the mechanics work." P0.5 asks the harder question: *does it feel
good?* Everything in P1 onward waits on that answer.

**What's new since P0**

- A 3D stall: counter, plate, neon signage, fixed camera locked to the composition
- Procedurally generated alien customers — body, eyes, antennae, all randomised
  per customer from primitives. No rigs, no meshes, no animation assets.
- Customers walk in from stage right, take a queue slot, and shuffle forward as
  slots free up. Served ones leave happy; walk-outs storm off the other way.
- Their **ticket floats above their head**, so the order arrives with the person
- Patience is now written on the customer: they redden, squint and fidget faster
  as the timer drains
- Ingredients drop onto the plate and **squash on landing** — that impact is most
  of what makes a keypress feel like it did something
- Serving flings the plate at the customer; a wrong order gets swept on the floor
- Camera shake on a Perfect serve and on fumbles (never on failure — don't reward
  a mistake with spectacle)

---

## Running it

Rojo is already installed (`C:\Users\Yenleng\bin\rojo.exe`, on your PATH) and the
Studio plugin is in place.

**1. Start the sync server** — from this folder:

```
rojo serve
```

Leave it running. It watches the files and pushes changes as you save.

**2. In Roblox Studio:** open a new **Baseplate** place, then
**Plugins → Rojo → Connect** (default address `localhost:34872`).

You should see `Shared`, `Server`, and `Client` folders appear in the Explorer.

**3. Press Play.**

To rebuild from scratch instead of live-syncing: `rojo build --output game.rbxlx`
then open that file in Studio.

---

## Controls

| Key | Action |
|---|---|
| `1` `2` `3` `4` | select a customer (switching abandons the current plate) |
| `Q W E R T` / `A S D F G` | add an ingredient |
| `SPACE` | serve the plate |
| `X` | scrap the plate |
| `E` | start shift / continue (only outside service) |

Every key has an on-screen button that fires the same code path, so touch works
already. Ingredient keys are relabelled per selected dish.

**Key convention across all dishes**, so muscle memory carries over:
`Q` = base · `A` = protein · `S D F` = toppings · `W` = lid

Build tickets **in the order listed, top to bottom**. The next ingredient's key
badge is highlighted blue; completed ones go green.

---

## What to tune

Everything worth fiddling with is in `src/Shared/Config.luau`. Save the file and
Rojo pushes it live — no restart needed.

| Knob | Try this |
|---|---|
| `WRONG_KEY_MODE` | **The big one.** `"reject"` refuses a wrong key with a short lockout (forgiving). `"corrupt"` puts it on the plate and forces you to `SCRAP` — the real Cook Serve Delicious punish. Play both. They are different games. |
| `ORDER_PATIENCE` | 22s default. Drop to 15 and see if it turns panicky or just unfair. |
| `SPAWN_INTERVAL` / `MAX_ACTIVE_ORDERS` | the difficulty curve — `{progress, value}` pairs across the shift |
| `SHIFT_DURATION` | 180s. Shorter is punchier; the plan assumed 3–5 min. |
| `COMBO_STEP` / `COMBO_MAX` | how much holding a streak is worth |
| `FUMBLE_LOCKOUT` | 0.45s. This one strongly changes how bad a mistake feels. |

Dish timings (`perfect` / `good` / `sloppy` thresholds) live per-dish in
`src/Shared/DishDefs.luau`.

---

## What to watch for while playing

The plan's whole economy rests on one assumption: **a sloppy run and a clean run
should differ by roughly 10× in payout.** Play three rounds badly and three well,
compare the end-of-shift scores, and we'll tune the unlock curve off real numbers
instead of my estimates.

Also worth noticing:
- Does juggling 3–4 tickets feel like pressure, or like busywork?
- Is switching tickets with `1-4` fluid, or do you forget which one you're on?
- Does losing a build when you switch tickets feel fair or annoying?

---

## File map

```
src/Shared/           → ReplicatedStorage.Shared
  Config.luau           all tuning knobs
  DishDefs.luau         dishes + per-ingredient 3D `visual` descriptors
  Remotes.luau          remote event plumbing

src/Server/           → ServerScriptService.Server
  Main.server.luau      entry point
  ShiftService.luau     player registry, tick loop, remote validation
  Kitchen.luau          core gameplay state machine
  OrderService.luau     bag randomiser + ticket construction
  ScoreService.luau     grading and payout

src/Client/           → StarterPlayer.StarterPlayerScripts.Client
  Main.client.luau      input binding, snapshot handling, event dispatch
  Scene.luau            builds the 3D stall, locks the camera, screen shake
  Alien.luau            procedural alien generator (seeded)
  Customers.luau        the queue: spawn, walk, mood, billboard tickets, exits
  FoodStack.luau        3D ingredient stacking on the plate
  UI.luau               the 2D HUD: score, clock, combo, key grid
```

**The server owns every timer and every decision.** The client sends intents
(`ingredient`, `serve`, `scrap`, `select`) and draws the last snapshot it got.
Actions are whitelisted and rate-limited at 20/sec.

Everything in `Scene`, `Alien`, `Customers` and `FoodStack` is **purely
presentational** — built client-side, never replicated, and deleting any of it
would not change a single gameplay outcome. The 3D set is assembled 500 studs
above the baseplate so your character and the default world never intrude, which
also means a plain Baseplate place is all Studio needs.

Feedback events (`graded`, `fumble`, `expired`, …) ride **inside** the snapshot
rather than on their own remote. Separate remotes have no ordering guarantee
between them, and "the plate emptied" arriving before "you served it" picks the
wrong animation.

---

## Deliberately not in P0.5

Sear / fry / chop / pour minigames · station switching · chores and hazards ·
environment modifiers and dish tags · the menu draft screen · saving · the debt
economy · sound.

Two hooks are already in place so they don't require rewrites later:

- `Kitchen.new()` takes a `participants` array (length 1 for now). Co-op means
  putting more players in it, not restructuring.
- `DishDefs` entries already carry `tags` and `workload` fields, unused in P0.
  The P2 environment system reads them directly.

**Sound is the biggest missing piece for feel** and can't be faked with guessed
asset IDs. Once the loop plays right, the priority list is: distinct key thunk,
ticket slam, combo chime rising in pitch, and a fryer-alarm-style walk-out warning.
