"""Ulanzi D200 Home Assistant Control Deck.

Three things live here: the panel where the deck is configured, the store that
keeps what was configured, and the hub that draws keys and acts on presses. The
deck itself is reached through a small bridge on the Mac it is plugged into.
"""

from __future__ import annotations

import asyncio
import base64
import importlib
import io
import json
from pathlib import Path
import re
import zipfile

from aiohttp import ClientError, web

from homeassistant.components import frontend, panel_custom
from homeassistant.components.http import KEY_HASS, HomeAssistantView, StaticPathConfig
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.network import NoURLAvailableError, get_url

from . import api, const as const_module, hub as hub_module, render
from .const import (
    APP_RELEASE_URL,
    APP_URL,
    BRIDGE_URL,
    DOMAIN,
    PAIRING_FILE,
    PANEL_URL,
    README_FILE,
    STATIC_URL,
)

PLATFORMS = [Platform.BINARY_SENSOR, Platform.SENSOR]
_ONCE = f"{DOMAIN}_registered"
_FRONTEND = Path(__file__).parent / "frontend"


def _reload_code() -> None:
    """Pick up changed code when the integration is reloaded.

    Nearly everything is in these modules, so tuning how keys look or
    adding a command needs the integration reloading, not Home Assistant
    restarting. Order matters: the others read const, the hub uses the
    renderer, and the commands use both.
    """
    importlib.reload(const_module)
    importlib.reload(render)
    importlib.reload(hub_module)
    importlib.reload(api)


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    await hass.async_add_executor_job(_reload_code)
    hub = hub_module.DeckHub(hass, entry)
    await hub.async_start()
    hass.data[DOMAIN] = hub
    api.async_register(hass)

    if not hass.data.get(_ONCE):  # these cannot be taken back, so only ever once
        hass.data[_ONCE] = True
        await hass.http.async_register_static_paths(
            [StaticPathConfig(STATIC_URL, str(_FRONTEND), cache_headers=False)])
        hass.http.register_view(BridgeView())
        hass.http.register_view(CompanionAppView())

    stamp = await hass.async_add_executor_job(lambda: int((_FRONTEND / "panel.js").stat().st_mtime))
    await panel_custom.async_register_panel(
        hass,
        webcomponent_name="ulanzi-deck-panel",
        frontend_url_path=PANEL_URL,
        module_url=f"{STATIC_URL}/panel.js?v={stamp}",
        sidebar_title="Ulanzi Deck",
        sidebar_icon="mdi:view-grid",
        require_admin=True,
        config={"static": STATIC_URL, "v": stamp},
    )
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    if not await hass.config_entries.async_unload_platforms(entry, PLATFORMS):
        return False
    frontend.async_remove_panel(hass, PANEL_URL)
    hub = hass.data.pop(DOMAIN)
    await hub.async_stop()
    return True


class BridgeView(HomeAssistantView):
    """Where the Mac bridge connects.

    Not behind Home Assistant's login, because the bridge has no user: it proves
    itself with a secret of its own, and until an admin has pressed Allow in the
    panel it is told to wait and nothing it sends is listened to.
    """

    url = BRIDGE_URL
    name = "api:ulanzi_deck:bridge"
    requires_auth = False

    async def get(self, request: web.Request) -> web.StreamResponse:
        hub = request.app[KEY_HASS].data.get(DOMAIN)
        if hub is None:
            return web.Response(status=503)
        ws = web.WebSocketResponse(heartbeat=30, max_msg_size=1 << 20)
        await ws.prepare(request)
        await hub.async_handle_bridge(ws)
        return ws


class CompanionAppView(HomeAssistantView):
    """Hands over the companion app with this server's details already inside it.

    The app is not kept here — it is fetched from where it is published and a
    small pairing file is put beside it in the same zip. That file says which
    Home Assistant to talk to and carries a key written down a moment earlier,
    so the app connects and is let in with nothing typed and no Allow pressed.

    Only an admin can ask for one, because asking for one creates a key that
    opens the door.
    """

    url = APP_URL
    name = "api:ulanzi_deck:companion-app"

    async def get(self, request: web.Request) -> web.StreamResponse:
        hass = request.app[KEY_HASS]
        user = request.get("hass_user")
        if user is None or not user.is_admin:
            return web.Response(status=403, text="Administrators only.")
        hub = hass.data.get(DOMAIN)
        if hub is None:
            return web.Response(status=503, text="Ulanzi Deck is not running.")

        try:
            url = get_url(hass, prefer_external=False, allow_ip=True)
        except NoURLAvailableError:
            return web.Response(
                status=503,
                text="Home Assistant does not know its own address, so the app "
                     "cannot be told where to find it. Set one under Settings, "
                     "System, Network.",
            )

        session = async_get_clientsession(hass)
        try:
            async with asyncio.timeout(120):
                response = await session.get(APP_RELEASE_URL)
                if response.status != 200:
                    return web.Response(
                        status=502,
                        text="The companion app could not be downloaded "
                             f"({response.status}). Try again in a moment.",
                    )
                app_zip = await response.read()
        except (ClientError, TimeoutError):
            return web.Response(
                status=502,
                text="Home Assistant could not reach the internet to fetch the "
                     "companion app. Check its connection and try again.",
            )

        pairing = await hub.async_new_pairing()
        pairing["url"] = url
        body = await hass.async_add_executor_job(_with_pairing, app_zip, pairing)
        return web.Response(
            body=body,
            content_type="application/zip",
            headers={"Content-Disposition": 'attachment; filename="Ulanzi Deck.zip"'},
        )


