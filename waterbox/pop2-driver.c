/* pop2-driver.c - Prince of Persia 2 (SDLPoP2) stepped one game step at a time.
 *
 * SDLPoP2's shell (source/shell.h) is the whole DOS program - start-up, the
 * title and its demos, the story scenes, the menus, the levels, the hall of
 * fame - kept in the original's blocking loops on a coroutine, and stepped one
 * VGA frame (70.086 Hz) at a time. A Chimera frame is one step of the game's
 * logic (docs/game-cores.md in chimera): while playing, the frames up to and
 * including the next game tick, which is where the game reads its controls
 * (5 or 6 frames, the game's own frame_delay); everywhere else - the title, the
 * scenes, the menus, the pause - one frame, because the program reads its keys
 * every frame there. The rate of the step just run is what GetVsync* report.
 *
 * Nothing here reads the host: the random seed is a setting, the sound is
 * rendered for exactly the time each frame covers, CONFIG.DAT is the original
 * setup's and the files the game writes (saved games, the hall of fame, the
 * options) live in guest memory, so a savestate carries them.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <emulibc.h>
#include <waterbox_settings.h>
#include <waterbox_slots.h>

#include "pop2-driver.h"
#include "sha1.h"

#include "audio.h"
#include "loader.h"
#include "render.h"
#include "settings.h"
#include "shell.h"

/* ------------------------------------------------------------ the game's files */

typedef struct
{
	const char *name;
	long size;
	const char *sha1;
} pop2_file;

/* Prince of Persia 2 1.0 as the Prince of Persia Collection CD has it - the
 * release SDLPoP2 is rebuilt from, whose PRINCE.EXE it reads tables out of.
 * The same list as SDLPoP2's own frontend checks (sdl/main.c game_files), less
 * CONFIG.DAT (the core's own, below), plus PRESETS.DEF (the FM instruments,
 * which audio.c and nis.c read). */
static const pop2_file k_files[] = {
	{ "PRINCE.EXE", 259583, "835FD96C57CD4AC729ED0B5630623552987E0AC4" },
	{ "SEQUENCE.DAT", 11980, "496AF1AF9AED022A0586734470268E3498D85FDA" },
	{ "PRINCE.DAT", 388168, "C39AC9540B73D8F7AA65D7E7EC6A85540BB4D709" },
	{ "KID.DAT", 79395, "E038004C360EE2ED5174542B808B41918A39DBE1" },
	{ "GUARD.DAT", 27299, "64820F5668965553A5770C4C39A7438E00F33BBD" },
	{ "HEAD.DAT", 20084, "1631EC0BD012488230151E853AA5236CD69924AA" },
	{ "SKELETON.DAT", 13744, "27A951260261D1C7A9D1C5E6C931C77675646CBB" },
	{ "BIRD.DAT", 32151, "3AE61A9D4BBAFA2C5006EDB99286EA6EF6F892D9" },
	{ "FLAME.DAT", 3126, "00898BA4B299BF85278B51932B989B050007226C" },
	{ "JINNEE.DAT", 3568, "39F55DBCD3F670A50D4094F8F1819634DE22B5CF" },
	{ "ROOFTOPS.DAT", 146028, "CEF749707F59A42405A138E06D4EB47266CC45E9" },
	{ "DESERT.DAT", 104211, "1653D628D573B37E2995AB401CB3045171E0D4F3" },
	{ "CAVERNS.DAT", 183189, "C75FE3409BB899A58040DFB7BDD8CE69A0463318" },
	{ "RUINS.DAT", 273461, "28A511F606AD548C1990F6588DCE517072612CFF" },
	{ "TEMPLE.DAT", 116801, "E8F32C5E71925CC4407469E67E5D9CA25ADFD89C" },
	{ "FINAL.DAT", 401268, "BE60A0B430CFFC9D90AC149F459126483A138FE4" },
	{ "TRANS.DAT", 485491, "59EB0DA70BF07FBFBB3E1BFB7ABC7F88496829DD" },
	{ "NIS.DAT", 1083866, "967577AE97BA90EDA9B6978052972FFEDC2E7108" },
	{ "NIS3VC.DAT", 124155, "80B38F4D950D784870DB7337342D2DB8345F6B1F" },
	{ "DIGISND.DAT", 669947, "C85676AF956DF86D81208953F6838C7DDC247E06" },
	{ "MIDISND.DAT", 414088, "78A11A430105E74E7F30D6EA7EDC52F78919A916" },
	{ "IBMSND.DAT", 33142, "5B8B40D3EB2F05176588B32A98CB8366F215981E" },
	{ "NISDIGI.DAT", 1118400, "6970F716575646A56CAB95DD1EE2D907CDCA901F" },
	{ "NISMIDI.DAT", 174611, "77CEF6AE39B138433927B7D41B8905B724FA99D3" },
	{ "NISIBM.DAT", 12168, "EE5D0BDC6ACFF9D26B560BB7C02EABD3C4E1A7DB" },
	{ "PRESETS.DEF", 2049, "AE5547FB0D840EE0AB643FE41046A9289B28F310" },
};
#define POP2_FILE_COUNT ((int)(sizeof k_files / sizeof k_files[0]))

