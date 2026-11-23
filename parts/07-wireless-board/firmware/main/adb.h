/* The deck's debug (ADB) port, reached as a USB host. Several streams at once. */
#pragma once
#include <stdbool.h>
#include <stddef.h>

typedef struct adb_stream adb_stream_t;

void adb_start(void);
bool adb_ready(void);            /* the deck is plugged in and its debug port is open */
bool adb_attached(void);         /* something is plugged in */

adb_stream_t *adb_open(const char *service, int timeout_ms);
int adb_write(adb_stream_t *s, const void *data, size_t n);                /* 0 = all of it went */
int adb_read(adb_stream_t *s, void *buf, size_t max, int timeout_ms);      /* >0 bytes, 0 closed, -2 nothing yet */
void adb_close(adb_stream_t *s);
