/*
 * The bridge.
 *
 *   deck  <-- ADB stream "tcp:5210" -->  this board  <-- WebSocket -->  Home Assistant
 *
 * It does what the Mac Connector app does (parts/03-mac-bridge/app/Service.swift):
 *   - tells the deck the time, the date and whether Home Assistant is listening, every 2 s
 *   - says hello to Home Assistant and waits to be allowed
 *   - once both ends are up, tells Home Assistant the deck is there, and passes
 *     messages both ways without reading them
 *
 * On the stream each message is a 4-byte length, then the message.
 */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_timer.h"
#include "esp_system.h"
#include "esp_ota_ops.h"
#include "esp_http_client.h"
#include "esp_websocket_client.h"
#include "mbedtls/base64.h"
#include "cJSON.h"
#include "adb.h"
#include "net.h"
#include "bridge.h"
#include "setup.h"
#include "say.h"

#define LINK_SERVICE "tcp:5210"

static adb_stream_t *dlink;                 /* the stream to the deck app */
static SemaphoreHandle_t link_lock;        /* one whole message at a time goes down it */
static volatile bool link_poison;          /* a message was cut short: start the stream again */

static esp_websocket_client_handle_t ws;
static volatile bool ws_up, ws_hello_due, ha_ready, ha_pending;
static bool announced, ha_up_told;
static uint8_t status_body[64];
static int status_len;
static int64_t last_status_ms = -100000;
static uint32_t n_to_deck, n_from_deck;

static int64_t now_ms(void) { return esp_timer_get_time() / 1000; }

/* ---------- to the deck ---------- */

/* Caller holds link_lock. */
static int link_write(const void *data, size_t n)
{
    if (!dlink) return -1;
    if (adb_write(dlink, data, n)) { link_poison = true; return -1; }
    return 0;
}

static void link_send(const uint8_t *msg, uint32_t n)
{
    uint8_t len[4] = { n, n >> 8, n >> 16, n >> 24 };
    xSemaphoreTake(link_lock, portMAX_DELAY);
    if (!link_write(len, 4)) link_write(msg, n);
    xSemaphoreGive(link_lock);
}

static void ping(void)
{
    static const char *wd[] = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    static const char *mo[] = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    uint8_t m[64];
    if (!dlink || !clock_known()) return;            /* never tell the deck a time we do not know */
    time_t t = time(NULL);
    uint32_t now = (uint32_t)t;
    int32_t tz = clock_tz_offset(now);
    struct tm lt;
    localtime_r(&t, &lt);
    char date[24];
    int dl = snprintf(date, sizeof date, "%s %d %s", wd[lt.tm_wday], lt.tm_mday, mo[lt.tm_mon]);
    m[0] = 1;
    memcpy(m + 1, &now, 4);
    memcpy(m + 5, &tz, 4);
    m[9] = ha_ready ? 1 : 0;
    m[10] = (uint8_t)dl;
    memcpy(m + 11, date, dl);
    link_send(m, 11 + dl);
}

/* ---------- to Home Assistant ---------- */

static void ws_json(const char *text)
{
    if (ws_up) esp_websocket_client_send_text(ws, text, strlen(text), pdMS_TO_TICKS(3000));
}

static void say_hello(void)
{
    char j[400];
    snprintf(j, sizeof j,
             "{\"type\":\"hello\",\"bridge_id\":\"%s\",\"secret\":\"%s\",\"name\":\"Ulanzi D200 Wireless\","
             "\"kind\":\"board\",\"updates\":true,\"version\":\"" FW_VERSION "\",\"deckd\":\"" FW_VERSION "\"}", cfg.id, cfg.secret);
    ws_json(j);
}

static void job(const char *what, const char *state, const char *line)
{
    char j[440];
    snprintf(j, sizeof j, "{\"type\":\"job\",\"what\":\"%s\",\"state\":\"%s\",\"line\":\"%s\"}", what, state, line);
    ws_json(j);
}

void bridge_job(const char *state, const char *line) { job("setup_deck", state, line); }

/* ---------- this board's own software, fetched when Home Assistant says there is a newer one ----------
 *
 * The same conversation the Mac connector app has: Home Assistant says update_now,
 * the board asks where from (want_app), and is given a one-time address on that
 * same Home Assistant (app_at). Nothing is fetched from anywhere else.
 */
static volatile bool update_due;
static char update_token[100];

