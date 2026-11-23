#!/usr/bin/env python3
"""Reach the Ulanzi deck through the ESP32 board's serial console.

  deckctl.py info
  deckctl.py sh "<shell command>"
  deckctl.py put <local file> <path on deck> [octal mode, default 644]
  deckctl.py raw <board command>    LOG, URL <address>, SETUP, FORGET, REBOOT
  deckctl.py log [seconds]          just listen to the board
"""
# One board only: the serial port named in tools/.port, a file you make yourself
# holding the full name of the port on the board's COM socket (ls /dev/cu.* shows
# it). Never a wildcard: other boards plugged into the same computer must not be
# touched by this.
import os as _os
try:
    PORT = open(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".port")).read().strip()
except OSError:
    raise SystemExit("missing tools/.port: put the board's serial port name in it")
import sys, time, glob, os, serial
DEBUG = os.environ.get("DECKCTL_DEBUG")

def port():
    p = glob.glob(PORT)
    if not p: sys.exit("board not found")
    return p[0]

class HubPort:
    """The serial port as seen through hub.py, which keeps it open so the board is not restarted."""
    def __init__(self, path):
        import socket
        self.k = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); self.k.connect(path); self.k.settimeout(0.05)
    in_waiting = 4096
    def read(self, n):
        try: return self.k.recv(n)
        except OSError: return b""
    def write(self, b): self.k.sendall(b)
    def reset_input_buffer(self):
        while self.read(4096): pass

def open_port():
    hub = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hub.sock")
    if os.path.exists(hub):
        try: return HubPort(hub)
        except OSError: pass
    s = serial.Serial()
    s.port = port(); s.baudrate = 115200; s.timeout = 0.05
    s.dtr = False; s.rts = False
    s.open()
    # Opening the port resets the board. Wait for it to boot and find the deck.
    buf = b""; end = time.time() + 0.8; booted = False
    while time.time() < end:
        buf += s.read(4096)
        if not booted and (b"ESP-ROM" in buf or b"boot:" in buf):
            booted = True; end = time.time() + 8
        if b"debug port open" in buf or b"no debug interface" in buf or b"did not answer" in buf:
            break
    time.sleep(0.05)
    s.reset_input_buffer()
    return s

_buf = b""
def lines(s, timeout):
    """Yield complete lines until timeout seconds pass with nothing complete.
    The buffer is shared, so a line that arrives early is never thrown away."""
    global _buf
    end = time.time() + timeout
    while True:
        while b"\n" in _buf:
            l, _buf = _buf.split(b"\n", 1)
            end = time.time() + timeout
            if DEBUG: print(f"[{time.time():.2f}] {l!r}", file=sys.stderr)
            yield l.decode("utf-8", "replace").rstrip("\r")
        if time.time() >= end: return
        _buf += s.read(s.in_waiting or 1)

def run(s, command, timeout=25, quiet=False):
    s.write(command.encode() + b"\n")
    out = []
    for l in lines(s, timeout):
        if l == "OK": return True, out
        if l.startswith("ERR"): out.append(l); return False, out
        if l.startswith("| "): out.append(l[2:])
        elif l == "|": out.append("")
        elif not quiet and l.startswith("# "): out.append(l)
    out.append("ERR no answer from the board")
    return False, out

def main():
    a = sys.argv[1:]
    if not a: sys.exit(__doc__)
    s = open_port()
    if a[0] == "log":
        for l in lines(s, float(a[1]) if len(a) > 1 else 5): print(l)
        return
    if a[0] == "info":
        ok, out = run(s, "INFO")
    elif a[0] == "sh":
        ok, out = run(s, "SH " + a[1])
        while out and out[-1] == "": out.pop()
    elif a[0] == "raw":                      # any board command: LOG, URL <addr>, SETUP, FORGET, REBOOT
        ok, out = run(s, " ".join(a[1:]))
        while out and out[-1] == "": out.pop()
    elif a[0] == "put":
        data = open(a[1], "rb").read()
        mode = a[3] if len(a) > 3 else "644"
        s.write(f"PUT {a[2]} {mode} {len(data)}\n".encode())
        ok, out = False, []
        def wait_plus():
            for l in lines(s, 10):
                if l == "+": return True
                if l.startswith("ERR"): out.append(l); return False
            out.append("ERR board did not ask for data"); return False
        good = wait_plus()
        i = 0
        while good and i < len(data):
            s.write(data[i:i+256].hex().encode() + b"\n"); i += 256
            good = wait_plus()
        if good:
            for l in lines(s, 30):
                if l == "OK": ok = True; break
                if l.startswith("ERR"): out.append(l); break
            else:
                out.append("ERR no confirmation")
    else:
        sys.exit(__doc__)
    print("\n".join(out))
    sys.exit(0 if ok else 1)

main()
