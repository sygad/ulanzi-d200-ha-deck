/*
 * USB host side, and just enough of the ADB protocol to open streams on the deck.
 *
 * One task owns the IN endpoint and reads every ADB message as it arrives,
 * handing data to whichever stream it belongs to. Anyone may write; writes are
 * serialised by a lock. A stream's writer waits for the deck's OKAY before it
 * sends the next piece, which is ADB's own flow control.
 */
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/stream_buffer.h"
#include "usb/usb_host.h"
#include "esp_timer.h"
#include "adb.h"
#include "say.h"

#define A_CNXN 0x4e584e43
#define A_OPEN 0x4e45504f
#define A_OKAY 0x59414b4f
#define A_CLSE 0x45534c43
#define A_WRTE 0x45545257

#define NSTREAMS 4
#define RXBUF 8192

typedef struct { uint32_t cmd, arg0, arg1, len, sum, magic; } amsg_t;

enum { S_FREE, S_OPENING, S_OPEN, S_CLOSED };

struct adb_stream {
    volatile int state;
    uint32_t local, remote;
    SemaphoreHandle_t ack;
    StreamBufferHandle_t rx;
};

static struct adb_stream streams[NSTREAMS];
static SemaphoreHandle_t table_lock, tx_lock;
static uint32_t next_local = 1;

static usb_host_client_handle_t client;
static usb_device_handle_t dev;
static SemaphoreHandle_t sem_dev, sem_in, sem_out;
static volatile uint8_t new_addr;
static volatile bool gone, arrived, up, attached;

static usb_transfer_t *t_in, *t_out;
static uint8_t ep_in, ep_out;
static int mps_in, adb_if = -1;
static uint32_t adb_max = 4096;
static uint8_t abuf[4096 + 64];

bool adb_ready(void) { return up; }
bool adb_attached(void) { return attached; }

/* ---------- USB plumbing ---------- */

static void lib_task(void *arg)
{
    usb_host_config_t cfg = {
        .skip_phy_setup = false,
        .intr_flags = ESP_INTR_FLAG_LEVEL1,
        .peripheral_map = BIT0,
    };
    ESP_ERROR_CHECK(usb_host_install(&cfg));
    xTaskNotifyGive((TaskHandle_t)arg);
    for (;;) {
        uint32_t flags;
        usb_host_lib_handle_events(portMAX_DELAY, &flags);
    }
}

static void client_cb(const usb_host_client_event_msg_t *msg, void *arg)
{
    if (msg->event == USB_HOST_CLIENT_EVENT_NEW_DEV) {
        new_addr = msg->new_dev.address;
        arrived = true;
    } else if (msg->event == USB_HOST_CLIENT_EVENT_DEV_GONE) {
        gone = true;
    }
    xSemaphoreGive(sem_dev);
}

static void client_task(void *arg)
{
    usb_host_client_config_t cc = {
        .is_synchronous = false,
        .max_num_event_msg = 5,
        .async = { .client_event_callback = client_cb, .callback_arg = NULL },
    };
    ESP_ERROR_CHECK(usb_host_client_register(&cc, &client));
    xTaskNotifyGive((TaskHandle_t)arg);
    for (;;) usb_host_client_handle_events(client, portMAX_DELAY);
}

static void xfer_cb(usb_transfer_t *t)
{
    xSemaphoreGive((SemaphoreHandle_t)t->context);
}

static void cancel(uint8_t ep, SemaphoreHandle_t sem)
{
    usb_host_endpoint_halt(dev, ep);
    usb_host_endpoint_flush(dev, ep);
    xSemaphoreTake(sem, pdMS_TO_TICKS(1000));
    usb_host_endpoint_clear(dev, ep);
}

