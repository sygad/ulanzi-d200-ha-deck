"""Ulanzi D200 Home Assistant Control Deck.

Three things live here: the panel where the deck is configured, the store that
keeps what was configured, and the hub that draws keys and acts on presses. The
deck itself is reached through a small bridge on the Mac it is plugged into.
"""

from __future__ import annotations

import importlib
from pathlib import Path

from aiohttp import web

from homeassistant.components import frontend, panel_custom
from homeassistant.components.http import KEY_HASS, HomeAssistantView, StaticPathConfig
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant

from . import api, const as const_module, hub as hub_module, render
from .const import BRIDGE_URL, DOMAIN, PANEL_URL, STATIC_URL

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
