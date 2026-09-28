/* game-state.c - Prince of Persia 2's properties (chimera docs/game-cores.md).
 *
 * The game keeps most of what a run is about in records that lie whole in
 * memory, as the DOS program's data segment had them: the prince's own record
 * (Kid), the five character slots of the room being played (chars), the level
 * (every room's tiles, their attributes, the characters each room starts with),
 * the moving floors (mobs) and the tile animations (trobs). Those are domains
 * in place, read and written where the game has them. What is scattered in
 * single variables - the level number, the time left, the random seed - is
 * gathered into the Game State block after every step and put back before the
 * next, so a poke or a freeze of one reaches the game at the next step.
 */
#include <stdio.h>
#include <string.h>

#include "pop2-driver.h"

#include "globals.h"
#include "types.h"

extern uint16_t minutes_left, clock_ticks, frame_delay;   /* game.c */

/* ------------------------------------------------------ the Game State block */

#pragma pack(push, 1)
typedef struct
{
	uint8_t level;          /* +0 level_number */
	uint8_t drawn_room;     /* +1 the room on the screen */
	uint16_t minutes_left;  /* +2 */
	uint16_t clock_ticks;   /* +4 ticks left of the current minute */
	uint32_t random_seed;   /* +6 */
	uint32_t tick;          /* +10 game ticks run */
	uint16_t frame_delay;   /* +14 */
	uint16_t mob_count;     /* +16 */
	uint16_t trob_count;    /* +18 */
} game_state;
#pragma pack(pop)

static game_state g_state;

void gamestate_from_game(void)
{
	g_state.level = level_number;
	g_state.drawn_room = drawn_room;
	g_state.minutes_left = minutes_left;
	g_state.clock_ticks = clock_ticks;
	g_state.random_seed = random_seed;
	g_state.tick = tick;
	g_state.frame_delay = frame_delay;
	g_state.mob_count = mob_count;
	g_state.trob_count = trob_count;
}

/* only what a person may set goes back (the table marks the rest read-only) */
void gamestate_to_game(void)
{
	minutes_left = g_state.minutes_left;
	clock_ticks = g_state.clock_ticks;
	random_seed = g_state.random_seed;
	frame_delay = g_state.frame_delay;
}

/* ------------------------------------------------------------------ domains */

typedef struct
{
	const char *name;
	uint8_t *ptr;
	int64_t size;
} domain;

static domain g_domains[6];
static int g_ndomains;

static void domains_init(void)
{
	if (g_ndomains) return;
	g_domains[g_ndomains++] = (domain){ "Game State", (uint8_t *)&g_state, sizeof g_state };
	g_domains[g_ndomains++] = (domain){ "Kid", (uint8_t *)&Kid, sizeof Kid };
	g_domains[g_ndomains++] = (domain){ "Characters", (uint8_t *)chars, sizeof chars };
	g_domains[g_ndomains++] = (domain){ "Level", (uint8_t *)&level, sizeof level };
	g_domains[g_ndomains++] = (domain){ "Mobs", (uint8_t *)mobs, sizeof mobs };
	g_domains[g_ndomains++] = (domain){ "Trobs", (uint8_t *)trobs, sizeof trobs };
}

int pop2drv_domain_count(void)
{
	domains_init();
	return g_ndomains;
}

const char *pop2drv_domain_name(int i)
{
	domains_init();
	return i >= 0 && i < g_ndomains ? g_domains[i].name : "";
}

uint8_t *pop2drv_domain_ptr(int i)
{
	domains_init();
	return i >= 0 && i < g_ndomains ? g_domains[i].ptr : NULL;
}

int64_t pop2drv_domain_size(int i)
{
	domains_init();
	return i >= 0 && i < g_ndomains ? g_domains[i].size : 0;
}

int pop2drv_domain_writable(int i) { return i >= 0 && i < pop2drv_domain_count(); }

/* -------------------------------------------------------------------- table */

static char g_table[160 * 1024];
static int g_len;

