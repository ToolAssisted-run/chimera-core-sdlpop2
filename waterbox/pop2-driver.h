/* pop2-driver.h - Prince of Persia 2 (SDLPoP2) as a machine that is stepped.
 *
 * The same driver is compiled for the miniBox guest and for the native
 * reference (run-native); wbx-entry.c puts the guest ABI on top of it.
 *
 * Wire format (waterbox.config "input.buttons", same order): the prince's
 * keys (P1; Shift also chooses the copy protection's symbol); then the game's
 * own commands, each its own button (Restart Level is the game's Alt+A, and
 * so on) - not its saved games or its menus; then the cheats the cheat word gives - the DOS game's and SDLPoP2's
 * own - which are active only with the cheats setting on (IsButtonActive).
 */
#ifndef POP2_DRIVER_H
#define POP2_DRIVER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum Pop2Button
{
	/* the prince */
	POP2_BTN_UP,
	POP2_BTN_DOWN,
	POP2_BTN_LEFT,
	POP2_BTN_RIGHT,
	POP2_BTN_SHIFT,
	POP2_BTN_CTRL,
	/* the game's commands */
	POP2_BTN_PAUSE,          /* Esc (also skips a story scene) */
	POP2_BTN_SHOW_TIME,      /* Space (also skips a story scene) */
	POP2_BTN_RESTART_LEVEL,  /* Alt+A */
	POP2_BTN_RESTART_GAME,   /* Alt+R */
	POP2_BTN_NEXT_LEVEL,     /* Alt+N */
	POP2_BTN_SOUND_ON_OFF,   /* Alt+S */
	POP2_BTN_MUSIC_ON_OFF,   /* Alt+M */
	POP2_BTN_VERSION,        /* Alt+V */
	POP2_BTN_JOYSTICK_MODE,  /* Alt+J */
	POP2_BTN_KEYBOARD_MODE,  /* Alt+K */
	/* the cheats: the DOS game's */
	POP2_BTN_CHEAT_FIRST,
	POP2_BTN_CHEAT_LOSE_HIT_POINT = POP2_BTN_CHEAT_FIRST, /* Shift+K */
	POP2_BTN_CHEAT_OPPONENT_HIT_POINT,  /* g */
	POP2_BTN_CHEAT_KILL_ROOM,           /* k */
	POP2_BTN_CHEAT_SPIRIT_LEAVES,       /* Shift+S */
	POP2_BTN_CHEAT_MORE_TIME,           /* keypad + */
	POP2_BTN_CHEAT_LESS_TIME,           /* keypad - */
	POP2_BTN_CHEAT_FLIP_SCREEN,         /* Shift+I */
	POP2_BTN_CHEAT_SHOW_ROOM,           /* Shift+R */
	POP2_BTN_CHEAT_ADD_MAX_HIT_POINT,   /* Shift+T */
	POP2_BTN_CHEAT_FEATHER_FALL,        /* Shift+W */
	POP2_BTN_CHEAT_REVIVE,              /* r */
	POP2_BTN_CHEAT_DEMO_PLAYER,         /* F3 */
	/* SDLPoP2's own */
	POP2_BTN_CHEAT_GOD_MODE,            /* Shift+G */
	POP2_BTN_CHEAT_LEAVE_BODY,          /* h: as the shadow */
	POP2_BTN_CHEAT_LEAVE_BODY_FLAME,    /* b: as the flame */
	POP2_BTN_CHEAT_SWORD,               /* z */
	POP2_BTN_CHEAT_LOOK_LEFT,           /* Alt+Left */
	POP2_BTN_CHEAT_LOOK_RIGHT,          /* Alt+Right */
	POP2_BTN_CHEAT_LOOK_UP,             /* Alt+Up */
	POP2_BTN_CHEAT_LOOK_DOWN,           /* Alt+Down */
	POP2_BTN_CHEAT_TELEPORT,            /* t */
	POP2_BTN_CHEAT_FLY,                 /* A, held */
	POP2_BTN_COUNT
};

#define POP2_VIDEO_WIDTH 320
#define POP2_VIDEO_HEIGHT 200

/* The VGA's frame: 3146875 / 44900 = 70.086 Hz, the rate the DOS program ran
 * its frames at and the shell steps them (source/shell.h). */
#define POP2_FRAME_RATE_NUM 3146875
#define POP2_FRAME_RATE_DEN 44900

/* A step ends where the game reads its controls: a game tick while playing
 * (5 or 6 frames), every frame elsewhere. A step that reads nothing is cut at
 * a second of frames, which bounds its sound. */
#define POP2_MAX_FRAMES_PER_STEP 70
/* stereo (the MT-32's; the card's is the same on both sides), 44100 frames a
 * second; the most a step hands out, in stereo frames */
#define POP2_AUDIO_RATE 44100
#define POP2_AUDIO_MAX_SAMPLES 44200

/* 0 on failure, with the reason in err */
int pop2drv_init(char *err, int errsize);
void pop2drv_set_button(int index, int down);
/* whether a button does anything (the cheats need the cheats setting); an
 * inactive one is ignored */
int pop2drv_button_active(int index);
/* runs the program to the end of its next step */
void pop2drv_frame(int render);
const uint32_t *pop2drv_video(void);
const int16_t *pop2drv_audio(int *samples);   /* stereo frames, left then right */
int pop2drv_input_was_read(void);
void pop2drv_vsync(int *num, int *den);
uint64_t pop2drv_frames(void);
/* the bytes the MT-32 was sent and a hash of them with their times (0 with the
 * FM chip): for the gate, which cannot hold the MT-32's sound to the native
 * reference */
uint64_t pop2drv_midi(uint64_t *bytes);

/* game-state.c: the property block, the raw domains, the table */
int pop2drv_domain_count(void);
const char *pop2drv_domain_name(int i);
uint8_t *pop2drv_domain_ptr(int i);
int64_t pop2drv_domain_size(int i);
int pop2drv_domain_writable(int i);
const char *pop2drv_game_properties(void);
void gamestate_from_game(void);
void gamestate_to_game(void);
void gamestate_igt_from_level_1(int on);   /* the igt_from_level_1 setting */

#ifdef __cplusplus
}
#endif

#endif
