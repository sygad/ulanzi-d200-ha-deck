"""A made-up house, and three screens built from it.

Everything the project shows off — the pictures in the README, the screens
`render_test.py` draws, the pretend Home Assistant behind `panel-harness/` — comes
from here, so none of it is anybody's real home. The entities below do not exist.
Point the panel at your own Home Assistant and you will see your own.

The three screens are meant to show what the deck can do rather than to be useful:
every kind of key, every way of drawing a reading, and the wide key laid out both
ways. They are a demonstration, not a starting layout — a fresh install opens on one
empty screen, because a key pointing at an entity you do not have is worse than no
key at all.
"""

# ---------------------------------------------------------------- the house

AREAS = {
    "living_room": "Living Room",
    "kitchen": "Kitchen",
    "studio": "Studio",
    "hallway": "Hallway",
    "porch": "Porch",
    "greenhouse": "Greenhouse",
    "workshop": "Workshop",
    "guest_room": "Guest Room",
}

# entity_id, friendly name, area, state, unit. A unit makes it a reading.
THINGS = [
    # lights
    ("light.living_room_ceiling", "Ceiling", "living_room", "on", None),
    ("light.living_room_lamp", "Standard Lamp", "living_room", "on", None),
    ("light.living_room_shelf_strip", "Shelf Strip", "living_room", "off", None),
    ("light.kitchen_ceiling", "Ceiling", "kitchen", "on", None),
    ("light.kitchen_counter", "Counter", "kitchen", "off", None),
    ("light.hallway_ceiling", "Ceiling", "hallway", "off", None),
    ("light.porch_lantern", "Lantern", "porch", "off", None),
    ("light.studio_desk", "Desk", "studio", "on", None),
    ("light.studio_shelves", "Shelves", "studio", "off", None),
    ("light.workshop_bench", "Bench", "workshop", "off", None),
    ("light.guest_room_ceiling", "Ceiling", "guest_room", "off", None),
    ("light.greenhouse_grow_lamp", "Grow Lamp", "greenhouse", "off", None),
    # switches
    ("switch.kitchen_coffee_machine", "Coffee Machine", "kitchen", "off", None),
    ("switch.studio_monitor_riser", "Monitor Riser", "studio", "on", None),
    ("switch.workshop_extractor", "Extractor", "workshop", "off", None),
    ("switch.greenhouse_heater", "Heater", "greenhouse", "on", None),
    ("switch.porch_christmas_lights", "Christmas Lights", "porch", "off", None),
    # covers
    ("cover.living_room_blind", "Blind", "living_room", "open", None),
    ("cover.kitchen_blind", "Blind", "kitchen", "open", None),
    ("cover.studio_blind", "Blind", "studio", "closed", None),
    ("cover.guest_room_blind", "Blind", "guest_room", "closed", None),
    ("cover.porch_awning", "Awning", "porch", "closed", None),
    # scenes, scripts, buttons
    ("scene.living_room_evening", "Evening", "living_room", "scening", None),
    ("scene.living_room_film", "Film", "living_room", "scening", None),
    ("scene.living_room_bright", "Bright", "living_room", "scening", None),
    ("scene.studio_focus", "Focus", "studio", "scening", None),
    ("script.goodnight", "Goodnight", None, "off", None),
    ("script.water_the_greenhouse", "Water the Greenhouse", "greenhouse", "off", None),
    ("button.studio_printer_restart", "Printer Restart", "studio", "unknown", None),
    ("button.porch_doorbell_chime", "Doorbell Chime", "porch", "unknown", None),
    # media
    ("media_player.living_room_speaker", "Speaker", "living_room", "playing", None),
    ("media_player.kitchen_radio", "Radio", "kitchen", "idle", None),
    # readings
    ("sensor.living_room_temperature", "Temperature", "living_room", "20.4", "°C"),
    ("sensor.living_room_humidity", "Humidity", "living_room", "47.2", "%"),
    ("sensor.studio_carbon_dioxide", "Carbon Dioxide", "studio", "812", "ppm"),
    ("sensor.studio_temperature", "Temperature", "studio", "21.8", "°C"),
    ("sensor.greenhouse_temperature", "Temperature", "greenhouse", "16.9", "°C"),
    ("sensor.greenhouse_humidity", "Humidity", "greenhouse", "68.5", "%"),
    ("sensor.house_power", "Power", None, "317", "W"),
    ("sensor.house_energy_today", "Energy Today", None, "6.4", "kWh"),
    ("sensor.solar_power", "Solar Power", None, "1240", "W"),
    ("sensor.porch_light_level", "Light Level", "porch", "184", "lx"),
    ("sensor.water_butt_level", "Water Butt Level", "greenhouse", "72", "%"),
    ("sensor.workshop_particulates", "Particulates", "workshop", "11.4", "µg/m³"),
    ("binary_sensor.porch_front_door", "Front Door", "porch", "off", None),
    ("binary_sensor.workshop_window", "Window", "workshop", "on", None),
]

