import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("summary", Path(__file__).parents[1] / "summarize_performance.py")
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class PerformanceSummaryTests(unittest.TestCase):
    def setUp(self):
        self.native = {"result": "Passed", "passedTests": 1, "totalTestCount": 1, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
        self.metrics = [{"testIdentifier": "PerformanceUITests/testLargeColdLaunch()", "testRuns": [{
            "device": {"deviceId": "fixed-device", "deviceName": "iPhone 16 Pro"},
            "metrics": [{"identifier": summary.CLOCK, "displayName": "Clock Monotonic Time", "unitOfMeasurement": "s", "measurements": list(range(10, 0, -1))}],
        }]}]
        launch = copy.deepcopy(self.metrics[0]["testRuns"][0]["metrics"][0])
        launch.update(identifier=summary.LAUNCH, displayName="Duration (ApplicationFirstFramePresentationResponsive)")
        self.metrics[0]["testRuns"][0]["metrics"].append(launch)
        self.fixtures = [{"version": 1, "banks": 10, "accounts": 10, "cards": 20, "billingCycles": 610, "promotions": 24,
                          "timeZone": "Asia/Shanghai", "transactions": 20_000, "searchMatches": 200, "allocations": 382,
                          "today": 20261023, "firstTransactionOn": 20211023, "lastTransactionOn": 20261023}]

    def report(self):
        return summary.summarize(self.native, self.metrics, self.fixtures, "a" * 40, expected_tests=1)

    def testNearestRankAndUnitsPreserveRawInput(self):
        original = copy.deepcopy(self.metrics)
        report = self.report()
        row = report["metrics"][0]
        self.assertEqual((row["mean"], row["p50"], row["p95"], row["min"], row["max"]), (5.5, 5, 10, 1, 10))
        self.assertEqual(row["unit"], "s")
        self.assertIn("nearest rank", report["percentileMethod"])
        self.assertIn("| 20000 | ColdLaunch", summary.markdown(report))
        self.assertEqual(self.metrics, original)

    def testFailedSkippedOrIncompleteRunsNeverBecomeBaselines(self):
        for key, value in [("result", "Failed"), ("skippedTests", 1), ("passedTests", 0)]:
            with self.subTest(key=key):
                original = self.native[key]
                self.native[key] = value
                with self.assertRaises(ValueError): self.report()
                self.native[key] = original

    def testMissingOrNonfiniteSamplesAreRejected(self):
        metric = self.metrics[0]["testRuns"][0]["metrics"][0]
        for samples in [list(range(9)), [float("nan")] * 10, [True] * 10]:
            with self.subTest(samples=samples):
                metric["measurements"] = samples
                with self.assertRaises(ValueError): self.report()

    def testRepeatedRunsAndWrongFixturesAreRejected(self):
        self.metrics[0]["testRuns"] *= 2
        with self.assertRaises(ValueError): self.report()
        self.metrics[0]["testRuns"] = self.metrics[0]["testRuns"][:1]
        self.fixtures[0]["cards"] = 19
        with self.assertRaises(ValueError): self.report()


class WritingPerformanceSummaryTests(unittest.TestCase):
    def setUp(self):
        self.native = {"result": "Passed", "passedTests": 4, "totalTestCount": 4, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
        self.metrics = []
        for phase, signpost in summary.WRITING_PHASES.items():
            identifiers = [summary.CLOCK] + [
                summary.MEMORY + suffix for suffix in ("physical", "physical_peak", "physical_absolute")
            ] + ["com.apple.dt.XCTMetric_OSSignpost-" + signpost + ".duration"]
            self.metrics.append({
                "testIdentifier": f"TransactionWritingPerformanceUITests/testSmall{phase}()",
                "testRuns": [{
                    "device": {"deviceId": "fixed-device", "deviceName": "iPhone 16 Pro"},
                    "metrics": [{
                        "identifier": identifier, "displayName": identifier,
                        "unitOfMeasurement": "s" if identifier.endswith(("duration", "monotonic")) else "kB",
                        "measurements": [0.001 * sample for sample in range(1, 11)],
                    } for identifier in identifiers],
                }],
            })
        self.fixtures = [{
            "version": 1, "banks": 10, "accounts": 10, "cards": 20, "billingCycles": 610, "promotions": 24,
            "timeZone": "Asia/Shanghai", "transactions": 100, "searchMatches": 1, "allocations": 22,
            "today": 20261027, "firstTransactionOn": 20211027, "lastTransactionOn": 20261027,
        } for _ in range(4)]

    def report(self):
        return summary.summarize(self.native, self.metrics, self.fixtures, "b" * 40, expected_tests=4, suite="writing")

    def testWritingProbeKeepsIntervalsUnitsAndPopulationLimits(self):
        original = copy.deepcopy(self.metrics)
        report = self.report()
        self.assertEqual(report["scope"], "transaction writing diagnostic subset")
        self.assertEqual(len(report["metrics"]), 20)
        self.assertIn("including warm-up", report["population"])
        self.assertIn("neither interval covers all view updates", report["applicationIntervals"])
        self.assertIn("DraftSave", summary.markdown(report))
        self.assertEqual(self.metrics, original)

    def testMissingNativeApplicationIntervalsAreRejected(self):
        self.metrics[0]["testRuns"][0]["metrics"].pop()
        with self.assertRaisesRegex(ValueError, "Missing native application interval"):
            self.report()

    def testWrongProfileAndRepeatedPhaseAreRejected(self):
        self.metrics[0]["testIdentifier"] = "TransactionWritingPerformanceUITests/testLargeAmountInput()"
        with self.assertRaisesRegex(ValueError, "Incomplete writing phase or profile coverage"):
            self.report()
        self.metrics[0] = copy.deepcopy(self.metrics[1])
        with self.assertRaisesRegex(ValueError, "Unknown or repeated performance case"):
            self.report()

    def testPartialSamplesRetriesAndSkippedCasesAreRejected(self):
        samples = self.metrics[0]["testRuns"][0]["metrics"][0]["measurements"]
        last = samples.pop()
        with self.assertRaises(ValueError):
            self.report()
        samples.append(last)
        runs = self.metrics[0]["testRuns"]
        runs.append(copy.deepcopy(runs[0]))
        with self.assertRaisesRegex(ValueError, "Repeated native test run"):
            self.report()
        runs.pop()
        self.native["skippedTests"] = 1
        with self.assertRaises(ValueError):
            self.report()

    def testFullWritingSuiteHasFourPhasesForEachPopulation(self):
        metrics, fixtures = [], []
        for profile, count in summary.PROFILES.items():
            for metric, fixture in zip(self.metrics, self.fixtures):
                item = copy.deepcopy(metric)
                item["testIdentifier"] = item["testIdentifier"].replace("testSmall", "test" + profile)
                metrics.append(item)
                item = copy.deepcopy(fixture)
                item.update(transactions=count, searchMatches=count // 100)
                fixtures.append(item)
        self.native.update(passedTests=12, totalTestCount=12)
        report = summary.summarize(self.native, metrics, fixtures, "b" * 40, expected_tests=12, suite="writing")
        self.assertEqual(report["scope"], "transaction writing baseline")
        self.assertEqual(len(report["metrics"]), 60)
        self.assertEqual({row["transactions"] for row in report["metrics"]}, {100, 5_000, 20_000})

    def testFullWritingSuiteRequiresAllTwelveCases(self):
        with self.assertRaises(ValueError):
            summary.summarize(self.native, self.metrics, self.fixtures, "b" * 40, expected_tests=12, suite="writing")


if __name__ == "__main__":
    unittest.main()
