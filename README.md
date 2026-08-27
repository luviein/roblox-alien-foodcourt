# Alien Food Court

You were abducted. The locals are curious about Earth food. Get to work.

A Cook Serve Delicious-style cooking game for Roblox. Tickets arrive, you build
each dish top to bottom on the keyboard, and you hand it over before the customer
loses patience. Solo for now.

---

## Running it

Rojo lives at `%USERPROFILE%\bin\rojo.exe`. From this folder:

```
rojo serve
```

Leave it running — it watches the files and pushes on save. Then in Studio,
**Plugins → Rojo → Connect** (default `localhost:34872`). `Shared`, `Server` and
`Client` should appear in the Explorer.

**Open the PUBLISHED place**, not a local file, and turn on
**Experience Settings → Security → Enable Studio Access to API Services**.
Without both, DataStores are unavailable: the game runs on a throwaway profile,
nothing saves, and anything that reads a save — offline earnings, daily tasks,
the shop — behaves as though you were brand new every time. The between-shifts
screen says `PROGRESS NOT SAVING` in red when this is the case.

`rojo build -o game.rbxlx` produces a file, but it is compile output for checking
the project builds — not something to play.

---

## Controls

| Key | Action |
|---|---|
| `1` `2` `3` `4` | pick up that ticket (switching abandons the current plate) |
| `Q W E R T` / `A S D F G` | add an ingredient |
| `SPACE` | serve |
| `X` | scrap the plate |
| drag | chores: five separate throws to airlock the trash, or seconds of scrubbing to clean |
| `E` | plan the day / continue (outside service only) |

Every key has an on-screen button firing the same code path, so touch works.
Ingredient keys are relabelled per dish, and the convention holds across all of
them so muscle memory carries: `Q` base · `A` protein · `S D F` toppings ·
`W` lid.

Tickets are built **in the order listed, top to bottom**.

---

## How a day works

1. **Plan the day** — draft up to three dishes from what you have unlocked. The
   screen shows what each does to your hype, per phase, before you commit.
2. **Service** — 90 seconds, split into morning / afternoon / night. Customers
   arrive, chores interrupt, the combo climbs while you keep grading Perfect.
3. **Results** — score converts to cash, the day counter advances, and the daily
   tasks take their cut of what you just did.

Between shifts you can spend at the Supply Depot, check the daily tasks on the
side rail, and collect whatever the understudy earned while you were away.

---

## The systems, and the one rule under all of them

**Score is pure skill. Cash is what that skill is worth.**

Nothing bought, rolled or waited for touches score. Upgrades, boosts, pets and
offline earnings all move cash only. That separation is what lets difficulty and
economy be tuned without dragging each other around, and it is worth defending —
most of the design decisions below fall out of it.

### Hype — how fast customers arrive

Hype is how full your counter is, as a fraction of a full house.
`Config.SPAWN_INTERVAL` holds the gap between customers at 100% hype, and the
real gap is that divided by current hype.

It is recomputed **per phase**, which is what makes drafting interesting: a
breakfast dish earns its place for thirty seconds and then stops. Dish tags move
hype **multiplicatively** (×1.05, not +0.05) so a tag is worth the same
*proportion* to a new player and a rebirthed one.

Two different percentages live on these screens and they are not the same unit.
The meter is a fraction of a **full house**; a dish tag is a fraction of **your
own base**. A +5% dish on a base of 25% moves the meter by about one point, so
both readouts show both numbers.

**The serve ceiling bounds all of this.** Hype only controls how fast customers
*arrive* — it cannot make anyone cook faster. One measured shift put that at
roughly one order every eight seconds, about eleven in a 90-second day. Any flow
upgrade that pushes arrivals past that is buying walkouts, which is what got the
old Word of Mouth upgrade deleted. Check every future flow feature against it.

### Daily tasks

Three goals a day, rolled from the UTC day number so everyone gets the same
three. Completed by playing ordinary shifts — there is no separate mode. Each
finished task is claimed for one roll on the prize pool: cash, or a timed boost.

The tasks are shared; the **prize is not**. It rolls per claim, per player. A
prize everyone can look up is not a prize.

### Boosts

Won from that pool. Better earnings (+10–30%, rolled when won) or customers who
tip a flat amount per order. Their clock **only runs while you are in the game** —
burning a fifteen minute prize while someone is asleep would make winning one a
punishment for logging off.

### The Understudy — offline earnings

Sector 7 licenses a counter on one condition: it is never unstaffed. When you
leave you are in breach, so the station plays back a recording of your last few
shifts through a service unit that stands where you stand and does what you did.
It plates the burger perfectly and hands it to the wrong customer.

