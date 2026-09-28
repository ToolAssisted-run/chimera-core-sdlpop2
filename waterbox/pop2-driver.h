/* pop2-driver.h - Prince of Persia 2 (SDLPoP2) as a machine that is stepped.
 *
 * The same driver is compiled for the miniBox guest and for the native
 * reference (run-native); wbx-entry.c puts the guest ABI on top of it.
 *
 * Wire format (waterbox.config "input.buttons", same order): the prince's
 * controls, then the keys the program reads outside play - the menus, the
 * story scenes, the copy protection's symbols (arrows and Enter), the hall of
 * fame's name (the letters) and the program's own keys (Esc, Space, Alt+...).
 */
#ifndef POP2_DRIVER_H
#define POP2_DRIVER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum Pop2Button
{
	POP2_BTN_UP,
	POP2_BTN_DOWN,
	POP2_BTN_LEFT,
	POP2_BTN_RIGHT,
	POP2_BTN_SHIFT,
	POP2_BTN_CTRL,
	POP2_BTN_ENTER,
	POP2_BTN_SPACE,
	POP2_BTN_ESCAPE,
	POP2_BTN_TAB,
	POP2_BTN_BACKSPACE,
	POP2_BTN_ALT,
	POP2_BTN_A, /* A..Z follow in order */
	POP2_BTN_COUNT = POP2_BTN_A + 26
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
#define POP2_AUDIO_RATE 44100
#define POP2_AUDIO_MAX_SAMPLES 44200

/* 0 on failure, with the reason in err */
int pop2drv_init(char *err, int errsize);
void pop2drv_set_button(int index, int down);
/* runs the program to the end of its next step */
void pop2drv_frame(int render);
const uint32_t *pop2drv_video(void);
const int16_t *pop2drv_audio(int *samples);
int pop2drv_input_was_read(void);
void pop2drv_vsync(int *num, int *den);
uint64_t pop2drv_frames(void);

/* game-state.c: the property block, the raw domains, the table */
int pop2drv_domain_count(void);
const char *pop2drv_domain_name(int i);
uint8_t *pop2drv_domain_ptr(int i);
int64_t pop2drv_domain_size(int i);
int pop2drv_domain_writable(int i);
const char *pop2drv_game_properties(void);
void gamestate_from_game(void);
void gamestate_to_game(void);

#ifdef __cplusplus
}
#endif

#endif
