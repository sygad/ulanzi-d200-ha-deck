/*
 * deckd — device app for the Ulanzi D200 Home Assistant Control Deck.
 *
 * Installed as /userdata/UlanziDeckKey, because that is the path the stock init
 * script (/etc/init.d/S51startApp.sh) launches at boot.
 *
 * What it does:
 *   - draws the cached layout from /userdata/deck/layout.bin the moment it starts,
 *     before any host is talking to it
 *   - reads the key matrix from /dev/input/event0
 *   - talks to the Mac bridge over the 1024-byte HID gadget, /dev/hidg0
 *   - ticks clock keys by itself once the bridge has told it the time
 *     (the deck has no real-time clock and no network)
 *   - turns the screen off after a while with nothing happening, and brings it
 *     back on the first key pressed, swallowing that press
 *
 * The host does the drawing. Every key arrives as a finished image; the only
 * thing rendered here is clock text, from glyph atlases the host supplies.
 *
 * Freestanding on purpose: no libc, raw Linux syscalls, static ARM binary.
 * It builds with any ARM compiler and has nothing to break on the device.
 */

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef signed char i8;
typedef short i16;
typedef int i32;

#define FW_MAJOR 4
#define FW_MINOR 12
/* The same two numbers as words, so --version and the log can never drift from
   what the status message reports. They used to be typed out by hand, and said
   1.2 for every release after it. */
#define VSTR_(x) #x
#define VSTR(x) VSTR_(x)
#define FW_TEXT VSTR(FW_MAJOR) "." VSTR(FW_MINOR)
#define PROTO 1

/* ---------- syscalls (ARM EABI) ---------- */
static long sys(long n, long a, long b, long c, long d, long e, long f)
{
    register long r7 __asm__("r7") = n;
    register long r0 __asm__("r0") = a;
    register long r1 __asm__("r1") = b;
    register long r2 __asm__("r2") = c;
    register long r3 __asm__("r3") = d;
    register long r4 __asm__("r4") = e;
    register long r5 __asm__("r5") = f;
    __asm__ volatile("svc 0"
                     : "+r"(r0)
                     : "r"(r7), "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5)
                     : "memory");
    return r0;
}
#define SYS_exit 1
#define SYS_read 3
#define SYS_write 4
#define SYS_open 5
#define SYS_close 6
#define SYS_lseek 19
#define SYS_rename 38
#define SYS_ioctl 54
#define SYS_mkdir 39
#define SYS_munmap 91
#define SYS_fsync 118
#define SYS_poll 168
#define SYS_mmap2 192
#define SYS_clock_gettime 263

#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0100
#define O_TRUNC 01000
#define O_APPEND 02000
#define O_NONBLOCK 04000
#define POLLIN 1
#define POLLOUT 4
#define POLLERR 8
#define POLLHUP 16

static long s_open(const char *p, int fl, int mode) { return sys(SYS_open, (long)p, fl, mode, 0, 0, 0); }
static long s_read(int fd, void *b, u32 n) { return sys(SYS_read, fd, (long)b, n, 0, 0, 0); }
static long s_write(int fd, const void *b, u32 n) { return sys(SYS_write, fd, (long)b, n, 0, 0, 0); }
static long s_close(int fd) { return sys(SYS_close, fd, 0, 0, 0, 0, 0); }
struct pollfd { int fd; short events; short revents; };
static long s_poll(struct pollfd *p, int n, int ms) { return sys(SYS_poll, (long)p, n, ms, 0, 0, 0); }
static void *s_mmap(u32 len, int prot, int flags, int fd)
{
    long r = sys(SYS_mmap2, 0, len, prot, flags, fd, 0);
    return (r < 0 && r > -4096) ? 0 : (void *)r;
}

