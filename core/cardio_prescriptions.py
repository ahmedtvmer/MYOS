"""Interpret legacy free-text Cardio prescriptions."""

import re
from typing import Any


def parse_legacy_cardio_prescription(text: str) -> dict[str, Any] | None:
    minutes = re.search(r"(\d+)\s*(?:-|–)?\s*(?:\d+\s*)?(?:min|minute)", text, re.I)
    if minutes is None:
        return None
    speed = re.search(r"(\d+(?:\.\d+)?)\s*km/?h", text, re.I)
    incline = re.search(r"(\d+(?:\.\d+)?)\s*%", text)
    return {
        "machine": "treadmill",
        "minutes": int(minutes.group(1)),
        "speed_kmh": float(speed.group(1)) if speed else None,
        "incline_pct": float(incline.group(1)) if incline else None,
    }