static void add(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
#include <stdarg.h>
static void add(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(g_table + g_len, sizeof g_table - (size_t)g_len, fmt, ap);
	va_end(ap);
	if (n > 0) g_len += n;
}

/* one property: name, domain, offset, type, group, extra JSON members (or "") */
static int g_first = 1;
static void prop(const char *name, const char *dom, long off, const char *type, const char *group, const char *extra)
{
	add("%s\n    { \"name\": \"%s\", \"domain\": \"%s\", \"offset\": %ld, \"type\": \"%s\", \"group\": \"%s\"%s%s }",
		g_first ? "" : ",", name, dom, off, type, group, extra[0] ? ", " : "", extra);
	g_first = 0;
}

/* the fields of a character record (types.h char_type), for the prince's own
 * record and as arrays over the five slots */
static void char_fields(const char *prefix, const char *dom, const char *group, const char *arr)
{
	char name[96], extra[256];
#define F(label, off, type, more)                                                        \
	do                                                                                   \
	{                                                                                    \
		snprintf(name, sizeof name, "%s.%s", prefix, label);                             \
		snprintf(extra, sizeof extra, "%s%s%s", arr, arr[0] && (more)[0] ? ", " : "", more); \
		prop(name, dom, off, type, group, extra);                                        \
	} while (0)
	F("X", 2, "s16", "\"description\": \"Across the screen, in the game's units\"");
	F("Y", 4, "s16", "\"description\": \"Down the screen, in the game's units\"");
	F("Direction", 1, "s8", "\"values\": { \"-1\": \"Left\", \"0\": \"Right\" }");
	F("Frame", 7, "u16", "\"description\": \"The animation frame shown (PoP1's numbering)\"");
	F("Column", 9, "s8", "");
	F("Row", 10, "s8", "");
	F("Action", 11, "u8", "");
	F("Fall X", 12, "s8", "");
	F("Fall Y", 13, "s8", "");
	F("Room", 14, "u8", "");
	F("Alive", 17, "s8", "\"description\": \"Below 0 while alive; counts up once dying\"");
	F("HP", 18, "u8", "\"description\": \"Hit points\"");
	F("Max HP", 19, "u8", "\"description\": \"The hit points a full potion gives back to\"");
	F("HP Delta", 20, "s8", "\"description\": \"A pending change of hit points\"");
	F("Sequence Position", 21, "u16", "");
	F("Sequence", 23, "u16", "\"description\": \"The animation sequence playing\"");
	F("Character Id", 6, "u8", "");
#undef F
}

static void table_init(void)
{
	if (g_len) return;
	char name[96];
	add("{ \"properties\": [");

	/* the Game State block */
	prop("Level", "Game State", 0, "u8", "Game", "\"writable\": false, \"description\": \"The level being played\"");
	prop("Drawn Room", "Game State", 1, "u8", "Game", "\"writable\": false, \"description\": \"The room on the screen\"");
	prop("Minutes Left", "Game State", 2, "u16", "Game", "");
	prop("Ticks Left", "Game State", 4, "u16", "Game", "\"description\": \"Game ticks left of the current minute (719 a minute)\"");
	prop("Random Seed", "Game State", 6, "u32", "Game", "");
	prop("Tick", "Game State", 10, "u32", "Game", "\"writable\": false, \"description\": \"Game ticks run\"");
	prop("Frame Delay", "Game State", 14, "u16", "Game", "\"description\": \"1/60 s between this tick and the next (5 walking, 6 fighting)\"");
	prop("Mob Count", "Game State", 16, "u16", "Game", "\"writable\": false");
	prop("Trob Count", "Game State", 18, "u16", "Game", "\"writable\": false");

	/* the prince, and the room's five character slots */
	char_fields("Kid", "Kid", "Kid", "");
	char_fields("Chars", "Characters", "Characters", "\"count\": 5, \"stride\": 64");

	/* the level */
	prop("Level.Number", "Level", 0x1847, "u8", "Level", "\"writable\": false");
	prop("Level.Rooms", "Level", 0x1840, "u8", "Level", "\"writable\": false");
	prop("Level.Type", "Level", 0x1866, "u8", "Level", "\"writable\": false");
	prop("Level.Start Room", "Level", 0x1860, "u8", "Level", "");
	prop("Level.Start Tile", "Level", 0x1861, "u8", "Level", "\"description\": \"Column + 10 x row\"");
	prop("Level.Start Direction", "Level", 0x1862, "s8", "Level", "\"values\": { \"-1\": \"Left\", \"0\": \"Right\" }");
	for (int room = 1; room <= 28; room++)
	{
		char group[32];
		snprintf(group, sizeof group, "Room %d", room);
		const long rec = 0x1867 + (long)(room - 1) * 0x74;
		snprintf(name, sizeof name, "Room %d.Tiles", room);
		prop(name, "Level", (long)(room - 1) * 30, "u8", group, "\"count\": 30, \"description\": \"Row by row, 10 to a row\"");
		snprintf(name, sizeof name, "Room %d.Attributes", room);
		prop(name, "Level", 0x348 + (long)room * 30 * 4, "u32", group, "\"count\": 30");
		snprintf(name, sizeof name, "Room %d.Characters", room);
		prop(name, "Level", rec, "u8", group, "\"description\": \"How many characters the room starts with\"");
		static const struct { const char *label; long off; const char *type; } k_init[] = {
			{ "Tile Position", 0, "s8" }, { "X", 1, "s16" }, { "Direction", 3, "s8" }, { "Sequence", 5, "u16" },
			{ "HP", 12, "u8" }, { "Type", 15, "u8" }, { "Max HP", 16, "u8" },
		};
		for (size_t k = 0; k < sizeof k_init / sizeof k_init[0]; k++)
		{
			snprintf(name, sizeof name, "Room %d.Char %s", room, k_init[k].label);
			prop(name, "Level", rec + 1 + k_init[k].off, k_init[k].type, group, "\"count\": 5, \"stride\": 23");
		}
	}

	/* the moving floors and the tile animations */
	prop("Mobs.X", "Mobs", 0, "s16", "Mobs", "\"count\": 30, \"stride\": 13");
	prop("Mobs.Y", "Mobs", 2, "s16", "Mobs", "\"count\": 30, \"stride\": 13");
	prop("Mobs.Room", "Mobs", 4, "u8", "Mobs", "\"count\": 30, \"stride\": 13");
	prop("Mobs.Speed", "Mobs", 5, "s16", "Mobs", "\"count\": 30, \"stride\": 13");
	prop("Mobs.Type", "Mobs", 9, "u8", "Mobs", "\"count\": 30, \"stride\": 13");
	prop("Mobs.Row", "Mobs", 10, "u8", "Mobs", "\"count\": 30, \"stride\": 13");
	prop("Trobs.Tile Position", "Trobs", 0, "s8", "Trobs", "\"count\": 20, \"stride\": 4");
	prop("Trobs.Room", "Trobs", 1, "u8", "Trobs", "\"count\": 20, \"stride\": 4");
	prop("Trobs.State", "Trobs", 2, "u8", "Trobs", "\"count\": 20, \"stride\": 4");
	prop("Trobs.Tile", "Trobs", 3, "u8", "Trobs", "\"count\": 20, \"stride\": 4");
	add("\n] }\n");
}

const char *pop2drv_game_properties(void)
{
	table_init();
	return g_table;
}