/* The 1993 floppy release's PRINCE.EXE: another build of the program (the
 * tables SDLPoP2 reads are elsewhere in it). Every other file of that release
 * is the CD's, byte for byte. */
#define FLOPPY_PRINCE_EXE_SHA1 "9BDBC04C4DA7443CDA8C4DACD5AD6ADD8BAEA228"

/* ---------------------------------------------------------------- the state */

static struct
{
	shell_input in;
	uint8_t held[POP2_BTN_COUNT];  /* what the previous step held */
	uint8_t want[POP2_BTN_COUNT];  /* what this step holds */
	pop2_settings settings;
	uint64_t frames;               /* VGA frames the program has run */
	uint64_t samples;              /* sound samples rendered through them */
	int step_frames;               /* frames the step just run took */
	int read;                      /* the step read the controls */
	int tick;                      /* a game tick began in this frame */
	int exited;                    /* the program has quit (Ctrl+Q, the copy protection) */
	int audio_n;
	int16_t audio[POP2_AUDIO_MAX_SAMPLES];
	uint32_t video[POP2_VIDEO_WIDTH * POP2_VIDEO_HEIGHT];
} g;

/* ------------------------------------------------------ what the host would be */

/* CONFIG.DAT, as the DOS setup writes it for a keyboard and a Sound Blaster Pro
 * (digitized sounds on card 1, the FM music as MIDI type 0x21). The game reads
 * two things from it: sound on or off (+6), and whether a joystick question
 * gets its "unavailable" message (+8). Each player's own file says what their
 * machine had, so the core does not take it from the project: every project
 * plays the original setup. */
static const uint8_t k_config[32] = {
	0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x21, 0x00, 0xfe, 0xff, 0xfe, 0xff, 0x20, 0x02,
	0xff, 0xff, 0x01, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00,
};

int config_load(pop2_config *c)
{
	for (int i = 0; i < 16; i++) c->w[i] = (int16_t)(k_config[i * 2] | k_config[i * 2 + 1] << 8);
	return 1;
}

/* The files the game writes (PRINCE.SAV, PRINCE.HOF, PRINCE.OPT): in guest
 * memory, as DOS files would be, starting from none. */
#define SAVE_FILES 4
#define SAVE_FILE_MAX 65536
static struct
{
	char name[16];
	long len;
	int used;
	uint8_t data[SAVE_FILE_MAX];
} g_files[SAVE_FILES];

