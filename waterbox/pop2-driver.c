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
 * options) live in guest memory, so a savestate carries them. The music is the
 * Sound Blaster Pro's FM chip, or a Roland MT-32 (Munt's libmt32emu, in guest
 * memory too) fed the bytes SDLPoP2's MPU-401 driver sends it.
 */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <emulibc.h>
#include <waterbox_settings.h>
#include <waterbox_slots.h>

#include "pop2-driver.h"
#include "sha1.h"

/* the MT-32: Munt's libmt32emu, through its C API */
#define MT32EMU_API_TYPE 1
#include <mt32emu.h>

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

/* The Roland MT-32's, when the music is the MT-32's (the music setting): the
 * setup's MIDI piece of the MT-32's timbres, which the DOS setup copies to
 * PRESETS.DEF for that device (both releases' SNDDRVRS\PRESET40.DEF), and the
 * MT-32's two ROMs - v1.07, the first generation (the DOSBox-X core's firmware
 * ids and hashes). The FM instruments' PRESETS.DEF above stays: the story
 * scenes' timing is the FM driver's whatever plays the music (nis.c). */
static const pop2_file k_roland_files[] = {
	{ "PRESET40.DEF", 20715, "951F5F9A340F41C128C232AD0CB31329A1722345" },
	{ "MT32_CONTROL.ROM", 65536, "B083518FFFB7F66B03C23B7EB4F868E62DC5A987" },
	{ "MT32_PCM.ROM", 524288, "F6B1EEBC4B2D200EC6D3D21D51325D5B48C60252" },
};
#define POP2_ROLAND_FILE_COUNT ((int)(sizeof k_roland_files / sizeof k_roland_files[0]))

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
	int shift_down, alt_down;      /* the modifier keys the buttons hold down */
	int cheats;                    /* the program started with its cheat word */
	int action_pressed;            /* P1 Shift went down in this step (the copy protection) */
	char player_name[64];          /* the hall of fame's name for a won game */
	pop2_settings settings;
	uint64_t frames;               /* VGA frames the program has run */
	uint64_t samples;              /* sound samples rendered through them */
	int step_frames;               /* frames the step just run took */
	int read;                      /* the step read the controls */
	int tick;                      /* a game tick began in this frame */
	int exited;                    /* the program has quit (Ctrl+Q, the copy protection) */
	int roland;                    /* the music is the MT-32's */
	uint64_t midi_bytes, midi_hash; /* what the MT-32 was sent, with its times (the gate's) */
	int audio_n;                   /* stereo frames in audio */
	int16_t audio[2 * POP2_AUDIO_MAX_SAMPLES];
	uint32_t video[POP2_VIDEO_WIDTH * POP2_VIDEO_HEIGHT];
} g;

/* ------------------------------------------------------ what the host would be */

/* CONFIG.DAT, as the DOS setup writes it for a keyboard and a Sound Blaster Pro
 * (digitized sounds on card 1, the FM music as MIDI type 0x21; with the MT-32,
 * MIDI type 0x28 on the MPU-401 at its default port and IRQ). The game reads
 * two things from it: sound on or off (+6), and whether a joystick question
 * gets its "unavailable" message (+8, only for type 0x20). Each player's own
 * file says what their machine had, so the core does not take it from the
 * project: every project plays the original setup. */
static const uint8_t k_config[32] = {
	0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x21, 0x00, 0xfe, 0xff, 0xfe, 0xff, 0x20, 0x02,
	0xff, 0xff, 0x01, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00,
};