/* Caller holds tx_lock. */
static int bulk_out(const void *data, int n)
{
    if (!dev || !up) return -1;
    memcpy(t_out->data_buffer, data, n);
    t_out->num_bytes = n;
    t_out->device_handle = dev;
    t_out->bEndpointAddress = ep_out;
    t_out->callback = xfer_cb;
    t_out->context = sem_out;
    xSemaphoreTake(sem_out, 0);
    if (usb_host_transfer_submit(t_out) != ESP_OK) return -1;
    if (xSemaphoreTake(sem_out, pdMS_TO_TICKS(5000)) != pdTRUE) { cancel(ep_out, sem_out); return -1; }
    return t_out->status == USB_TRANSFER_STATUS_COMPLETED ? 0 : -1;
}

/* Only the adb task calls this. timeout_ms < 0 waits for ever. */
static int bulk_in(uint8_t *buf, int want, int timeout_ms)
{
    if (!dev) return -1;
    int ask = ((want + mps_in - 1) / mps_in) * mps_in;      /* IN must be a multiple of the packet size */
    if (ask > (int)t_in->data_buffer_size) ask = t_in->data_buffer_size;
    t_in->num_bytes = ask;
    t_in->device_handle = dev;
    t_in->bEndpointAddress = ep_in;
    t_in->callback = xfer_cb;
    t_in->context = sem_in;
    xSemaphoreTake(sem_in, 0);
    if (usb_host_transfer_submit(t_in) != ESP_OK) return -1;
    if (xSemaphoreTake(sem_in, timeout_ms < 0 ? portMAX_DELAY : pdMS_TO_TICKS(timeout_ms)) != pdTRUE) {
        cancel(ep_in, sem_in);
        return -2;
    }
    if (t_in->status != USB_TRANSFER_STATUS_COMPLETED) return -1;
    int got = t_in->actual_num_bytes;
    if (got > want) got = want;
    memcpy(buf, t_in->data_buffer, got);
    return got;
}

/* ---------- ADB messages ---------- */

static int adb_send(uint32_t cmd, uint32_t a0, uint32_t a1, const void *data, uint32_t len)
{
    amsg_t m = { cmd, a0, a1, len, 0, cmd ^ 0xffffffff };
    for (uint32_t i = 0; i < len; i++) m.sum += ((const uint8_t *)data)[i];
    xSemaphoreTake(tx_lock, portMAX_DELAY);
    int r = bulk_out(&m, sizeof m);
    if (!r && len) r = bulk_out(data, len);
    xSemaphoreGive(tx_lock);
    return r;
}

static int adb_recv(amsg_t *m, int timeout_ms)
{
    int n = bulk_in((uint8_t *)m, sizeof *m, timeout_ms);
    if (n == -2) return -2;
    if (n != sizeof *m) return -1;
    if (m->magic != (m->cmd ^ 0xffffffff) || m->len > 4096) return -1;
    uint32_t got = 0;
    while (got < m->len) {
        n = bulk_in(abuf + got, m->len - got, 3000);
        if (n <= 0) return -1;
        got += n;
    }
    return 0;
}

static struct adb_stream *find(uint32_t local)
{
    for (int i = 0; i < NSTREAMS; i++)
        if (streams[i].state != S_FREE && streams[i].local == local) return &streams[i];
    return NULL;
}

static void dispatch(const amsg_t *m)
{
    struct adb_stream *s = find(m->arg1);
    switch (m->cmd) {
    case A_OKAY:
        if (!s) break;
        s->remote = m->arg0;
        if (s->state == S_OPENING) s->state = S_OPEN;
        xSemaphoreGive(s->ack);
        break;
    case A_WRTE:
        if (!s || s->state != S_OPEN) { adb_send(A_CLSE, m->arg1, m->arg0, NULL, 0); break; }
        if (m->len) xStreamBufferSend(s->rx, abuf, m->len, pdMS_TO_TICKS(10000));
        adb_send(A_OKAY, s->local, s->remote, NULL, 0);
        break;
    case A_CLSE:
        if (!s) break;
        if (s->state == S_OPEN) adb_send(A_CLSE, s->local, s->remote, NULL, 0);
        s->state = S_CLOSED;
        xSemaphoreGive(s->ack);
        break;
    }
}

