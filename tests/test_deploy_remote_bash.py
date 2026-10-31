import os
import subprocess
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "deploy" / "deploy_server.sh"


def test_remote_bash_preserves_empty_and_spaced_arguments(tmp_path):
    stub = tmp_path / "ssh"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        "shift\n"
        "command=\"$*\"\n"
        "exec bash -c \"$command\"\n",
        encoding="utf-8",
    )
    stub.chmod(0o755)
    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}{os.pathsep}{env.get('PATH', '')}"
    result = subprocess.run(
        ["bash", "-c", 'source "$1"; ssh_target=selftest; remote_bash "" "two words"', "test", str(SCRIPT)],
        input='printf "%s\\n" "$#" "$1" "$2"\n',
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["2", "", "two words"]
    # The old `bash -s -- "${remote_args[@]}"` expansion loses the empty value
    # when ssh joins its arguments into the remote command string.


def _run_deploy_release(tmp_path, readiness_result):
    log = tmp_path / "calls.log"
    harness = r'''
source "$1"
log="$2"
current_tag=""
record() { printf '%s\n' "$1" >> "$log"; }
upload_build_input() { record upload_build_input; }
set_image_tag() { record set_image_tag; }
build_and_start() { record build_and_start; }
check_readiness() { record check_readiness; return "$READINESS_RESULT"; }
start_companion_services() { record start_companion_services; }
remember_image() { record remember_image; }
prune_images() { record prune_images; }
prune_build_cache_and_report_disk() { record prune_build_cache_and_report_disk; }
restore_previous_after_failure() { record restore_previous_after_failure; }
deploy_release fakecommit faketag
'''
    env = os.environ.copy()
    env["READINESS_RESULT"] = str(readiness_result)
    return subprocess.run(
        ["bash", "-c", harness, "test", str(SCRIPT), str(log)],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    ), log


def test_companion_services_start_after_successful_readiness(tmp_path):
    result, log = _run_deploy_release(tmp_path, 0)
    assert result.returncode == 0, result.stderr
    calls = log.read_text(encoding="utf-8").splitlines()
    assert calls.index("check_readiness") < calls.index("start_companion_services")
    assert calls.index("start_companion_services") < calls.index("remember_image")


def test_companion_services_do_not_start_when_readiness_fails(tmp_path):
    result, log = _run_deploy_release(tmp_path, 1)
    assert result.returncode == 0, result.stderr
    calls = log.read_text(encoding="utf-8").splitlines()
    assert "restore_previous_after_failure" in calls
    assert "start_companion_services" not in calls