/* the compiler may call these even in freestanding code */
void *memcpy(void *d, const void *s, u32 n)
{
    u8 *a = d; const u8 *b = s;
    while (n--) *a++ = *b++;
    return d;
}
void *memmove(void *d, const void *s, u32 n)
{
    u8 *a = d; const u8 *b = s;
    if (a < b) while (n--) *a++ = *b++;
    else { a += n; b += n; while (n--) *--a = *--b; }
    return d;
}
void *memset(void *d, int c, u32 n)
{
    u8 *a = d;
    while (n--) *a++ = (u8)c;
    return d;
}
void __aeabi_memcpy(void *d, const void *s, u32 n) { memcpy(d, s, n); }
void __aeabi_memcpy4(void *d, const void *s, u32 n) { memcpy(d, s, n); }
void __aeabi_memcpy8(void *d, const void *s, u32 n) { memcpy(d, s, n); }
void __aeabi_memmove(void *d, const void *s, u32 n) { memmove(d, s, n); }
void __aeabi_memmove4(void *d, const void *s, u32 n) { memmove(d, s, n); }
void __aeabi_memmove8(void *d, const void *s, u32 n) { memmove(d, s, n); }
void __aeabi_memset(void *d, u32 n, int c) { memset(d, c, n); }
void __aeabi_memset4(void *d, u32 n, int c) { memset(d, c, n); }
void __aeabi_memset8(void *d, u32 n, int c) { memset(d, c, n); }
void __aeabi_memclr(void *d, u32 n) { memset(d, 0, n); }
void __aeabi_memclr4(void *d, u32 n) { memset(d, 0, n); }
void __aeabi_memclr8(void *d, u32 n) { memset(d, 0, n); }

static u32 slen(const char *s) { u32 n = 0; while (s[n]) n++; return n; }
static int seq(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }

/* ---------- log: /tmp is tmpfs, so this costs no flash ---------- */
static int logfd = -1;
static u32 logged;
static void logs(const char *s)
{
    u32 n = slen(s);
    if (logfd >= 0 && logged < 200000) { s_write(logfd, s, n); logged += n; }
}
static void logn(const char *s, u32 v)
{
    char b[12]; int i = 11;
    b[i] = 0;
    do { b[--i] = '0' + v % 10; v /= 10; } while (v);
    logs(s); logs(b + i); logs("\n");
}

/* ---------- geometry ---------- */
#define LW 1280        /* landscape canvas */
#define LH 720
#define FBW 720        /* framebuffer is portrait, and 180 degrees round */
#define FBH 1280
#define NKEYS 14
#define WIDE 13
#define TILE_MAX (512 * 240)     /* the largest picture one key may have */
#define MAXSCREENS 32
#define BUFMAX (12u << 20)

static u32 *fb;                 /* mmap of /dev/fb0, or the shadow below */
static int fbfd = -1, fb_is_shadow;
static u32 shadow[FBW * FBH];
static u32 tile[TILE_MAX];

static u8 rxbuf[BUFMAX];        /* message being reassembled from HID reports */
static u32 rxlen;
static int rxlive;

static u8 lay[BUFMAX];          /* the current layout blob */
static u32 laylen;
static int layok, nscreens, cur;
static u32 layout_id;

static struct { u8 *p; u32 len, maplen; } live[MAXSCREENS][NKEYS];

/* Key map: the key code at each position, in reading order, wide key last.
   Recorded on 13 Nov 2026 by pressing all fourteen in turn (bridge --keytest).
   Against the device tree's matrix: columns run right to left, and the top
   two rows are swapped — matrix row 1 is the top row, row 0 the middle.
   /userdata/deck/keymap, or a KEYMAP message, overrides this. */
static u8 keymap[NKEYS] = { 29, 15, 14, 13, 12, 11, 10, 9, 8, 7, 34, 33, 31, 30 };

static u8 down[NKEYS], held[NKEYS];
static u32 t_down[NKEYS];
static u8 hist[16];
static int nhist;

static int hidfd = -1, evfd = -1;
static u32 last_ping, have_ping, ha_up;
static u32 host_unix, host_mono;        /* time, as the bridge last told us */
static i32 host_tz;
static u8 datestr[48];
static u32 datelen;
static u32 clock_drawn[NKEYS];

/* ---------- the screen going to sleep ----------
   The panel is lit for as long as the deck has power, which is as long as the
   Mac is on, so it is turned off after a spell with nothing happening. The
   layout carries the number of minutes (byte 15; 0 means never). Until a
   layout says otherwise this is the default, so a deck with no usable layout
   does not sit lit for days. */
#define SLEEP_DEFAULT 20                /* minutes */
#define BL_PATH "/sys/class/backlight/backlight/brightness"
static u32 sleep_min = SLEEP_DEFAULT;
static u32 t_act;                       /* when something last happened */
static int asleep;
static u32 bright = 220;                /* the brightness to come back to */

static u32 r32(const u8 *p) { return p[0] | p[1] << 8 | p[2] << 16 | (u32)p[3] << 24; }
static u32 r16(const u8 *p) { return p[0] | p[1] << 8; }

