import re
from pathlib import Path

from database.registry.accounts import CURRENT_FEATURE_RELEASE


def test_mobile_feature_release_matches_server_constant():
    feature_list = (
        Path(__file__).resolve().parents[1]
        / "mobile/lib/src/features/player/tour/feature_list.dart"
    )
    source = feature_list.read_text(encoding="utf-8")
    match = re.search(r"const int currentFeatureRelease = (\d+);", source)
    assert match is not None
    assert int(match.group(1)) == CURRENT_FEATURE_RELEASE