int board_update_from(const char *url, char *why, int max)
{
    esp_http_client_config_t hc = { .url = url, .timeout_ms = 20000, .buffer_size = 4096 };
    esp_http_client_handle_t c = esp_http_client_init(&hc);
    char *buf = malloc(4096);
    const esp_partition_t *part = esp_ota_get_next_update_partition(NULL);
    esp_ota_handle_t h = 0;
    bool begun = false;
    int total = 0, idle = 0, ok = -1;

    if (!c || !buf || !part) { snprintf(why, max, "The board could not start an update."); goto out; }
    if (esp_http_client_open(c, 0) != ESP_OK) { snprintf(why, max, "The board could not reach Home Assistant to fetch it."); goto out; }
    esp_http_client_fetch_headers(c);
    int status = esp_http_client_get_status_code(c);
    if (status != 200) { snprintf(why, max, "Home Assistant would not hand it over (answer %d).", status); goto out; }
    for (;;) {
        int n = esp_http_client_read(c, buf, 4096);
        if (n < 0) { snprintf(why, max, "The download stopped part way."); goto out; }
        if (n == 0) {
            if (esp_http_client_is_complete_data_received(c)) break;
            if (++idle > 20) { snprintf(why, max, "The download stopped part way."); goto out; }
            continue;
        }
        idle = 0;
        if (!begun) {
            /* An integration older than this board answers with the Mac's app, a zip. Say so
             * rather than let it fail later as "not valid". Board software starts with 0xE9. */
            if ((uint8_t)buf[0] != 0xE9) {
                snprintf(why, max, "Home Assistant sent something that is not board software. Update the integration first.");
                goto out;
            }
            if (esp_ota_begin(part, OTA_SIZE_UNKNOWN, &h) != ESP_OK) { snprintf(why, max, "The board could not start an update."); goto out; }
            begun = true;
        }
        if (esp_ota_write(h, buf, n) != ESP_OK) { snprintf(why, max, "The board could not store the download."); goto out; }
        total += n;
    }
    if (!begun) { snprintf(why, max, "Home Assistant sent nothing."); goto out; }
    begun = false;
    if (esp_ota_end(h) != ESP_OK) { snprintf(why, max, "What arrived was damaged, so the board kept what it had."); goto out; }
    if (esp_ota_set_boot_partition(part) != ESP_OK) { snprintf(why, max, "The board could not switch to the new software."); goto out; }
    say("update: fetched %d bytes, ready to restart into it", total);
    ok = 0;
out:
    if (begun) esp_ota_abort(h);
    if (c) { esp_http_client_close(c); esp_http_client_cleanup(c); }
    free(buf);
    if (ok) say("update: %s", why);
    return ok;
}

static void self_update(void)
{
    static char url[sizeof cfg.url + 160], why[160];
    size_t n = strlen(cfg.url);
    while (n && cfg.url[n - 1] == '/') n--;
    snprintf(url, sizeof url, "%.*s/api/ulanzi_deck/companion-app/%s", (int)n, cfg.url, update_token);
    update_token[0] = 0;
    say("update: Home Assistant has newer software for this board; fetching it");
    job("update_app", "running", "Fetching the board's new software\u2026");
    if (board_update_from(url, why, sizeof why)) { job("update_app", "failed", why); return; }
    job("update_app", "done", "The board is restarting\u2026");
    vTaskDelay(pdMS_TO_TICKS(1500));
    esp_restart();
}

static volatile bool setup_requested;
void bridge_request_setup(void) { setup_requested = true; }

static bool deck_alive(void) { return dlink && now_ms() - last_status_ms < 6000; }

static void reconcile(void)
{
    bool should = ha_ready && deck_alive();
    if (should && !announced) {
        char b64[100], j[160];
        size_t n = 0;
        mbedtls_base64_encode((unsigned char *)b64, sizeof b64 - 1, &n, status_body, status_len);
        b64[n] = 0;
        snprintf(j, sizeof j, "{\"type\":\"deck\",\"status\":\"%s\"}", b64);
        announced = true;
        ws_json(j);
        say("bridge: told Home Assistant the deck is here");
    } else if (!should && announced) {
        announced = false;
        if (ha_ready) ws_json("{\"type\":\"deck_gone\"}");
        say("bridge: deck no longer announced");
    }
    if (ha_ready != ha_up_told) { ha_up_told = ha_ready; ping(); }
}

static void from_deck(const uint8_t *m, uint32_t n)
{
    if (!n) return;
    n_from_deck++;
    if (m[0] == 0x81) {
        last_status_ms = now_ms();
        if ((int)n - 1 != status_len || memcmp(m + 1, status_body, n - 1)) {
            status_len = n - 1 > sizeof status_body ? sizeof status_body : n - 1;
            memcpy(status_body, m + 1, status_len);
            if (announced && ws_up) esp_websocket_client_send_bin(ws, (const char *)m, n, pdMS_TO_TICKS(3000));
        }
    } else if (m[0] == 0x82) {
        if (announced && ws_up) esp_websocket_client_send_bin(ws, (const char *)m, n, pdMS_TO_TICKS(3000));
    }
}

