--!strict
-- Central tuning knobs for P0. Everything here is meant to be fiddled with
-- during playtesting -- change a number, save, Rojo pushes it, hit Play.

local Config = {}

-- Bumped by hand whenever something changes that you need to SEE change.
-- Shown in the corner of the loading screen, so one glance confirms Studio is
-- actually running the current files rather than a stale synced copy.
Config.BUILD = "noword-34"

-- ---------------------------------------------------------------- shift ----
-- One shift is one day: morning, afternoon and night, thirty seconds each.
Config.SHIFT_DURATION = 90
-- Base seconds before a customer walks out. Deliberately tight: at 22s every
-- order graded Perfect, so the combo never broke and the multiplier sat on its
-- ceiling for the back half of the shift. Counter Service upgrades raise this.
Config.ORDER_PATIENCE = 15
Config.MAX_ORDER_SLOTS = 4         -- hard cap on tickets on screen

-- Difficulty curve. Each entry is {progress 0-1, value}. The value used is
-- the last entry whose progress has been passed, so orders get denser as the
-- shift wears on.
Config.MAX_ACTIVE_ORDERS = {
	{ 0.00, 2 },
	{ 0.30, 3 },
	{ 0.60, 4 },
}

-- Seconds between customers AT FULL HYPE (1.00). The real interval is this
-- divided by current hype.
--
-- At the 0.25 a new player opens on, these work out to 14s, 11s and 8s: about
-- eight customers across the first shift. You cook, you get a couple of seconds,
-- then the next one is at the counter. At a full house they are 3.6s, 2.7s and
-- 2.1s -- roughly 34 in a shift, which four order slots can only just contain.
--
-- That gap IS the progression. Nothing about the cooking changes; the counter
-- just stops being quiet.
--
-- The floor was raised from 0.15 because five customers in ninety seconds read
-- as broken rather than quiet -- most of the shift was spent standing still.
-- Word of Mouth is gone, so the menu is now the only thing that moves it.
Config.SPAWN_INTERVAL = {
	{ 0.00, 3.6 },
	{ 0.30, 2.7 },
	{ 0.60, 2.1 },
}

-- ---------------------------------------------------------------- score ----
-- Grade boundaries as a fraction of the customer's remaining patience.
-- These are also the colour stops on the patience bar, deliberately: the bar
-- is the grade meter, so serving while it is green is a Perfect.
-- Chores interrupt on their own schedule during service. The gap is randomised
-- inside this range so they never become something you can plan around.
-- Halved along with the shift length, so a ninety second day still gets
-- roughly one interruption per phase rather than one per shift.
Config.CHORE_GAP = { 9, 17 }

-- What failing one costs. Halving is deliberate: a full reset for missing a
-- five second window would make chores the whole game, and a flat -1 would
-- make them free once a streak is long.
Config.CHORE_COMBO_PENALTY = 0.5

Config.GRADE_PATIENCE = {
	perfect = 0.55,
	good = 0.30,
}

Config.GRADE_MULT = {
	Perfect = 1.5,
	Good = 1.0,
	Sloppy = 0.6,
	Fail = 0.0,
}

Config.COMBO_STEP = 0.10           -- +10% per combo step
Config.COMBO_MAX = 3.0             -- multiplier ceiling

-- Score is skill; cash is what that skill is worth, and the two are separate
-- so difficulty and economy can be tuned without dragging each other around.
-- Keeping the score number big and the cash number small is deliberate: the
-- shift should feel good to finish and the unlock should still feel earned.
-- This tracks the customer count. At five customers a shift it had to sit at
-- 0.60 or the opening days paid nothing; at roughly eight it comes back down,
-- because a longer queue also keeps the combo alive and score climbs faster
-- than the headcount does.
--
-- Where that lands: about 180 c for a first shift, against fries at 250, so
-- the first unlock is a day and a half of play. This is the knob to turn if
-- unlocks feel too fast or slow -- it moves the economy without touching
-- difficulty, and the dish costs in ShopDefs are the other half of the same
-- dial.
Config.CASH_PER_POINT = 0.25

-- ---------------------------------------------------------------- hype -----
-- Hype is how busy your counter is, as a fraction of a full house. Nobody has
-- heard of you yet, so you open at 25% -- a thin queue with real gaps in it,
-- but never an empty counter. Everything you do from there raises it.
--
-- This is the floor of the whole game's pacing, and with Word of Mouth gone it
-- is also the CENTRE of it: a menu can only swing hype between 0.60x and 1.35x
-- of this number, so the whole pre-rebirth range is 0.15 to 0.34 -- roughly
-- five customers for a badly drafted day and eleven for a well drafted one.
--
-- Eleven is deliberate. One measured shift put a player's serve ceiling at
-- about one order every eight seconds, so eleven is all anyone can physically
-- cook in ninety seconds. Setting the base so a PERFECT draft lands on that
-- ceiling is what makes drafting worth doing: any higher and the top of the
-- menu range buys customers who only walk out, which is exactly the flaw that
-- got Word of Mouth removed.
Config.BASE_HYPE = 0.25

-- Each rebirth is worth two more points of base hype, so a rebirthed player
-- works a permanently busier counter than a fresh one.
Config.REBIRTH_HYPE_STEP = 0.02

-- A dish stays stale for this many days after you serve it. Two, so you cannot
-- simply alternate between two menus and never pay a repeat penalty.
Config.MENU_STALE_DAYS = 2

-- ---------------------------------------------------------------- input ----
-- "reject"  : a wrong key is refused outright with a short fumble lockout.
--             Forgiving. Good for learning the feel.
-- "corrupt" : a wrong key lands on the plate and ruins the build -- you must
--             SCRAP and start over. This is the Cook Serve Delicious punish.
-- Flip this during playtesting; it changes the whole texture of the game.
Config.WRONG_KEY_MODE = "reject" :: "reject" | "corrupt"
Config.FUMBLE_LOCKOUT = 0.45       -- seconds of input lock after a wrong key

-- --------------------------------------------------------------- server ----
Config.TICK_RATE = 10              -- authoritative ticks per second
Config.ACTION_RATE_LIMIT = 20      -- max client actions accepted per second

return Config
