"""Committed Program import evaluation reports stay bound to the current prompts.

Kept out of tests/test_program_import.py, which is the evaluation privacy suite:
re-recording a report after a prompt change must not depend on the stale report.
"""

import json
from pathlib import Path


def test_committed_sheet_report_and_prompt_hash_remain_valid():
    from service import program_import_ai

    report = json.loads((Path(__file__).parents[1] / "reports/program_import_eval.json").read_text(encoding="utf-8"))
    assert program_import_ai.prompt_version_hash() == "a5c879aa7e28699a58ef47234425587fadabbe720b2b47471c1512788d1f3e7c"
    assert program_import_ai.text_prompt_version_hash() == "fdd73d190b388369fabe9f0270d985bc038725e2aacf342209ee2603136a2120"
    assert program_import_ai.validate_report(report) == (True, [])
    text_report = json.loads((Path(__file__).parents[1] / "reports/program_import_text_eval.json").read_text(encoding="utf-8"))
    assert program_import_ai.validate_report(text_report) == (True, [])
