/* What the Mac Connector app used to do: carry messages between the deck and Home Assistant. */
#pragma once
#define FW_VERSION "4.17"
void bridge_start(void);
void bridge_status(char *out, int max);
void bridge_job(const char *state, const char *line);   /* progress of a deck setup, for the panel */
void bridge_request_setup(void);                        /* put the deck app on again */
int board_update_from(const char *url, char *why, int max);   /* 0 = stored and set to start next; restart to use it */
