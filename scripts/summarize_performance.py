"""Summarize Xcode 16.4's native metrics; incomplete runs never become baselines."""

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import re
import statistics


PROFILES = {"Small": 100, "Medium": 5_000, "Large": 20_000}
PHASES = (
    "ColdLaunch", "WarmActivation", "CardsFirstEntry", "PromotionsFirstEntry",
    "TransactionsFirstEntry", "TransactionSearch", "TransactionScroll",
)
CLOCK = "com.apple.dt.XCTMetric_Clock.time.monotonic"
LAUNCH = "com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration"
MEMORY = "com.apple.dt.XCTMetric_Memory-com.maxduke.CardPilot."
SCROLL = "com.apple.dt.XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.duration"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def percentiles(values):
    """Nearest rank for both percentiles; ten samples make p95 the maximum."""
    ordered = sorted(values)
    return {f"p{p}": ordered[math.ceil(p / 100 * len(ordered)) - 1] for p in (50, 95)}


def summarize(summary, metrics, fixtures, source_revision, expected_tests=21):
    require(summary.get("result") == "Passed", "Native run did not pass")
    require(summary.get("passedTests") == expected_tests == summary.get("totalTestCount"), "Incomplete native test count")
    require(summary.get("failedTests") == summary.get("skippedTests") == summary.get("expectedFailures") == 0, "Native failures or skips")
    require(re.fullmatch(r"[a-f0-9]{40}", source_revision), "Missing exact source revision")
    require(len(metrics) == expected_tests == len(fixtures), "Missing metrics or isolated fixture reports")
    rows, tests, devices, profiles = [], set(), set(), Counter()
    for test in metrics:
        test_id = test["testIdentifier"]
        match = re.fullmatch(r"PerformanceUITests/test(Small|Medium|Large)(" + "|".join(PHASES) + r")\(\)", test_id)
        require(match is not None and test_id not in tests, "Unknown or repeated performance case")
        tests.add(test_id)
        count = PROFILES[match[1]]
        profiles[count] += 1
        require(len(test["testRuns"]) == 1, "Repeated native test run")
        run = test["testRuns"][0]
        devices.add((run["device"]["deviceId"], run["device"]["deviceName"]))
        identifiers = set()
        for metric in run["metrics"]:
            identifier, values = metric["identifier"], metric["measurements"]
            require(identifier not in identifiers, "Repeated metric")
            identifiers.add(identifier)
            require(len(values) == 10, f"Expected ten samples: {test_id}/{identifier}")
            require(all(type(value) in (int, float) and math.isfinite(value) for value in values), "Invalid metric value")
            rows.append({
                "test": test_id, "transactions": count, "phase": match[2],
                "metric": metric["displayName"], "identifier": identifier,
                "unit": metric["unitOfMeasurement"], "samples": len(values),
                "mean": statistics.mean(values), **percentiles(values),
                "min": min(values), "max": max(values),
            })
        require(CLOCK in identifiers, f"Missing clock metric: {test_id}")
        if match[2] == "ColdLaunch":
            require(LAUNCH in identifiers, "Missing responsive launch metric")
        else:
            require({MEMORY + suffix for suffix in ("physical", "physical_peak", "physical_absolute")} <= identifiers, "Missing app memory metrics")
        if match[2] == "TransactionScroll":
            require(SCROLL in identifiers, "Missing native scrolling metric")
    require(len(devices) == 1, "Mixed measurement devices")
    require(Counter(fixture["transactions"] for fixture in fixtures) == profiles, "Fixture sizes differ from measured cases")
    for fixture in fixtures:
        require(all(fixture[key] == value for key, value in {
            "version": 1, "banks": 10, "accounts": 10, "cards": 20,
            "billingCycles": 610, "promotions": 24, "timeZone": "Asia/Shanghai",
        }.items()), "Fixture population mismatch")
        require(fixture["searchMatches"] == fixture["transactions"] // 100 and fixture["allocations"] >= 2, "Invalid fixture search or allocations")
        require(fixture["lastTransactionOn"] == fixture["today"] > fixture["firstTransactionOn"], "Invalid fixture dates")
    require(len({fixture["today"] for fixture in fixtures}) == 1, "Business date changed during sampling")
    return {
        "sourceRevision": source_revision, "tests": expected_tests,
        "scope": "full baseline" if expected_tests == 21 else "diagnostic subset",
        "device": dict(zip(("id", "name"), next(iter(devices)))),
        "businessDate": fixtures[0]["today"],
        "percentileMethod": "nearest rank: sorted[ceil(p * n) - 1]; p95 of ten samples is the maximum",
        "metrics": rows,
    }


def markdown(report):
    lines = [
        f"# Release performance {report['scope']} — {report['sourceRevision']}", "",
        f"{report['tests']} passed cases; {report['device']['name']}; business date {report['businessDate']}.", "",
        "Ten effective samples per metric; the XCTest warm-up is excluded. Percentiles use nearest rank; p95 is the largest of ten samples.", "",
        "Clock measurements include native UI automation and readiness checks. Memory names and units are preserved from Xcode. Raw samples remain in metrics.json; this simulator run does not establish real-device performance.", "",
        "| Transactions | Phase | Metric | Unit | n | Mean | p50 | p95 | Min | Max |",
        "| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in sorted(report["metrics"], key=lambda row: (row["transactions"], row["phase"], row["identifier"])):
        text = [str(row[key]).replace("|", "\\|").replace("\n", " ") for key in ("transactions", "phase", "metric", "unit", "samples")]
        values = [f"{row[key]:.6f}" for key in ("mean", "p50", "p95", "min", "max")]
        lines.append("| " + " | ".join(text + values) + " |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--expected-tests", type=int, default=21)
    args = parser.parse_args()
    for name in ("baseline-summary.json", "baseline.md"):
        (args.evidence / name).unlink(missing_ok=True)
    log = (args.evidence / "xcodebuild.log").read_text()
    require(not re.search(r"Restarting after unexpected exit|Re-executing after failure|exceeded execution time allowance", log), "Native execution restarted, retried, or timed out")
    report = summarize(
        json.loads((args.evidence / "summary.json").read_text()),
        json.loads((args.evidence / "metrics.json").read_text()),
        [json.loads(path.read_text()) for path in sorted((args.evidence / "fixtures").glob("*.json"))],
        (args.evidence / "source-revision.txt").read_text().strip(), args.expected_tests,
    )
    (args.evidence / "baseline-summary.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.evidence / "baseline.md").write_text(markdown(report))


if __name__ == "__main__":
    main()
