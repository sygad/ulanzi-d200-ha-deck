"""Serves the panel against a pretend Home Assistant, for working on it in a browser.

    python3 tools/panel-harness/serve.py 8788   then open http://127.0.0.1:8788/
"""
import http.server, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FRONTEND = HERE.parent.parent / "custom_components" / "ulanzi_deck" / "frontend"


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        path = path.split("?", 1)[0]
        if path.startswith("/ulanzi_deck_static/"):
            return str(FRONTEND / path[len("/ulanzi_deck_static/"):])
        return str(HERE / (path.lstrip("/") or "index.html"))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8788), Handler).serve_forever()
