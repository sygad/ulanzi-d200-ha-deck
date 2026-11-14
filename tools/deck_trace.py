"""Keeps a running record of the deck's health on the Mac, over adb.

The deck froze once (13 Nov 2026, 20:43) and took its own logs with it when it
was power-cycled. This writes uptime, memory, temperature, the device app's
memory and any new kernel messages to ~/Library/Logs/UlanziDeck/deck-trace.log
every 30 seconds, so the minutes before a freeze are on the Mac, not the deck.
It stops, saying so, when the deck has not answered for 90 seconds.

    python3 tools/deck_trace.py
"""
import os, subprocess, time

LOG = os.path.expanduser("~/Library/Logs/UlanziDeck/deck-trace.log")
CMD = ('cat /proc/uptime; grep -E "MemAvailable|Slab:|SUnreclaim" /proc/meminfo | tr -s " " | tr "\\n" " "; echo; '
       'cat /sys/class/thermal/thermal_zone0/temp; '
       'P=$(pidof UlanziDeckKey); grep VmRSS /proc/$P/status 2>/dev/null | tr -s " \\t" " "; echo "pid $P"; '
       'echo ---; dmesg | tail -40')
seen, last_ok = set(), time.time()
os.makedirs(os.path.dirname(LOG), exist_ok=True)
with open(LOG, "a") as f:
    f.write(time.strftime("\n%Y-%m-%d %H:%M:%S trace started\n"))
    while True:
        try:
            r = subprocess.run(["adb", "shell", CMD], capture_output=True, text=True, timeout=15)
            ok = r.returncode == 0 and "---" in r.stdout
        except subprocess.TimeoutExpired:
            ok = False
        now = time.strftime("%H:%M:%S")
        if ok:
            last_ok = time.time()
            head, kmsg = r.stdout.split("---", 1)
            f.write(f"{now} " + " | ".join(l.strip() for l in head.strip().split("\n")) + "\n")
            for line in kmsg.strip().split("\n"):
                if line and line not in seen:
                    seen.add(line)
                    f.write(f"{now}   kernel: {line}\n")
        else:
            f.write(f"{now} no answer from the deck\n")
            if time.time() - last_ok > 90:
                f.write(f"{now} deck silent for 90 s: stopping\n")
                f.flush()
                print(f"deck stopped answering; last good reading {time.strftime('%H:%M:%S', time.localtime(last_ok))}. See {LOG}")
                break
        f.flush()
        time.sleep(30)