# a day's readings for the keys that draw a graph, oldest first
HISTORY = {
    "sensor.living_room_temperature": [
        18.1, 17.9, 17.6, 17.4, 17.2, 17.1, 17.3, 18.4, 19.2, 19.6, 19.8, 20.1,
        20.3, 20.6, 20.9, 21.2, 21.0, 20.7, 20.5, 20.4, 20.6, 20.5, 20.4],
    "sensor.studio_carbon_dioxide": [
        471, 462, 455, 449, 447, 452, 486, 604, 712, 788, 836, 870,
        902, 861, 795, 742, 706, 688, 742, 806, 848, 830, 812],
    "sensor.greenhouse_humidity": [
        74.1, 75.0, 75.6, 76.1, 76.4, 76.0, 74.8, 72.6, 70.9, 69.4, 68.2, 67.5,
        66.8, 66.2, 66.0, 66.4, 67.1, 67.9, 68.6, 69.2, 69.0, 68.8, 68.5],
    "sensor.house_power": [
        212, 198, 186, 181, 178, 180, 244, 612, 735, 498, 402, 376,
        355, 348, 362, 390, 441, 688, 812, 640, 470, 358, 317],
}

UNITS = {e: u for e, _, _, _, u in THINGS if u}
NAMES = {e: n for e, n, _, _, _ in THINGS}
OFF_STATES = {"off", "closed", "idle", "unavailable", "unknown"}
# these do something and are done, so their keys stay lit (MOMENTARY in hub.py)
MOMENTARY = {"button", "input_button", "scene", "script"}


# ---------------------------------------------------------------- the screens

def B(l, i, c, a, t="", ha="none", ht=""):
    return {"type": "button", "l": l, "i": i, "c": c, "layout": "v",
            "tap": {"a": a, "t": t}, "hold": {"a": ha, "t": ht}}


def E(l, ent, c, show="value", style="icon", icon="gauge", lo=0, hi=100, **kw):
    k = {"type": "entity", "l": l, "i": icon, "c": c, "ent": ent, "show": show, "style": style,
         "min": lo, "max": hi, "band": False, "warn": lo + (hi - lo) * .5,
         "alert": lo + (hi - lo) * .75, "layout": "v"}
    k.update(kw)
    return k