static u32 now_ms(void)
{
    u32 ts[2];
    sys(SYS_clock_gettime, 1 /* CLOCK_MONOTONIC */, (long)ts, 0, 0, 0, 0);
    return ts[0] * 1000u + ts[1] / 1000000u;
}
static int linked(void) { return have_ping && (now_ms() - last_ping) < 5000; }

/* ---------- the backlight ---------- */
static u32 bl_read(void)                /* whatever brightness the panel is at now */
{
    long fd = s_open(BL_PATH, O_RDONLY, 0), n;
    u8 b[8]; u32 v = 0, i;
    if (fd < 0) return 0;
    n = s_read(fd, b, sizeof b);
    s_close(fd);
    for (i = 0; i < (u32)n && b[i] >= '0' && b[i] <= '9'; i++) v = v * 10 + (b[i] - '0');
    return v > 255 ? 255 : v;
}
static void bl_write(u32 v)
{
    long fd; u8 t[4]; u32 i = 0;
    if (v > 255) v = 255;
    if (v >= 100) t[i++] = '0' + v / 100;
    if (v >= 10) t[i++] = '0' + v / 10 % 10;
    t[i++] = '0' + v % 10;
    fd = s_open(BL_PATH, O_WRONLY, 0);
    if (fd >= 0) { s_write(fd, t, i); s_close(fd); }
}

static void draw_all(void);
static void screen_off(void)
{
    if (asleep) return;
    bright = bl_read();                 /* come back to what it was showing at */
    if (!bright) bright = 220;
    asleep = 1;
    bl_write(0);
    logs("screen off\n");
}
static void screen_on(void)             /* also the one place activity is noted */
{
    t_act = now_ms();
    if (!asleep) return;
    asleep = 0;
    bl_write(bright);
    draw_all();
    logs("screen on\n");
}

/* ---------- drawing ---------- */
static const u8 *keyrec(int s, int k) { return lay + r32(lay + 20) + (u32)(s * NKEYS + k) * 32; }

static void rle_decode(const u8 *src, u32 n, u32 *dst, u32 npx)
{
    u32 i = 0, o = 0;
    while (i < n && o < npx) {
        u32 t = src[i++], cnt, px;
        if (t >= 0x80 && t != 0xFF) {               /* literal pixels */
            cnt = t - 0x7F;
            while (cnt-- && o < npx && i + 3 <= n) {
                dst[o++] = (u32)src[i] << 16 | (u32)src[i + 1] << 8 | src[i + 2];
                i += 3;
            }
            continue;
        }
        if (t == 0xFF) {                            /* long run */
            if (i + 2 > n) break;
            cnt = r16(src + i); i += 2;
        } else cnt = t + 1;
        if (i + 3 > n) break;
        px = (u32)src[i] << 16 | (u32)src[i + 1] << 8 | src[i + 2];
        i += 3;
        if (cnt > npx - o) cnt = npx - o;
        while (cnt--) dst[o++] = px;
    }
    while (o < npx) dst[o++] = 0;
}

static u32 blend(u32 d, u32 r, u32 g, u32 b, u32 a)
{
    u32 dr = d >> 16 & 255, dg = d >> 8 & 255, db = d & 255;
    dr += ((i32)r - (i32)dr) * (i32)a / 255;
    dg += ((i32)g - (i32)dg) * (i32)a / 255;
    db += ((i32)b - (i32)db) * (i32)a / 255;
    return dr << 16 | dg << 8 | db;
}

/* font: u16 nglyphs, u16 pad, then 12 bytes a glyph:
   u16 code, u8 w, u8 h, i8 xoff, i8 yoff (top, from the baseline), u8 advance, u8 pad, u32 data */
