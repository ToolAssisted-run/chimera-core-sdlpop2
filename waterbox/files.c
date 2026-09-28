/* files.c - how the game's file names reach the files a project mounts.
 *
 * SDLPoP2 opens its files as <game directory>/<NAME>, and the core's game
 * directory is "." - so every open is "./PRINCE.DAT". miniBox mounts a
 * project's files under their bare names and has no current directory to
 * resolve "./" against; natively the work dir is the current one either way.
 * So the game's opens go through here (the link wraps fopen) and lose a
 * leading "./". Nothing else changes: a name that is not mounted still fails
 * to open, as a missing file did in DOS.
 */
#include <stdio.h>
#include <string.h>

FILE *__real_fopen(const char *path, const char *mode);

FILE *__wrap_fopen(const char *path, const char *mode)
{
	while (path && path[0] == '.' && path[1] == '/') path += 2;
	return __real_fopen(path, mode);
}
