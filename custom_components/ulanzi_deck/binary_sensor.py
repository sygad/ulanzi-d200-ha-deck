"""Whether the deck is connected."""

from __future__ import annotations

from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .hub import DeckHub


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    async_add_entities([DeckConnection(hass.data[DOMAIN], entry)])


class DeckConnection(BinarySensorEntity):
    _attr_has_entity_name = True
    _attr_translation_key = "connection"
    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY
    _attr_should_poll = False

    def __init__(self, hub: DeckHub, entry: ConfigEntry) -> None:
        self._hub = hub
        self._attr_unique_id = f"{entry.entry_id}_connection"
        self._attr_device_info = hub.device_info

    @property
    def is_on(self) -> bool:
        return self._hub.deck_online

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(self._hub.async_listen(self._changed))

    @callback
    def _changed(self) -> None:
        self.async_write_ha_state()