/* ---------- Home Assistant talking ---------- */

static void control(const char *text)
{
    cJSON *o = cJSON_Parse(text);
    const cJSON *t = o ? cJSON_GetObjectItem(o, "type") : NULL;
    if (cJSON_IsString(t)) {
        if (!strcmp(t->valuestring, "pending")) {
            if (!ha_pending) say("ha: waiting to be allowed. Open the Ulanzi Deck panel and press Allow");
            ha_pending = true;
        } else if (!strcmp(t->valuestring, "setup_deck")) {
            setup_requested = true;
        } else if (!strcmp(t->valuestring, "update_now")) {
            ws_json("{\"type\":\"want_app\"}");
        } else if (!strcmp(t->valuestring, "app_at")) {
            const cJSON *tok = cJSON_GetObjectItem(o, "token");
            if (cJSON_IsString(tok) && strlen(tok->valuestring) < sizeof update_token) {
                strcpy(update_token, tok->valuestring);
                update_due = true;                      /* done by the bridge task, not in here */
            }
        } else if (!strcmp(t->valuestring, "ready")) {
            ha_pending = false;
            ha_ready = true;
            say("ha: connected and allowed");
        }
    }
    cJSON_Delete(o);
}

static void on_ws(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    static char text[600];
    static bool mid_binary;
    esp_websocket_event_data_t *e = data;
    switch (id) {
    case WEBSOCKET_EVENT_CONNECTED:
        ws_up = true;
        ws_hello_due = true;
        break;
    case WEBSOCKET_EVENT_DISCONNECTED:
    case WEBSOCKET_EVENT_CLOSED:
        if (ha_ready) say("ha: link lost");
        ws_up = false; ha_ready = false; ha_pending = false;
        if (mid_binary) { mid_binary = false; link_poison = true; xSemaphoreGive(link_lock); }
        break;
    case WEBSOCKET_EVENT_DATA:
        if (e->op_code == 1) {                                  /* text: for us */
            if (e->payload_offset + e->data_len < (int)sizeof text) {
                memcpy(text + e->payload_offset, e->data_ptr, e->data_len);
                if (e->payload_offset + e->data_len >= e->payload_len) {
                    text[e->payload_len] = 0;
                    control(text);
                }
            }
        } else if (e->op_code == 2) {                           /* binary: for the deck, untouched */
            if (e->payload_offset == 0) {
                uint32_t n = e->payload_len;
                uint8_t len[4] = { n, n >> 8, n >> 16, n >> 24 };
                xSemaphoreTake(link_lock, portMAX_DELAY);
                mid_binary = true;
                n_to_deck++;
                link_write(len, 4);
            }
            if (mid_binary) {
                if (e->data_len) link_write(e->data_ptr, e->data_len);
                if (e->payload_offset + e->data_len >= e->payload_len) {
                    mid_binary = false;
                    xSemaphoreGive(link_lock);
                }
            }
        }
        break;
    }
}

/* Home Assistant's clock, from the Date line of any reply it gives. The deck
   has no clock of its own and this board has none either until it asks. */
static esp_err_t on_http(esp_http_client_event_t *e)
{
    if (e->event_id == HTTP_EVENT_ON_HEADER && !strcasecmp(e->header_key, "Date"))
        clock_from_http_date(e->header_value);
    return ESP_OK;
}

static void clock_refresh(void)
{
    esp_http_client_config_t hc = {
        .url = cfg.url,
        .method = HTTP_METHOD_HEAD,
        .event_handler = on_http,
        .timeout_ms = 5000,
    };
    esp_http_client_handle_t c = esp_http_client_init(&hc);
    if (!c) return;
    esp_http_client_perform(c);
    esp_http_client_cleanup(c);
}

static void ws_begin(void)
{
    static char uri[200 + sizeof cfg.url];
    const char *u = cfg.url;
    if (!strncmp(u, "https://", 8)) snprintf(uri, sizeof uri, "wss://%s/api/ulanzi_deck/bridge", u + 8);
    else if (!strncmp(u, "http://", 7)) snprintf(uri, sizeof uri, "ws://%s/api/ulanzi_deck/bridge", u + 7);
    else return;
    esp_websocket_client_config_t wc = {
        .uri = uri,
        .buffer_size = 4096,
        .task_stack = 8192,
        .reconnect_timeout_ms = 5000,
        .network_timeout_ms = 10000,
        .ping_interval_sec = 20,
        .pingpong_timeout_sec = 60,
        .enable_close_reconnect = true,     /* Home Assistant closing the link (a restart, a reload) is not the end */
    };
    ws = esp_websocket_client_init(&wc);
    if (!ws) return;
    esp_websocket_register_events(ws, WEBSOCKET_EVENT_ANY, on_ws, NULL);
    esp_websocket_client_start(ws);
    say("ha: connecting to %s", uri);
}

