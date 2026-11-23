/*
 * Wi-Fi, and the page that sets the board up.
 *
 * With no Wi-Fi details, or when the saved ones do not work for a minute, the
 * board offers a network of its own, "Ulanzi Deck Setup". Join it and open
 * http://192.168.4.1 to choose the Wi-Fi and say where Home Assistant is. The
 * password is typed there and goes nowhere else.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_random.h"
#include "esp_http_server.h"
#include "esp_ota_ops.h"
#include "driver/gpio.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "net.h"
#include "bridge.h"
#include "setup.h"
#include "say.h"

config_t cfg;

#define AP_SSID "Ulanzi Deck Setup"
#define TZ_DEFAULT "GMT0BST,M3.5.0/1,M10.5.0"

static volatile bool online, setup_mode, time_ok;
static char ip_text[20];
static httpd_handle_t server;

/* ---------- settings ---------- */

static void get(nvs_handle_t h, const char *key, char *out, size_t max)
{
    size_t n = max;
    if (nvs_get_str(h, key, out, &n) != ESP_OK) out[0] = 0;
}

static void random_hex(char *out, int bytes)
{
    for (int i = 0; i < bytes; i++) sprintf(out + 2 * i, "%02x", (unsigned)(esp_random() & 0xff));
}

void cfg_load(void)
{
    nvs_handle_t h;
    memset(&cfg, 0, sizeof cfg);
    if (nvs_open("deck", NVS_READWRITE, &h) != ESP_OK) return;
    get(h, "ssid", cfg.ssid, sizeof cfg.ssid);
    get(h, "pass", cfg.pass, sizeof cfg.pass);
    get(h, "url", cfg.url, sizeof cfg.url);
    get(h, "tz", cfg.tz, sizeof cfg.tz);
    get(h, "id", cfg.id, sizeof cfg.id);
    get(h, "secret", cfg.secret, sizeof cfg.secret);
    nvs_close(h);
    if (!cfg.tz[0]) strcpy(cfg.tz, TZ_DEFAULT);
    if (!cfg.id[0] || !cfg.secret[0]) {         /* first start: decide who we are, once */
        strcpy(cfg.id, "esp32-");
        random_hex(cfg.id + 6, 8);
        random_hex(cfg.secret, 32);
        cfg_save();
    }
    setenv("TZ", cfg.tz, 1);
    tzset();
}

void cfg_save(void)
{
    nvs_handle_t h;
    if (nvs_open("deck", NVS_READWRITE, &h) != ESP_OK) return;
    nvs_set_str(h, "ssid", cfg.ssid);
    nvs_set_str(h, "pass", cfg.pass);
    nvs_set_str(h, "url", cfg.url);
    nvs_set_str(h, "tz", cfg.tz);
    nvs_set_str(h, "id", cfg.id);
    nvs_set_str(h, "secret", cfg.secret);
    nvs_commit(h);
    nvs_close(h);
}

/* ---------- the clock ---------- */

