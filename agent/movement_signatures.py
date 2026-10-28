"""Shared Movement signature matching for generation and coverage reporting."""

from agent.program_blueprints import SLOT_SPECS, SlotSpec


def matches_movement_signature(
    primary_action: object,
    primary_muscle: object,
    spec: SlotSpec,
) -> bool:
    """Return whether both curated fields are allowed by the slot signature."""
    return (
        bool(primary_action)
        and bool(primary_muscle)
        and primary_action in spec.primary_actions
        and primary_muscle in spec.primary_muscles
    )


def infer_candidate_slots(candidate: dict) -> set[str]:
    """Return a slot only when the curated movement signature is unambiguous."""
    action = candidate.get("primary_action")
    muscle = candidate.get("primary_muscle")
    slots: set[str] = set()
    for key, spec in SLOT_SPECS.items():
        if matches_movement_signature(action, muscle, spec):
            slots.add(key)
    name = " ".join(str(candidate.get(key) or "") for key in ("name", "source_name")).casefold()
    if "landmine" in name:
        return slots - {"shoulder_press"}
    overhead_terms = (
        "overhead", "military", "shoulder press", "push press", "arnold",
        "behind the neck", "z press", "jerk", "french press",
    )
    secondary = candidate.get("secondary_actions") or []
    if isinstance(secondary, str):
        secondary = secondary.replace("|", ",").split(",")
    press_actions = (
        str(action or "").casefold() in {"shoulder abduction", "shoulder flexion"}
        and any(str(value).strip().casefold() == "elbow extension" for value in secondary)
    )
    if any(term in name for term in overhead_terms) or (press_actions and "landmine" not in name):
        triceps = "triceps" in str(muscle or "").casefold()
        return {"triceps_overhead" if triceps else "shoulder_press"}
    return slots if len(slots) == 1 else set()
