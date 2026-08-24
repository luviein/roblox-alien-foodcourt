--!strict
-- Central tuning knobs for P0. Everything here is meant to be fiddled with
-- during playtesting -- change a number, save, Rojo pushes it, hit Play.

local Config = {}

-- Bumped by hand whenever something changes that you need to SEE change.
-- Shown in the corner of the loading screen, so one glance confirms Studio is
-- actually running the current files rather than a stale synced copy.
Config.BUILD = "tune-31"

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

Config.SPAWN_INTERVAL = {
	{ 0.00, 5.0 },
	{ 0.30, 3.5 },
	{ 0.60, 2.5 },
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
Config.CASH_PER_POINT = 0.30

-- ---------------------------------------------------------------- hype -----
-- Where a neutral menu sits before any tag is counted. Not 1.0: the station
-- has a baseline reputation, and rebirths raise it permanently.
Config.BASE_HYPE = 1.15
Config.REBIRTH_HYPE_STEP = 0.05

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