static int64_t days_from_civil(int y, int m, int d)
{
    y -= m <= 2;
    int64_t era = (y >= 0 ? y : y - 399) / 400;
    int yoe = (int)(y - era * 400);
    int doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    int doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

bool clock_known(void) { return time_ok; }

void clock_from_http_date(const char *date)
{
    static const char *mon = "JanFebMarAprMayJunJulAugSepOctNovDec";
    char wd[8], mo[8];
    int d, y, hh, mm, ss;
    if (sscanf(date, "%7[^,], %d %7s %d %d:%d:%d", wd, &d, mo, &y, &hh, &mm, &ss) != 7) return;
    const char *p = strstr(mon, mo);
    if (!p || y < 2024) return;
    int m = (int)(p - mon) / 3 + 1;
    struct timeval tv = { .tv_sec = days_from_civil(y, m, d) * 86400 + hh * 3600 + mm * 60 + ss };
    settimeofday(&tv, NULL);
    if (!time_ok) say("clock: set from Home Assistant, %s", date);
    time_ok = true;
}

int32_t clock_tz_offset(uint32_t now)
{
    time_t t = now;
    struct tm lt;
    localtime_r(&t, &lt);
    int64_t local = days_from_civil(lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday) * 86400
                    + lt.tm_hour * 3600 + lt.tm_min * 60 + lt.tm_sec;
    return (int32_t)(local - (int64_t)now);
}

/* ---------- the setup page ---------- */

static void html_escape(char *out, size_t max, const char *in)
{
    size_t n = 0;
    for (; *in && n + 7 < max; in++) {
        if (*in == '<') n += sprintf(out + n, "&lt;");
        else if (*in == '>') n += sprintf(out + n, "&gt;");
        else if (*in == '&') n += sprintf(out + n, "&amp;");
        else if (*in == '"') n += sprintf(out + n, "&quot;");
        else out[n++] = *in;
    }
    out[n] = 0;
}

static const char PAGE_HEAD[] =
    "<!doctype html><html><head><meta charset=utf-8>"
    "<meta name=viewport content='width=device-width,initial-scale=1'>"
    "<title>Ulanzi Deck</title><style>"
    "body{font:17px -apple-system,system-ui,sans-serif;margin:0;background:#16181c;color:#eee}"
    "main{max-width:420px;margin:0 auto;padding:24px 16px}"
    "h1{font-size:22px}label{display:block;margin:18px 0 6px;color:#aaa;font-size:14px}"
    "input,select{width:100%;box-sizing:border-box;font:inherit;padding:12px;border-radius:10px;"
    "border:1px solid #444;background:#22252b;color:#eee}"
    "button{margin-top:26px;width:100%;font:inherit;font-weight:600;padding:14px;border:0;"
    "border-radius:10px;background:#3d8bfd;color:#fff}"
    "p{color:#aaa;line-height:1.4}"
    "</style></head><body><main>";

static esp_err_t page_get(httpd_req_t *req)
{
    static char esc[900];
    httpd_resp_set_type(req, "text/html");
    httpd_resp_sendstr_chunk(req, PAGE_HEAD);
    if (!setup_mode) {
        static char st[400];
        bridge_status(st, sizeof st);
        httpd_resp_sendstr_chunk(req, "<h1>Ulanzi D200 Wireless</h1><p>Firmware " FW_VERSION ".</p><p>");
        html_escape(esc, sizeof esc, st);
        httpd_resp_sendstr_chunk(req, esc);
        httpd_resp_sendstr_chunk(req, "</p><p>To change the Wi-Fi or the Home Assistant address, hold the board's "
                                      "BOOT button for five seconds. It will offer the <b>" AP_SSID
                                      "</b> network again.</p></main></body></html>");
        return httpd_resp_sendstr_chunk(req, NULL);
    }
    httpd_resp_sendstr_chunk(req, "<h1>Set up the deck</h1><form method=post action=/save>"
                                  "<label>Wi-Fi network</label><select name=ssid>");
    wifi_scan_config_t sc = { 0 };
    uint16_t n = 0;
    if (esp_wifi_scan_start(&sc, true) == ESP_OK) esp_wifi_scan_get_ap_num(&n);
    if (n > 20) n = 20;
    wifi_ap_record_t *aps = n ? calloc(n, sizeof *aps) : NULL;
    if (aps && esp_wifi_scan_get_ap_records(&n, aps) == ESP_OK) {
        for (int i = 0; i < n; i++) {
            bool dup = !aps[i].ssid[0];
            for (int k = 0; k < i && !dup; k++) dup = !strcmp((char *)aps[k].ssid, (char *)aps[i].ssid);
            if (dup) continue;
            static char row[1900];
            html_escape(esc, sizeof esc, (char *)aps[i].ssid);
            snprintf(row, sizeof row, "<option value=\"%s\"%s>%s</option>", esc,
                     !strcmp((char *)aps[i].ssid, cfg.ssid) ? " selected" : "", esc);
            httpd_resp_sendstr_chunk(req, row);
        }
    }
    free(aps);
    httpd_resp_sendstr_chunk(req, "</select><label>Wi-Fi password</label>"
                                  "<input name=pass type=password autocomplete=off>"
                                  "<label>Home Assistant address</label><input name=url value=\"");
    html_escape(esc, sizeof esc, cfg.url[0] ? cfg.url : "http://homeassistant.local:8123");
    httpd_resp_sendstr_chunk(req, esc);
    httpd_resp_sendstr_chunk(req, "\"><button>Save and connect</button></form>"
                                  "<p>The board restarts and joins your Wi-Fi. This setup network then goes away.</p>"
                                  "</main></body></html>");
    return httpd_resp_sendstr_chunk(req, NULL);
}

static void url_decode(char *s)
{
    char *o = s;
    for (; *s; s++) {
        if (*s == '+') *o++ = ' ';
        else if (*s == '%' && s[1] && s[2]) {
            char h[3] = { s[1], s[2], 0 };
            *o++ = (char)strtol(h, NULL, 16);
            s += 2;
        } else *o++ = *s;
    }
    *o = 0;
}

static void field(const char *body, const char *name, char *out, size_t max)
{
    size_t nl = strlen(name);
    out[0] = 0;
    for (const char *p = body; p && *p; ) {
        if (!strncmp(p, name, nl) && p[nl] == '=') {
            const char *v = p + nl + 1, *e = strchr(v, '&');
            size_t n = e ? (size_t)(e - v) : strlen(v);
            if (n >= max) n = max - 1;
            memcpy(out, v, n); out[n] = 0;
            url_decode(out);
            return;
        }
        p = strchr(p, '&');
        if (p) p++;
    }
}

static void restart_task(void *arg)
{
    vTaskDelay(pdMS_TO_TICKS(1500));
    esp_restart();
}

static esp_err_t page_save(httpd_req_t *req)
{
    static char body[700];
    int n = httpd_req_recv(req, body, sizeof body - 1);
    if (!setup_mode || n <= 0) { httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "no"); return ESP_FAIL; }
    body[n] = 0;
    char ssid[33], pass[200], url[128];
    field(body, "ssid", ssid, sizeof ssid);
    field(body, "pass", pass, sizeof pass);
    field(body, "url", url, sizeof url);
    memset(body, 0, sizeof body);
    if (!ssid[0]) { httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Choose a network"); return ESP_FAIL; }
    strlcpy(cfg.ssid, ssid, sizeof cfg.ssid);
    strlcpy(cfg.pass, pass, sizeof cfg.pass);
    while (strlen(url) && url[strlen(url) - 1] == '/') url[strlen(url) - 1] = 0;
    if (url[0] && strncmp(url, "http://", 7) && strncmp(url, "https://", 8)) {
        char t[140]; snprintf(t, sizeof t, "http://%s", url); strlcpy(url, t, sizeof url);
    }
    if (url[0]) strlcpy(cfg.url, url, sizeof cfg.url);
    cfg_save();
    say("setup: details saved, restarting");
    httpd_resp_set_type(req, "text/html");
    httpd_resp_sendstr_chunk(req, PAGE_HEAD);
    httpd_resp_sendstr_chunk(req, "<h1>Saved</h1><p>The board is restarting and joining your Wi-Fi. "
                                  "You can close this page. If it cannot join, this setup network "
                                  "comes back after a minute.</p></main></body></html>");
    httpd_resp_sendstr_chunk(req, NULL);
    xTaskCreate(restart_task, "restart", 2048, NULL, 5, NULL);
    return ESP_OK;
}

/* ---------- the workbench, over Wi-Fi ----------
   The same things the serial console does, for a board that is on a wall
   supply with no cable to it. Every one needs the board's key, which is only
   ever shown on the serial console (KEY). */

static bool key_ok(httpd_req_t *req)
{
    char k[80];
    if (httpd_req_get_hdr_value_str(req, "X-Deck-Key", k, sizeof k) != ESP_OK || strcmp(k, cfg.secret)) {
        httpd_resp_set_status(req, "403 Forbidden");
        httpd_resp_sendstr(req, "no\n");
        return false;
    }
    return true;
}

static esp_err_t page_status(httpd_req_t *req)
{
    static char text[7000];
    if (!key_ok(req)) return ESP_OK;
    bridge_status(text, 400);
    strcat(text, "\n");
    say_copy(text + strlen(text), sizeof text - strlen(text));
    httpd_resp_set_type(req, "text/plain");
    return httpd_resp_sendstr(req, text);
}

static esp_err_t page_sh(httpd_req_t *req)
{
    static char cmd[1200], out[8000];
    if (!key_ok(req)) return ESP_OK;
    int n = httpd_req_recv(req, cmd, sizeof cmd - 1);
    if (n <= 0) { httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "no command"); return ESP_FAIL; }
    cmd[n] = 0;
    httpd_resp_set_type(req, "text/plain");
    if (deck_shell(cmd, out, sizeof out, 20000) < 0) return httpd_resp_sendstr(req, "ERR the deck's debug port is not open\n");
    return httpd_resp_sendstr(req, out);
}