/* ---------- streams, for everyone else ---------- */

adb_stream_t *adb_open(const char *service, int timeout_ms)
{
    struct adb_stream *s = NULL;
    if (!up) return NULL;
    xSemaphoreTake(table_lock, portMAX_DELAY);
    for (int i = 0; i < NSTREAMS; i++)
        if (streams[i].state == S_FREE) { s = &streams[i]; break; }
    if (s) {
        s->local = next_local++;
        s->remote = 0;
        xStreamBufferReset(s->rx);
        xSemaphoreTake(s->ack, 0);
        s->state = S_OPENING;
    }
    xSemaphoreGive(table_lock);
    if (!s) return NULL;
    if (adb_send(A_OPEN, s->local, 0, service, strlen(service) + 1) ||
        xSemaphoreTake(s->ack, pdMS_TO_TICKS(timeout_ms)) != pdTRUE || s->state != S_OPEN) {
        s->state = S_FREE;
        return NULL;
    }
    return s;
}

int adb_write(adb_stream_t *s, const void *data, size_t n)
{
    const uint8_t *p = data;
    while (n) {
        uint32_t c = n > adb_max ? adb_max : n;
        if (s->state != S_OPEN) return -1;
        xSemaphoreTake(s->ack, 0);
        if (adb_send(A_WRTE, s->local, s->remote, p, c)) return -1;
        if (xSemaphoreTake(s->ack, pdMS_TO_TICKS(10000)) != pdTRUE || s->state != S_OPEN) return -1;
        p += c; n -= c;
    }
    return 0;
}

int adb_read(adb_stream_t *s, void *buf, size_t max, int timeout_ms)
{
    int waited = 0;
    for (;;) {
        size_t n = xStreamBufferReceive(s->rx, buf, max, pdMS_TO_TICKS(20));
        if (n) return (int)n;
        if (s->state != S_OPEN) { if (xStreamBufferIsEmpty(s->rx)) return 0; continue; }
        waited += 20;
        if (waited >= timeout_ms) return -2;
    }
}

void adb_close(adb_stream_t *s)
{
    if (!s) return;
    if (s->state == S_OPEN) adb_send(A_CLSE, s->local, s->remote, NULL, 0);
    s->state = S_FREE;
}

/* ---------- the deck arriving and leaving ---------- */

static void deck_close(void)
{
    up = false;
    for (int i = 0; i < NSTREAMS; i++)
        if (streams[i].state == S_OPEN || streams[i].state == S_OPENING) {
            streams[i].state = S_CLOSED;
            xSemaphoreGive(streams[i].ack);
        }
    xSemaphoreTake(tx_lock, portMAX_DELAY);         /* nobody is mid-write */
    if (dev) {
        if (adb_if >= 0) usb_host_interface_release(client, dev, adb_if);
        usb_host_device_close(client, dev);
    }
    dev = NULL; adb_if = -1; attached = false;
    xSemaphoreGive(tx_lock);
}

