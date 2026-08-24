--!strict
-- Central tuning knobs for P0. Everything here is meant to be fiddled with
-- during playtesting -- change a number, save, Rojo pushes it, hit Play.

local Config = {}

-- Bumped by hand whenever something changes that you need to SEE change.
-- Shown in the corner of the loading screen, so one glance confirms Studio is
-- actually running the current files rather than a stale synced copy.
Config.BUILD = "census-03"

-- ---------------------------------------------------------------- shift ----
Config.SHIFT_DURATION = 180        -- seconds of service per round
Config.ORDER_PATIENCE = 22         -- seconds before a customer walks out
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
Config.GRADE_MULT = {
	Perfect = 1.5,
	Good = 1.0,
	Sloppy = 0.6,
	Fail = 0.0,
}

Config.COMBO_STEP = 0.10           -- +10% per combo step
Config.COMBO_MAX = 3.0             -- multiplier ceiling

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