PAGES = [
    # 1 — things to press, and two readings. The wide key draws its graph beside its text.
    {"name": "Home", "icon": "home", "keys": [
        B("Ceiling", "ceiling-light", "#ffc107", "light.toggle", "light.living_room_ceiling"),
        E("Living Room", "sensor.living_room_temperature", "#4dd0e1", "full", "graph", "thermometer", 0, 30),
        B("Lamp", "floor-lamp", "#ffc107", "light.toggle", "light.living_room_lamp"),
        B("Counter", "countertop", "#ffc107", "light.toggle", "light.kitchen_counter"),
        B("Coffee", "coffee-maker", "#ff7043", "switch.toggle", "switch.kitchen_coffee_machine"),
        B("Hallway", "coat-rack", "#ffc107", "light.toggle", "light.hallway_ceiling"),
        B("Porch", "outdoor-lamp", "#ffc107", "light.toggle", "light.porch_lantern"),
        B("Desk", "desk-lamp", "#ffc107", "light.toggle", "light.studio_desk"),
        B("Bench", "tools", "#ffc107", "light.toggle", "light.workshop_bench"),
        E("House", "sensor.house_power", "#8bc34a", "full", "gauge", "flash", 0, 2000),
        B("Scenes", "palette", "#03a9f4", "deck.go_to_page", "1"),
        B("Blinds", "window-shutter", "#03a9f4", "deck.go_to_page", "2"),
        B("Next screen", "arrow-right-bold", "#ffffff", "deck.next_page"),
        E("Studio CO₂", "sensor.studio_carbon_dioxide", "#8bc34a", "full", "graph",
          "molecule-co2", 400, 2000, band=True, layout="h"),
    ]},
    # 2 — scenes and scripts, and the other ways a reading can be drawn. A clock key too.
    {"name": "Scenes", "icon": "palette", "keys": [
        B("Evening", "weather-night", "#ba68c8", "scene.turn_on", "scene.living_room_evening"),
        B("Film", "television-play", "#ba68c8", "scene.turn_on", "scene.living_room_film"),
        B("Bright", "white-balance-sunny", "#ba68c8", "scene.turn_on", "scene.living_room_bright"),
        B("Focus", "lightbulb-on", "#ba68c8", "scene.turn_on", "scene.studio_focus"),
        E("Greenhouse", "sensor.greenhouse_temperature", "#4dd0e1", "full", "icon", "thermometer", 0, 30),
        {"type": "clock", "l": "", "i": "clock-outline", "c": "#ffffff", "layout": "v",
         "fmt": "24", "secs": True, "date": True, "showIcon": False},
        E("Solar", "sensor.solar_power", "#8bc34a", "value", "bar", "solar-power", 0, 3000),
        E("Water Butt", "sensor.water_butt_level", "#4dd0e1", "value", "number", "water-percent"),
        E("Today", "sensor.house_energy_today", "#8bc34a", "value", "gauge", "lightning-bolt", 0, 20),
        E("Greenhouse", "sensor.greenhouse_humidity", "#4dd0e1", "full", "graph", "water-percent"),
        B("Printer", "printer-3d", "#ff7043", "button.press", "button.studio_printer_restart"),
        B("Water", "watering-can", "#ff7043", "script.turn_on", "script.water_the_greenhouse"),
        B("Back", "keyboard-backspace", "#ffffff", "deck.back"),
        # the wide key the other way about: the clock reads across it
        {"type": "clock", "l": "Studio", "i": "clock-outline", "c": "#03a9f4", "layout": "h",
         "fmt": "12", "secs": False, "date": True},
    ]},
    # 3 — covers and media, and a key that does one thing tapped and another held
    {"name": "Blinds", "icon": "window-shutter", "keys": [
        B("Living Room", "window-shutter", "#4dd0e1", "cover.toggle", "cover.living_room_blind"),
        B("Kitchen", "window-shutter", "#4dd0e1", "cover.toggle", "cover.kitchen_blind"),
        B("Studio", "window-shutter", "#4dd0e1", "cover.toggle", "cover.studio_blind"),
        B("Guest Room", "window-shutter", "#4dd0e1", "cover.toggle", "cover.guest_room_blind"),
        B("Awning", "awning-outline", "#4dd0e1", "cover.toggle", "cover.porch_awning"),
        # tap plays or pauses, hold turns it up: both sit on the key at once in the panel
        B("Speaker", "speaker", "#f06292", "media_player.media_play_pause",
          "media_player.living_room_speaker", "media_player.volume_up", "media_player.living_room_speaker"),
        B("Radio", "radio", "#f06292", "media_player.media_play_pause", "media_player.kitchen_radio"),
        B("Extractor", "fan", "#ff7043", "switch.toggle", "switch.workshop_extractor"),
        E("Workshop", "sensor.workshop_particulates", "#8bc34a", "full", "bar", "air-filter", 0, 50),
        E("Porch", "sensor.porch_light_level", "#ffc107", "full", "icon", "brightness-5", 0, 1000),
        B("Goodnight", "weather-night", "#ba68c8", "script.turn_on", "script.goodnight"),
        B("Chime", "bell-ring", "#ff7043", "button.press", "button.porch_doorbell_chime"),
        B("Back", "keyboard-backspace", "#ffffff", "deck.back"),
        B("Home", "home", "#ffffff", "deck.go_to_page", "0"),
    ]},
]


# ------------------------------------------- what the renderer is told, for tests

LIVE = {
    e: {"text": s, "unit": u, "value": float(s), "name": NAMES[e],
        "history": HISTORY.get(e, [])}
    for e, _, _, s, u in THINGS if u
}
LIT = {e: e.split(".")[0] in MOMENTARY or s not in OFF_STATES
       for e, _, _, s, _ in THINGS}


def live(screen, n):
    """What render.preview() should take as true, so the demo pictures have readings."""
    keys = PAGES[screen]["keys"]
    k = keys[n] if n < len(keys) else None
    if not k:
        return None
    if k["type"] == "entity":
        return LIVE.get(k["ent"])
    if k["type"] == "button":
        return {"lit": LIT.get(k["tap"]["t"], True)}
    return None
