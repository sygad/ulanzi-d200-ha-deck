"""The part of the integration that knows about the deck.

It keeps the draft and the published layout, draws keys when the things they
show change, talks to the bridge, and carries out what a key press asks for.

Draft and published are deliberately separate. Every edit in the panel lands in
the draft at once and survives a restart; the deck only ever sees what was
published with Send to device.
"""

from __future__ import annotations

import asyncio
import base64
import copy
from datetime import timedelta
from functools import partial
import hashlib
import hmac
import json
import logging
from pathlib import Path
import secrets
import struct
from typing import Any

from aiohttp import WSMsgType, web

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import STATE_UNAVAILABLE, STATE_UNKNOWN
from homeassistant.core import CALLBACK_TYPE, Event, HomeAssistant, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.event import (
    async_call_later,
    async_track_state_change_event,
    async_track_time_interval,
)
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import render
from .const import (
    ACTIONS,
    DOMAIN,
    EVENT_KEY,
    MAX_SCREENS,
    MSG_CLEAR,
    MSG_KEY,
    MSG_LAYOUT,
    MSG_STATUS,
    MSG_TILE,
    NKEYS,
)

_LOGGER = logging.getLogger(__name__)

OFF_STATES = {"off", "closed", STATE_UNAVAILABLE, STATE_UNKNOWN}
# These do something and are done; they have no "off" to look like, so their keys stay lit.
MOMENTARY = {"button", "input_button", "scene", "script"}
HISTORY_HOURS = 24
# Minutes of nothing happening before the deck turns its screen off; 0 is never.
# Here rather than in const.py because a reload of the integration re-imports
# this module and const.py is not re-imported (see _reload_code in __init__.py).
DEFAULT_SLEEP = 20
MAX_SLEEP = 255


def clean_pages(pages: Any) -> list[dict]:
    """Whatever the panel sent, return something the renderer can trust."""
    out: list[dict] = []
    for page in (pages if isinstance(pages, list) else [])[:MAX_SCREENS]:
        if not isinstance(page, dict):
            continue
        keys = [k if isinstance(k, dict) else None for k in (page.get("keys") or [])][:NKEYS]
        keys += [None] * (NKEYS - len(keys))
        out.append({
            "name": str(page.get("name") or "Untitled")[:40],
            "icon": str(page.get("icon") or "")[:64],
            "keys": keys,
        })
    return out or [{"name": "Screen 1", "icon": "", "keys": [None] * NKEYS}]


def clean_settings(settings: Any) -> dict:
    """The deck's own settings, as against any one screen's. Trust nothing sent."""
    settings = settings if isinstance(settings, dict) else {}
    try:
        sleep = int(settings.get("sleep", DEFAULT_SLEEP))
    except (TypeError, ValueError):
        sleep = DEFAULT_SLEEP
    return {"sleep": max(0, min(MAX_SLEEP, sleep))}


def _is_nav(action: str) -> bool:
    return action.startswith("deck.")


class _Bridge:
    """One connected bridge: a Mac with (perhaps) a deck plugged into it."""

    def __init__(self, ws: web.WebSocketResponse, bridge_id: str, name: str, digest: str) -> None:
        self.ws = ws
        self.id = bridge_id
        self.name = name
        self.digest = digest
        self.version = ""            # which companion app it is
        self.allowed = False