static const u8 *glyph(int font, u32 code)
{
    u32 nf = lay[13], ft = r32(lay + 16), off, n, i;
    if ((u32)font >= nf) return 0;
    off = r32(lay + ft + 4 * font);
    if (off + 4 > laylen) return 0;
    n = r16(lay + off);
    if (off + 4 + n * 12 > laylen) return 0;
    for (i = 0; i < n; i++) {
        const u8 *g = lay + off + 4 + i * 12;
        if (r16(g) == code) return g;
    }
    return 0;
}
static u32 utf8(const u8 *s, u32 n, u32 *i)
{
    u32 c = s[(*i)++];
    if (c < 0x80) return c;
    if (c >= 0xC0 && c < 0xE0 && *i < n) { c = (c & 31) << 6 | (s[*i] & 63); *i += 1; return c; }
    if (c >= 0xE0 && c < 0xF0 && *i + 1 < n) { c = (c & 15) << 12 | (s[*i] & 63) << 6 | (s[*i + 1] & 63); *i += 2; return c; }
    return '?';
}
static void draw_text(int tw, int th, int font, const u8 *s, u32 n, int align, int x, int y, const u8 *rgb)
{
    u32 i; int w = 0;
    for (i = 0; i < n;) { const u8 *g = glyph(font, utf8(s, n, &i)); if (g) w += g[6]; }
    if (align == 0) x -= w / 2; else if (align == 2) x -= w;
    for (i = 0; i < n;) {
        const u8 *g = glyph(font, utf8(s, n, &i));
        u32 gw, gh, off; int gx, gy; u32 px, py;
        if (!g) continue;
        gw = g[2]; gh = g[3]; off = r32(g + 8);
        gx = x + (i8)g[4]; gy = y + (i8)g[5];
        x += g[6];
        if (off + gw * gh > laylen) continue;
        for (py = 0; py < gh; py++) {
            int ty = gy + (int)py;
            if (ty < 0 || ty >= th) continue;
            for (px = 0; px < gw; px++) {
                int tx = gx + (int)px; u32 a = lay[off + py * gw + px];
                if (!a || tx < 0 || tx >= tw) continue;
                tile[ty * tw + tx] = blend(tile[ty * tw + tx], rgb[0], rgb[1], rgb[2], a);
            }
        }
    }
}

static int local_secs(u32 *out)             /* seconds since local midnight */
{
    u32 t;
    if (!have_ping) return 0;
    t = host_unix + (u32)host_tz + (now_ms() - host_mono) / 1000u;
    *out = t % 86400u;
    return 1;
}
static u32 clock_text(const u8 *kr, u8 *b)
{
    u32 s, n = 0, h, m, fl = kr[4];
    if (!local_secs(&s)) { memcpy(b, "--:--", 5); return 5; }
    h = s / 3600; m = s / 60 % 60;
    if (fl & 4) {                           /* 12 hour: no leading zero */
        u32 h12 = h % 12; if (!h12) h12 = 12;
        if (h12 >= 10) b[n++] = '1';
        b[n++] = '0' + h12 % 10;
    } else { b[n++] = '0' + h / 10; b[n++] = '0' + h % 10; }
    b[n++] = ':'; b[n++] = '0' + m / 10; b[n++] = '0' + m % 10;
    if (fl & 8) { b[n++] = ':'; b[n++] = '0' + s % 60 / 10; b[n++] = '0' + s % 10; }
    if (fl & 4) { b[n++] = ' '; b[n++] = h < 12 ? 'a' : 'p'; b[n++] = 'm'; }
    return n;
}

/* Where key k's picture goes on the panel. The layout says; this program
   has no grid of its own. With no layout at all there is nothing to draw but
   the "not connected" dot, which needs somewhere to be: the corner where the
   wide key usually is. */
static void slot(int k, int *x, int *y, int *w, int *h)
{
    if (layok) {
        const u8 *p = lay + 24 + k * 8;
        *x = r16(p); *y = r16(p + 2); *w = r16(p + 4); *h = r16(p + 6);
    } else { *x = 768; *y = 512; *w = 512; *h = 208; }
}

static void blit(int x0, int y0, int tw, int th)
{
    int lx, ly;
    /* fb[y][x] = L[lx = 1279 - y][ly = x] */
    for (lx = 0; lx < tw; lx++) {
        u32 *row = fb + (u32)(LW - 1 - (x0 + lx)) * FBW + y0;
        const u32 *src = tile + lx;
        for (ly = 0; ly < th; ly++) row[ly] = src[ly * tw];
    }
    if (fb_is_shadow) {
        u32 first = LW - (x0 + tw);
        sys(SYS_lseek, fbfd, first * FBW * 4, 0, 0, 0, 0);
        s_write(fbfd, fb + first * FBW, (u32)tw * FBW * 4);
    }
}

static void clear_screen(void)          /* between the keys the panel is always black */
{
    u32 i;
    for (i = 0; i < FBW * FBH; i++) fb[i] = 0;
    if (fb_is_shadow) { sys(SYS_lseek, fbfd, 0, 0, 0, 0, 0); s_write(fbfd, fb, FBW * FBH * 4); }
}