static esp_err_t page_setupdeck(httpd_req_t *req)
{
    if (!key_ok(req)) return ESP_OK;
    bridge_request_setup();
    return httpd_resp_sendstr(req, "ok\n");
}

static esp_err_t page_update(httpd_req_t *req)
{
    if (!key_ok(req)) return ESP_OK;
    const esp_partition_t *part = esp_ota_get_next_update_partition(NULL);
    esp_ota_handle_t h;
    char *buf = malloc(4096);
    int left = req->content_len;
    if (!part || !buf || esp_ota_begin(part, OTA_SIZE_UNKNOWN, &h) != ESP_OK) {
        free(buf);
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "cannot start an update");
        return ESP_FAIL;
    }
    say("update: receiving %d bytes", left);
    while (left > 0) {
        int n = httpd_req_recv(req, buf, left > 4096 ? 4096 : left);
        if (n == HTTPD_SOCK_ERR_TIMEOUT) continue;
        if (n <= 0 || esp_ota_write(h, buf, n) != ESP_OK) {
            esp_ota_abort(h); free(buf);
            say("update: failed part way");
            httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "update failed part way");
            return ESP_FAIL;
        }
        left -= n;
    }
    free(buf);
    if (esp_ota_end(h) != ESP_OK || esp_ota_set_boot_partition(part) != ESP_OK) {
        say("update: the firmware sent was not valid");
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "not a valid firmware");
        return ESP_FAIL;
    }
    say("update: accepted, restarting into it");
    httpd_resp_sendstr(req, "ok, restarting\n");
    xTaskCreate(restart_task, "restart", 2048, NULL, 5, NULL);
    return ESP_OK;
}

