/* Status lines. Kept in a small ring so they can be read back later (LOG), and
   printed live as "# ..." unless the console is in the middle of a command. */
#pragma once
#include <stdbool.h>
void say(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
void say_quiet(bool quiet);
void say_dump(void);
int say_copy(char *out, int max);     /* the same lines, as text */