static void draw_key(int k)
{
    int x0, y0, tw, th;
    u32 npx, i;
    const u8 *img = 0, *kr = 0;
    u32 len = 0;

    if (asleep) return;                 /* the screen is off: redrawn on the way back */
    if (!layok && k != WIDE) return;
    slot(k, &x0, &y0, &tw, &th);
    npx = (u32)tw * th;
    if (layok) {
        kr = keyrec(cur, k);
        if (live[cur][k].p) { img = live[cur][k].p; len = live[cur][k].len; }
        else if (kr[4] & 1) { img = lay + r32(kr + 24); len = r32(kr + 28); }
    }
    if (img && len >= 4 && (int)r16(img) == tw && (int)r16(img + 2) == th)
        rle_decode(img + 4, len - 4, tile, npx);
    else
        for (i = 0; i < npx; i++) tile[i] = 0;

    if (kr && (kr[4] & 3) == 3) {           /* a clock key: the time is ours to draw */
        u8 b[16]; u32 n = clock_text(kr, b), s = 0;
        draw_text(tw, th, kr[5], b, n, kr[6], (i16)r16(kr + 8), (i16)r16(kr + 10), kr + 16);
        if ((kr[4] & 16) && datelen)
            draw_text(tw, th, kr[7], datestr, datelen, kr[19], (i16)r16(kr + 12), (i16)r16(kr + 14), kr + 20);
        local_secs(&s);
        clock_drawn[k] = (kr[4] & 8) ? s : s / 60;
    }
    if (down[k])                            /* pressed: lift the whole key a little */
        for (i = 0; i < npx; i++) {
            u32 p = tile[i], r = (p >> 16 & 255) + 0x38, g = (p >> 8 & 255) + 0x38, b = (p & 255) + 0x38;
            tile[i] = (r > 255 ? 255 : r) << 16 | (g > 255 ? 255 : g) << 8 | (b > 255 ? 255 : b);
        }
    if (k == WIDE && !(linked() && ha_up) && tw >= 64 && th >= 64) {
        /* the "not connected" marker, in the top right of the wide key: red with
           no bridge, amber with a bridge but no Home Assistant behind it */
        u32 col = linked() ? 0xFFA000 : 0xFF2020;
        int cx = tw - 44, cy = 36, r = 9, x, y;
        for (y = -r; y <= r; y++)
            for (x = -r; x <= r; x++)
                if (x * x + y * y <= r * r) tile[(cy + y) * tw + cx + x] = col;
    }
    blit(x0, y0, tw, th);
}
static void draw_all(void) { int k; for (k = 0; k < NKEYS; k++) draw_key(k); }

/* At power-up the panel is showing the bootloader's logo from a buffer of its
   own, and goes on showing it whatever is drawn to /dev/fb0. Unblanking the
   framebuffer is what hands the screen over. (The vendor app did this without
   knowing, through Qt.) Done at start and twice more shortly after, in case
   the display driver was not ready the first time; it costs nothing if it was. */
static void show_fb(void)
{
    if (fbfd >= 0) sys(SYS_ioctl, fbfd, 0x4611 /* FBIOBLANK */, 0 /* FB_BLANK_UNBLANK */, 0, 0, 0);
}

/* ---------- live tiles ---------- */
static void live_drop(int s, int k)
{
    if (live[s][k].p) sys(SYS_munmap, (long)live[s][k].p, live[s][k].maplen, 0, 0, 0, 0);
    live[s][k].p = 0; live[s][k].len = 0;
}
static void live_clear(void)
{
    int s, k;
    for (s = 0; s < MAXSCREENS; s++) for (k = 0; k < NKEYS; k++) live_drop(s, k);
}