static void web_start(void)
{
    httpd_config_t hc = HTTPD_DEFAULT_CONFIG();
    hc.stack_size = 8192;
    hc.lru_purge_enable = true;
    hc.max_uri_handlers = 12;
    hc.recv_wait_timeout = 15;
    if (httpd_start(&server, &hc) != ESP_OK) return;
    httpd_uri_t get = { .uri = "/", .method = HTTP_GET, .handler = page_get };
    httpd_uri_t save = { .uri = "/save", .method = HTTP_POST, .handler = page_save };
    httpd_uri_t status = { .uri = "/status", .method = HTTP_GET, .handler = page_status };
    httpd_uri_t sh = { .uri = "/sh", .method = HTTP_POST, .handler = page_sh };
    httpd_uri_t sd = { .uri = "/setupdeck", .method = HTTP_POST, .handler = page_setupdeck };
    httpd_uri_t up = { .uri = "/update", .method = HTTP_POST, .handler = page_update };
    httpd_register_uri_handler(server, &get);
    httpd_register_uri_handler(server, &save);
    httpd_register_uri_handler(server, &status);
    httpd_register_uri_handler(server, &sh);
    httpd_register_uri_handler(server, &sd);
    httpd_register_uri_handler(server, &up);
}

/* ---------- Wi-Fi ---------- */

static void on_wifi(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        if (cfg.ssid[0] && !setup_mode) esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *d = data;
        if (online) say("wifi: lost, reason %d, signal %d", d->reason, d->rssi);
        online = false;
        if (cfg.ssid[0] && !setup_mode) esp_wifi_connect();
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *e = data;
        snprintf(ip_text, sizeof ip_text, IPSTR, IP2STR(&e->ip_info.ip));
        online = true;
        say("wifi: joined, address %s", ip_text);
        esp_ota_mark_app_valid_cancel_rollback();   /* an update that gets this far is kept */
    }
}

static void start_setup_mode(void)
{
    wifi_config_t ap = { 0 };
    setup_mode = true;
    esp_wifi_disconnect();
    strcpy((char *)ap.ap.ssid, AP_SSID);
    ap.ap.ssid_len = strlen(AP_SSID);
    ap.ap.channel = 1;
    ap.ap.max_connection = 2;
    ap.ap.authmode = WIFI_AUTH_OPEN;
    esp_wifi_set_mode(WIFI_MODE_APSTA);
    esp_wifi_set_config(WIFI_IF_AP, &ap);
    say("setup: offering the network \"%s\"; open http://192.168.4.1", AP_SSID);
}

static void net_task(void *arg)
{
    /* Saved details that do not get us on in a minute are probably wrong:
       offer the setup network so they can be put right. */
    int waited = 0, held = 0, tick = 0;
    gpio_config_t boot = { .pin_bit_mask = 1ULL << GPIO_NUM_0, .mode = GPIO_MODE_INPUT, .pull_up_en = GPIO_PULLUP_ENABLE };
    gpio_config(&boot);
    if (!cfg.ssid[0]) start_setup_mode();
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(100));
        held = gpio_get_level(GPIO_NUM_0) ? 0 : held + 1;
        if (held == 50 && !setup_mode) { say("setup: BOOT button held"); start_setup_mode(); }
        if (++tick % 10) continue;
        if (!setup_mode && !online && cfg.ssid[0] && ++waited >= 60) start_setup_mode();
        if (online) waited = 0;
    }
}

bool net_online(void) { return online; }
bool net_setup_mode(void) { return setup_mode; }
const char *net_ip(void) { return ip_text; }

void net_start(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();
    esp_netif_create_default_wifi_ap();
    wifi_init_config_t wc = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&wc));
    esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi, NULL);
    esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, on_wifi, NULL);
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    esp_wifi_set_mode(WIFI_MODE_STA);
    if (cfg.ssid[0]) {
        wifi_config_t sta = { 0 };
        strlcpy((char *)sta.sta.ssid, cfg.ssid, sizeof sta.sta.ssid);
        strlcpy((char *)sta.sta.password, cfg.pass, sizeof sta.sta.password);
        esp_wifi_set_config(WIFI_IF_STA, &sta);
    }
    ESP_ERROR_CHECK(esp_wifi_start());
    esp_wifi_set_ps(WIFI_PS_NONE);          /* mains powered: never doze, never miss a beacon */
    web_start();
    xTaskCreate(net_task, "net", 4096, NULL, 3, NULL);
}
