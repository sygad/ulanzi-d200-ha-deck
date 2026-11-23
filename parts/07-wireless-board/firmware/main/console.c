/*
 * The workbench: commands on the serial console (the COM socket), so the deck
 * and the board can be looked at and changed from the Mac during development.
 *
 *   INFO                          where everything stands
 *   LOG                           the board's recent status lines
 *   SH <shell command>            run it on the deck, print what it says
 *   PUT <path> <octal mode> <n>   then n bytes as hex lines; writes the file on the deck
 *   URL <address>                 where Home Assistant is
 *   SETUP                         offer the setup network now
 *   FORGET                        forget the Wi-Fi details and restart
 *   REBOOT
 *
 * Replies: "| " a line of output, "+" ready for the next hex line, "OK", "ERR ...".
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_core_dump.h"
#include "driver/uart.h"
#include "driver/uart_vfs.h"
#include "adb.h"
#include "net.h"
#include "bridge.h"
#include "console.h"
#include "setup.h"
#include "say.h"

static char line[1200];
static uint8_t chunk[4096];

static int read_line(void)
{
    int n = 0;
    for (;;) {
        uint8_t c;
        if (uart_read_bytes(UART_NUM_0, &c, 1, pdMS_TO_TICKS(200)) != 1) continue;
        if (c == '\r') continue;
        if (c == '\n') { line[n] = 0; return n; }
        if (n < (int)sizeof line - 1) line[n++] = (char)c;
    }
}

static void cmd_sh(const char *cmd)
{
    static char svc[1300];
    snprintf(svc, sizeof svc, "shell:%s", cmd);
    adb_stream_t *s = adb_open(svc, 5000);
    if (!s) { printf("ERR could not open a shell\n"); return; }
    printf("| ");
    for (;;) {
        int n = adb_read(s, chunk, sizeof chunk, 20000);
        if (n < 0) { adb_close(s); printf("\nERR timed out\n"); return; }
        if (n == 0) break;
        for (int i = 0; i < n; i++) {
            char c = (char)chunk[i];
            if (c == '\r') continue;
            if (c == '\n') printf("\n| "); else putchar(c);
        }
    }
    adb_close(s);
    printf("\nOK\n");
}

static int hexval(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void cmd_put(char *args)
{
    char path[200]; unsigned mode; unsigned long size;
    if (sscanf(args, "%199s %o %lu", path, &mode, &size) != 3 || size > 250000) { printf("ERR usage: PUT path mode bytes\n"); return; }
    uint8_t *data = malloc(size ? size : 1);
    if (!data) { printf("ERR no memory\n"); return; }
    unsigned long got = 0;
    printf("+\n");
    while (got < size) {
        int n = read_line();
        for (int i = 0; i + 1 < n && got < size; i += 2) {
            int a = hexval(line[i]), b = hexval(line[i + 1]);
            if (a < 0 || b < 0) { free(data); printf("ERR bad hex\n"); return; }
            data[got++] = (uint8_t)(a << 4 | b);
        }
        printf("+\n");
    }

    char why[160];
    if (deck_push(path, mode, data, size, why, sizeof why)) printf("ERR %s\n", why);
    else printf("OK\n");
    free(data);
}

/* If the board ever crashed, it wrote down where. Say so at every start until the
 * record is cleared (console command CLEARCRASH), so it can be read over Wi-Fi later. */
static void last_crash(void)
{
    static esp_core_dump_summary_t sum;
    static char line[400], reason[160];
    if (esp_core_dump_image_check() != ESP_OK) return;
    if (esp_core_dump_get_summary(&sum) != ESP_OK) { say("crash record: present but unreadable"); return; }
    reason[0] = 0;
    esp_core_dump_get_panic_reason(reason, sizeof reason);
    int n = snprintf(line, sizeof line, "crash record: task %s, at %08x, cause %u, address %08x, app %.8s, trail",
                     sum.exc_task, (unsigned)sum.exc_pc, (unsigned)sum.ex_info.exc_cause,
                     (unsigned)sum.ex_info.exc_vaddr, (const char *)sum.app_elf_sha256);
    for (unsigned i = 0; i < sum.exc_bt_info.depth && i < 16 && n < (int)sizeof line - 12; i++)
        n += snprintf(line + n, sizeof line - n, " %08x", (unsigned)sum.exc_bt_info.bt[i]);
    say("%s", line);
    if (reason[0]) say("crash record: %s", reason);
}

static void console_task(void *arg)
{
    const char *why;
    switch (esp_reset_reason()) {
    case ESP_RST_POWERON:  why = "power on or the reset button"; break;
    case ESP_RST_SW:       why = "a restart it chose itself"; break;
    case ESP_RST_PANIC:    why = "a crash"; break;
    case ESP_RST_INT_WDT: case ESP_RST_TASK_WDT: case ESP_RST_WDT: why = "a watchdog"; break;
    case ESP_RST_BROWNOUT: why = "a dip in its power"; break;
    default:               why = "another cause"; break;
    }
    say("workbench ready, firmware " FW_VERSION ", started by %s (%d)", why, (int)esp_reset_reason());
    last_crash();
    for (;;) {
        int n = read_line();
        if (!n) continue;
        say_quiet(true);                        /* nothing else prints while a command answers */
        if (!strcmp(line, "INFO")) {
            static char st[400];
            bridge_status(st, sizeof st);
            printf("| %s\n| home assistant address: %s\n| wifi network: %s\n| board id: %s\nOK\n",
                   st, cfg.url[0] ? cfg.url : "(not set)", cfg.ssid[0] ? cfg.ssid : "(not set)", cfg.id);
        } else if (!strcmp(line, "LOG")) {
            say_dump();
            printf("OK\n");
        } else if (!strncmp(line, "URL ", 4)) {
            strlcpy(cfg.url, line + 4, sizeof cfg.url);
            cfg_save();
            printf("OK\n");
            vTaskDelay(pdMS_TO_TICKS(200));
            esp_restart();
        } else if (!strcmp(line, "FORGET")) {
            cfg.ssid[0] = 0; cfg.pass[0] = 0;
            cfg_save();
            printf("OK\n");
            vTaskDelay(pdMS_TO_TICKS(200));
            esp_restart();
        } else if (!strcmp(line, "KEY")) {
            /* the key the Wi-Fi workbench asks for; only ever shown here, on the cable */
            printf("| %s\nOK\n", cfg.secret);
        } else if (!strcmp(line, "SETUPDECK")) {
            bridge_request_setup();
            printf("OK\n");
        } else if (!strcmp(line, "CRASH")) {
            abort();                                    /* on purpose, to prove the crash record works */
        } else if (!strcmp(line, "CLEARCRASH")) {
            esp_core_dump_image_erase();
            printf("OK\n");
        } else if (!strcmp(line, "REBOOT")) {
            printf("OK\n");
            vTaskDelay(pdMS_TO_TICKS(200));
            esp_restart();
        } else if (!strncmp(line, "SH ", 3) || !strncmp(line, "PUT ", 4)) {
            if (!adb_ready()) printf("ERR the deck's debug port is not open\n");
            else if (line[0] == 'S') cmd_sh(line + 3);
            else cmd_put(line + 4);
        } else {
            printf("ERR unknown command\n");
        }
        say_quiet(false);
    }
}

void console_start(void)
{
    uart_driver_install(UART_NUM_0, 16384, 0, 0, NULL, 0);
    uart_vfs_dev_use_driver(UART_NUM_0);
    setvbuf(stdout, NULL, _IONBF, 0);
    xTaskCreatePinnedToCore(console_task, "console", 8192, NULL, 3, NULL, 1);
}
