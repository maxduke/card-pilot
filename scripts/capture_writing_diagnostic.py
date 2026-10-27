"""Temporary bounded app-process sampling for the writing lifecycle diagnostic."""

from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
import time


def command(arguments, output, timeout=10):
    try:
        result = subprocess.run(
            arguments, capture_output=True, text=True, errors="replace", timeout=timeout
        )
        output.write_text(f"$ {arguments!r}\nexit={result.returncode}\n{result.stdout}{result.stderr}")
        return result.returncode, result.stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        output.write_text(f"$ {arguments!r}\n{error!r}\n")
        return None, ""


def main():
    log_path, destination = map(Path, sys.argv[1:])
    destination.mkdir(parents=True, exist_ok=True)
    marker = re.compile(r"CARDPILOT_WRITING_DIAGNOSTIC phase=([\w-]+) session=([\w-]+)")
    phases = {"background-without-metrics", "background-after-metrics", "save-commit", "search-readback"}
    counts = Counter()
    captures = 0
    with log_path.open() as log:
        pending = ""
        while captures < 8:
            pending += log.readline()
            if not pending.endswith("\n"):
                time.sleep(0.2)
                continue
            line, pending = pending, ""
            match = marker.search(line)
            if match and match[1] in phases:
                phase, session = match.groups()
            elif "App event loop idle notification not received" in line:
                phase, session = "app-idle-timeout", "unknown"
            else:
                continue
            if counts[phase] >= 2:
                continue
            counts[phase] += 1
            captures += 1
            folder = destination / f"{captures:02d}-{phase}"
            folder.mkdir()
            (folder / "trigger.txt").write_text(line)
            metadata = {
                "phase": phase, "session": session,
                "capturedAt": datetime.now(timezone.utc).isoformat(), "applications": [],
            }
            _, pids = command(["pgrep", "-f", "/CardPilot[.]app/CardPilot"], folder / "pgrep.txt")
            for pid in pids.split():
                if not pid.isdecimal():
                    continue
                command(["ps", "-p", pid, "-o", "pid,ppid,etime,time,%cpu,%mem,state,comm"], folder / f"app-{pid}-ps.txt")
                sample_path = folder / f"app-{pid}.sample.txt"
                status, _ = command(["sample", pid, "1", "-file", str(sample_path)], folder / f"app-{pid}-sample-command.txt")
                metadata["applications"].append({
                    "pid": int(pid), "sampleExit": status, "samplePath": str(sample_path),
                    "sampleBytes": sample_path.stat().st_size if sample_path.exists() else 0,
                })
            (folder / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
            print(json.dumps(metadata), flush=True)


if __name__ == "__main__":
    main()