/* ---------- the task ---------- */

static void bridge_task(void *arg)
{
    static uint8_t buf[2048];
    uint32_t have = 0;
    int64_t last_ping = 0, last_try = -10000;

    int64_t last_clock = -1000000;
    bool checked = false;

    int64_t ws_down_since = now_ms();
    for (;;) {
        if (net_online() && cfg.url[0] &&
            now_ms() - last_clock > (clock_known() ? 6 * 3600 * 1000 : 5000)) {
            last_clock = now_ms();
            clock_refresh();
        }
        if (!ws && net_online() && cfg.url[0]) { ws_begin(); ws_down_since = now_ms(); }
        /* Belt and braces: whatever the reason, a link that has been down this long is started afresh. */
        if (ws_up || !net_online()) ws_down_since = now_ms();
        else if (ws && now_ms() - ws_down_since > 45000) {
            say("ha: no link for a while, starting it afresh");
            esp_websocket_client_stop(ws);
            esp_websocket_client_destroy(ws);
            ws = NULL;
        }
        if (ws_hello_due) { ws_hello_due = false; say_hello(); }
        if (update_due) { update_due = false; self_update(); }

        if (dlink && (link_poison || !adb_ready())) {
            xSemaphoreTake(link_lock, portMAX_DELAY);
            adb_close(dlink);
            dlink = NULL; link_poison = false; have = 0;
            xSemaphoreGive(link_lock);
            say("bridge: link to the deck app closed");
        }
        if (!adb_ready()) checked = false;
        if (adb_ready() && (!checked || setup_requested)) {
            bool force = setup_requested;
            setup_requested = false;
            checked = true;
            if (dlink) {                                /* the deck app is about to be replaced under it */
                xSemaphoreTake(link_lock, portMAX_DELAY);
                adb_close(dlink);
                dlink = NULL; link_poison = false; have = 0;
                xSemaphoreGive(link_lock);
            }
            if (deck_setup(force)) vTaskDelay(pdMS_TO_TICKS(1500));
            else if (setup_unsure) { checked = false; reconcile(); vTaskDelay(pdMS_TO_TICKS(2000)); continue; }
            last_try = -10000;
        }
        if (!dlink) {
            if (adb_ready() && now_ms() - last_try > 1000) {
                last_try = now_ms();
                adb_stream_t *s = adb_open(LINK_SERVICE, 3000);
                if (s) {
                    xSemaphoreTake(link_lock, portMAX_DELAY);
                    dlink = s; link_poison = false; have = 0;
                    xSemaphoreGive(link_lock);
                    say("bridge: link to the deck app open");
                    ping();
                    last_ping = now_ms();
                }
            }
            if (!dlink) { reconcile(); vTaskDelay(pdMS_TO_TICKS(200)); continue; }
        }

        int n = adb_read(dlink, buf + have, sizeof buf - have, 100);
        if (n == 0) { link_poison = true; continue; }           /* the deck app closed it */
        if (n > 0) {
            have += n;
            uint32_t at = 0;
            while (have - at >= 4) {
                uint32_t len = buf[at] | buf[at + 1] << 8 | buf[at + 2] << 16 | (uint32_t)buf[at + 3] << 24;
                if (len > sizeof buf - 4) { link_poison = true; break; }
                if (have - at < 4 + len) break;
                from_deck(buf + at + 4, len);
                at += 4 + len;
            }
            if (at) { memmove(buf, buf + at, have - at); have -= at; }
        }
        if (now_ms() - last_ping >= 2000) { last_ping = now_ms(); ping(); }
        reconcile();
    }
}

void bridge_status(char *out, int max)
{
    snprintf(out, max,
             "wifi %s%s%s, home assistant %s, deck %s, link %s, clock %s, to deck %u, from deck %u, running from %s, memory free %u (lowest %u)",
             net_online() ? "joined " : net_setup_mode() ? "setup mode" : "not joined", net_online() ? net_ip() : "", "",
             ha_ready ? "ready" : ha_pending ? "waiting to be allowed" : ws_up ? "connected" : "not connected",
             adb_ready() ? "debug port open" : adb_attached() ? "attached" : "not attached",
             dlink ? (deck_alive() ? "open and answering" : "open, silent") : "closed",
             clock_known() ? "known" : "not known", (unsigned)n_to_deck, (unsigned)n_from_deck,
             esp_ota_get_running_partition()->label,
             (unsigned)esp_get_free_heap_size(), (unsigned)esp_get_minimum_free_heap_size());
}

void bridge_start(void)
{
    link_lock = xSemaphoreCreateMutex();
    xTaskCreatePinnedToCore(bridge_task, "bridge", 8192, NULL, 3, NULL, 1);
}
