"""Reads the deck's framebuffer over adb and saves it the right way up.
Usage: fb_grab.py out.png   — a way to see the screen without being in the room."""
import subprocess, sys, tempfile, os
from PIL import Image
tmp = os.path.join(tempfile.mkdtemp(), "fb.raw")
subprocess.run(["adb", "shell", "cat /dev/fb0 > /tmp/fb.raw"], check=True)
subprocess.run(["adb", "pull", "/tmp/fb.raw", tmp], check=True, capture_output=True)
subprocess.run(["adb", "shell", "rm /tmp/fb.raw"], check=True)
raw = open(tmp, "rb").read()
fb = Image.frombuffer("RGBX", (720, 1280), raw[:720 * 1280 * 4], "raw", "BGRX", 0, 1).convert("RGB")
# fb[y][x] = L[lx = 1279 - y][ly = x]
fb.transpose(Image.Transpose.ROTATE_270).save(sys.argv[1])
