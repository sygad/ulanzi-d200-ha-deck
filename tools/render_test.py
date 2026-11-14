"""Draw the made-up demo screens to PNGs and build a layout blob. No deck needed."""
import sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "custom_components" / "ulanzi_deck"))
sys.path.insert(0, str(ROOT / "tools"))
import render, demo_house

out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
out.mkdir(parents=True, exist_ok=True)
for s in range(len(demo_house.PAGES)):
    render.preview(demo_house.PAGES, s).save(out / f"screen{s}-cached.png")
    render.preview(demo_house.PAGES, s, demo_house.live).save(out / f"screen{s}-live.png")
t = time.time()
blob = render.build_layout(demo_house.PAGES)
(out / "layout.bin").write_bytes(blob)
print(f"layout {len(blob)} bytes, id {render.layout_id(blob):08x}, built in {time.time()-t:.2f}s")
