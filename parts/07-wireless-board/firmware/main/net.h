/* Settings kept on the board, Wi-Fi, the setup page, and the clock. */
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    char ssid[33];
    char pass[65];
    char url[128];          /* Home Assistant, e.g. http://192.168.1.10:8123 */
    char tz[48];            /* POSIX time zone */
    char id[40];            /* who this board is, to Home Assistant */
    char secret[70];
} config_t;

extern config_t cfg;

void cfg_load(void);
void cfg_save(void);

void net_start(void);
bool net_online(void);          /* on Wi-Fi with an address */
bool net_setup_mode(void);      /* offering its own setup network */
const char *net_ip(void);
bool clock_known(void);
void clock_from_http_date(const char *date);   /* "Sun, 22 Nov 2026 17:30:00 GMT" */
int32_t clock_tz_offset(uint32_t now);         /* seconds east of UTC, at that moment */
