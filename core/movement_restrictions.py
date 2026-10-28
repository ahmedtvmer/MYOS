"""Player-confirmed Movement restriction vocabulary and matching."""

from collections.abc import Iterable

from database.exercise_library.values import split_curation_values
from database.exercise_library.vocabulary import PRIMARY_ACTIONS

MOVEMENT_RESTRICTIONS = {
    "Knee flexion": {"actions": {"knee flexion"}, "slots": {"ham_curl"}},
    "Loaded knee extension": {"actions": {"knee extension"}, "slots": {"quad_iso", "quad_compound", "quad_lunge"}},
    "Hip adduction": {"actions": {"hip adduction"}, "slots": {"adductors"}},
    "Hip abduction": {"actions": {"hip abduction"}, "slots": set()},
    "Deep hip flexion": {"actions": {"hip flexion"}, "slots": {"quad_compound", "quad_lunge"}},
    "Spinal loading / flexion": {"actions": {"spinal flexion", "spinal extension"}, "slots": {"ham_hinge"}},
    "Overhead pressing": {"actions": set(), "slots": {"shoulder_press", "triceps_overhead"}},
    "Pressing / fly (shoulder horizontal adduction under load)": {
        "actions": {"shoulder horizontal adduction"},
        "slots": {"flat_press", "incline_press", "chest_fly"},
    },
    "Wrist loading": {"actions": {"wrist flexion", "wrist extension"}, "slots": {"forearm_wrist", "forearm_reverse"}},
}


def validate_movement_restrictions(values: Iterable[str]) -> list[str]:
    if isinstance(values, (str, bytes)) or not isinstance(values, Iterable):
        raise ValueError("Movement restrictions must be a list of known labels")
    supplied = list(values)
    if any(not isinstance(value, str) or value not in MOVEMENT_RESTRICTIONS for value in supplied):
        raise ValueError("Movement restrictions must be a list of known labels")
    selected = set(supplied)
    return [label for label in MOVEMENT_RESTRICTIONS if label in selected]


def is_movement_restricted(candidate: dict, slot: str, restrictions: Iterable[str]) -> bool:
    actions = {str(candidate.get("primary_action") or "").casefold()}
    secondary = candidate.get("secondary_actions") or []
    if isinstance(secondary, str):
        secondary = split_curation_values(secondary.replace(",", "|"))
    actions.update(str(value).casefold() for value in secondary)
    selected_restrictions = tuple(restrictions)
    from agent.movement_signatures import infer_candidate_slots

    inferred_slots = infer_candidate_slots(candidate)
    candidate_actions = {
        str(value).strip()
        for value in (candidate.get("primary_action"), *secondary)
        if value is not None and str(value).strip()
    }
    known_actions = {value.casefold() for value in PRIMARY_ACTIONS}
    if selected_restrictions and not slot and not candidate_actions.intersection(PRIMARY_ACTIONS) and not inferred_slots:
        return True
    if selected_restrictions and any(value.casefold() not in known_actions for value in candidate_actions):
        return True
    for label in selected_restrictions:
        rule = MOVEMENT_RESTRICTIONS.get(label)
        if rule and (
            actions.intersection(rule["actions"])
            or slot in rule["slots"]
            or bool(inferred_slots.intersection(rule["slots"]))
        ):
            return True
    return False


def restriction_for_candidate(candidate: dict, slot: str, restrictions: Iterable[str]) -> str | None:
    return next(
        (label for label in restrictions if is_movement_restricted(candidate, slot, (label,))),
        None,
    )


def restriction_for_slot(slot: str, restrictions: Iterable[str]) -> str | None:
    return next(
        (label for label in restrictions if slot in MOVEMENT_RESTRICTIONS[label]["slots"]),
        None,
    )