/* ---------- layout ---------- */
#define DIR "/userdata/deck"
static int layout_valid(const u8 *b, u32 n)
{
    u32 ns, so, s, k;
    if (n < 24 + 8 * NKEYS || b[0] != 'U' || b[1] != 'D' || b[2] != 'L' || b[3] != '2') return 0;
    if (r32(b + 4) != n) return 0;
    for (k = 0; k < NKEYS; k++) {           /* every key's place must be on the panel */
        const u8 *p = b + 24 + k * 8;
        u32 x = r16(p), y = r16(p + 2), w = r16(p + 4), h = r16(p + 6);
        if (!w || !h || w * h > TILE_MAX || x + w > LW || y + h > LH) return 0;
    }
    ns = b[12];
    if (ns < 1 || ns > MAXSCREENS) return 0;
    so = r32(b + 20);
    if (so > n || ns * NKEYS * 32 > n - so) return 0;
    if (r32(b + 16) > n || b[13] * 4u > n - r32(b + 16)) return 0;
    for (s = 0; s < ns; s++)
        for (k = 0; k < NKEYS; k++) {
            const u8 *kr = b + so + (s * NKEYS + k) * 32;
            u32 io = r32(kr + 24), il = r32(kr + 28);
            if ((kr[4] & 1) && (io > n || il > n - io)) return 0;
        }
    return 1;
}
static void layout_adopt(void)
{
    layok = 1; nscreens = lay[12]; layout_id = r32(lay + 8);
    cur = lay[14] < nscreens ? lay[14] : 0;
    sleep_min = lay[15];                /* minutes before the screen goes off, 0 never */
    nhist = 0;
    memset(down, 0, sizeof down);
    live_clear();
    clear_screen();
}
static void layout_load(void)
{
    long fd = s_open(DIR "/layout.bin", O_RDONLY, 0), n;
    u32 got = 0;
    layok = 0;
    if (fd < 0) { logs("no cached layout\n"); return; }
    while (got < BUFMAX && (n = s_read(fd, lay + got, BUFMAX - got)) > 0) got += n;
    s_close(fd);
    laylen = got;
    if (layout_valid(lay, got)) { layout_adopt(); logn("layout loaded, screens ", nscreens); }
    else logs("cached layout is not valid\n");
}
static void layout_store(const u8 *b, u32 n)
{
    long fd;
    if (!layout_valid(b, n)) { logs("layout rejected\n"); return; }
    fd = s_open(DIR "/layout.tmp", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        u32 put = 0; long w;
        while (put < n && (w = s_write(fd, b + put, n - put)) > 0) put += w;
        sys(SYS_fsync, fd, 0, 0, 0, 0, 0);
        s_close(fd);
        if (put == n) sys(SYS_rename, (long)DIR "/layout.tmp", (long)DIR "/layout.bin", 0, 0, 0, 0);
        else logs("layout: short write to cache\n");
    }
    memcpy(lay, b, n);
    laylen = n;
    layout_adopt();
    logn("layout received, bytes ", n);
    screen_on();                            /* somebody pressed Send to device */
    draw_all();
}

/* ---------- HID link ---------- */
static void hid_send(u8 type, const u8 *body, u32 n)
{
    static u8 rep[1024];
    struct pollfd p;
    if (hidfd < 0 || n > 1020) return;
    memset(rep, 0, sizeof rep);
    rep[0] = 3;                             /* first and last fragment */
    rep[1] = (u8)(n + 1); rep[2] = (u8)((n + 1) >> 8);
    rep[3] = type;
    memcpy(rep + 4, body, n);
    p.fd = hidfd; p.events = POLLOUT; p.revents = 0;
    if (s_poll(&p, 1, 60) > 0 && (p.revents & POLLOUT)) s_write(hidfd, rep, sizeof rep);
    /* else: nobody is reading. Dropped on purpose — presses are never queued. */
}
static void send_status(void)
{
    u8 b[10 + NKEYS];
    b[0] = PROTO; b[1] = FW_MAJOR; b[2] = FW_MINOR;
    b[3] = (u8)cur; b[4] = (u8)nscreens; b[5] = (u8)layok;
    b[6] = (u8)layout_id; b[7] = (u8)(layout_id >> 8); b[8] = (u8)(layout_id >> 16); b[9] = (u8)(layout_id >> 24);
    memcpy(b + 10, keymap, NKEYS);
    hid_send(0x81, b, sizeof b);
}

static void go(int s, int push)
{
    if (!layok || s < 0 || s >= nscreens || s == cur) return;
    if (push) {
        if (nhist == 16) { memmove(hist, hist + 1, 15); nhist = 15; }
        hist[nhist++] = (u8)cur;
    }
    cur = s;
    memset(down, 0, sizeof down);           /* a key held across the change is forgotten */
    draw_all();
    send_status();
}

static void fire(int k, int hold)
{
    const u8 *kr; u8 kind, arg, b[3];
    if (!layok) return;
    kr = keyrec(cur, k);
    if (!(kr[4] & 1)) return;
    kind = kr[hold ? 2 : 0]; arg = kr[hold ? 3 : 1];
    switch (kind) {
    case 1:                                 /* Home Assistant's to act on */
        if (ha_up) { b[0] = (u8)cur; b[1] = (u8)k; b[2] = hold ? 2 : 1; hid_send(0x82, b, 3); }
        break;
    case 2: go((cur + nscreens - 1) % nscreens, 1); break;
    case 3: go((cur + 1) % nscreens, 1); break;
    case 4: go(arg, 1); break;
    case 5: if (nhist) go(hist[--nhist], 0); break;
    }
}

