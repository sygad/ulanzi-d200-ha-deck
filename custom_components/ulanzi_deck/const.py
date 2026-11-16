"""Constants for the Ulanzi Deck integration."""

DOMAIN = "ulanzi_deck"
NKEYS = 14
MAX_SCREENS = 32
PANEL_URL = "ulanzi-deck"
STATIC_URL = "/ulanzi_deck_static"
BRIDGE_URL = "/api/ulanzi_deck/bridge"
APP_URL = "/api/ulanzi_deck/companion-app"
APP_UPDATE_URL = "/api/ulanzi_deck/companion-app/{token}"

# Where the connector app is published. Home Assistant fetches this when somebody
# presses the download button, puts a pairing file beside the app, and hands the
# pair over as one zip — so the app arrives already knowing this server.
# Where to ask what the newest release is. The Marketplace only looks every
# couple of days, which is long enough for somebody to be told to update from a
# shop that has not noticed yet.
RELEASES_URL = "https://api.github.com/repos/sygad/ulanzi-d200-ha-deck/releases/latest"

# The same repository again, as the Marketplace knows it: GitHub's own numeric id
# for it, which is the same number on every install because it comes from GitHub
# rather than from anybody's local database. It is what
# marketplace/repository/refresh wants, and asking the Marketplace for it instead
# would mean downloading its whole catalogue — 5,167 repositories and about
# three and a half megabytes — to read one number. If this repository is ever
# forked or renamed, this and RELEASES_URL above both have to follow.
REPO_ID = "1458113259"

# The app that goes with THIS integration, named by version rather than
# "whatever is newest". Handing out latest meant the panel could offer 4.3 and
# deliver 4.4: a Mac then runs a version its Home Assistant knows nothing
# about, and the three parts are out of step again for no reason.
APP_RELEASE_AT = (
    "https://github.com/sygad/ulanzi-d200-ha-deck/releases/download/v{version}/Ulanzi-Deck.zip"
)
APP_RELEASE_URL = (
    "https://github.com/sygad/ulanzi-d200-ha-deck/releases/latest/download/Ulanzi-Deck.zip"
)
PAIRING_FILE = "ulanzi-deck-pairing.json"
README_FILE = "Start here.html"
EVENT_KEY = "ulanzi_deck_key"

# Jumping a dashboard to one of its views. Unlike every other action here, its
# target is a path rather than an entity, and the thing it moves is a browser
# showing Home Assistant, not something in the house. browser_mod supplies it;
# the panel only offers this action when that integration is installed.
NAVIGATE = "browser_mod.navigate"

# What a button key may ask Home Assistant to do. The panel offers exactly these.
ACTIONS = {
    "light.toggle", "light.turn_on", "light.turn_off",
    "switch.toggle", "switch.turn_on", "switch.turn_off",
    "button.press",
    "cover.toggle", "cover.open_cover", "cover.close_cover",
    "media_player.media_play_pause", "media_player.volume_up", "media_player.volume_down",
    "script.turn_on", "scene.turn_on",
    NAVIGATE,
}

# Messages to the deck (see parts/02-deck-app/deckd.c)
MSG_LAYOUT = 0x02
MSG_TILE = 0x03
MSG_CLEAR = 0x06
# Messages from the deck
MSG_STATUS = 0x81
MSG_KEY = 0x82