def _with_pairing(app_zip: bytes, pairing: dict) -> bytes:
    """Copy the published zip, and add the pairing file and a note beside the app.

    Everything is copied entry by entry, permissions included, because the app
    will not run if the executable bit is lost. Nothing inside the app bundle
    is touched: changing a signed bundle is what stops macOS opening it.
    """
    out = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(app_zip)) as src, \
            zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as dst:
        version = ""
        for item in src.infolist():
            data = src.read(item.filename)
            if item.filename.endswith(".app/Contents/Info.plist"):
                version = _version_in(data)
            dst.writestr(item, data)
        dst.writestr(PAIRING_FILE, json.dumps(pairing, indent=2, sort_keys=True))
        dst.writestr(README_FILE, _readme(version))
    return out.getvalue()


def _version_in(plist: bytes) -> str:
    """The app's own version, read out of its Info.plist."""
    m = re.search(rb"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>", plist)
    return m.group(1).decode() if m else ""


def _readme(version: str) -> str:
    """The page that opens with the download.

    It cannot be the app that says this. macOS refuses to run a program nobody
    has paid Apple to vouch for, so at the moment somebody needs telling what
    to do, our app is the one thing that cannot speak. A page can: it is a
    document, not a program, so it opens.

    It says what will happen before it happens, and carries a button that opens
    System Settings at the Security section, so nobody goes hunting.
    """
    shot = (_FRONTEND / "blocked.png").read_bytes()
    picture = base64.b64encode(shot).decode()
    title = f"Ulanzi Deck {version}".strip()
    return f"""<!doctype html>
<html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
  :root{{--ink:#1d1d1f;--soft:#6e6e73;--line:#e3e3e5;--blue:#2f7fe0}}
  *{{box-sizing:border-box}}
  body{{margin:0;padding:48px 24px;background:#f2f2f4;color:var(--ink);
       font:400 15px/1.55 -apple-system,"SF Pro Text",system-ui,sans-serif}}
  main{{max-width:1000px;margin:0 auto;display:flex;flex-direction:column;gap:28px}}
  h1{{margin:0;font-size:26px;font-weight:600;letter-spacing:-.01em}}
  .lede{{margin:0;color:var(--soft);max-width:62ch}}
  .pair{{display:grid;grid-template-columns:1fr 280px;gap:32px;align-items:center;
        background:#fff;border:1px solid var(--line);border-radius:14px;padding:24px}}
  .pair img{{width:100%;height:auto;border-radius:10px;display:block}}
  .flow{{display:flex;flex-direction:column;gap:12px;align-items:stretch}}
  .step{{background:#ececef;border-radius:28px;padding:13px 18px;text-align:center;font-size:17px}}
  .arrow{{text-align:center;color:var(--soft);font-size:18px;line-height:1}}
  .go{{display:block;background:var(--blue);color:#fff;text-align:center;text-decoration:none;
      font-size:17px;font-weight:500;padding:15px 18px;border-radius:28px;margin-top:8px}}
  ol{{margin:0;padding-left:22px;display:flex;flex-direction:column;gap:9px;max-width:68ch}}
  .after{{margin:0;color:var(--soft);max-width:68ch}}
  code{{background:#ececef;border-radius:5px;padding:1px 6px;font-size:14px}}
  @media (max-width:760px){{.pair{{grid-template-columns:1fr}}}}
</style>
<main>
  <div>
    <h1>macOS will block Ulanzi Deck the first time</h1>
    <p class="lede">Nothing is wrong with it. Every Mac does this for software not sold through
      Apple's own store — it means nobody has paid Apple to vouch for it, not that anything is
      wrong with the app. You tell your Mac once that you want it, and never again.</p>
  </div>

  <div class="pair">
    <img src="data:image/png;base64,{picture}" alt="System Settings, Privacy and Security, with Ulanzi Deck blocked and an Open Anyway button">
    <div class="flow">
      <div class="step">System Settings</div>
      <div class="arrow">&#8595;</div>
      <div class="step">Privacy &amp; Security</div>
      <div class="arrow">&#8595;</div>
      <div class="step">Security</div>
      <a class="go" href="x-apple.systempreferences:com.apple.preference.security?General">Open Settings</a>
    </div>
  </div>

  <ol>
    <li>Double-click <b>Ulanzi Deck</b>. macOS says it cannot check it: press <b>Done</b> —
        not Move to Bin.</li>
    <li>Press <b>Open Settings</b> above, and in the <b>Security</b> section press
        <b>Open Anyway</b> beside Ulanzi Deck.</li>
    <li>It asks once more, with Move to Bin in blue. Press <b>Open Anyway</b> — the middle
        button.</li>
  </ol>

  <p class="after">Leave <code>ulanzi-deck-pairing.json</code> next to the app. It is what tells
    the app which Home Assistant is yours, so there is nothing to type and nothing to allow.
    Once the app has opened you can delete it, and this page.</p>
</main>
</html>
"""