The premise does the mechanical work rather than decorating it:

| Rule | Why, in fiction |
|---|---|
| Pay scales with your skill | It is a recording *of you* |
| It can never beat playing | A copy is lossy |
| Capped in hours | The cell degrades past its capacity |
| Upgrades buy **time**, never rate | The station will not sell fidelity |

That last one is load-bearing: raising the rate would make not-playing better,
where raising the cap only ever helps someone already away. An hour offline is
about two shifts against roughly thirty an hour of active play — under a tenth,
and there is a test asserting exactly that.

---

## Saving

**Roblox `DataStoreService`, and nothing else.** No external database, no HTTP,
no third-party persistence library.

- One store, `AFC_Profiles_v1`, key `p_<UserId>`, one table per player
- `UpdateAsync` rather than `SetAsync`, so a concurrent write merges instead of
  blindly replacing
- Retries with backoff, except for failures that are configuration rather than
  weather — an unticked API-services box fails on the first try and says what to
  do about it instead of spending nine seconds arriving at the same answer
- Saves on leave, on shutdown (`BindToClose`, in parallel), on autosave every
  120s when dirty, and after anything that pays out
- A `lastSeen` heartbeat every 60s while online, which is what the understudy
  measures an absence from

**The rule that matters most: a profile that FAILED to load is never saved.**
Writing defaults over a good save because a `GetAsync` timed out is the worst
thing this code could do, and it is the easy mistake to make.

ProfileService and friends mostly solve session locking across servers, which
matters when duping is the threat — trading games, tradeable inventories. This is
one profile per player with no transfers, so retry-plus-autosave covers what
actually goes wrong here, and it is a dependency small enough to read in full.

---

## Tuning

Everything worth fiddling with is in `src/Shared/Config.luau`, heavily commented
with *why* each number is what it is. Save and Rojo pushes it live.

| Knob | What it does |
|---|---|
| `WRONG_KEY_MODE` | `"reject"` refuses a wrong key with a short lockout. `"corrupt"` puts it on the plate and forces a `SCRAP`. These are different games. |
| `ORDER_PATIENCE` | 15s. Grading is on *remaining fraction*, so the bar above each customer literally is the grade meter. |
| `BASE_HYPE` | 0.25. With no shop upgrade moving it, this is the centre of the pre-rebirth range, not its floor. |
| `CASH_PER_POINT` | 0.25. The one knob for the whole economy. |
| `SPAWN_INTERVAL` / `MAX_ACTIVE_ORDERS` | the difficulty curve, as `{progress, value}` pairs |
| `OFFLINE_*` | rate, cap and losses for the understudy |

Dish values and tags live per-dish in `src/Shared/DishDefs.luau`; prices and
upgrades in `src/Shared/ShopDefs.luau`.

**`Config.BUILD` is bumped by hand on every change.** It renders on the loading
screen and is the only proof Studio is running current files rather than a stale
synced copy. When something looks wrong, the first question is what the build
stamp says.

---

## Testing

### Automated

About 155 assertions over the pure logic in `Shared` — hype maths and its clamps,
daily task rolling and progress, boosts, the offline model, and consistency
checks across the shop tables (every dish priced, every price ordered, the unlock
curve monotonic, retired upgrades still refundable).

They run in Studio at startup when `Config.DEBUG_LOGGING` is on, printing to
Output. Failures `warn()`, so they come out orange.

```
[tests]   ok  daily          42 passed
[tests]   ok  hype           40 passed
[tests]   ok  offline        51 passed
[tests]   ok  shop           22 passed
[tests] all 155 assertions passed
```

**Read that line.** A suite reporting `crashed` once went unnoticed for several
builds while the feature it covered was completely broken.

What they cannot reach is anything made of Instances: rendering, input, clicks,
ZIndex, layout. Most bugs this project has shipped were exactly that, so a green
run means the numbers are right — not that the game is.

### Debug commands

Two flags, wanted at different times:

- **`DEBUG_COMMANDS`** — anything that *changes state*. **Off before release.**
- **`DEBUG_LOGGING`** — Output only: the test suite, the offline decline reasons,
  and the read-only `/offline` dump. Safe to leave on through a realistic
  playtest, which is exactly when a silent failure is hardest to reproduce.

| Command | Key | Effect |
|---|---|---|
| `/skip [n]` | `F5` | Bank finished shifts without cooking them |
| `/away [hours]` | `F6` | Rewind the clock and settle the gap for real |
| `/boost [earnings\|tips] [secs]` | `F7` / `F8` | Start a boost |
| `/endshift` | `Backspace` | End the running shift now |
| `/offline` | — | Dump every input the understudy reads (read-only) |