class DeckHub:
    """State and behaviour for the one deck."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self._store: Store = Store(hass, 1, DOMAIN)
        self.data: dict[str, Any] = {
            "pages": clean_pages(None), "published": None, "bridges": {},
            "settings": clean_settings(None), "published_settings": None,
        }

        self._bridge: _Bridge | None = None      # allowed and connected
        self._pending: _Bridge | None = None     # connected, waiting for Allow
        self.deck_online = False
        self.screen = 0
        self.firmware: str | None = None
        self._device_layout = 0

        self._blob: bytes | None = None
        self._base: dict[tuple[int, int], bytes] = {}    # each key as the cache holds it
        self._sent: dict[tuple[int, int], bytes] = {}    # each key as the deck shows it now
        self._deps: dict[str, set[tuple[int, int]]] = {}
        self._history: dict[str, list[float]] = {}
        self._dirty: set[tuple[int, int]] = set()

        self._lock = asyncio.Lock()
        # kept outside the hub so that a panel left open goes on hearing about
        # the deck when the integration is reloaded and this hub is replaced
        self._listeners: set[CALLBACK_TYPE] = hass.data.setdefault(f"{DOMAIN}_listeners", set())
        self._unsub_states: CALLBACK_TYPE | None = None
        self._unsub_flush: CALLBACK_TYPE | None = None
        self._unsub_timer: CALLBACK_TYPE | None = None

    # ------------------------------------------------------------ lifecycle

    async def async_start(self) -> None:
        stored = await self._store.async_load()
        if stored:
            self.data["pages"] = clean_pages(stored.get("pages"))
            self.data["published"] = clean_pages(stored["published"]) if stored.get("published") else None
            self.data["bridges"] = dict(stored.get("bridges") or {})
            self.data["settings"] = clean_settings(stored.get("settings"))
            self.data["published_settings"] = (
                clean_settings(stored["published_settings"]) if stored.get("published_settings") else None)
        await self._rebuild()
        self._unsub_timer = async_track_time_interval(self.hass, self._history_tick, timedelta(minutes=5))
        self._notify()

    async def async_stop(self) -> None:
        for unsub in (self._unsub_states, self._unsub_flush, self._unsub_timer):
            if unsub:
                unsub()
        self._unsub_states = self._unsub_flush = self._unsub_timer = None
        for b in (self._bridge, self._pending):
            if b:
                await b.ws.close()

    @property
    def device_info(self) -> DeviceInfo:
        return DeviceInfo(
            identifiers={(DOMAIN, self.entry.entry_id)},
            name="Ulanzi Deck",
            manufacturer="Ulanzi",
            model="D200",
            sw_version=self.firmware,
        )

    # ------------------------------------------------------------ what the panel sees

    @property
    def published(self) -> list[dict]:
        return self.data["published"] or clean_pages(None)

    @property
    def published_settings(self) -> dict:
        return self.data["published_settings"] or clean_settings(None)

    @property
    def screen_name(self) -> str | None:
        pages = self.published
        return pages[self.screen]["name"] if self.screen < len(pages) else None

    @callback
    def status(self) -> dict[str, Any]:
        return {
            "bridge": "connected" if self._bridge else "pending" if self._pending else "none",
            "bridge_name": self._bridge.name if self._bridge else None,
            "bridge_version": self._bridge.version if self._bridge else None,
            "app_version": self.app_version,
            "pending": {"bridge_id": self._pending.id, "name": self._pending.name} if self._pending else None,
            "deck": self.deck_online,
            "screen": self.screen,
            "firmware": self.firmware,
        }

    @callback
    def async_listen(self, cb: CALLBACK_TYPE) -> CALLBACK_TYPE:
        self._listeners.add(cb)
        return lambda: self._listeners.discard(cb)

    @callback
    def _notify(self) -> None:
        for cb in list(self._listeners):
            cb()

    # ------------------------------------------------------------ draft and publish

    @callback
    def async_save_draft(self, pages: Any, settings: Any = None) -> None:
        self.data["pages"] = clean_pages(pages)
        if settings is not None:
            self.data["settings"] = clean_settings(settings)
        self._store.async_delay_save(lambda: self.data, 1.0)

    async def async_publish(self, pages: Any, settings: Any = None) -> None:
        self.data["pages"] = clean_pages(pages)
        if settings is not None:
            self.data["settings"] = clean_settings(settings)
        self.data["published"] = copy.deepcopy(self.data["pages"])
        self.data["published_settings"] = copy.deepcopy(self.data["settings"])
        await self._store.async_save(self.data)
        await self._rebuild()
        if self.deck_online:
            await self._send_layout()
        self._notify()

    async def _rebuild(self) -> None:
        """Draw the published layout as the deck will cache it, and work out what it depends on."""
        base: dict[tuple[int, int], bytes] = {}
        if self.data["published"] is None:
            # nothing has ever been sent: leave the deck showing what it has
            pages: list[dict] = []
            self._blob, self._base = None, base
        else:
            pages = copy.deepcopy(self.published)
            async with self._lock:
                self._blob = await self.hass.async_add_executor_job(
                    partial(render.build_layout, pages, None, base,
                            sleep=self.published_settings["sleep"]))
                self._base = base
        deps: dict[str, set[tuple[int, int]]] = {}
        for s, page in enumerate(pages):
            for k, key in enumerate(page["keys"]):
                ent = self._entity_of(key)
                if ent:
                    deps.setdefault(ent, set()).add((s, k))
        self._deps = deps
        if self._unsub_states:
            self._unsub_states()
            self._unsub_states = None
        if deps:
            self._unsub_states = async_track_state_change_event(self.hass, list(deps), self._on_state)

    @staticmethod
    def _entity_of(key: dict | None) -> str | None:
        """The entity a key's appearance follows, if it follows one."""
        if not key:
            return None
        if key.get("type") == "entity":
            return key.get("ent") or None
        if key.get("type", "button") == "button":
            tap = key.get("tap") or {}
            action = tap.get("a") or "none"
            if action != "none" and not _is_nav(action):
                return tap.get("t") or None
        return None

    # ------------------------------------------------------------ drawing live keys

    def _facts(self, key: dict) -> dict[str, Any] | None:
        """What is true right now that changes how this key looks."""
        ent = self._entity_of(key)
        if not ent:
            return None
        state = self.hass.states.get(ent)
        if key.get("type") != "entity":
            return {"lit": state is None or ent.split(".")[0] in MOMENTARY or state.state not in OFF_STATES}
        if state is None or state.state in (STATE_UNAVAILABLE, STATE_UNKNOWN):
            return {"text": "--", "unit": "", "value": None, "name": state.name if state else "", "history": []}
        unit = state.attributes.get("unit_of_measurement") or ""
        try:
            value: float | None = float(state.state)
        except ValueError:
            return {"text": state.state[:12], "unit": "", "value": None, "name": state.name, "history": []}
        history = list(self._history.get(ent) or [])
        if history:
            history.append(value)
        return {"text": self._format(ent, state.state, value), "unit": unit, "value": value,
                "name": state.name, "history": history}

    def _format(self, entity_id: str, raw: str, value: float) -> str:
        """Round the way the dashboard would, so the deck and the dashboard agree."""
        precision = None
        if entry := er.async_get(self.hass).async_get(entity_id):
            opts = entry.options.get("sensor") or {}
            precision = opts.get("display_precision", opts.get("suggested_display_precision"))
        if precision is None:
            if "." not in raw:
                return raw
            decimals = len(raw.split(".", 1)[1])
            precision = min(decimals, 2 if abs(value) < 10 else 1 if abs(value) < 1000 else 0)
        return f"{value:.{int(precision)}f}"

    async def _push(self, slots: set[tuple[int, int]] | None) -> None:
        """Redraw the given keys (all of them if None) and send the ones that changed."""
        if not self.deck_online:
            return
        async with self._lock:
            pages = self.published
            jobs = []
            for s, k in sorted(slots if slots is not None else self._base):
                if s >= len(pages):
                    continue
                key = pages[s]["keys"][k]
                if not key or key.get("type") == "clock":
                    continue  # the deck draws its own clock
                facts = self._facts(key)
                if facts is not None:
                    jobs.append((s, k, key, facts))
            if not jobs:
                return
            tiles = await self.hass.async_add_executor_job(_render_tiles, jobs)
            for s, k, tile in tiles:
                if self._sent.get((s, k)) == tile:
                    continue
                self._sent[(s, k)] = tile
                await self._send(bytes([MSG_TILE, s, k]) + tile)

    @callback
    def _on_state(self, event: Event) -> None:
        self._dirty |= self._deps.get(event.data["entity_id"], set())
        if self._unsub_flush is None and self.deck_online:
            self._unsub_flush = async_call_later(self.hass, 0.15, self._flush)

    async def _flush(self, _now: Any) -> None:
        self._unsub_flush = None
        slots, self._dirty = self._dirty, set()
        await self._push(slots)

    # ------------------------------------------------------------ history, for graph keys

    def _graph_entities(self) -> set[str]:
        return {
            key["ent"]
            for page in self.published for key in page["keys"]
            if key and key.get("type") == "entity" and key.get("style") == "graph" and key.get("ent")
        }

    async def _load_history(self) -> None:
        ents = self._graph_entities()
        self._history = {e: h for e, h in self._history.items() if e in ents}
        if not ents or "recorder" not in self.hass.config.components:
            return
        from homeassistant.components.recorder import get_instance, history  # noqa: PLC0415

        start = dt_util.utcnow() - timedelta(hours=HISTORY_HOURS)
        for ent in ents:
            try:
                found = await get_instance(self.hass).async_add_executor_job(partial(
                    history.state_changes_during_period, self.hass, start, None, ent,
                    no_attributes=True, include_start_time_state=True))
            except Exception:  # noqa: BLE001 - a graph is not worth failing over
                _LOGGER.debug("No history for %s", ent, exc_info=True)
                continue
            self._history[ent] = _hourly(found.get(ent, []), start)

    async def _history_tick(self, _now: Any) -> None:
        if not self.deck_online:
            return
        await self._load_history()
        ents = self._graph_entities()
        await self._push({slot for e in ents for slot in self._deps.get(e, set())})

    # ------------------------------------------------------------ the bridge

    async def async_handle_bridge(self, ws: web.WebSocketResponse) -> None:
        """Serve one bridge connection from hello to goodbye."""
        try:
            hello = await ws.receive_json(timeout=10)
            bridge_id, secret = str(hello["bridge_id"]), str(hello["secret"])
            if hello.get("type") != "hello" or not (8 <= len(bridge_id) <= 64) or not (16 <= len(secret) <= 128):
                raise ValueError
        except (asyncio.TimeoutError, TypeError, KeyError, ValueError):
            await ws.close()
            return
        bridge = _Bridge(ws, bridge_id, str(hello.get("name") or "Mac")[:60],
                         hashlib.sha256(secret.encode()).hexdigest())
        bridge.version = str(hello.get("version") or "")[:20]
        known = self.data["bridges"].get(bridge_id)
        try:
            if known and hmac.compare_digest(known.get("hash", ""), bridge.digest):
                await self._admit(bridge)
            else:
                if self._pending:
                    await self._pending.ws.close()
                self._pending = bridge
                await ws.send_json({"type": "pending"})
                self._notify()
            async for msg in ws:
                if not bridge.allowed or bridge is not self._bridge:
                    continue
                if msg.type == WSMsgType.BINARY:
                    await self._from_deck(msg.data)
                elif msg.type == WSMsgType.TEXT:
                    try:
                        obj = json.loads(msg.data)
                    except ValueError:
                        continue
                    if obj.get("type") == "deck":
                        await self._deck_arrived(base64.b64decode(obj.get("status") or ""))
                    elif obj.get("type") == "deck_gone":
                        self._deck_left()
                    elif obj.get("type") == "want_app":
                        await bridge.ws.send_json(
                            {"type": "app_at", "token": self.new_download_token()})
        finally:
            if self._pending is bridge:
                self._pending = None
            if self._bridge is bridge:
                self._bridge = None
                self._deck_left()
            self._notify()

    # ------------------------------------------------------------ keeping the Mac current
    #
    # The Mac app is handed out by this integration, so this is the only thing
    # that knows a newer one exists. It says so when a bridge is admitted, and
    # hands over a one-time address to fetch it from — this server, not the
    # internet, which is the only address the app has ever been told to trust.

    @property
    def app_version(self) -> str:
        """The version of the app this integration goes with."""
        if not hasattr(self, "_app_version"):
            try:
                path = Path(__file__).parent / "manifest.json"
                self._app_version = str(json.loads(path.read_text()).get("version") or "")
            except Exception:  # noqa: BLE001 - a missing version is not worth failing for
                self._app_version = ""
        return self._app_version

    def new_download_token(self) -> str:
        """A one-time address for the app to fetch its own update from."""
        token = secrets.token_urlsafe(24)
        self._tokens = {t: when for t, when in getattr(self, "_tokens", {}).items()
                        if when > dt_util.utcnow()}
        self._tokens[token] = dt_util.utcnow() + timedelta(minutes=5)
        return token

    def spend_download_token(self, token: str) -> bool:
        """True once, for a token that has not expired."""
        tokens = getattr(self, "_tokens", {})
        when = tokens.pop(token, None)
        return bool(when and when > dt_util.utcnow())

    async def _admit(self, bridge: _Bridge) -> None:
        if self._bridge and self._bridge is not bridge:
            old, self._bridge = self._bridge, None
            self._deck_left()
            await old.ws.close()
        bridge.allowed = True
        self._bridge = bridge
        if self._pending is bridge:
            self._pending = None
        await bridge.ws.send_json({"type": "ready", "app_version": self.app_version})
        self._notify()

    async def async_allow(self, bridge_id: str) -> bool:
        """The admin pressed Allow in the panel."""
        bridge = self._pending
        if not bridge or bridge.id != bridge_id:
            return False
        self.data["bridges"][bridge.id] = {"name": bridge.name, "hash": bridge.digest}
        await self._store.async_save(self.data)
        await self._admit(bridge)
        return True

    async def async_new_pairing(self, name: str = "Mac") -> dict[str, str]:
        """Write down a Mac before it has ever connected, and hand back its key.

        This is what makes the download button worth pressing: the key goes into
        the zip beside the app, so the app proves itself the first time it
        connects and nobody has to press Allow. Only an admin can ask for one,
        and the key itself is never stored — only what it hashes to, exactly as
        for a Mac that was allowed by hand.
        """
        bridge_id = secrets.token_hex(8)
        secret = secrets.token_hex(32)
        bridges = self.data["bridges"]
        bridges[bridge_id] = {
            "name": name,
            "hash": hashlib.sha256(secret.encode()).hexdigest(),
        }
        # Pressing the button more than once should not leave a pile of keys
        # behind that would each still be let in. The newest few are kept, so a
        # Mac that is simply switched off at the time does not lose its place.
        connected = self._bridge.id if self._bridge else None
        for old in list(bridges)[:-4]:
            if old != connected:
                del bridges[old]
        await self._store.async_save(self.data)
        return {"bridgeId": bridge_id, "secret": secret}

    async def _send(self, data: bytes) -> None:
        bridge = self._bridge
        if not bridge:
            return
        try:
            await bridge.ws.send_bytes(data)
        except (ConnectionError, RuntimeError):
            _LOGGER.debug("Bridge went away mid-send")

    async def _send_layout(self) -> None:
        if self._blob is None:
            return
        await self._send(bytes([MSG_LAYOUT]) + self._blob)
        self._device_layout = render.layout_id(self._blob)
        self._sent = dict(self._base)
        await self._load_history()
        await self._push(None)

    async def _deck_arrived(self, status: bytes) -> None:
        self._read_status(status)
        self.deck_online = True
        _LOGGER.info("Deck connected (firmware %s)", self.firmware)
        if self._blob is not None and self._device_layout != render.layout_id(self._blob):
            await self._send_layout()          # the deck is holding something older
        else:
            await self._send(bytes([MSG_CLEAR]))
            self._sent = dict(self._base)
            await self._load_history()
            await self._push(None)
        self._notify()

    @callback
    def _deck_left(self) -> None:
        if self.deck_online:
            _LOGGER.info("Deck disconnected")
        self.deck_online = False
        self._sent = {}
        self._dirty = set()

    def _read_status(self, body: bytes) -> None:
        if len(body) < 10:
            return
        self.firmware = f"{body[1]}.{body[2]}"
        self.screen = body[3]
        self._device_layout = struct.unpack_from("<I", body, 6)[0] if body[5] else 0

    async def _from_deck(self, msg: bytes) -> None:
        if not msg:
            return
        if msg[0] == MSG_STATUS:
            self._read_status(msg[1:])
            self._notify()
        elif msg[0] == MSG_KEY and len(msg) >= 4:
            await self._pressed(msg[1], msg[2], "hold" if msg[3] == 2 else "tap")

    async def async_preview_press(self, screen: int, k: int, gesture: str) -> None:
        """A key pressed in the panel's preview, acting on the draft.

        The draft and not the published layout, because the point of it is to try
        a key out before sending it to the deck. Everything else is the same code
        path as a real press, so the two can never disagree about what a key does.
        """
        await self._pressed(screen, k, gesture, pages=self.data["pages"], preview=True)

    async def _pressed(self, screen: int, k: int, gesture: str,
                       pages: list[dict] | None = None, preview: bool = False) -> None:
        pages = self.published if pages is None else pages
        if screen >= len(pages) or k >= NKEYS:
            return
        key = pages[screen]["keys"][k]
        if not key or key.get("type", "button") != "button":
            return
        slot = key.get(gesture) or {}
        action, target = slot.get("a") or "none", slot.get("t") or ""
        # preview says where the press came from, so an automation listening for
        # this event can tell a trial run from somebody pressing the real deck
        self.hass.bus.async_fire(EVENT_KEY, {
            "screen": screen, "screen_name": pages[screen]["name"], "key": k,
            "label": key.get("l") or "", "gesture": gesture, "action": action, "target": target,
            "preview": preview,
        })
        if action not in ACTIONS or not target:
            return
        domain, service = action.split(".", 1)
        if not self.hass.services.has_service(domain, service):
            _LOGGER.warning("Key %s on screen %s wants %s, which does not exist here", k, screen, action)
            return
        await self.hass.services.async_call(domain, service, {"entity_id": target}, blocking=False)


def _render_tiles(jobs: list[tuple[int, int, dict, dict]]) -> list[tuple[int, int, bytes]]:
    return [(s, k, render.rle_encode(render.render_key(key, k, facts)[0])) for s, k, key, facts in jobs]


def _hourly(states: list, start) -> list[float]:
    """One reading an hour for the last day: whatever the sensor said at each hour's end."""
    readings: list[tuple[Any, float]] = []
    for st in states:
        try:
            readings.append((st.last_changed, float(st.state)))
        except (ValueError, TypeError):
            continue
    out: list[float] = []
    i, last = 0, None
    for hour in range(1, HISTORY_HOURS + 1):
        edge = start + timedelta(hours=hour)
        while i < len(readings) and readings[i][0] <= edge:
            last = readings[i][1]
            i += 1
        if last is not None:
            out.append(last)
    return out