static int file_index(const char *name, int create)
{
	for (int i = 0; i < SAVE_FILES; i++)
		if (g_files[i].used && !strcmp(g_files[i].name, name)) return i;
	if (!create || strlen(name) >= sizeof g_files[0].name) return -1;
	for (int i = 0; i < SAVE_FILES; i++)
	{
		if (g_files[i].used) continue;
		g_files[i].used = 1;
		g_files[i].len = 0;
		strcpy(g_files[i].name, name);
		return i;
	}
	return -1;
}

long file_size(const char *name)
{
	int i = file_index(name, 0);
	return i < 0 ? -1 : g_files[i].len;
}

long file_read(const char *name, long off, void *buf, long n)
{
	int i = file_index(name, 0);
	if (i < 0) return -1;
	if (off < 0 || off >= g_files[i].len || n <= 0) return 0;
	if (n > g_files[i].len - off) n = g_files[i].len - off;
	memcpy(buf, g_files[i].data + off, (size_t)n);
	return n;
}

int file_write_at(const char *name, long off, const void *buf, long n, int create)
{
	int i = file_index(name, create);
	if (i < 0 || off < 0 || n < 0 || off + n > SAVE_FILE_MAX) return 0;
	if (off > g_files[i].len) memset(g_files[i].data + g_files[i].len, 0, (size_t)(off - g_files[i].len));
	memcpy(g_files[i].data + off, buf, (size_t)n);
	if (off + n > g_files[i].len) g_files[i].len = off + n;
	return 1;
}

int file_create(const char *name, const void *buf, long n)
{
	int i = file_index(name, 1);
	if (i < 0 || n < 0 || n > SAVE_FILE_MAX) return 0;
	memcpy(g_files[i].data, buf, (size_t)n);
	g_files[i].len = n;
	return 1;
}

/* -------------------------------------------------------------------- sound */

extern void (*sound_start_hook)(int), (*sound_stop_hook)(int);   /* source/sound.c */

static void on_sound_start(int n) { audio_request((uint16_t)(10000 + n)); }
static void on_sound_stop(int n) { audio_stop(n == -10000 ? 0 : (uint16_t)(10000 + n)); }
static void on_sound_volume(int v) { audio_volume(v >= 15 ? 15 : v); }   /* the game's 15 = on, 0 = off (Alt+S) */

/* ----------------------------------------------------------------- settings */

typedef struct
{
	const char *name;
	int is_bool;
	const char *section;
	long dflt, lo, hi;
} pop2_setting;

#define BOOL 1
#define INT 0
#define POP2_SETTING(name, kind, section, dflt, lo, hi, display, desc) { #name, kind, section, dflt, lo, hi },
static const pop2_setting k_settings[] = {
#include "settings.inc"
};
#undef POP2_SETTING
#undef BOOL
#undef INT
#define POP2_SETTING_COUNT ((int)(sizeof k_settings / sizeof k_settings[0]))

/* The project's settings that differ from the original's, as SDLPoP2.ini text,
 * through SDLPoP2's own parser. Returns how many there were: with none, no
 * overrides are installed and the game runs its verified original path. */
static int apply_settings(char *err, int errsize)
{
	static char ini[4096];
	int len = 0, changed = 0;
	const char *section = "";
	for (int i = 0; i < POP2_SETTING_COUNT; i++)
	{
		const pop2_setting *st = &k_settings[i];
		long v = st->is_bool ? wbx_setting_bool(st->name, (int)st->dflt) : wbx_setting_long(st->name, st->dflt);
		if (v == st->dflt) continue;
		if (!st->is_bool && (v < st->lo || v > st->hi))
		{
			snprintf(err, (size_t)errsize, "the setting %s is %ld; it goes from %ld to %ld", st->name, v, st->lo, st->hi);
			return -1;
		}
		if (strcmp(section, st->section))
		{
			section = st->section;
			len += snprintf(ini + len, sizeof ini - (size_t)len, "[%s]\n", section);
		}
		if (st->is_bool)
			len += snprintf(ini + len, sizeof ini - (size_t)len, "%s = %s\n", st->name, v ? "true" : "false");
		else
			len += snprintf(ini + len, sizeof ini - (size_t)len, "%s = %ld\n", st->name, v);
		changed++;
	}
	if (!changed) return 0;
	settings_defaults(&g.settings);
	if (settings_parse_text(&g.settings, ini, "the project's settings", NULL) != 0)
	{
		snprintf(err, (size_t)errsize, "SDLPoP2 did not take the project's settings:\n%s", ini);
		return -1;
	}
	pop2_settings_game = &g.settings;
	return changed;
}

