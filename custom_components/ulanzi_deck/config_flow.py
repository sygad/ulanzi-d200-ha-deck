"""Config flow: there is nothing to ask, the deck finds its own way in."""

from __future__ import annotations

from typing import Any

from homeassistant.config_entries import ConfigFlow, ConfigFlowResult

from .const import DOMAIN


class UlanziDeckConfigFlow(ConfigFlow, domain=DOMAIN):
    """One deck, one entry."""

    VERSION = 1

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        if user_input is not None:
            return self.async_create_entry(title="Ulanzi Deck", data={})
        return self.async_show_form(step_id="user")
