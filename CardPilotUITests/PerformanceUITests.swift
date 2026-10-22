#if PERFORMANCE_TESTING && targetEnvironment(simulator)
#if DEBUG
#error("Performance measurements require the Release configuration without DEBUG")
#endif
import XCTest
import UIKit

@MainActor
final class PerformanceUITests: XCTestCase {
    private enum Profile: Int {
        case small = 100, medium = 5_000, large = 20_000

        var scenario: String {
            switch self {
            case .small: "performanceSmall"
            case .medium: "performanceMedium"
            case .large: "performanceLarge"
            }
        }
    }

    private enum Page: String {
        case cards = "卡片", promotions = "促销", transactions = "交易"
    }

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Ten samples plus XCTest's discarded warm-up, with a fresh launch for
        // each first-entry sample. This is separate from ordinary regression CI.
        executionTimeAllowance = 600
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-cardPilot.homeTimeZone", "Asia/Shanghai",
            "-cardPilot.appLockEnabled", "NO",
            "-cardPilot.statementRemindersEnabled", "NO",
            "-cardPilot.repaymentRemindersEnabled", "NO",
            "-cardPilot.lastUsedCardID", ""
        ]
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            capture("性能基线失败")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
        app = nil
    }

    func testSmallColdLaunch() { measureColdLaunch(.small) }
    func testMediumColdLaunch() { measureColdLaunch(.medium) }
    func testLargeColdLaunch() { measureColdLaunch(.large) }
    func testSmallWarmActivation() { measureWarmActivation(.small) }
    func testMediumWarmActivation() { measureWarmActivation(.medium) }
    func testLargeWarmActivation() { measureWarmActivation(.large) }
    func testSmallCardsFirstEntry() { measureFirstEntry(.cards, profile: .small) }
    func testMediumCardsFirstEntry() { measureFirstEntry(.cards, profile: .medium) }
    func testLargeCardsFirstEntry() { measureFirstEntry(.cards, profile: .large) }
    func testSmallPromotionsFirstEntry() { measureFirstEntry(.promotions, profile: .small) }
    func testMediumPromotionsFirstEntry() { measureFirstEntry(.promotions, profile: .medium) }
    func testLargePromotionsFirstEntry() { measureFirstEntry(.promotions, profile: .large) }
    func testSmallTransactionsFirstEntry() { measureFirstEntry(.transactions, profile: .small) }
    func testMediumTransactionsFirstEntry() { measureFirstEntry(.transactions, profile: .medium) }
    func testLargeTransactionsFirstEntry() { measureFirstEntry(.transactions, profile: .large) }
    func testSmallTransactionSearch() { measureSearch(.small) }
    func testMediumTransactionSearch() { measureSearch(.medium) }
    func testLargeTransactionSearch() { measureSearch(.large) }
    func testSmallTransactionScroll() { measureScroll(.small) }
    func testMediumTransactionScroll() { measureScroll(.medium) }
    func testLargeTransactionScroll() { measureScroll(.large) }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        return options
    }

    private var interactionMetrics: [XCTMetric] {
        [XCTClockMetric(), XCTMemoryMetric(application: app)]
    }

    private func prepare(_ profile: Profile) {
        let session = UUID().uuidString
        app.launchEnvironment["CARDPILOT_UI_SESSION"] = session
        app.launchEnvironment["CARDPILOT_UI_SCENARIO"] = profile.scenario
        // Seed and validate the on-disk store before any measured iteration.
        app.launch()
        assertDashboardReady()
        open(.transactions, profile: profile)
        XCTAssertTrue(app.buttons["transaction.Baseline Latest"].waitForExistence(timeout: 30))
        let metadata = XCTAttachment(string: """
            session=\(session)
            scenario=\(profile.scenario)
            transactions=\(profile.rawValue)
            samples=10 (XCTest warm-up excluded)
            locale=zh_CN; homeTimeZone=Asia/Shanghai; textSize=large
            setupCompletedAt=\(ISO8601DateFormatter().string(from: .now))
            """
        )
        metadata.name = "performance-session"
        metadata.lifetime = .keepAlways
        add(metadata)
        app.terminate()
    }

    private func freshLaunch() {
        app.terminate()
        app.launch()
        assertDashboardReady()
    }

    private func assertDashboardReady() {
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
        XCTAssertTrue(app.navigationBars["CardPilot"].waitForExistence(timeout: 30))
        let billingRow = app.buttons.matching(NSPredicate(format: "identifier CONTAINS %@", "billingCycle.")).firstMatch
        XCTAssertTrue(billingRow.waitForExistence(timeout: 30))
    }

    private func open(_ page: Page, profile: Profile) {
        let tab = app.tabBars.buttons[page.rawValue]
        XCTAssertTrue(tab.isEnabled && tab.isHittable)
        tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(tab.isSelected)
        XCTAssertTrue(app.navigationBars[page.rawValue].waitForExistence(timeout: 30))
        switch page {
        case .cards:
            XCTAssertTrue(app.buttons["card.Baseline Card 00"].waitForExistence(timeout: 30))
        case .promotions:
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Baseline Series 0")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 30))
        case .transactions:
            assertResultCount(profile.rawValue)
            XCTAssertTrue(app.buttons["transaction.Baseline Latest"].waitForExistence(timeout: 30))
        }
    }

    private func assertResultCount(_ count: Int) {
        let result = app.staticTexts["transactions.results.count"]
        let displayedCount = count.formatted(.number.locale(Locale(identifier: "zh_CN")))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "共 \(displayedCount) 笔交易"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
    }

    private func measureColdLaunch(_ profile: Profile) {
        prepare(profile)
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), XCTClockMetric()], options: options) {
            app.terminate()
            startMeasuring()
            app.launch()
            assertDashboardReady()
            stopMeasuring()
        }
        capture("性能基线\(profile.rawValue)-进程冷启动首页")
    }

    private func measureWarmActivation(_ profile: Profile) {
        prepare(profile)
        freshLaunch()
        measure(metrics: interactionMetrics, options: options) {
            XCUIDevice.shared.press(.home)
            let backgrounded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [backgrounded], timeout: 10), .completed)
            startMeasuring()
            app.activate()
            assertDashboardReady()
            stopMeasuring()
        }
        capture("性能基线\(profile.rawValue)-前台恢复首页")
    }

    private func measureFirstEntry(_ page: Page, profile: Profile) {
        prepare(profile)
        measure(metrics: interactionMetrics, options: options) {
            freshLaunch()
            startMeasuring()
            open(page, profile: profile)
            stopMeasuring()
        }
        capture("性能基线\(profile.rawValue)-\(page.rawValue)首次进入")
    }

    private func measureSearch(_ profile: Profile) {
        prepare(profile)
        freshLaunch()
        open(.transactions, profile: profile)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        measure(metrics: interactionMetrics, options: options) {
            startMeasuring()
            search.typeText("73519")
            assertResultCount(profile.rawValue / 100)
            stopMeasuring()
            // Reset outside the window; every sample starts with the same list.
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
            assertResultCount(profile.rawValue)
        }
        search.typeText("73519")
        assertResultCount(profile.rawValue / 100)
        capture("性能基线\(profile.rawValue)-搜索结果")
    }

    private func measureScroll(_ profile: Profile) {
        prepare(profile)
        measure(metrics: interactionMetrics + [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            freshLaunch()
            open(.transactions, profile: profile)
            let list = app.collectionViews.firstMatch
            XCTAssertTrue(list.isHittable)
            startMeasuring()
            list.swipeUp(velocity: .fast)
            list.swipeUp(velocity: .fast)
            stopMeasuring()
            XCTAssertFalse(app.buttons["transaction.Baseline Latest"].isHittable)
        }
        capture("性能基线\(profile.rawValue)-交易滚动")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