/* ---------------------------------------------------------------------- init */

static void on_tick(void) { g.tick = 1; }
extern void (*shell_tick_hook)(void);   /* source/shell.c: where each game tick begins */

static int check_files(char *err, int errsize)
{
	for (int i = 0; i < POP2_FILE_COUNT; i++)
	{
		const pop2_file *f = &k_files[i];
		FILE *fp = fopen(f->name, "rb");
		if (!fp)
		{
			snprintf(err, (size_t)errsize, "Prince of Persia 2 needs %s - add it as the project's firmware.", f->name);
			return 0;
		}
		char hex[41];
		long size = 0;
		int ok = sha1_file(fp, hex, &size);
		fclose(fp);
		if (!ok)
		{
			snprintf(err, (size_t)errsize, "%s could not be read.", f->name);
			return 0;
		}
		if (strcmp(hex, f->sha1))
		{
			if (!strcmp(f->name, "PRINCE.EXE") && !strcmp(hex, FLOPPY_PRINCE_EXE_SHA1))
				snprintf(err, (size_t)errsize,
					"This PRINCE.EXE is the 1993 floppy release's. SDLPoP2 is rebuilt from the Prince of Persia "
					"Collection CD's (1.0, %ld bytes), which is another build of the program; every other file of the "
					"floppy release is the same as the CD's.", f->size);
			else
				snprintf(err, (size_t)errsize,
					"%s is not Prince of Persia 2 1.0's, as the Prince of Persia Collection CD has it: %ld bytes, "
					"SHA-1 %s; that release's is %ld bytes, SHA-1 %s.", f->name, size, hex, f->size, f->sha1);
			return 0;
		}
	}
	return 1;
}

/* The project's "savegame" slot: a PRINCE.SAV the game finds as if it had
 * written it, so a run can start from a saved game (Alt+L restores it). */
static int load_savegame(char *err, int errsize)
{
	char name[512];
	if (!wbx_slot_first("savegame", name, sizeof name)) return 1;
	FILE *f = fopen(name, "rb");
	if (!f)
	{
		snprintf(err, (size_t)errsize, "the saved game %s could not be opened", name);
		return 0;
	}
	static uint8_t buf[SAVE_FILE_MAX];
	const long n = (long)fread(buf, 1, sizeof buf, f);
	const int more = fgetc(f) != EOF;
	fclose(f);
	if (n <= 0 || more || !file_create("PRINCE.SAV", buf, n))
	{
		snprintf(err, (size_t)errsize, "%s is not a Prince of Persia 2 saved game (PRINCE.SAV)", name);
		return 0;
	}
	return 1;
}