/* The brightness somebody chose, kept on the deck so a power cut does not
   throw it away and nothing has to tell it again at every start. */
static void bright_save(void)
{
    long fd = s_open(DIR "/brightness", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) { u8 b = (u8)bright; s_write(fd, &b, 1); s_close(fd); }
}

static void keymap_save(void)
{
    long fd = s_open(DIR "/keymap", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) { s_write(fd, keymap, NKEYS); s_close(fd); }
}

static void on_message(const u8 *m, u32 n)
{
    u8 type; const u8 *b;
    if (!n) return;
    type = m[0]; b = m + 1; n--;
    switch (type) {
    case 1: {                               /* PING: time, link state, today's date */
        u32 was = linked() && ha_up, dl;
        if (n < 10) return;
        host_unix = r32(b); host_tz = (i32)r32(b + 4); host_mono = now_ms();
        ha_up = b[8];
        dl = b[9]; if (dl > sizeof datestr) dl = sizeof datestr; if (dl > n - 10) dl = n - 10;
        if (dl != datelen || (dl && r32(b + 10) != r32(datestr))) { memcpy(datestr, b + 10, dl); datelen = dl; }
        if (!have_ping) { have_ping = 1; last_ping = host_mono; draw_all(); }
        last_ping = host_mono;
        if (was && !ha_up) { live_clear(); draw_all(); }
        send_status();
        break;
    }
    case 2: layout_store(b, n); send_status(); break;
    case 3: {                               /* TILE: a live image for one key */
        u32 s, k, il; u8 *p;
        if (n < 6) return;
        s = b[0]; k = b[1]; il = n - 2;
        if (s >= MAXSCREENS || k >= NKEYS) return;
        live_drop(s, k);
        p = s_mmap(il, 3 /* RW */, 0x22 /* PRIVATE|ANON */, -1);
        if (!p) return;
        memcpy(p, b + 2, il);
        live[s][k].p = p; live[s][k].len = il; live[s][k].maplen = il;
        if ((int)s == cur) draw_key(k);
        break;
    }
    case 4: if (n >= 1) { screen_on(); go(b[0], 1); } break;
    case 5: {                               /* BACKLIGHT 0-255 */
        u32 v;
        if (n < 1) return;
        v = b[0];
        if (!v) { screen_off(); break; }     /* zero is the host turning it off */
        bright = v;
        bright_save();
        if (asleep) screen_on();            /* any other brightness is also a wake */
        else { bl_write(v); t_act = now_ms(); }
        break;
    }
    case 6: live_clear(); draw_all(); break;
    case 7: if (n >= NKEYS) { memcpy(keymap, b, NKEYS); keymap_save(); send_status(); } break;
    }
}

static void hid_report(const u8 *r, u32 got)
{
    u32 fl, n;
    if (got < 3) return;
    fl = r[0]; n = r16(r + 1);
    if (n > got - 3) n = got - 3;
    if (fl & 1) { rxlen = 0; rxlive = 1; }
    if (!rxlive) return;
    if (n > BUFMAX - rxlen) { rxlive = 0; return; }
    memcpy(rxbuf + rxlen, r + 3, n);
    rxlen += n;
    if (fl & 2) { rxlive = 0; on_message(rxbuf, rxlen); }
}

static void on_key(u32 code, u32 value)
{
    int k; u8 b[2];
    if (value > 1) return;                  /* autorepeat */
    if (linked()) { b[0] = (u8)code; b[1] = (u8)value; hid_send(0x83, b, 2); }
    if (asleep) {
        /* The screen is off. Any key brings it back and does nothing else: the
           press that wakes the deck must not also work a light. Its release is
           ignored too, because down[] was never set for it. */
        if (value) screen_on();
        return;
    }
    t_act = now_ms();                       /* a key, down or up, is activity */
    for (k = 0; k < NKEYS; k++) if (keymap[k] == code) break;
    if (k == NKEYS) return;
    if (value) {
        const u8 *kr;
        if (!linked() || !layok) return;    /* no bridge: drawn, but inert */
        kr = keyrec(cur, k);
        down[k] = 1; held[k] = 0; t_down[k] = now_ms();
        draw_key(k);
        if (!(kr[4] & 1) || kr[2] == 0) { held[k] = 1; fire(k, 0); }   /* nothing on hold: act at once */
    } else if (down[k]) {
        down[k] = 0;
        draw_key(k);
        if (!held[k]) fire(k, 0);
    }
}

