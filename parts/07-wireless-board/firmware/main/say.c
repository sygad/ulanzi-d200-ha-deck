#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "esp_timer.h"
#include "say.h"

#define RING 6000
static char ring[RING];
static int head, used;
static volatile bool quiet;
static SemaphoreHandle_t lock;

void say(const char *fmt, ...)
{
    char line[200];
    va_list ap;
    if (!lock) lock = xSemaphoreCreateMutex();
    long long ds = esp_timer_get_time() / 100000;      /* tenths of a second; no floating point on small stacks */
    int n = snprintf(line, sizeof line, "%5lld.%lld ", ds / 10, ds % 10);
    va_start(ap, fmt);
    n += vsnprintf(line + n, sizeof line - n - 1, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof line - 2) n = sizeof line - 2;
    line[n++] = '\n';
    xSemaphoreTake(lock, portMAX_DELAY);
    for (int i = 0; i < n; i++) {
        ring[(head + used) % RING] = line[i];
        if (used < RING) used++; else head = (head + 1) % RING;
    }
    xSemaphoreGive(lock);
    if (!quiet) printf("# %.*s", n, line);
}

void say_quiet(bool q) { quiet = q; }

void say_dump(void)
{
    xSemaphoreTake(lock, portMAX_DELAY);
    int i = 0;
    while (i < used && ring[(head + i) % RING] != '\n' && head) i++;     /* skip a line cut in half */
    if (i < used && head) i++;
    printf("| ");
    for (; i < used; i++) {
        char c = ring[(head + i) % RING];
        if (c == '\n') printf("\n| "); else putchar(c);
    }
    printf("\n");
    xSemaphoreGive(lock);
}

int say_copy(char *out, int max)
{
    int n = 0;
    if (!lock) return 0;
    xSemaphoreTake(lock, portMAX_DELAY);
    int skip = used > max - 1 ? used - (max - 1) : 0;
    for (int i = skip; i < used; i++) out[n++] = ring[(head + i) % RING];
    xSemaphoreGive(lock);
    out[n] = 0;
    return n;
}
