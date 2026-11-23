/*
 * Setting a deck up, with no computer.
 *
 * A deck out of its box runs Ulanzi's original app, which cannot talk to Home
 * Assistant. This firmware carries the deck app that can, and puts it on the
 * deck the first time one is plugged in, exactly as the Mac connector app does
 * (parts/03-mac-bridge/app/DeckInstaller.swift): keep the original, copy ours
 * beside it, give it a starter screen, swap, start.
 *
 * It never runs a program on the deck to find out what it is. It compares
 * checksums, and reads the version out of the file.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/sha256.h"
#include "adb.h"
#include "bridge.h"
#include "setup.h"
#include "say.h"

extern const uint8_t deckd_start[] asm("_binary_deckd_start");
extern const uint8_t deckd_end[] asm("_binary_deckd_end");
extern const uint8_t layout_start[] asm("_binary_default_layout_bin_start");
extern const uint8_t layout_end[] asm("_binary_default_layout_bin_end");

#define APP "/userdata/UlanziDeckKey"

int deck_shell(const char *cmd, char *out, int max, int timeout_ms)
{
    static char svc[1400];
    int n = 0, r;
    snprintf(svc, sizeof svc, "shell:%s", cmd);
    adb_stream_t *s = adb_open(svc, 5000);
    if (!s) return -1;
    while (n < max - 1 && (r = adb_read(s, out + n, max - 1 - n, timeout_ms)) > 0) n += r;
    out[n] = 0;
    adb_close(s);
    return n;
}

static void put32(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }

int deck_push(const char *path, unsigned mode, const void *data, size_t size, char *why, int whymax)
{
    uint8_t hdr[260], reply[300];
    char spec[220];
    const uint8_t *p = data;
    int sl = snprintf(spec, sizeof spec, "%s,%u", path, 0100000u | mode);
    adb_stream_t *s = adb_open("sync:", 5000);
    if (!s) { snprintf(why, whymax, "could not open the deck's file service"); return -1; }
    memcpy(hdr, "SEND", 4); put32(hdr + 4, sl); memcpy(hdr + 8, spec, sl);
    int bad = adb_write(s, hdr, 8 + sl);
    for (size_t off = 0; !bad && off < size; ) {
        uint32_t c = size - off > 2048 ? 2048 : size - off;
        memcpy(hdr, "DATA", 4); put32(hdr + 4, c);
        bad = adb_write(s, hdr, 8) || adb_write(s, p + off, c);
        off += c;
    }
    if (!bad) { memcpy(hdr, "DONE", 4); put32(hdr + 4, 0); bad = adb_write(s, hdr, 8); }
    if (bad) { adb_close(s); snprintf(why, whymax, "the link dropped while sending"); return -1; }
    int n = 0, r;
    while (n < 8 && (r = adb_read(s, reply + n, sizeof reply - 1 - n, 10000)) > 0) n += r;
    int ok = n >= 4 && !memcmp(reply, "OKAY", 4);
    if (ok) { memcpy(hdr, "QUIT", 4); put32(hdr + 4, 0); adb_write(s, hdr, 8); }
    else if (n >= 8 && !memcmp(reply, "FAIL", 4)) { reply[n] = 0; snprintf(why, whymax, "the deck refused: %s", (char *)reply + 8); }
    else snprintf(why, whymax, "the deck did not confirm the copy");
    adb_close(s);
    return ok ? 0 : -1;
}

static void step(const char *state, const char *line)
{
    say("setup: %s", line);
    bridge_job(state, line);
}

static bool install(void)
{
    static char out[600];
    char why[160];

    step("running", "Keeping the deck's own software safe…");
    deck_shell("mkdir -p /userdata/deck /userdata/vendor; "
               "if [ ! -f /userdata/vendor/UlanziDeckKey ]; then cp -p " APP " /userdata/vendor/UlanziDeckKey; fi; "
               "echo kept", out, sizeof out, 15000);
    if (!strstr(out, "kept")) { step("failed", "Could not write to the deck. Unplug it, plug it back in, and try again."); return false; }

    step("running", "Copying the app across…");
    if (deck_push(APP ".new", 0755, deckd_start, deckd_end - deckd_start, why, sizeof why)) {
        say("setup: %s", why);
        step("failed", "The copy to the deck did not finish. Unplug it, plug it back in, and try again.");
        return false;
    }

    deck_shell("ls /userdata/deck/layout.bin 2>/dev/null", out, sizeof out, 10000);
    if (!strstr(out, "layout.bin")) {
        step("running", "Giving it something to show…");
        if (deck_push("/userdata/deck/layout.bin", 0644, layout_start, layout_end - layout_start, why, sizeof why))
            step("running", "The starter screen did not copy across — the deck will be blank until Home Assistant sends your keys.");
    }

    step("running", "Starting it…");
    deck_shell("killall UlanziDeckKey 2>/dev/null; chmod 755 " APP ".new; "
               "mv " APP ".new " APP " || echo MOVEFAILED; sync; "
               "(setsid " APP " -platform linuxfb >/dev/null 2>&1 &); sleep 1; "
               "ps | grep '[U]lanziDeckKey' >/dev/null && echo running || echo stopped",
               out, sizeof out, 20000);
    if (strstr(out, "MOVEFAILED")) {
        step("failed", "The new deck software could not be put in place, so the deck is still running the old one. "
                       "Unplug it, plug it back in, and try again.");
        return false;
    }
    if (!strstr(out, "running")) {
        step("failed", "The deck took the app but would not start it. Unplug it, plug it back in, and try again.");
        return false;
    }
    step("done", "The deck is restarting…");
    return true;
}

bool setup_unsure;

bool deck_setup(bool force)
{
    static char out[400];
    char want[65];
    uint8_t sha[32];
    int ours_major = 0, ours_minor = 0, major = -1, minor = -1;

    setup_unsure = false;
    if (!adb_ready()) { setup_unsure = true; return false; }
    if (force) return install();

    mbedtls_sha256(deckd_start, deckd_end - deckd_start, sha, 0);
    for (int i = 0; i < 32; i++) sprintf(want + 2 * i, "%02x", sha[i]);

    /* Each question ends with a marker. An answer without it was cut short (the deck is
     * restarting, the plug is half in) and says nothing about the deck: ask again later. */
    if (deck_shell("sha256sum " APP " 2>/dev/null; echo ASKED", out, sizeof out, 15000) < 0 || !strstr(out, "ASKED")) {
        say("setup: could not ask the deck what it runs; will ask again");
        setup_unsure = true;
        return false;
    }
    if (!strncmp(out, want, 64)) { say("setup: the deck already runs the deck app this board carries"); return false; }

    /* Not the same file. Is it a later one of ours? Read the version out of it; never run it. */
    sscanf(FW_VERSION, "%d.%d", &ours_major, &ours_minor);
    if (deck_shell("grep -ao 'deckd [0-9]*\\.[0-9]*' " APP " 2>/dev/null | head -n 1; echo ASKED", out, sizeof out, 15000) < 0 ||
        !strstr(out, "ASKED")) {
        say("setup: could not ask the deck what it runs; will ask again");
        setup_unsure = true;
        return false;
    }
    if (sscanf(out, "deckd %d.%d", &major, &minor) == 2 &&
        (major > ours_major || (major == ours_major && minor >= ours_minor))) {
        say("setup: the deck runs deck app %d.%d, not older than this board's %s; leaving it", major, minor, FW_VERSION);
        return false;
    }
    if (major >= 0) say("setup: the deck runs deck app %d.%d; this board carries %s", major, minor, FW_VERSION);
    else say("setup: the deck is not running the deck app");
    return install();
}
