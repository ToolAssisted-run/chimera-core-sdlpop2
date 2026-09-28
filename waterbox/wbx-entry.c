/* wbx-entry.c - the chimera guest ABI over pop2-driver.
 *
 * Compiles identically for the guest (miniBox emulibc) and for the native
 * reference (native-shim/emulibc.h), which is what makes the equivalence gate
 * a real proof: the same driver, the same exports, one in the sandbox and one
 * out of it.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <emulibc.h>

#include "pop2-driver.h"

static char g_load_error[1024];

/* A panel of more than 64 buttons arrives through SetButton only (the engine
 * sends a wide panel's changes that way); the packed mask covers the first 64,
 * which the gate harness does not use. A step sees their union. */
static uint8_t g_set_buttons[POP2_BTN_COUNT];

/* Turbo: the picture is not converted. Only the conversion - the game draws
 * its screen whatever happens, because what it draws is part of the game. */
ECL_INVISIBLE int chimera_render_enabled = 1;

ECL_EXPORT const char *GetLoadError(void) { return g_load_error; }

ECL_EXPORT int Init(void)
{
	g_load_error[0] = '\0';
	return pop2drv_init(g_load_error, (int)sizeof g_load_error);
}

ECL_EXPORT void SetButton(int32_t index, int32_t state)
{
	if (index >= 0 && index < POP2_BTN_COUNT) g_set_buttons[index] = state ? 1 : 0;
}

ECL_EXPORT void FrameAdvance(uint64_t packed)
{
	for (int i = 0; i < POP2_BTN_COUNT; i++)
		pop2drv_set_button(i, g_set_buttons[i] | (i < 64 ? (int)((packed >> i) & 1) : 0));
	pop2drv_frame(chimera_render_enabled);
}

ECL_EXPORT void SetRenderingEnabled(int on) { chimera_render_enabled = on != 0; }

ECL_EXPORT uint32_t *GetVideoBgra(void) { return (uint32_t *)pop2drv_video(); }
ECL_EXPORT int GetVideoWidth(void) { return POP2_VIDEO_WIDTH; }
ECL_EXPORT int GetVideoHeight(void) { return POP2_VIDEO_HEIGHT; }
/* mode 13h on a 4:3 monitor */
ECL_EXPORT int GetDisplayAspectX(void) { return 4; }
ECL_EXPORT int GetDisplayAspectY(void) { return 3; }

ECL_EXPORT int16_t *GetAudio(void)
{
	int n;
	return (int16_t *)pop2drv_audio(&n);
}

ECL_EXPORT int GetAudioSampleCount(void)
{
	int n;
	pop2drv_audio(&n);
	return n;
}

/* the length of the step just run, as a rate: 70.086/6 Hz for a tick of play */
ECL_EXPORT int GetVsyncNumerator(void)
{
	int num, den;
	pop2drv_vsync(&num, &den);
	return num;
}

ECL_EXPORT int GetVsyncDenominator(void)
{
	int num, den;
	pop2drv_vsync(&num, &den);
	return den;
}

ECL_EXPORT int InputWasRead(void) { return pop2drv_input_was_read(); }

/* memory domains: Game State (the property block), then the prince, the
 * room's characters, the level, the moving floors and the tile animations in
 * place */
ECL_EXPORT int GetMemoryDomainCount(void) { return pop2drv_domain_count(); }
ECL_EXPORT const char *GetMemoryDomainName(int i) { return pop2drv_domain_name(i); }
ECL_EXPORT uint8_t *GetMemoryDomainPtr(int i) { return pop2drv_domain_ptr(i); }
ECL_EXPORT int64_t GetMemoryDomainSize(int i) { return pop2drv_domain_size(i); }
ECL_EXPORT int GetMemoryDomainWritable(int i) { return pop2drv_domain_writable(i); }

/* chimera docs/game-cores.md: the property table */
ECL_EXPORT const char *GetGameProperties(void) { return pop2drv_game_properties(); }

/* the machine's own clock: VGA frames (70.086 Hz), for harnesses that compare
 * machines */
ECL_EXPORT uint64_t GetCycleCount(void) { return pop2drv_frames(); }
