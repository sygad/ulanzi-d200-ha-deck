"""Builds tools/panel-harness/data.json from the made-up house in demo_house.py.

Run it after changing the house:  python3 tools/make_demo_data.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import demo_house as house

states, entities = {}, {}
for entity_id, name, area, state, unit in house.THINGS:
    attributes = {"friendly_name": name}
    if unit:
        attributes["unit_of_measurement"] = unit
    states[entity_id] = {"entity_id": entity_id, "state": state, "attributes": attributes}
    entities[entity_id] = {"entity_id": entity_id, "area_id": area}

data = {
    "states": states,
    "areas": {area_id: {"area_id": area_id, "name": name} for area_id, name in house.AREAS.items()},
    "entities": entities,
    "hist": house.HISTORY,
    "pages": house.PAGES,
}

out = ROOT / "tools" / "panel-harness" / "data.json"
out.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"{out.relative_to(ROOT)}: {len(states)} entities, {len(data['areas'])} areas, "
      f"{len(house.PAGES)} screens")
