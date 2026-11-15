"""What the panel can ask of the integration, over Home Assistant's WebSocket."""

from __future__ import annotations

import voluptuous as vol

from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, callback

from .const import DOMAIN


def _hub(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict):
    hub = hass.data.get(DOMAIN)
    if hub is None:
        connection.send_error(msg["id"], "not_loaded", "Ulanzi Deck is not set up")
    return hub


@websocket_api.websocket_command({vol.Required("type"): "ulanzi_deck/get"})
@websocket_api.require_admin
@callback
def ws_get(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict) -> None:
    if hub := _hub(hass, connection, msg):
        connection.send_result(msg["id"], {
            "pages": hub.data["pages"], "published": hub.data["published"],
            "settings": hub.data["settings"], "published_settings": hub.data["published_settings"],
            "status": hub.status()})


@websocket_api.websocket_command({
    vol.Required("type"): "ulanzi_deck/save",
    vol.Required("pages"): list,
    vol.Optional("settings"): dict,
})
@websocket_api.require_admin
@callback
def ws_save(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict) -> None:
    if hub := _hub(hass, connection, msg):
        hub.async_save_draft(msg["pages"], msg.get("settings"))
        connection.send_result(msg["id"])


@websocket_api.websocket_command({
    vol.Required("type"): "ulanzi_deck/publish",
    vol.Required("pages"): list,
    vol.Optional("settings"): dict,
})
@websocket_api.require_admin
@websocket_api.async_response
async def ws_publish(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict) -> None:
    if hub := _hub(hass, connection, msg):
        await hub.async_publish(msg["pages"], msg.get("settings"))
        connection.send_result(msg["id"], {
            "published": hub.data["published"],
            "published_settings": hub.data["published_settings"],
            "status": hub.status()})


@websocket_api.websocket_command({
    vol.Required("type"): "ulanzi_deck/press",
    vol.Required("screen"): int,
    vol.Required("key"): int,
    vol.Optional("gesture", default="tap"): vol.In(("tap", "hold")),
})
@websocket_api.require_admin
@websocket_api.async_response
async def ws_press(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict) -> None:
    """A key pressed in the panel's preview. It really does what the key says."""
    if hub := _hub(hass, connection, msg):
        await hub.async_preview_press(msg["screen"], msg["key"], msg["gesture"])
        connection.send_result(msg["id"])


@websocket_api.websocket_command({
    vol.Required("type"): "ulanzi_deck/brightness",
    vol.Required("value"): vol.All(int, vol.Range(min=0, max=255)),
})
@websocket_api.require_admin
@websocket_api.async_response
async def ws_brightness(hass: HomeAssistant, connection: websocket_api.ActiveConnection,
                        msg: dict) -> None:
    """The brightness slider, while it is being dragged."""
    if hub := _hub(hass, connection, msg):
        await hub.async_set_brightness(msg["value"])
        connection.send_result(msg["id"], None)


@websocket_api.websocket_command({vol.Required("type"): "ulanzi_deck/update_app"})
@websocket_api.require_admin
@websocket_api.async_response
async def ws_update_app(hass: HomeAssistant, connection: websocket_api.ActiveConnection,
                        msg: dict) -> None:
    """The panel asking the Mac to update its companion app."""
    if hub := _hub(hass, connection, msg):
        connection.send_result(msg["id"], {"asked": await hub.async_tell_mac_to_update()})


@websocket_api.websocket_command({vol.Required("type"): "ulanzi_deck/subscribe"})
@websocket_api.require_admin
@callback
def ws_subscribe(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict) -> None:
    if not (hub := _hub(hass, connection, msg)):
        return

    @callback
    def forward() -> None:
        # the hub is replaced when the integration reloads; always speak for the current one
        current = hass.data.get(DOMAIN)
        if current is not None:
            connection.send_message(websocket_api.event_message(msg["id"], current.status()))

    connection.subscriptions[msg["id"]] = hub.async_listen(forward)
    connection.send_result(msg["id"])
    forward()


@websocket_api.websocket_command({vol.Required("type"): "ulanzi_deck/allow", vol.Required("bridge_id"): str})
@websocket_api.require_admin
@websocket_api.async_response
async def ws_allow(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict) -> None:
    if hub := _hub(hass, connection, msg):
        connection.send_result(msg["id"], {"allowed": await hub.async_allow(msg["bridge_id"])})


@callback
def async_register(hass: HomeAssistant) -> None:
    """Registering again replaces the handlers, which is what a reload wants."""
    for command in (ws_get, ws_save, ws_publish, ws_press, ws_subscribe, ws_allow,
                    ws_update_app, ws_brightness):
        websocket_api.async_register_command(hass, command)