static void tick(void)
{
    static u32 was_linked, was_marker = 99, started, shown;
    u32 l = linked(), s = 0, k, t = now_ms(), marker;
    if (!started) { started = t | 1; t_act = t; }
    if (!asleep && sleep_min && t - t_act >= sleep_min * 60000u) screen_off();
    if ((shown == 0 && t - started >= 2000) || (shown == 1 && t - started >= 6000)) { shown++; show_fb(); }
    if (was_linked && !l) { ha_up = 0; live_clear(); memset(down, 0, sizeof down); draw_all(); }
    was_linked = l;
    marker = l ? (ha_up ? 2 : 1) : 0;       /* red, amber or nothing: redraw when it changes */
    if (marker != was_marker) { was_marker = marker; draw_key(WIDE); }
    for (k = 0; k < NKEYS; k++)
        if (down[k] && !held[k] && t - t_down[k] >= 500) { held[k] = 1; fire(k, 1); }
    if (!layok || !local_secs(&s)) return;
    for (k = 0; k < NKEYS; k++) {
        const u8 *kr = keyrec(cur, k);
        if ((kr[4] & 3) == 3 && clock_drawn[k] != ((kr[4] & 8) ? s : s / 60)) draw_key(k);
    }
}

int cmain(long *sp)
{
    static u8 rep[1024];
    static u8 ev[16 * 16];
    long fd;
    u32 hid_retry = 0;
    char **argv = (char **)(sp + 1);

    if (sp[0] > 1 && seq(argv[1], "--version")) {
        s_write(1, "deckd " FW_TEXT "\n", sizeof("deckd " FW_TEXT "\n") - 1);
        return 0;
    }
    logfd = s_open("/tmp/deck.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    logs("deckd " FW_TEXT " starting\n");

    fbfd = s_open("/dev/fb0", O_RDWR, 0);
    fb = fbfd >= 0 ? s_mmap(FBW * FBH * 4, 3, 1 /* SHARED */, fbfd) : 0;
    if (!fb) { fb = shadow; fb_is_shadow = 1; logs("fb: mmap failed, writing instead\n"); }

    sys(SYS_mkdir, (long)DIR, 0755, 0, 0, 0, 0);
    fd = s_open(DIR "/keymap", O_RDONLY, 0);
    if (fd >= 0) { u8 t[NKEYS]; if (s_read(fd, t, NKEYS) == NKEYS) memcpy(keymap, t, NKEYS); s_close(fd); }
    fd = s_open(DIR "/brightness", O_RDONLY, 0);
    if (fd >= 0) { u8 t; if (s_read(fd, &t, 1) == 1 && t) bright = t; s_close(fd); }
    bl_write(bright);                       /* whatever was chosen, from the first frame */

    clear_screen();
    layout_load();
    draw_all();
    show_fb();
    evfd = s_open("/dev/input/event0", O_RDONLY | O_NONBLOCK, 0);
    if (evfd < 0) logs("cannot open /dev/input/event0\n");

    for (;;) {
        struct pollfd p[2];
        long n; int i;
        if (hidfd < 0 && now_ms() - hid_retry > 500) {      /* the gadget may come up after us */
            hid_retry = now_ms();
            hidfd = s_open("/dev/hidg0", O_RDWR | O_NONBLOCK, 0);
            if (hidfd >= 0) logs("hid channel open\n");
        }
        p[0].fd = evfd; p[0].events = POLLIN; p[0].revents = 0;
        p[1].fd = hidfd; p[1].events = POLLIN; p[1].revents = 0;
        s_poll(p, 2, 100);
        if (p[0].revents & POLLIN)
            while ((n = s_read(evfd, ev, sizeof ev)) >= 16)
                for (i = 0; i + 16 <= n; i += 16)
                    if (r16(ev + i + 8) == 1 /* EV_KEY */) on_key(r16(ev + i + 10), r32(ev + i + 12));
        if (hidfd >= 0 && (p[1].revents & POLLIN))
            while ((n = s_read(hidfd, rep, sizeof rep)) > 0) hid_report(rep, (u32)n);
        if (hidfd >= 0 && (p[1].revents & (POLLERR | POLLHUP))) { s_close(hidfd); hidfd = -1; }
        tick();
    }
}

__asm__(".text\n"
        ".globl _start\n"
        ".type _start,%function\n"
        "_start:\n"
        "  mov r0, sp\n"
        "  bic sp, sp, #7\n"
        "  bl cmain\n"
        "  mov r7, #1\n"
        "  svc 0\n");
