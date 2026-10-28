"""Deterministic, non-diagnostic Movement restriction suggestions."""

import re

from core.movement_restrictions import MOVEMENT_RESTRICTIONS

_SUGGESTION_PATTERNS = {
    "Knee flexion": (
        r"\bknee flexion\b", r"\bleg curls?\b", r"\bacl\b", "الرباط الصليبي",
    ),
    "Loaded knee extension": (r"\bknee extension\b", r"\bacl\b", "الرباط الصليبي"),
    "Hip adduction": (r"\badductors?\b", r"\bhip adduction\b", "تقريب الفخذ"),
    "Hip abduction": (r"\babductors?\b", r"\bhip abduction\b", "إبعاد الفخذ"),
    "Deep hip flexion": (
        r"\bfai\b", r"hip impingement", r"deep hip flexion", "احتكاك مفصل الحوض",
    ),
    "Spinal loading / flexion": (
        r"\bspinal (?:loading|flexion)\b", r"\bback pain\b", r"\blumbar\b", r"\bspine\b",
        "وجع الظهر", "ألم الظهر", "العمود الفقري",
    ),
    "Overhead pressing": (r"overhead press(?:ing)?",),
    "Pressing / fly (shoulder horizontal adduction under load)": (
        r"shoulder horizontal adduction", r"chest press(?:ing)?", r"bench press", r"chest fly",
    ),
    "Wrist loading": (r"wrist loading", r"wrist flexion", r"wrist extension"),
}


def suggest_movement_restrictions(description: str | None) -> list[str]:
    """Suggest fixed labels from explicit deterministic injury wording."""
    if not description:
        return []
    normalized = description.casefold()
    sentences = re.split(r"[.!?;،؛]+", normalized)

    def mentioned_without_injury(clause: str, match: re.Match[str]) -> bool:
        context = clause[max(0, match.start() - 64):match.start()]
        return bool(
            re.search(r"\b(?:no|not|never)\b.{0,80}$", context)
            and not re.search(r"\b(?:cannot|can't|can not|unable to)\b.{0,80}$", context)
            or re.search(r"ما\s+عنديش\s+.{0,32}$", context)
            or re.search(r"مش\s+(?:عندي|مصاب(?:ة)?\s+ب|بعاني\s+من)\s*.{0,24}$", context)
        )

    clauses: list[tuple[str, bool, bool]] = []
    third_party = False
    negated = False
    third_party_pattern = r"\b(?:my|our)\s+(?:friend|brother|sister|mother|father|wife|husband|son|daughter)\b|\bfriend of mine\b|صاحبي|صديقي|أخي|اخويا|أختي"
    player_subject_pattern = r"\b(?:i|i'm|ive|i have|i do|my injury|my injuries)\b"
    for sentence in sentences:
        third_party = False
        negated = False
        for raw_clause in re.split(r"\s+(?:and|but|و)\s+", sentence):
            clause = raw_clause.strip()
            if not clause:
                continue
            if re.search(third_party_pattern, clause):
                third_party = True
            elif re.search(player_subject_pattern, clause):
                third_party = False
            has_explicit_player_clause = bool(re.search(
                r"\b(?:i|i'm|ive|i have|i do)\s+(?:am|have|had|tore|suffer|experience|feel|got|get|was|were)\b|(?:^|\s)(?:و\s*)?(?:أنا|عندي|لدي|أعاني|بعاني)\b",
                clause,
            ))
            if (
                re.search(r"\b(?:no|not|never)\b|ما\s+عنديش|مش\s+(?:عندي|مصاب(?:ة)?\s+ب|بعاني\s+من)", clause)
                and not re.search(r"\b(?:cannot|can't|can not|unable to)\b", clause)
            ):
                negated = True
            elif has_explicit_player_clause:
                negated = False
            clauses.append((clause, third_party, negated))

    def clause_has_suggestion(clause: str, third_party: bool, inherited_negation: bool, pattern: str) -> bool:
        if third_party:
            return False
        return any(
            not (inherited_negation or mentioned_without_injury(clause, match))
            for match in re.finditer(pattern, clause, flags=re.IGNORECASE)
        )

    return [
        label
        for label in MOVEMENT_RESTRICTIONS
        if any(
            any(clause_has_suggestion(clause, third_party, negated, pattern) for clause, third_party, negated in clauses)
            for pattern in _SUGGESTION_PATTERNS[label]
        )
    ]