static void deck_open(void)
{
    const usb_device_desc_t *dd;
    const usb_config_desc_t *cd;
    usb_device_info_t info;
    amsg_t m;
    static const char ident[] = "host::";

    if (usb_host_device_open(client, new_addr, &dev) != ESP_OK) { dev = NULL; return; }
    attached = true;
    usb_host_device_info(dev, &info);
    usb_host_get_device_descriptor(dev, &dd);
    usb_host_get_active_config_descriptor(dev, &cd);
    say("usb: device %04x:%04x at %s speed", dd->idVendor, dd->idProduct,
        info.speed == USB_SPEED_LOW ? "low" : info.speed == USB_SPEED_FULL ? "full" : "high");

    adb_if = -1;
    for (int i = 0; i < cd->bNumInterfaces; i++) {
        int off = 0;
        const usb_intf_desc_t *id = usb_parse_interface_descriptor(cd, i, 0, &off);
        if (!id) continue;
        if (!(id->bInterfaceClass == 0xff && id->bInterfaceSubClass == 0x42 && id->bInterfaceProtocol == 0x01)) continue;
        adb_if = i;
        for (int k = 0; k < id->bNumEndpoints; k++) {
            int o = off;
            const usb_ep_desc_t *ep = usb_parse_endpoint_descriptor_by_index(id, k, cd->wTotalLength, &o);
            if (!ep) continue;
            if (ep->bEndpointAddress & 0x80) { ep_in = ep->bEndpointAddress; mps_in = USB_EP_DESC_GET_MPS(ep); }
            else ep_out = ep->bEndpointAddress;
        }
    }
    if (adb_if < 0) { say("usb: no debug interface on this device"); return; }
    esp_err_t e = usb_host_interface_claim(client, dev, adb_if, 0);
    if (e != ESP_OK) { say("usb: could not claim the debug interface: %s", esp_err_to_name(e)); adb_if = -1; return; }

    up = true;                                      /* so the handshake can be written */
    if (adb_send(A_CNXN, 0x01000000, 4096, ident, sizeof ident) || adb_recv(&m, 5000) || m.cmd != A_CNXN) {
        up = false;
        say("usb: debug port did not answer");
        return;
    }
    adb_max = m.arg1 < 4096 ? m.arg1 : 4096;
    say("usb: debug port open");
}

static void adb_task(void *arg)
{
    int64_t idle_since = esp_timer_get_time();
    int kicks = 0;
    for (;;) {
        if (!up) {
            xSemaphoreTake(sem_dev, pdMS_TO_TICKS(1000));
            if (gone) { gone = false; deck_close(); say("usb: deck unplugged"); }
            if (arrived) { arrived = false; idle_since = esp_timer_get_time(); deck_close(); deck_open(); }
            if (up) { if (kicks) say("usb: found the deck after looking again %d time(s)", kicks); kicks = 0; continue; }
            /* Nothing usable for a while. The port can miss a deck that was already plugged in
             * when this board restarted, and then waits for ever. Switch the port off and on
             * to look again. With no deck plugged in this does nothing. */
            if (esp_timer_get_time() - idle_since > 8000000) {
                idle_since = esp_timer_get_time();
                if (usb_host_lib_set_root_port_power(false) == ESP_OK) {
                    vTaskDelay(pdMS_TO_TICKS(300));
                    usb_host_lib_set_root_port_power(true);
                    if (kicks++ == 0) say("usb: no deck seen, looking again");
                }
            }
            continue;
        }
        amsg_t m;
        int r = adb_recv(&m, -1);
        if (r == 0) { dispatch(&m); continue; }
        /* the read failed: the deck went away, or the port is in a state we cannot use */
        bool was_gone = gone;
        deck_close();
        if (was_gone) { gone = false; say("usb: deck unplugged"); }
        else say("usb: debug port stopped answering");
        idle_since = esp_timer_get_time();
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void adb_start(void)
{
    sem_dev = xSemaphoreCreateCounting(8, 0);
    sem_in = xSemaphoreCreateBinary();
    sem_out = xSemaphoreCreateBinary();
    table_lock = xSemaphoreCreateMutex();
    tx_lock = xSemaphoreCreateMutex();
    for (int i = 0; i < NSTREAMS; i++) {
        streams[i].ack = xSemaphoreCreateBinary();
        streams[i].rx = xStreamBufferCreate(RXBUF, 1);
    }
    xTaskCreatePinnedToCore(lib_task, "usb_lib", 4096, xTaskGetCurrentTaskHandle(), 2, NULL, 0);
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(2000));
    xTaskCreatePinnedToCore(client_task, "usb_client", 4096, xTaskGetCurrentTaskHandle(), 5, NULL, 0);
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(2000));
    ESP_ERROR_CHECK(usb_host_transfer_alloc(4096 + 64, 0, &t_in));
    ESP_ERROR_CHECK(usb_host_transfer_alloc(4096 + 64, 0, &t_out));
    xTaskCreatePinnedToCore(adb_task, "adb", 6144, NULL, 4, NULL, 0);
}