int pop2drv_init(char *err, int errsize)
{
	memset(&g, 0, sizeof g);
	memset(g_files, 0, sizeof g_files);
	if (!check_files(err, errsize)) return 0;
	if (apply_settings(err, errsize) < 0) return 0;
	if (!load_savegame(err, errsize)) return 0;

	/* the cheat word on the DOS command line, which the game reads as the
	 * original did: it also lets Alt+N skip past level 3 and the debug keys */
	static const char *words[] = { "yippeeyahoo" };
	const int cheats = wbx_setting_bool("cheats", 0);
	const uint32_t seed = (uint32_t)(wbx_setting_long("random_seed", 0) & 0xFFFFFFFFl);

	/* the original setup's sound: the digitized sounds and the FM music, as the
	 * DOS program played them on a Sound Blaster Pro */
	if (!audio_init(".", SOUND_DEVICE_FM_DIGITAL))
	{
		snprintf(err, (size_t)errsize, "SDLPoP2 could not load the sound files.");
		return 0;
	}
	audio_add_file("./NISDIGI.DAT");
	audio_add_file("./NISMIDI.DAT");
	audio_volume(15);
	sound_start_hook = on_sound_start;
	sound_stop_hook = on_sound_stop;
	platform_sound_volume_hook = on_sound_volume;

	shell_tick_hook = on_tick;
	shell_set_seed(seed);
	if (!shell_init(".", cheats ? 1 : 0, words))
	{
		snprintf(err, (size_t)errsize, "SDLPoP2 could not load the game.");
		return 0;
	}
	return 1;
}

/* --------------------------------------------------------------------- input */

/* the PC scan code (set 1) and the character each button types */
static const uint8_t k_scan[POP2_BTN_COUNT] = {
	[POP2_BTN_UP] = 0x48, [POP2_BTN_DOWN] = 0x50, [POP2_BTN_LEFT] = 0x4B, [POP2_BTN_RIGHT] = 0x4D,
	[POP2_BTN_SHIFT] = 0x2A, [POP2_BTN_CTRL] = 0x1D, [POP2_BTN_ENTER] = 0x1C, [POP2_BTN_SPACE] = 0x39,
	[POP2_BTN_ESCAPE] = 0x01, [POP2_BTN_TAB] = 0x0F, [POP2_BTN_BACKSPACE] = 0x0E, [POP2_BTN_ALT] = 0x38,
	/* A..Z by their place on the keyboard */
	[POP2_BTN_A + 0] = 0x1E, [POP2_BTN_A + 1] = 0x30, [POP2_BTN_A + 2] = 0x2E, [POP2_BTN_A + 3] = 0x20,
	[POP2_BTN_A + 4] = 0x12, [POP2_BTN_A + 5] = 0x21, [POP2_BTN_A + 6] = 0x22, [POP2_BTN_A + 7] = 0x23,
	[POP2_BTN_A + 8] = 0x17, [POP2_BTN_A + 9] = 0x24, [POP2_BTN_A + 10] = 0x25, [POP2_BTN_A + 11] = 0x26,
	[POP2_BTN_A + 12] = 0x32, [POP2_BTN_A + 13] = 0x31, [POP2_BTN_A + 14] = 0x18, [POP2_BTN_A + 15] = 0x19,
	[POP2_BTN_A + 16] = 0x10, [POP2_BTN_A + 17] = 0x13, [POP2_BTN_A + 18] = 0x1F, [POP2_BTN_A + 19] = 0x14,
	[POP2_BTN_A + 20] = 0x16, [POP2_BTN_A + 21] = 0x2F, [POP2_BTN_A + 22] = 0x11, [POP2_BTN_A + 23] = 0x2D,
	[POP2_BTN_A + 24] = 0x15, [POP2_BTN_A + 25] = 0x2C,
};

static int ascii_of(int b)
{
	switch (b)
	{
	case POP2_BTN_ENTER: return 0x0D;
	case POP2_BTN_SPACE: return 0x20;
	case POP2_BTN_ESCAPE: return 0x1B;
	case POP2_BTN_TAB: return 0x09;
	case POP2_BTN_BACKSPACE: return 0x08;
	default: break;
	}
	if (b >= POP2_BTN_A && b < POP2_BTN_A + 26)
		return (g.want[POP2_BTN_SHIFT] ? 'A' : 'a') + (b - POP2_BTN_A);
	return 0;   /* the arrows and the modifiers type their scan code (shell_input_key) */
}

