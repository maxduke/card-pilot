#if PERFORMANCE_TESTING && targetEnvironment(simulator)
#if DEBUG
#error("Performance measurements require the Release configuration without DEBUG")
#endif
import XCTest
import UIKit

@MainActor
final class TransactionWritingPerformanceUITests: XCTestCase {
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

    private var app: XCUIApplication!
    private let amountText = "123456.78"
    private let displayedAmount = "123,456.78 CNY"
    private let merchantText = "Performance merchant 0123456789"

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Ten measured samples and XCTest's warm-up, including unmeasured form
        // setup and recovery assertions. Existing read benchmarks stay at 600s.
        executionTimeAllowance = 1_200
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-cardPilot.homeTimeZone", "Asia/Shanghai",
            "-cardPilot.appLockEnabled", "NO",
            "-cardPilot.statementRemindersEnabled", "NO",
            "-cardPilot.repaymentRemindersEnabled", "NO",
            "-cardPilot.lastUsedCardID", "CA190000-0000-0000-0005-000000000000"
        ]
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            capture("交易写入性能失败")
            attach(app.debugDescription, named: "failure-hierarchy")
        }
        app.terminate()
        app = nil
    }

    func testSmallAmountInput() { measureAmountInput(.small) }
    func testMediumAmountInput() { measureAmountInput(.medium) }
    func testLargeAmountInput() { measureAmountInput(.large) }
    func testSmallMerchantInput() { measureMerchantInput(.small) }
    func testMediumMerchantInput() { measureMerchantInput(.medium) }
    func testLargeMerchantInput() { measureMerchantInput(.large) }
    func testSmallDraftClose() { measureDraftClose(.small) }
    func testMediumDraftClose() { measureDraftClose(.medium) }
    func testLargeDraftClose() { measureDraftClose(.large) }
    func testSmallTransactionSave() { measureTransactionSave(.small) }
    func testMediumTransactionSave() { measureTransactionSave(.medium) }
    func testLargeTransactionSave() { measureTransactionSave(.large) }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        return options
    }

    private func metrics(signpost: String) -> [XCTMetric] {
        [
            XCTClockMetric(),
            XCTMemoryMetric(application: app),
            XCTOSSignpostMetric(
                subsystem: "com.maxduke.CardPilot.performance",
                category: "Transaction", name: signpost
            )
        ]
    }

    private func prepare(_ profile: Profile) {
        let session = UUID().uuidString
        app.launchEnvironment["CARDPILOT_UI_SESSION"] = session
        app.launchEnvironment["CARDPILOT_UI_SCENARIO"] = profile.scenario
        app.launch()
        assertHome()
        openTransactions(expectedCount: profile.rawValue)
        XCTAssertTrue(app.buttons["transaction.Baseline Latest"].waitForExistence(timeout: 30))
        app.tabBars.buttons["首页"].tap()
        assertHome()
        attach("""
            session=\(session)
            scenario=\(profile.scenario)
            initialTransactions=\(profile.rawValue)
            samples=10 (XCTest warm-up excluded)
            locale=zh_CN; homeTimeZone=Asia/Shanghai; textSize=large
            clockIncludes=UI automation and readiness/value assertions
            DraftSave=validation, JSON encoding, size check, atomic protected write
            TransactionCommit=TransactionEditActions.save including validation, relationships and context persistence
            savePopulation=initialTransactions plus one transaction per invocation, including warm-up
            setupCompletedAt=\(ISO8601DateFormatter().string(from: .now))
            """, named: "writing-performance-session")
    }

    private func assertHome() {
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
        XCTAssertTrue(app.navigationBars["CardPilot"].waitForExistence(timeout: 30))
    }

    private func openEditor(discarding draftMerchant: String? = nil) {
        app.tabBars.buttons["记一笔"].tap()
        if let draftMerchant {
            assertDraftSummary(merchant: draftMerchant)
            app.buttons["丢弃草稿并新建"].tap()
        }
        XCTAssertTrue(app.textFields["transactionAmount"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["继续草稿"].exists)
        reveal(app.buttons["transactionCardPicker"])
        XCTAssertTrue(app.buttons["transactionCardPicker"].label.contains("Baseline Card 00"))
    }

    private func fill(merchant: String) {
        let amount = app.textFields["transactionAmount"]
        reveal(amount)
        amount.tap()
        amount.typeText(amountText)
        XCTAssertEqual(amount.value as? String, amountText)
        dismissNumericKeyboard()
        let field = app.textFields["商户（可选）"]
        reveal(field)
        field.tap()
        field.typeText(merchant)
        XCTAssertEqual(field.value as? String, merchant)
    }

    private func dismissNumericKeyboard() {
        let dismissal = app.buttons["transaction.keyboard.dismiss"]
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
    }

    private func discardEditor() {
        app.navigationBars["添加交易"].buttons["关闭"].tap()
        let discard = app.buttons["丢弃草稿"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        discard.tap()
        XCTAssertTrue(app.navigationBars["添加交易"].waitForNonExistence(timeout: 30))
    }

    private func assertDraftSummary(merchant: String) {
        let summary = app.staticTexts["transactionDraftSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        XCTAssertTrue(summary.label.contains(merchant))
        XCTAssertTrue(summary.label.contains(displayedAmount))
        XCTAssertTrue(summary.label.contains("Baseline Card 00"))
    }

    private func assertRestoredFields(merchant: String) {
        app.buttons["继续草稿"].tap()
        let card = app.buttons["transactionCardPicker"]
        reveal(card)
        XCTAssertTrue(card.label.contains("Baseline Card 00"))
        let amount = app.textFields["transactionAmount"]
        reveal(amount)
        XCTAssertEqual(amount.value as? String, amountText)
        if app.keyboards.firstMatch.exists { dismissNumericKeyboard() }
        let field = app.textFields["商户（可选）"]
        reveal(field)
        XCTAssertEqual(field.value as? String, merchant)
    }

    private func measureAmountInput(_ profile: Profile) {
        prepare(profile)
        var invocations = 0
        measure(metrics: metrics(signpost: "DraftSave"), options: options) {
            if invocations > 0 { discardEditor() }
            openEditor()
            let amount = app.textFields["transactionAmount"]
            reveal(amount)
            amount.tap()
            startMeasuring()
            amount.typeText(amountText)
            XCTAssertEqual(amount.value as? String, amountText)
            stopMeasuring()
            invocations += 1
        }
        capture("交易写入\(profile.rawValue)-快速金额输入")
        attach("invocations=\(invocations); committedTransactions=0", named: "writing-invocations")
        discardEditor()
    }

    private func measureMerchantInput(_ profile: Profile) {
        prepare(profile)
        var invocations = 0
        measure(metrics: metrics(signpost: "DraftSave"), options: options) {
            if invocations > 0 { discardEditor() }
            openEditor()
            let amount = app.textFields["transactionAmount"]
            reveal(amount)
            amount.tap()
            amount.typeText(amountText)
            dismissNumericKeyboard()
            let merchant = app.textFields["商户（可选）"]
            reveal(merchant)
            merchant.tap()
            startMeasuring()
            merchant.typeText(merchantText)
            XCTAssertEqual(merchant.value as? String, merchantText)
            stopMeasuring()
            invocations += 1
        }
        capture("交易写入\(profile.rawValue)-快速商户输入")
        // Exercise the existing scene-phase flush while the editor is still open.
        XCUIDevice.shared.press(.home)
        let stateAfterHome = app.state
        let backgrounded = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let state = self.app.state
                return state == .runningBackground || state == .runningBackgroundSuspended
            }, object: app
        )
        let backgroundResult = XCTWaiter.wait(for: [backgrounded], timeout: 10)
        attach("""
            stateAfterHome=\(stateAfterHome.rawValue)
            stateAfterWait=\(app.state.rawValue)
            springboardState=\(XCUIApplication(bundleIdentifier: "com.apple.springboard").state.rawValue)
            backgroundWait=\(backgroundResult.rawValue)
            """, named: "writing-background-state")
        capture("交易写入\(profile.rawValue)-后台状态确认")
        XCTAssertEqual(backgroundResult, .completed)
        app.terminate()
        app.launch()
        assertHome()
        app.tabBars.buttons["记一笔"].tap()
        assertDraftSummary(merchant: merchantText)
        assertRestoredFields(merchant: merchantText)
        capture("交易写入\(profile.rawValue)-后台重启恢复输入")
        attach("invocations=\(invocations); committedTransactions=0", named: "writing-invocations")
        discardEditor()
    }

    private func measureDraftClose(_ profile: Profile) {
        prepare(profile)
        var invocations = 0
        measure(metrics: metrics(signpost: "DraftSave"), options: options) {
            openEditor(discarding: invocations > 0 ? merchantText : nil)
            fill(merchant: merchantText)
            app.navigationBars["添加交易"].buttons["关闭"].tap()
            let keep = app.buttons["保留草稿并关闭"]
            XCTAssertTrue(keep.waitForExistence(timeout: 10))
            startMeasuring()
            keep.tap()
            XCTAssertTrue(app.navigationBars["添加交易"].waitForNonExistence(timeout: 30))
            stopMeasuring()
            invocations += 1
        }
        app.terminate()
        app.launch()
        assertHome()
        app.tabBars.buttons["记一笔"].tap()
        assertDraftSummary(merchant: merchantText)
        capture("交易写入\(profile.rawValue)-保留草稿重启概要")
        assertRestoredFields(merchant: merchantText)
        capture("交易写入\(profile.rawValue)-保留草稿重启字段")
        attach("invocations=\(invocations); committedTransactions=0", named: "writing-invocations")
        discardEditor()
    }

    private func measureTransactionSave(_ profile: Profile) {
        prepare(profile)
        var invocations = 0
        var lastMerchant = ""
        measure(metrics: metrics(signpost: "TransactionCommit"), options: options) {
            openEditor()
            lastMerchant = "Performance saved \(invocations)"
            fill(merchant: lastMerchant)
            let save = app.buttons["saveTransaction"]
            XCTAssertEqual(save.label, "继续确认促销")
            save.tap()
            XCTAssertTrue(app.buttons["返回修改交易"].waitForExistence(timeout: 30))
            XCTAssertEqual(save.label, "确认并保存")
            startMeasuring()
            save.tap()
            XCTAssertTrue(app.navigationBars["添加交易"].waitForNonExistence(timeout: 30))
            stopMeasuring()
            invocations += 1
        }
        openTransactions(expectedCount: profile.rawValue + invocations)
        findSavedTransaction(merchant: lastMerchant)
        capture("交易写入\(profile.rawValue)-保存交易读回")
        app.terminate()
        app.launch()
        assertHome()
        openTransactions(expectedCount: profile.rawValue + invocations)
        findSavedTransaction(merchant: lastMerchant)
        capture("交易写入\(profile.rawValue)-重启后唯一保存交易")
        attach("""
            invocations=\(invocations)
            committedTransactions=\(invocations)
            finalTransactions=\(profile.rawValue + invocations)
            lastMerchant=\(lastMerchant)
            """, named: "writing-invocations")
    }

    private func openTransactions(expectedCount: Int) {
        app.tabBars.buttons["交易"].tap()
        XCTAssertTrue(app.navigationBars["交易"].waitForExistence(timeout: 30))
        assertResultCount(expectedCount)
    }

    private func assertResultCount(_ expectedCount: Int) {
        let result = app.staticTexts["transactions.results.count"]
        let count = expectedCount.formatted(.number.locale(Locale(identifier: "zh_CN")))
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "共 \(count) 笔交易"), object: result
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
    }

    private func findSavedTransaction(merchant: String) {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText(merchant + "\n")
        assertResultCount(1)
        let row = app.buttons["transaction.\(merchant)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons.matching(identifier: "transaction.\(merchant)").count, 1)
        XCTAssertTrue(row.label.contains(displayedAmount))
        XCTAssertTrue(row.label.contains("Baseline Card 00"))
        XCTAssertTrue(row.label.contains("已计入 2 个促销"))
    }

    private func reveal(_ element: XCUIElement) {
        let form = app.descendants(matching: .any).matching(identifier: "transaction.form").firstMatch
        let navigation = app.navigationBars["添加交易"]
        let header = app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 30))
        for _ in 0..<6 {
            let top = max(navigation.frame.maxY, header.exists ? header.frame.maxY : 0)
            var bottom = min(form.frame.maxY, app.buttons["saveTransaction"].frame.minY - 11)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
            XCTAssertGreaterThanOrEqual(bottom - top, 88, "Expected usable form space for a native scroll")
            if element.exists {
                let frame = element.frame
                if !frame.isEmpty && frame.minY + 0.001 >= top && frame.maxY < bottom && element.isHittable {
                    return
                }
                if !frame.isEmpty && frame.minY < top {
                    let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: form.frame.midX, dy: top + 40))
                    let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: form.frame.midX, dy: bottom - 40))
                    start.press(forDuration: 0.05, thenDragTo: end)
                    continue
                }
            }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: form.frame.midX, dy: bottom - 40))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: form.frame.midX, dy: top + 40))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Expected an unobscured transaction input: \(element.identifier)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
