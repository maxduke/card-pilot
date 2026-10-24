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


if __name__ == "__main__":
    unittest.main()
