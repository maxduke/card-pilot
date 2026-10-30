"""Capture bounded native app system stacks after explicit search-ready markers."""

from datetime import datetime, timezone
from pathlib import Path
import subprocess
import sys
import time


def run(command, timeout=10):
    print(f"$ {command!r}", flush=True)
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, errors="replace", timeout=timeout
        )
    except subprocess.TimeoutExpired as error:
        print(f"Capture failed: {error}", flush=True)
        for output in (error.stdout, error.stderr):
            if output:
                print(output.decode(errors="replace") if isinstance(output, bytes) else output, flush=True)
        return ""
    except OSError as error:
        print(f"Capture failed: {error}", flush=True)
        return ""
    print(f"exit={result.returncode}\n{result.stdout}{result.stderr}", flush=True)
    return result.stdout


def capture(line, test_case, device_id, index):
    evidence = Path("search-profile-diagnostics") / f"capture-{index:02d}"
    evidence.mkdir(parents=True, exist_ok=True)
    trigger = f"{datetime.now(timezone.utc).isoformat()}\n{test_case}\ndevice={device_id}\n{line}"
    (evidence / "trigger.txt").write_text(trigger)
    print(trigger, flush=True)
    app_pids = run(["pgrep", "-f", "/CardPilot[.]app/CardPilot"])
    for pid in app_pids.split():
        if pid.isdecimal():
            run(["ps", "-p", pid, "-o", "pid,ppid,etime,time,%cpu,%mem,state,comm"])
            report = run(["sudo", "-n", "/usr/sbin/spindump", pid, "2", "10", "-onlyTarget",
                          "-timelimit", "25", "-noBinary", "-o",
                          str(Path("/tmp") / f"CardPilotSearch-{pid}.spindump.txt"),
                          "-stdout"], timeout=30)
            if report:
                (evidence / f"app-{pid}.spindump.txt").write_text(report)


def main():
    log_path, device_id = sys.argv[1:]
    captured_tests = set()
    test_case = "Unknown test case"
    with open(log_path) as log:
        line = ""
        while True:
            line += log.readline()
            if not line.endswith("\n"):
                time.sleep(0.25)
                continue
            if line.startswith("Test Case '") and line.rstrip().endswith(" started."):
                test_case = line.strip()
            if "CARDPILOT_SEARCH_PROFILE_BEGIN" in line and test_case not in captured_tests:
                captured_tests.add(test_case)
                capture(line, test_case, device_id, len(captured_tests))
                # Bound diagnostic work without letting an earlier test consume
                # the only capture opportunity for the rest of the suite.
                if len(captured_tests) == 8:
                    print("Reached the eight-test diagnostic capture limit.", flush=True)
                    return
            line = ""


if __name__ == "__main__":
    main()