int config_load(pop2_config *c)
{
	for (int i = 0; i < 16; i++) c->w[i] = (int16_t)(k_config[i * 2] | k_config[i * 2 + 1] << 8);
	if (g.roland) c->w[4] = AUDIO_MIDI_MT32;
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

/* the MT-32, when the music is the MT-32's (below) */
static mt32emu_context g_mt32;

/* SDLPoP2's MPU-401 driver hands every byte it sends the MT-32 over with its
 * time in the sound's samples since the init; the MT-32 takes each at that
 * time and plays it into the samples the frame renders next (one_frame) */
static mt32emu_report_handler_version MT32EMU_C_CALL mt32_version(mt32emu_report_handler_i i)
{
	(void)i;
	return MT32EMU_REPORT_HANDLER_VERSION_0;
}
/* what Munt would print (its LCD's messages, the sequencer's sysex for the FM
 * device, which the original also hands the MPU-401 and the MT-32 ignores): to
 * nobody - the guest's console is the frontend's */
static void MT32EMU_C_CALL mt32_debug(void *instance, const char *fmt, va_list list) { (void)instance; (void)fmt; (void)list; }
static void MT32EMU_C_CALL mt32_lcd(void *instance, const char *message) { (void)instance; (void)message; }
static const mt32emu_report_handler_i_v0 k_mt32_reports = { .getVersionID = mt32_version, .printDebug = mt32_debug, .showLCDMessage = mt32_lcd };

static long read_all(const char *name, uint8_t **data)
{
	FILE *f = fopen(name, "rb");
	if (!f) return -1;
	fseek(f, 0, SEEK_END);
	const long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	*data = n > 0 ? malloc((size_t)n) : NULL;
	const long got = *data ? (long)fread(*data, 1, (size_t)n, f) : -1;
	fclose(f);
	return got == n ? n : -1;
}

static int mt32_open(char *err, int errsize)
{
	mt32emu_report_handler_i reports = { &k_mt32_reports };
	g_mt32 = mt32emu_create_context(reports, NULL);
	static const char *const roms[] = { "MT32_CONTROL.ROM", "MT32_PCM.ROM" };
	for (int i = 0; i < 2; i++)
	{
		uint8_t *data;
		const long n = read_all(roms[i], &data);
		/* Munt keeps the data as given, it does not copy it: the buffers live
		 * as long as the machine */
		if (n < 0 || mt32emu_add_rom_data(g_mt32, data, (size_t)n, NULL) < 0)
		{
			snprintf(err, (size_t)errsize, "the MT-32 did not take %s", roms[i]);
			return 0;
		}
	}
	mt32emu_set_stereo_output_samplerate(g_mt32, POP2_AUDIO_RATE);
	if (mt32emu_open_synth(g_mt32) != MT32EMU_RC_OK)
	{
		snprintf(err, (size_t)errsize, "the MT-32 could not start");
		return 0;
	}
	return 1;
}

static void on_midi(uint8_t byte, uint64_t sample)
{
	/* FNV-1a over each byte and its time: what the gate holds natively and
	 * sandboxed, since the MT-32's own sound differs by its libm */
	const uint8_t rec[9] = { byte, (uint8_t)sample, (uint8_t)(sample >> 8), (uint8_t)(sample >> 16), (uint8_t)(sample >> 24),
		(uint8_t)(sample >> 32), (uint8_t)(sample >> 40), (uint8_t)(sample >> 48), (uint8_t)(sample >> 56) };
	for (int i = 0; i < 9; i++) g.midi_hash = (g.midi_hash ^ rec[i]) * 0x100000001B3ull;
	g.midi_bytes++;
	mt32emu_parse_stream_at(g_mt32, &byte, 1, mt32emu_convert_output_to_synth_timestamp(g_mt32, (mt32emu_bit32u)sample));
}

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

static int check_files(const pop2_file *files, int count, char *err, int errsize)
{
	for (int i = 0; i < count; i++)
	{
		const pop2_file *f = &files[i];
		FILE *fp = fopen(f->name, "rb");
		if (!fp)
		{
			snprintf(err, (size_t)errsize, "Prince of Persia 2 needs %s%s - add it as the project's firmware.", f->name,
				files == k_roland_files ? " for the Roland MT-32's music" : "");
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
			else if (files == k_roland_files)
				snprintf(err, (size_t)errsize,
					"%s is not the Roland MT-32's %s: %ld bytes, SHA-1 %s; that is %ld bytes, SHA-1 %s.", f->name,
					!strcmp(f->name, "PRESET40.DEF") ? "timbres as Prince of Persia 2's setup has them (SNDDRVRS\\PRESET40.DEF)"
					: !strcmp(f->name, "MT32_CONTROL.ROM") ? "control ROM, v1.07" : "PCM ROM",
					size, hex, f->size, f->sha1);
			else
				snprintf(err, (size_t)errsize,
					"%s is not Prince of Persia 2 1.0's, as the Prince of Persia Collection CD has it: %ld bytes, "
					"SHA-1 %s; that release's is %ld bytes, SHA-1 %s.", f->name, size, hex, f->size, f->sha1);
			return 0;
		}
	}
	return 1;
}

/* the hall of fame as the game last wrote it (PRINCE.HOF), for the property
 * table: none until a won game enters a name */
long pop2drv_hof(uint8_t *buf, long max)
{
	const int i = file_index("PRINCE.HOF", 0);
	if (i < 0) return 0;
	const long n = g_files[i].len < max ? g_files[i].len : max;
	memcpy(buf, g_files[i].data, (size_t)n);
	return n;
}

/* patch 0002's hooks: the hall of fame's name (the player_name setting), and
 * the action button choosing the copy protection's symbol - pressed in this
 * step, taken once */
const char *hof_given_name(void) { return g.player_name; }
int cp_action_pressed(void)
{
	const int r = g.action_pressed;
	g.action_pressed = 0;
	return r;
}

int pop2drv_init(char *err, int errsize)
{
	memset(&g, 0, sizeof g);
	memset(g_files, 0, sizeof g_files);
	g.midi_hash = 0xCBF29CE484222325ull;
	/* the music: a Roland MT-32 on an MPU-401 (the default, user-decided
	 * 2026-09-29), or the Sound Blaster Pro's FM chip, as the original setup */
	char music[16];
	if (wbx_setting_str("music", music, sizeof music) < 0) strcpy(music, "roland");
	if (!strcmp(music, "roland")) g.roland = 1;
	else if (strcmp(music, "fm"))
	{
		snprintf(err, (size_t)errsize, "the music setting is %s; it is fm or roland", music);
		return 0;
	}
	if (!check_files(k_files, POP2_FILE_COUNT, err, errsize)) return 0;
	if (g.roland && !check_files(k_roland_files, POP2_ROLAND_FILE_COUNT, err, errsize)) return 0;
	if (apply_settings(err, errsize) < 0) return 0;
	/* the name a won game enters in the hall of fame: the game takes the
	 * printable characters, and wants at least one */
	if (wbx_setting_str("player_name", g.player_name, sizeof g.player_name) < 0) strcpy(g.player_name, "Chimera");
	int printable = 0;
	for (const char *c = g.player_name; *c; c++) printable |= *c > 0x20 && *c < 0x7F;
	if (!printable)
	{
		snprintf(err, (size_t)errsize, "the Player Name (Hall of Fame) setting has nothing the game can show - give it a name");
		return 0;
	}

	/* the cheat word on the DOS command line, which the game reads as the
	 * original did: it also lets Alt+N skip past level 3 and the debug keys */
	static const char *words[] = { "yippeeyahoo" };
	const int cheats = g.cheats = wbx_setting_bool("cheats", 0) != 0;
	/* the in-game time from the start of level 1, the ticks before the game's
	 * clock started included (game-state.c); nothing in play changes */
	gamestate_igt_from_level_1(wbx_setting_bool("igt_from_level_1", 1) != 0);
	const uint32_t seed = (uint32_t)(wbx_setting_long("random_seed", 0) & 0xFFFFFFFFl);

	/* the original setup's sound: the digitized sounds and the FM music, as the
	 * DOS program played them on a Sound Blaster Pro - or the music on an
	 * MT-32, whose timbres the start-up sends it first and waits for (9.35 s),
	 * as the original did (shell_sound_setup_hook) */
	if (g.roland && !mt32_open(err, errsize)) return 0;
	audio_midi_out = g.roland ? on_midi : NULL;
	if (!audio_init_midi(".", SOUND_DEVICE_FM_DIGITAL, g.roland ? AUDIO_MIDI_MT32 : AUDIO_MIDI_FM, g.roland ? "PRESET40.DEF" : NULL))
	{
		snprintf(err, (size_t)errsize, "SDLPoP2 could not load the sound files.");
		return 0;
	}
	if (g.roland && !audio_setup_playing())
	{
		snprintf(err, (size_t)errsize, "SDLPoP2 did not take PRESET40.DEF as the MT-32's timbres.");
		return 0;
	}
	audio_add_scene_files(".");
	audio_volume(15);
	shell_sound_setup_hook = audio_setup_playing;
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
/* What each button is on the DOS keyboard: the key's scan code, the character
 * it types (a letter follows Shift, as the keyboard's does), and the modifiers
 * held with it. Shift and Ctrl are the keys themselves. */
enum { MOD_SHIFT = 1, MOD_ALT = 2 };
static const struct { uint8_t scan; char ascii; uint8_t mods; } k_keys[POP2_BTN_COUNT] = {
	[POP2_BTN_UP] = { 0x48, 0, 0 }, [POP2_BTN_DOWN] = { 0x50, 0, 0 },
	[POP2_BTN_LEFT] = { 0x4B, 0, 0 }, [POP2_BTN_RIGHT] = { 0x4D, 0, 0 },
	[POP2_BTN_SHIFT] = { 0x2A, 0, 0 }, [POP2_BTN_CTRL] = { 0x1D, 0, 0 },
	[POP2_BTN_PAUSE] = { 0x01, 0x1B, 0 }, [POP2_BTN_SHOW_TIME] = { 0x39, 0x20, 0 },
	[POP2_BTN_RESTART_LEVEL] = { 0x1E, 'a', MOD_ALT }, [POP2_BTN_RESTART_GAME] = { 0x13, 'r', MOD_ALT },
	[POP2_BTN_NEXT_LEVEL] = { 0x31, 'n', MOD_ALT }, [POP2_BTN_SOUND_ON_OFF] = { 0x1F, 's', MOD_ALT },
	[POP2_BTN_MUSIC_ON_OFF] = { 0x32, 'm', MOD_ALT }, [POP2_BTN_VERSION] = { 0x2F, 'v', MOD_ALT },
	[POP2_BTN_JOYSTICK_MODE] = { 0x24, 'j', MOD_ALT }, [POP2_BTN_KEYBOARD_MODE] = { 0x25, 'k', MOD_ALT },
	[POP2_BTN_CHEAT_LOSE_HIT_POINT] = { 0x25, 'k', MOD_SHIFT }, [POP2_BTN_CHEAT_OPPONENT_HIT_POINT] = { 0x22, 'g', 0 },
	[POP2_BTN_CHEAT_KILL_ROOM] = { 0x25, 'k', 0 }, [POP2_BTN_CHEAT_SPIRIT_LEAVES] = { 0x1F, 's', MOD_SHIFT },
	[POP2_BTN_CHEAT_MORE_TIME] = { 0x4E, '+', 0 }, [POP2_BTN_CHEAT_LESS_TIME] = { 0x4A, '-', 0 },
	[POP2_BTN_CHEAT_FLIP_SCREEN] = { 0x17, 'i', MOD_SHIFT }, [POP2_BTN_CHEAT_SHOW_ROOM] = { 0x13, 'r', MOD_SHIFT },
	[POP2_BTN_CHEAT_ADD_MAX_HIT_POINT] = { 0x14, 't', MOD_SHIFT }, [POP2_BTN_CHEAT_FEATHER_FALL] = { 0x11, 'w', MOD_SHIFT },
	[POP2_BTN_CHEAT_REVIVE] = { 0x13, 'r', 0 }, [POP2_BTN_CHEAT_DEMO_PLAYER] = { 0x3D, 0, 0 },
	[POP2_BTN_CHEAT_GOD_MODE] = { 0x22, 'g', MOD_SHIFT }, [POP2_BTN_CHEAT_LEAVE_BODY] = { 0x23, 'h', 0 },
	[POP2_BTN_CHEAT_LEAVE_BODY_FLAME] = { 0x30, 'b', 0 }, [POP2_BTN_CHEAT_SWORD] = { 0x2C, 'z', 0 },
	[POP2_BTN_CHEAT_LOOK_LEFT] = { 0x4B, 0, MOD_ALT }, [POP2_BTN_CHEAT_LOOK_RIGHT] = { 0x4D, 0, MOD_ALT },
	[POP2_BTN_CHEAT_LOOK_UP] = { 0x48, 0, MOD_ALT }, [POP2_BTN_CHEAT_LOOK_DOWN] = { 0x50, 0, MOD_ALT },
	[POP2_BTN_CHEAT_TELEPORT] = { 0x14, 't', 0 }, [POP2_BTN_CHEAT_FLY] = { 0x1E, 'a', 0 },
};

int pop2drv_button_active(int index)
{
	if (index < 0 || index >= POP2_BTN_COUNT) return 0;
	return index < POP2_BTN_CHEAT_FIRST || g.cheats;
}

void pop2drv_set_button(int index, int down)
{
	if (pop2drv_button_active(index)) g.want[index] = down ? 1 : 0;
}

static void key(int scan, int down, int ascii) { shell_input_key(&g.in, scan, down, down ? ascii : 0); }

/* whether a modifier is still wanted by a held button */
static int mod_held(int mod)
{
	if (mod == MOD_SHIFT && g.held[POP2_BTN_SHIFT]) return 1;
	for (int b = 0; b < POP2_BTN_COUNT; b++)
		if (g.held[b] && (k_keys[b].mods & mod)) return 1;
	return 0;
}

/* whether another held button holds the same key (P1 Left and Look Left are
 * both the left arrow): the keyboard has one of each */
static int key_held_by_other(int self)
{
	for (int b = 0; b < POP2_BTN_COUNT; b++)
		if (b != self && g.held[b] && k_keys[b].scan == k_keys[self].scan) return 1;
	return 0;
}

/* The buttons that changed, as the keys the keyboard interrupt would have
 * seen: Shift and Ctrl first, then the rest in the panel's order. A command's
 * modifiers are real keys, put down before its key and lifted after unless
 * another held button still holds them; a key two buttons share is down with
 * the first and up with the last. A letter types its capital while Shift is
 * down. */
static void apply_buttons(void)
{
	for (int pass = 0; pass < 2; pass++)
	{
		for (int b = 0; b < POP2_BTN_COUNT; b++)
		{
			const int modifier = b == POP2_BTN_SHIFT || b == POP2_BTN_CTRL;
			if (modifier != (pass == 0) || g.want[b] == g.held[b]) continue;
			const int down = g.want[b];
			g.held[b] = g.want[b];
			if (b == POP2_BTN_SHIFT)
			{
				if (down) g.action_pressed = 1;
				if (down && !g.shift_down) { g.shift_down = 1; key(0x2A, 1, 0); }
				if (!down && g.shift_down && !mod_held(MOD_SHIFT)) { g.shift_down = 0; key(0x2A, 0, 0); }
				continue;
			}
			const int mods = k_keys[b].mods;
			if (down)
			{
				if ((mods & MOD_SHIFT) && !g.shift_down) { g.shift_down = 1; key(0x2A, 1, 0); }
				if ((mods & MOD_ALT) && !g.alt_down) { g.alt_down = 1; key(0x38, 1, 0); }
				int ascii = k_keys[b].ascii;
				if (ascii >= 'a' && ascii <= 'z' && g.shift_down) ascii -= 'a' - 'A';
				if (!key_held_by_other(b)) key(k_keys[b].scan, 1, ascii);
			}
			else
			{
				if (!key_held_by_other(b)) key(k_keys[b].scan, 0, 0);
				if (g.alt_down && !mod_held(MOD_ALT)) { g.alt_down = 0; key(0x38, 0, 0); }
				if (g.shift_down && !mod_held(MOD_SHIFT)) { g.shift_down = 0; key(0x2A, 0, 0); }
			}
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
	/* the sound of exactly the time this frame covers, in whole samples: the
	 * card's mono on both sides, and the MT-32's stereo added to it (the MIDI
	 * bytes of the frame are in by now: the program's own, sent before the
	 * frame's sound, and the music timer's, sent while it is rendered) */
	const uint64_t upto = g.frames * (uint64_t)POP2_AUDIO_RATE * POP2_FRAME_RATE_DEN / POP2_FRAME_RATE_NUM;
	const int n = (int)(upto - g.samples);
	g.samples = upto;
	static int16_t mono[1024], mt[2 * 1024], spill[2 * 1024];
	audio_render(mono, n, POP2_AUDIO_RATE);
	/* past the step's room it is played, not handed out */
	int16_t *out = g.audio_n + n <= POP2_AUDIO_MAX_SAMPLES ? g.audio + 2 * g.audio_n : spill;
	for (int k = 0; k < n; k++) out[2 * k] = out[2 * k + 1] = mono[k];
	if (g_mt32)
	{
		mt32emu_render_bit16s(g_mt32, mt, (mt32emu_bit32u)n);
		for (int k = 0; k < 2 * n; k++)
		{
			const int v = out[k] + mt[k];
			out[k] = (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v);
		}
	}
	if (out != spill) g.audio_n += n;
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
	g.action_pressed = 0;   /* (a press is for the step it came in) */
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

uint64_t pop2drv_midi(uint64_t *bytes)
{
	*bytes = g.midi_bytes;
	return g.midi_hash;
}