void pop2drv_set_button(int index, int down)
{
	if (index >= 0 && index < POP2_BTN_COUNT) g.want[index] = down ? 1 : 0;
}

/* A button held is a key held down, and one pressed since the last step is
 * that key going down - which is when DOS typed it. The modifiers go first,
 * so a letter pressed with Alt held is Alt+letter. There is no key repeat: a
 * movie that wants a key typed twice presses it twice. */
static void apply_buttons(void)
{
	static const int k_order_first[] = { POP2_BTN_SHIFT, POP2_BTN_CTRL, POP2_BTN_ALT };
	for (int pass = 0; pass < 2; pass++)
	{
		for (int b = 0; b < POP2_BTN_COUNT; b++)
		{
			const int modifier = b == k_order_first[0] || b == k_order_first[1] || b == k_order_first[2];
			if (modifier != (pass == 0) || g.want[b] == g.held[b]) continue;
			shell_input_key(&g.in, k_scan[b], g.want[b], g.want[b] ? ascii_of(b) : 0);
			g.held[b] = g.want[b];
		}
	}
}

/* ------------------------------------------------------------------ the step */

static void one_frame(void)
{
	g.tick = 0;
	if (shell_step(&g.in) == SHELL_EXIT) g.exited = 1;
	g.in.ntyped = 0;   /* (what was typed has been handed over) */
	g.frames++;
	/* the sound of exactly the time this frame covers, in whole samples */
	const uint64_t upto = g.frames * (uint64_t)POP2_AUDIO_RATE * POP2_FRAME_RATE_DEN / POP2_FRAME_RATE_NUM;
	int n = (int)(upto - g.samples);
	g.samples = upto;
	if (g.audio_n + n <= POP2_AUDIO_MAX_SAMPLES)
	{
		audio_render(g.audio + g.audio_n, n, POP2_AUDIO_RATE);
		g.audio_n += n;
	}
	else
	{
		static int16_t spill[2048];
		audio_render(spill, n, POP2_AUDIO_RATE);   /* played, not handed out */
	}
}

void pop2drv_frame(int render)
{
	gamestate_to_game();
	apply_buttons();
	g.audio_n = 0;
	g.read = 0;
	g.step_frames = 0;
	while (!g.exited && g.step_frames < POP2_MAX_FRAMES_PER_STEP)
	{
		one_frame();
		g.step_frames++;
		/* while playing the step runs to the tick that reads the controls;
		 * anywhere else the program reads its keys every frame */
		if (g.tick || shell_mode() != SH_PLAY)
		{
			g.read = 1;
			break;
		}
	}
	if (g.step_frames == 0) g.step_frames = 1;   /* the program has quit: a frame of nothing */
	gamestate_from_game();

	if (render)
	{
		for (int i = 0; i < POP2_VIDEO_WIDTH * POP2_VIDEO_HEIGHT; i++)
		{
			const uint8_t *c = &render_palette[screen_buf[i] * 3];
			const uint32_t r = (uint32_t)((c[0] & 63) << 2 | (c[0] & 63) >> 4);
			const uint32_t gr = (uint32_t)((c[1] & 63) << 2 | (c[1] & 63) >> 4);
			const uint32_t b = (uint32_t)((c[2] & 63) << 2 | (c[2] & 63) >> 4);
			g.video[i] = 0xFF000000u | r << 16 | gr << 8 | b;
		}
	}
}

const uint32_t *pop2drv_video(void) { return g.video; }

const int16_t *pop2drv_audio(int *samples)
{
	*samples = g.audio_n;
	return g.audio;
}

int pop2drv_input_was_read(void) { return g.read; }

void pop2drv_vsync(int *num, int *den)
{
	*num = POP2_FRAME_RATE_NUM;
	*den = POP2_FRAME_RATE_DEN * (g.step_frames > 0 ? g.step_frames : 1);
}

uint64_t pop2drv_frames(void) { return g.frames; }
