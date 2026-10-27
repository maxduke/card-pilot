"""Capture native app evidence once XCTest reports an app-idle timeout."""

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
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"Capture failed: {error}", flush=True)
        return ""
    print(f"exit={result.returncode}\n{result.stdout}{result.stderr}", flush=True)
    return result.stdout


def main():
    log_path, device_id = sys.argv[1:]
    with open(log_path) as log:
        line = ""
        while True:
            line += log.readline()
            if not line.endswith("\n"):
                time.sleep(0.25)
                continue
            if "App event loop idle notification not received" in line:
                break
            line = ""

    evidence = Path("app-idle-diagnostics")
    evidence.mkdir(exist_ok=True)
    trigger = f"{datetime.now(timezone.utc).isoformat()}\n{line}"
    (evidence / "trigger.txt").write_text(trigger)
    print(trigger, flush=True)
    app_pids = run(["pgrep", "-f", "/CardPilot[.]app/CardPilot"])
    for pid in app_pids.split():
        if pid.isdecimal():
            run(["ps", "-p", pid, "-o", "pid,ppid,etime,time,%cpu,%mem,state,comm"])
            run(["sample", pid, "1", "-file", str(evidence / f"app-{pid}.sample.txt")])
    run(["xcrun", "simctl", "io", device_id, "screenshot", str(evidence / "screen.png")], timeout=15)


if __name__ == "__main__":
    main()
