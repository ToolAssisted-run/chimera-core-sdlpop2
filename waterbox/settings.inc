/* settings.inc - SDLPoP2's gameplay settings as a project's settings.
 *
 * One table, read twice: by pop2-driver.c, which writes the ones a project
 * changed into SDLPoP2.ini's form and hands that to SDLPoP2's own parser, and by
 * gen-config.py, which declares them in waterbox.config. Only what changes the
 * game is here - what a movie must reproduce; SDLPoP2's frontend settings (the
 * window, the keys, the volume) are not the machine. The defaults are the
 * original game's, and with every one at its default the game runs on SDLPoP2's
 * verified path (no overrides installed at all).
 *
 * POP2_SETTING(ini name, BOOL | INT, ini section, default, min, max, display, description)
 */
POP2_SETTING(enable_intro, BOOL, "General", 1, 0, 1, "Intro",
	"Shows the intro, which is story scenes 7, 4 and 8 of the title sequence. Without it the title goes on to the credits and the demos, where a key starts the game.")
POP2_SETTING(enable_story_scenes, BOOL, "General", 1, 0, 1, "Story scenes",
	"Shows the story scenes between the levels, the scene when the time runs out and the ending. A skipped scene counts as played to its end, so the game after it is the same.")
POP2_SETTING(skip_title, BOOL, "General", 0, 0, 1, "Skip the title",
	"Skips the title sequence. A new game starts immediately, at the level chosen in First level.")
POP2_SETTING(start_minutes_left, INT, "CustomGameplay", 75, 1, 32767, "Starting minutes",
	"The minutes left when a game starts. The original has 75.")
POP2_SETTING(ticks_per_minute, INT, "CustomGameplay", 719, 1, 65535, "Clock ticks a minute",
	"How many ticks of the game clock make one minute of the time left. The original has 719. A tick is 1/12 of a second, so a minute of the clock lasts 59.92 seconds.")
POP2_SETTING(start_hitp, INT, "CustomGameplay", 3, 1, 127, "Starting hit points",
	"The prince's hit points when a game starts. The original has 3.")
POP2_SETTING(max_hitp_allowed, INT, "CustomGameplay", 12, 1, 127, "Most hit points",
	"The most hit points the prince can have. Potions of life add nothing above this. The original has 12.")
POP2_SETTING(skip_level_reduced_minutes, INT, "CustomGameplay", 15, 1, 32767, "Minutes after Alt+N",
	"The minutes left after skipping a level with Alt+N when the cheats are off (allowed up to level 3). The original has 15.")
POP2_SETTING(first_level, INT, "CustomGameplay", 1, 1, 14, "First level",
	"The level a new game starts at. The original starts at 1.")
POP2_SETTING(base_speed, INT, "CustomGameplay", 5, 1, 255, "Walking speed",
	"The time between two ticks of play when not fighting, in 1/60 of a second. Smaller is faster. The original has 5.")
POP2_SETTING(fight_speed, INT, "CustomGameplay", 6, 1, 255, "Fighting speed",
	"The time between two ticks of play with the sword drawn, in 1/60 of a second. Smaller is faster. The original has 6.")
