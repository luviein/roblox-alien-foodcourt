---
name: optimise
description: Audit Alien Food Court for waste and fix it - both performance (work repeated per tick or per frame, redundant property writes, per-player leaks) and simplification (duplicated logic, repeated literals, functions called several times in one scope). Covers BOTH unless told otherwise. Use when asked to optimise, simplify, clean up, check performance, look for waste, or investigate lag or memory growth.
---

# Optimising Alien Food Court

Two passes, and **do both unless told otherwise**: performance waste, and code
that is more complicated than it needs to be. They are the same job — each is
work that should not be there — and the second is usually what causes the first.

## The bar

**A change that alters behaviour is not an optimisation, it is a rewrite.** If a
change needs the test suite re-read to be sure it was safe, it does not belong
in this pass — raise it separately.

That applies to simplification too. Collapsing three copies of a loop into one
helper is safe. "Simplifying" a rule because it looks convoluted is not — the
convoluted ones here are usually load-bearing, and the comment above them says
why. Read it before touching it.

Do not guess. Read the hot paths and show why something is hot before touching
it. A number in a commit message that nobody measured is worse than no number.

## What is actually hot here

Three loops, and almost nothing else matters:

| Loop | Rate | Where |
|---|---|---|
| Server tick | 10/s **per player** | `ShiftService.startTickLoop` |
| Snapshot push | up to 10/s per player | `ShiftService.pushSnapshot` → `UI.render` |
| Client frame | ~60/s | `RunService.RenderStepped` → `UI.renderTimers`, `Customers.update` |

Anything called from those runs thousands of times a minute. Anything not
called from those is almost certainly not worth touching, however ugly.

`Kitchen:tick` is the gameplay state machine and runs at the tick rate. Its
inner loops walk the order list, which is capped at `MAX_ORDER_SLOTS` — four.
Four is not a performance problem. Leave it alone.

## The five things to look for

Ranked by how often they have actually been found here.

### 1. Rendering something nobody is looking at

The commonest and biggest. A panel render wired into the snapshot handler runs
whether or not the panel is open.

This cost the project twice over: `ShopUI.render` walked nineteen rows and
`DraftUI.render` evaluated the whole menu once per phase, both ten times a
second, both discarded unseen.

Check every `*.render(...)` call in `Main.client.luau`'s snapshot handler is
gated on that panel being open. **If you gate one, make it render on the way
open too** — otherwise it shows stale data the moment someone opens it. Grep
for `isOpen` to see the pattern.

### 2. Per-player tables that are never cleared

`onPlayerRemoving` in `ShiftService` must clear **every** per-player registry.
One missed entry holds a `Player` instance and its table for the life of the
server.

Grep for `: { [Player]:` and check each one is cleared there. `dayConditions`
was missed for weeks.

### 3. Recomputing an answer that changes once a day

`os.date`, date string formatting, and anything else formatting or parsing in a
tick loop. `DailyDefs.todayString` exists because the midnight check was
formatting a date ten times a second per player.

Memoise for a second. Nothing in this game is fussier than that.

### 4. Property writes that write the same value

`renderTimers` runs every frame, and the shift clock reads the same for sixty
frames in a row. Assigning `.Text` unconditionally meant fifty-nine redundant
writes a second.

Guard with a comparison. **But only where the value genuinely repeats** — the
timer fill bar moves every frame and guarding it would just add a read. Do not
apply this blindly.

### 5. Replicating more than the client needs

`pushSnapshot` sends the whole profile on every push. It is fine at this scale
and it is on the list, but changing it means changing what the client can
assume is present — which is a rewrite, not an optimisation. See "Known and
deliberately not done".

## The simplification pass

Same principle, different symptom: something written more times than it needed
to be. Ranked, again, by what has actually been found here.

### 1. The same loop, written more than once

`pushRecent` exists because "insert at the front, trim to a window" was written
out **three times** — recent earnings once, recent menus twice. Every copy had
to agree about which end is newest, and one of them being written backwards is
a bug nothing would catch.

Grep for repeated `table.insert(..., 1, ...)`, matching `while #x > n do` loops,
and any pair of blocks that differ only in the variable name.

### 2. The same table literal, written twice

`freshStats` exists because the zeroed stats table appeared in both
`Kitchen.new` and `Kitchen:startShift`. Adding `chores` meant editing both, and
forgetting the second would have left a stat that counted correctly on the first
shift of a session and carried over silently on every one after.

A literal that must be kept in step with another literal is a function.

### 3. The same function called repeatedly in one scope

`unlockedMenu(profile)` was called three times inside `loadoutFor`, each call
rebuilding the same list. Hoist it. This is a simplification and a small
performance win at once, which is the usual pattern.

### 4. A comment explaining that two things match

The strongest single tell in this codebase. `loadoutFor` had a comment saying
one call "was built from the same list above" — which is the code asking to be
one call rather than two. When a comment exists to reassure the reader that two
places agree, delete the second place instead.

### 5. Dead configuration

`OFFLINE_MIN_SECONDS` was a knob that disagreed with the arithmetic around it
and created a silent dead zone. If two numbers have to be consistent, derive one
from the other rather than documenting the relationship.

Grep `Config.` usage for anything defined and never read, or read in exactly one
place that could compute it.

## Known and deliberately not done

Do not "fix" these without asking. Each is a considered trade.

- **The full profile rides every snapshot.** Wasteful, and the client currently
  assumes it is always there. Splitting it into a separate rarely-pushed
  channel is a real improvement and a real change — propose it, do not sneak it
  into a cleanup pass.
- **`DailyDefs.statusOf` allocates a table per call**, so a few per tick. Small,
  and the alternative is a dirty-flag cache that can go stale. Not worth it yet.
- **Idle kitchens are skipped, with exceptions.** The idle push exists so boost
  timers do not freeze on screen. Do not "optimise" the exception away; read the
  comment first.
- **Everything visual is client-side and never replicated.** `Scene`, `Alien`,
  `Customers`, `FoodStack`, `Face`, `NpcAnimator`. Deleting any of it changes no
  gameplay outcome. It is not on the server's budget.
- **The long comments are not clutter.** `Config.luau` explains why each number
  is what it is, and most of those numbers were set against a real measured
  shift. Deleting the reasoning is how the next person re-derives it wrongly.
  Shortening a comment is not a simplification.
- **`debugFinishShift` and `endShiftNow` look redundant and are not.** One fills
  in a plausible result, the other moves the clock so the ordinary end-of-shift
  path runs. Read both comments before merging them.

## Verifying

1. `~/bin/rojo.exe build -o afc-check.rbxlx` — proves the project still builds.
   **It does not parse Luau.** A syntax error still ships.
2. Bump `Config.BUILD`. The loading screen stamp is the only proof Studio is
   running current files.
3. Press Play and read the `[tests]` block in Output. All suites must say `ok`.
   A suite reporting `crashed` once went unnoticed for several builds.
4. Play a shift. The traps in `README.md` under "Traps this codebase has
   actually fallen into" are all invisible to steps 1–3.

## Traps specific to this kind of change

- **Forward references.** Moving a function to gate or reorder it can put it
  below a caller. A `local` declared after its reader resolves to a nil
  **global** at runtime, not a compile error. This has bitten five times.
- **Gating a render without rendering on open** shows stale data — a real bug
  traded for a small win.
- **Reading a property to avoid writing it** is not free. Worth it for strings
  that repeat, not for a value that changes every frame anyway.

## Reporting

Say what was found, why it was hot, and what it now costs instead. If something
was inspected and left alone, say that too — "checked, four orders maximum, not
worth it" is a useful result and stops the next pass re-treading it.
