"""Constants for the Ulanzi Deck integration."""

DOMAIN = "ulanzi_deck"
NKEYS = 14
MAX_SCREENS = 32
PANEL_URL = "ulanzi-deck"
STATIC_URL = "/ulanzi_deck_static"
BRIDGE_URL = "/api/ulanzi_deck/bridge"
APP_URL = "/api/ulanzi_deck/companion-app"

# Where the companion app is published. Home Assistant fetches this when somebody
# presses the download button, puts a pairing file beside the app, and hands the
# pair over as one zip — so the app arrives already knowing this server.
APP_RELEASE_URL = (
    "https://github.com/sygad/ulanzi-d200-ha-deck/releases/latest/download/Ulanzi-Deck.zip"
)
PAIRING_FILE = "ulanzi-deck-pairing.json"
README_FILE = "Start here.html"
EVENT_KEY = "ulanzi_deck_key"

# What a button key may ask Home Assistant to do. The panel offers exactly these.
ACTIONS = {
    "light.toggle", "light.turn_on", "light.turn_off",
    "switch.toggle", "switch.turn_on", "switch.turn_off",
    "button.press",
    "cover.toggle", "cover.open_cover", "cover.close_cover",
    "media_player.media_play_pause", "media_player.volume_up", "media_player.volume_down",
    "script.turn_on", "scene.turn_on",
}

# Messages to the deck (see parts/02-deck-app/deckd.c)
MSG_LAYOUT = 0x02
MSG_TILE = 0x03
MSG_CLEAR = 0x06
# Messages from the deck
MSG_STATUS = 0x81
MSG_KEY = 0x82
