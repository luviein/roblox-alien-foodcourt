--!strict
-- Central tuning knobs for P0. Everything here is meant to be fiddled with
-- during playtesting -- change a number, save, Rojo pushes it, hit Play.

local Config = {}

-- Bumped by hand whenever something changes that you need to SEE change.
-- Shown in the corner of the loading screen, so one glance confirms Studio is
-- actually running the current files rather than a stale synced copy.
Config.BUILD = "slowstart-32"

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
-- At the 0.15 a new player opens on, these work out to 24s, 18s and 14s: about
-- five customers across the whole first shift, arriving one at a time with room
-- to breathe. At a full house they are 3.6s, 2.7s and 2.1s -- roughly 34 in a
-- shift, which four order slots can only just contain.
--
-- That gap IS the progression. Nothing about the cooking changes; the counter
-- just stops being quiet.
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
-- Raised from 0.30 now that a first shift is five customers rather than
-- twenty-two: the rate had to come back up or the opening days would pay
-- almost nothing. This is the knob to turn if unlocks feel too fast or slow --
-- it moves the economy without touching difficulty.
Config.CASH_PER_POINT = 0.60

-- ---------------------------------------------------------------- hype -----
-- Hype is how busy your counter is, as a fraction of a full house. Nobody has
-- heard of you yet, so you open at 15% -- a slow trickle of customers with
-- plenty of room to breathe. Everything you do from there raises it.
Config.BASE_HYPE = 0.15

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
