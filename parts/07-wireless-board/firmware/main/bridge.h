/* What the Mac Connector app used to do: carry messages between the deck and Home Assistant. */
#pragma once
#define FW_VERSION "4.15"
void bridge_start(void);
void bridge_status(char *out, int max);
void bridge_job(const char *state, const char *line);   /* progress of a deck setup, for the panel */
void bridge_request_setup(void);                        /* put the deck app on again */
