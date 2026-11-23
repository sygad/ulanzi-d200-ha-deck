/* Putting the deck's own software on it, through its debug port. */
#pragma once
#include <stdbool.h>
#include <stddef.h>

/* Run a shell command on the deck; what it printed lands in out. Returns its length, or -1. */
int deck_shell(const char *cmd, char *out, int max, int timeout_ms);
/* Write a file on the deck. 0 = done; otherwise why is filled in. */
int deck_push(const char *path, unsigned mode, const void *data, size_t n, char *why, int whymax);

/* Look at what the deck is running and install the deck app if it is missing or
   older than the one this firmware carries. force installs regardless.
   Returns true if it installed (the deck app has just restarted). */
bool deck_setup(bool force);
extern bool setup_unsure;        /* the last check could not get an answer from the deck */
