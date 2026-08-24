--!strict
-- Every sound the game uses, in one place.
--
-- Asset ids only load if the audio is public -- Roblox-published audio always
-- is, most user uploads are not. An id set to 0 is simply skipped, so half a
-- soundtrack never breaks anything.

local SoundDefs = {}

-- One-shots. `volume` is relative to the SFX slider; `pitchJitter` randomises
-- PlaybackSpeed a little each time so a sound played hundreds of times a round
-- does not turn into a machine gun.
SoundDefs.Sfx = {
	click = {
		id = 70862388846559,
		volume = 0.55,
		pitchJitter = 0.06,   -- ingredient added; the most repeated sound here
	},
	wrongOrder = {
		id = 131268007007000,
		volume = 0.85,
		pitchJitter = 0.02,   -- also the walk-out sting
	},
	maxCombo = {
		id = 130014350102430,
		volume = 0.8,
		pitchJitter = 0,      -- fires once per streak, so keep it identical
	},
	roundComplete = {
		id = 2940337254,
		volume = 0.9,
		pitchJitter = 0,
	},

	serveSuccess = {
		id = 124743961969068,
		volume = 0.75,
		pitchJitter = 0.03,
	},

	-- Not sourced yet. Left at 0 so they no-op rather than erroring.
	ticketArrive = { id = 0, volume = 0.6, pitchJitter = 0.04 },
	fumble       = { id = 0, volume = 0.4, pitchJitter = 0.05 },
}

-- Played in order, then looped back to the start.
-- Held while something is cooking, rather than fired once. A sizzle that plays
-- for a moment and stops tells you a thing happened; one that runs for as long
-- as the pan is hot tells you something is STILL happening, which is the part
-- that matters when it is out of sight behind the prep panel.
SoundDefs.Loops = {
	sizzle = { id = 7056816387, volume = 0.45 },   -- grill, while searing
	frying = { id = 6377822658, volume = 0.35 },   -- fryer, while a basket is down
}

-- Trims the tracks themselves before the slider is applied. Music assets are
-- usually mastered far louder than short effects, so without this the slider
-- spends its whole range fighting the source material.
SoundDefs.MusicGain = 0.45

SoundDefs.Music = {
	85881788376421,
	90665611745011,
	113772778748041,
	71516573136394,
}

return SoundDefs