Use `/skip` rather than `/endshift` to get a shift on the books: ending an
untouched shift scores zero, and a run of zeroes drags the recent-earnings
average to nothing — which then makes offline earnings pay nothing and look
broken.

---

## Architecture

```
src/Shared/     → ReplicatedStorage.Shared
  Config          every tuning knob, with the reasoning
  DishDefs        dishes, ingredients, tags, 3D visual descriptors
  HypeDefs        phases, weather, and how a menu becomes hype
  ShopDefs        prices, upgrades, refunds for retired ones
  DailyDefs       daily tasks, prize pool, boost state
  OfflineDefs     the understudy
  ChoreDefs       interruptions
  SoundDefs       asset ids
  AvatarPool      catalogue ids for customer generation
  Remotes         remote plumbing

src/Server/     → ServerScriptService.Server
  Main.server     entry point
  ShiftService    player registry, tick loop, every remote handler
  Kitchen         the gameplay state machine
  DataService     profiles: load, autosave, flush
  OrderService    bag randomiser and ticket construction
  ScoreService    grading and payout
  CustomerRigs    prebuilds the avatar pool
  CatalogSource   resolves catalogue asset ids
  Tests/          the suite above

src/Client/     → StarterPlayer.StarterPlayerScripts.Client
  Main.client     input binding, snapshot handling, event dispatch
  UI              the HUD, side rail, daily and offline panels
  DraftUI         the plan-the-day screen
  ShopUI          the Supply Depot
  SettingsUI      volume and toggles
  Scene           the 3D stall, camera, screen shake
  Customers       queue, walking, mood, billboard tickets
  Alien/Face      procedural customers
  NpcAnimator     rig posing
  FoodStack       ingredients stacking on the plate
  Loading         boot screen and build stamp
  Audio           music and SFX
```

**The server owns every timer and every decision.** The client sends intents and
draws the last snapshot it received. Actions are whitelisted and rate-limited.

Everything visual is built client-side and never replicated — deleting all of it
would not change a single gameplay outcome. The set is assembled 500 studs above
the baseplate so the default world never intrudes.

Feedback events ride **inside** the snapshot rather than on their own remote.
Separate remotes have no ordering guarantee between them, and "the plate emptied"
arriving before "you served it" picks the wrong animation.

---

## Traps this codebase has actually fallen into

Every one of these shipped, and `rojo build` caught none of them — it checks file
layout and does not parse Luau.

- **Forward references.** A `local` declared below the function that closes over
  it resolves to a nil *global* at runtime, not a compile error. This has bitten
  at least five times. After editing, check that every local a function reads is
  declared above it.
- **A greyed button is not a disabled button.** Dimming `BackgroundColor3`
  changes nothing; `Activated` still fires. Set `Active = false`, and guard the
  handler too.
- **A panel absorbs mouse clicks and teaches the keyboard nothing.** Every modal
  needs an `isOpen` accessor that the key handler checks, or `E` fires straight
  through and starts a shift underneath it.
- **A plain `Frame` does not absorb clicks.** Modal panels must be a `TextButton`
  with `Text = ""` and `AutoButtonColor = false`.
- **Scale width plus `UIAspectRatioConstraint` inside a `UIListLayout`** resolves
  to zero height. The element exists, sized nothing, and is simply invisible.
- **Cached rows must not close over the profile.** Rows built once outlive the
  render that made them; a handler capturing that render's profile redraws
  everything from a frozen one.
- **Idle kitchens are not sent snapshots.** Anything that changes while nothing
  is happening — a boost timer, a late profile load — has to ask for a push.

---

## Not built yet

**Rebirth.** Only a `rebirths` counter and the hype maths that reads it. Decided:
unlocked dishes reset. `REBIRTH_HYPE_STEP` needs revisiting when it lands — 0.02
against a base of 0.25 does not match the intent of rebirth being where base hype
meaningfully grows.

**Flyers.** A per-day consumable, randomly rolled +10–30% customer flow, unlocked
at rebirth 1. Design and open questions in `PLAN-flyers.md`.

**Daily check-ins**, **achievements**, **RNG pets** (buffs by rarity, bought with
earned cash; premium ones with Robux). Later: an open map for ~10 players,
decorating, visiting other restaurants, co-op.

`Kitchen.new()` already takes a participants array of length one, so co-op means
putting more players in it rather than restructuring.

**A known bug, unfixed:** `Counter Space` is two levels at base 3, +1 each, so it
maxes at 5 order slots — but `Config.MAX_ORDER_SLOTS` clamps to 4. The second
level buys nothing. Either raise the cap or cut it to one level.
