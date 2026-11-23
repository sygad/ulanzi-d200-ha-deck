#!/usr/bin/env python3
"""Holds the board's serial port open, once, so looking at the board does not restart it.

Everything the board says is appended to serial.log (with the time) and passed to
any client connected to the socket; anything a client sends goes to the board.
deckctl.py uses the socket when this is running.
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
import re, os, sys, time, glob, socket, select, serial

HERE = os.path.dirname(os.path.abspath(__file__))
SOCK = os.path.join(HERE, "hub.sock")
LOG = os.path.join(HERE, "serial.log")

def open_serial():
    p = glob.glob(PORT)
    if not p: return None
    s = serial.Serial()
    s.port = p[0]; s.baudrate = 115200; s.timeout = 0
    s.dtr = False; s.rts = False
    s.open()
    return s

def main():
    if os.path.exists(SOCK): os.unlink(SOCK)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK); srv.listen(4)
    clients = []
    ser = None
    log = open(LOG, "ab", buffering=0)
    pending = b""
    while True:
        if ser is None:
            try: ser = open_serial()
            except Exception: ser = None
            if ser is None: time.sleep(1); continue
            log.write(f"\n==== {time.strftime('%H:%M:%S')} port opened ====\n".encode())
        try:
            r, _, _ = select.select([srv, ser] + clients, [], [], 1.0)
        except Exception:
            r = []
        for x in r:
            if x is srv:
                c, _ = srv.accept(); clients.append(c)
            elif x is ser:
                try: data = ser.read(4096)
                except Exception:
                    try: ser.close()
                    except Exception: pass
                    ser = None; break
                if not data: continue
                pending += data
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    shown = re.sub(rb"[0-9a-f]{64}", b"<key hidden>", line.rstrip(b"\r"))   # never keep the board's key
                    log.write(time.strftime("%H:%M:%S ").encode() + shown + b"\n")
                for c in clients[:]:
                    try: c.sendall(data)
                    except Exception: clients.remove(c); c.close()
            else:
                try: data = x.recv(65536)
                except Exception: data = b""
                if not data:
                    if x in clients: clients.remove(x)
                    x.close(); continue
                if ser:
                    try: ser.write(data)
                    except Exception: pass

main()
