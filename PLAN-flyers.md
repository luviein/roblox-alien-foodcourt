# Flyers and rebirth — planned, not built

Captured 2026-08-26, after Word of Mouth was removed in `noword-34`.

## Why Word of Mouth went

Hype controls how fast customers **arrive**. It cannot make you cook faster.

One measured shift — 22 served in a 180 second day, nothing walked out, the
spawner slot-capped throughout — puts a player's serve ceiling at roughly one
order every 8 seconds. That is about **11 orders in a 90 second shift**.

Word of Mouth sold five levels of permanently higher arrival rate, which pushed
well past that ceiling. Its last levels bought nothing but customers who walked
out. An upgrade whose top half is dead is worse than no upgrade, because it
reads as progress.

Customer flow is now sourced entirely from hype the player **earns**:

- **Dish tags** — a dish worth +5% in the phase or weather that suits it. This
  is the pre-rebirth growth lever, which is why the unlock curve was roughly
  halved at the same time.
- **Rebirths** — `Config.REBIRTH_HYPE_STEP` raises base hype permanently.

## Flyers (design agreed, not implemented)

Advertising bought one day at a time, replacing the permanent upgrade with a
consumable gamble.

- **Unlocks at rebirth 1.** Dead content until rebirth exists — build rebirth
  first.
- **Bought per day.** One purchase covers one shift. There is no subscription
  and no carry-over; if you want flyers tomorrow you buy them again.
- **Random +10% to +30%** customer flow, rolled per purchase.
- **Multiplicative on hype**, like every other hype tag, so it is worth the
  same proportion to a new player and a rebirthed one. Never flat — a flat
  +0.05 is a fifth of a new counter and a rounding error on a big one.

### Open decisions

- **When the roll is revealed.** Recommendation: roll at purchase and show the
  number on the draft screen, so the day's hype is fully visible before
  cooking. The draft screen's whole premise is that a rule you cannot see is a
  guess, not a strategy — a hidden roll would break that.
- **Cost.** Wants to be a real fraction of a shift's take, since the payoff is
  one shift. Suggest starting near half a good shift's cash and tuning from a
  real number.
- **Whether the boost can push past the serve ceiling.** At base 0.25 a perfect
  draft already lands near 11 arrivals. A +30% flyer on top of that is buying
  walkouts — the same flaw as Word of Mouth. Either flyers should be worth
  more once base hype is higher after several rebirths, or the serve ceiling
  needs to rise first (see below).

## Rebirth (not implemented)

Only a `rebirths` counter in the profile and the hype maths that reads it. No
reset loop, no UI, nothing that increments it.

Decided previously: unlocked dishes reset on rebirth.

**`Config.REBIRTH_HYPE_STEP` needs revisiting when this is built.** It is 0.02
against a base of 0.25 — an 8% lift, which does not match the stated intent of
rebirth being where base hype meaningfully grows. Something nearer +0.05 per
rebirth would, but it should be set against a real measured shift rather than
picked.

## The serve ceiling is the real constraint

Worth stating plainly, because it bounds every flow upgrade the game will ever
have: **no amount of hype matters past ~11 orders per shift** until the player
can physically cook faster. Things that genuinely raise that ceiling:

- Dishes that cook passively on the grill or fryer while your hands build
  something else — this is what makes a mixed menu better than a fast one, and
  it is the stated goal for the dish system.
- `Config.MAX_ORDER_SLOTS` and Counter Space, which buffer against idling.
- `Longer Licence`, which buys seconds rather than rate.

Any future flow upgrade should be checked against this number first.

## Known bug, not yet fixed

`Counter Space` is 2 levels at base 3, +1 each, so it maxes at 5 order slots —
but `Config.MAX_ORDER_SLOTS` clamps to 4 in `ShiftService.luau:202`. The second
level, at 5,000 cash, buys nothing. Either raise the cap to 5 or cut the
upgrade to a single level.
