import XCTest
import UIKit

@MainActor
final class CoreFlowsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["CARDPILOT_UI_SESSION"] = UUID().uuidString
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-cardPilot.homeTimeZone", "Asia/Shanghai",
            "-cardPilot.appLockEnabled", "NO",
            "-cardPilot.statementRemindersEnabled", "NO",
            "-cardPilot.repaymentRemindersEnabled", "NO",
            "-cardPilot.lastUsedCardID", ""
        ]
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
        app = nil
    }

    func testCreateCardAndReopenDetails() {
        launch("empty")
        tap(app.tabBars.buttons["记一笔"])
        tap(app.buttons["bank.cn.icbc"])
        XCTAssertTrue(app.staticTexts["设置账务规则"].waitForExistence(timeout: 10))
        tap(app.buttons["onboarding.advance"])
        enter("UI Created", into: app.textFields["卡产品名称"])
        enter("2468", into: app.textFields["末四位"])
        tap(app.buttons["onboarding.advance"])
        XCTAssertTrue(app.staticTexts["卡片已保存"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["onboarding.reminders.configure"].exists)
        let finish = app.buttons["onboarding.reminders.finish"]
        XCTAssertGreaterThanOrEqual(finish.frame.width, 44)
        XCTAssertGreaterThanOrEqual(finish.frame.height, 44)
        finish.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["放弃修改"].exists)
        openCard("UI Created")
        XCTAssertTrue(app.navigationBars["卡片详情"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openCard("UI Created")
        tap(app.buttons["card.transactions"])
        XCTAssertTrue(app.staticTexts["这张卡还没有交易"].waitForExistence(timeout: 10))
    }

    func testFirstCardReminderSettingsPersistAndRemainAccessible() throws {
        // These preferences are changed through the app, so launch overrides
        // must not hide their persisted values on the subsequent launch.
        for key in ["-cardPilot.statementRemindersEnabled", "-cardPilot.repaymentRemindersEnabled"] {
            let index = try XCTUnwrap(app.launchArguments.firstIndex(of: key))
            app.launchArguments.removeSubrange(index...index + 1)
        }
        launch("empty")
        tap(app.tabBars.buttons["记一笔"])
        tap(app.buttons["bank.cn.icbc"])
        tap(app.buttons["onboarding.advance"])
        enter("UI Reminders", into: app.textFields["卡产品名称"])
        enter("1357", into: app.textFields["末四位"])
        tap(app.buttons["onboarding.advance"])
        tap(app.buttons["onboarding.reminders.configure"])
        XCTAssertTrue(app.navigationBars["通知与提醒"].waitForExistence(timeout: 10))

        let statement = app.switches["reminders.statement.enabled"]
        let repayment = app.switches["reminders.repayment.enabled"]
        if statement.value as? String == "1" { tap(statement.switches.firstMatch) }
        if repayment.value as? String == "1" { tap(repayment.switches.firstMatch) }
        XCTAssertEqual(statement.value as? String, "0")
        XCTAssertEqual(repayment.value as? String, "0")
        let disabled = app.staticTexts["reminders.disabled"]
        reveal(disabled)
        XCTAssertTrue(disabled.exists)

        // The controls are above the plan section, including when lazy rows disappear.
        tap(repayment.switches.firstMatch, scrollTowardTopWhenMissing: true)
        XCTAssertEqual(repayment.value as? String, "1")
        reveal(statement, scrollTowardTopWhenMissing: true)
        XCTAssertEqual(statement.value as? String, "0")
        tap(app.buttons["onboarding.reminders.finish"])
        XCTAssertTrue(app.buttons["card.UI Reminders"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "card.UI Reminders").count, 1)
        openCard("UI Reminders")

        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["首页"])
        tap(app.buttons["打开设置"])
        tap(app.buttons["settings.reminders"])
        XCTAssertTrue(app.navigationBars["通知与提醒"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["reminders.statement.enabled"].value as? String, "0")
        XCTAssertEqual(app.switches["reminders.repayment.enabled"].value as? String, "1")
        XCTAssertFalse(app.buttons["onboarding.reminders.configure"].exists)
    }

    func testAdditionalCardDoesNotRepeatReminderOnboarding() {
        launch("core")
        tap(app.tabBars.buttons["卡片"])
        tap(app.buttons["添加信用卡"])
        tap(app.buttons["bank.cn.icbc"])
        tap(app.buttons["onboarding.advance"])
        enter("UI Additional", into: app.textFields["卡产品名称"])
        enter("2468", into: app.textFields["末四位"])
        tap(app.buttons["onboarding.advance"])
        XCTAssertTrue(app.buttons["card.UI Additional"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding.reminders.configure"].exists)
        openCard("UI Additional")
        XCTAssertTrue(app.navigationBars["卡片详情"].waitForExistence(timeout: 10))
    }

    func testTransactionAllocationPersistsAndUpdatesPromotion() {
        launch("core")
        openCard("UI Primary")
        tap(app.buttons["card.addTransaction"])
        enter("125", into: app.textFields["transactionAmount"])
        enter("UI Coffee", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])
        let amount = app.textFields["allocation.amount.UI Spend"]
        reveal(amount)
        XCTAssertEqual(amount.value as? String, "125")
        // Confirm a bank-recognized amount different from the transaction total.
        tap(amount)
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "100")
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(app.navigationBars["卡片详情"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openCard("UI Primary")
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.UI Coffee"])
        XCTAssertTrue(app.navigationBars["交易详情"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "促销 UI Spend", "100 CNY")).firstMatch.waitForExistence(timeout: 10))
        tap(app.buttons["完成"])
        tap(app.navigationBars.buttons.element(boundBy: 0))
        let promotion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI Spend")).firstMatch
        tap(promotion)
        let progress = app.staticTexts["promotion.progress.UI Spend"]
        reveal(progress)
        XCTAssertEqual(progress.label, "100 CNY / 1,000 CNY")
    }

    func testDraftKeepsCommaDecimalMeaningAfterRegionChange() throws {
        let localeIndex = try XCTUnwrap(app.launchArguments.firstIndex(of: "-AppleLocale")) + 1
        app.launchArguments[localeIndex] = "de_DE"
        launch("core")
        openCard("UI Primary")
        tap(app.buttons["card.addTransaction"])
        enter("1,500", into: app.textFields["transactionAmount"])
        enter("UI Locale", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])
        let allocation = app.textFields["allocation.amount.UI Spend"]
        reveal(allocation)
        XCTAssertEqual(allocation.value as? String, "1,5")
        tap(allocation)
        allocation.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "1,250")
        app.terminate()

        app.launchArguments[localeIndex] = "zh_CN"
        app.launch()
        tap(app.tabBars.buttons["记一笔"])
        let summary = app.staticTexts["transactionDraftSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("1.5 CNY"))
        XCTAssertTrue(summary.label.contains("UI Locale"))
        tap(app.buttons["继续草稿"])
        let restored = app.textFields["allocation.amount.UI Spend"]
        reveal(restored)
        XCTAssertEqual(restored.value as? String, "1,250")
        tap(app.buttons["返回修改交易"])
        XCTAssertEqual(app.textFields["transactionAmount"].value as? String, "1,500")
        tap(app.buttons["saveTransaction"])
        tap(app.buttons["saveTransaction"])

        app.terminate()
        app.launch()
        openCard("UI Primary")
        tap(app.buttons["card.transactions"])
        let transaction = app.buttons["transaction.UI Locale"]
        reveal(transaction)
        XCTAssertTrue(transaction.label.contains("1.5 CNY"))
        tap(transaction)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "促销 UI Spend", "1.25 CNY")).firstMatch.waitForExistence(timeout: 10))
    }

    func testDraftRestoresManualAllocationAndSavesOnlyOnce() {
        launch("core")
        openCard("UI Primary")
        tap(app.buttons["card.addTransaction"])
        enter("125", into: app.textFields["transactionAmount"])
        enter("UI Draft", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])
        let allocation = app.textFields["allocation.amount.UI Spend"]
        reveal(allocation)
        tap(allocation)
        allocation.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "100")
        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["记一笔"])
        tap(app.buttons["继续草稿"])
        let restored = app.textFields["allocation.amount.UI Spend"]
        reveal(restored)
        XCTAssertEqual(restored.value as? String, "100")
        tap(app.buttons["返回修改交易"])
        XCTAssertEqual(app.textFields["transactionAmount"].value as? String, "125")
        XCTAssertEqual(app.textFields["商户（可选）"].value as? String, "UI Draft")
        tap(app.buttons["saveTransaction"])
        tap(app.buttons["saveTransaction"])
        app.terminate()
        app.launch()
        openCard("UI Primary")
        tap(app.buttons["card.transactions"])
        XCTAssertTrue(app.buttons["transaction.UI Draft"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "transaction.UI Draft").count, 1)
        tap(app.tabBars.buttons["记一笔"])
        XCTAssertTrue(app.textFields["transactionAmount"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["saveTransaction"].isEnabled)
        XCTAssertFalse(app.buttons["继续草稿"].exists)
    }

    func testDiscardDraftDoesNotCreateTransaction() {
        launch("core")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        enter("50", into: app.textFields["transactionAmount"])
        enter("UI Discarded", into: app.textFields["商户（可选）"])
        tap(app.buttons["关闭"])
        tap(app.buttons["保留草稿并关闭"])
        tap(app.buttons["card.addTransaction"])
        tap(app.buttons["丢弃草稿并新建"])
        XCTAssertTrue(app.textFields["transactionAmount"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["saveTransaction"].isEnabled)
        let amount = app.textFields["transactionAmount"]
        enter("75", into: amount)
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        XCTAssertFalse(app.buttons["saveTransaction"].isEnabled)
        app.terminate()
        app.launch()
        openCard("UI Shared")
        tap(app.buttons["card.transactions"])
        XCTAssertTrue(app.staticTexts["这张卡还没有交易"].waitForExistence(timeout: 10))
        tap(app.tabBars.buttons["记一笔"])
        XCTAssertTrue(app.textFields["transactionAmount"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["继续草稿"].exists)
    }

    func testDraftWithDeletedCardCanSelectReplacementAndSave() {
        launch("core")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        enter("50", into: app.textFields["transactionAmount"])
        enter("UI Replacement", into: app.textFields["商户（可选）"])
        tap(app.buttons["关闭"])
        tap(app.buttons["保留草稿并关闭"])
        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["卡片"])
        let card = app.buttons["card.UI Shared"]
        reveal(card)
        // The card row must expose card actions, without inheriting the bank header's menu.
        card.press(forDuration: 1)
        let deleteCard = app.buttons["删除卡片"]
        XCTAssertTrue(deleteCard.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["删除银行"].exists)
        deleteCard.tap()
        tap(app.buttons["永久删除"])
        tap(app.tabBars.buttons["记一笔"])
        tap(app.buttons["继续草稿"])
        XCTAssertFalse(app.buttons["saveTransaction"].isEnabled)
        tap(app.buttons["选择其他卡片"])
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI Primary")).firstMatch)
        XCTAssertEqual(app.textFields["transactionAmount"].value as? String, "50")
        XCTAssertEqual(app.textFields["商户（可选）"].value as? String, "UI Replacement")
        tap(app.buttons["saveTransaction"])
        tap(app.buttons["saveTransaction"])
        app.terminate()
        app.launch()
        openCard("UI Primary")
        tap(app.buttons["card.transactions"])
        XCTAssertTrue(app.buttons["transaction.UI Replacement"].waitForExistence(timeout: 10))
    }

    func testRepaymentAndUndoPersistAcrossSharedCards() {
        launch("core")
        openCard("UI Primary")
        let cycle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "billingCycle.")).firstMatch
        reveal(cycle)
        let cycleID = cycle.identifier
        tap(cycle)
        tap(app.buttons["标记已还"])
        XCTAssertTrue(app.buttons["撤销已还款"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openCard("UI Shared")
        tap(app.buttons["card.account"])
        tap(app.buttons[cycleID])
        tap(app.buttons["撤销已还款"])
        XCTAssertTrue(app.buttons["标记已还"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openCard("UI Primary")
        tap(app.buttons[cycleID])
        XCTAssertTrue(app.buttons["标记已还"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["撤销已还款"].exists)
    }

    func testTransactionWithoutPromotion() {
        launch("core")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        XCTAssertFalse(app.buttons["saveTransaction"].isEnabled)
        enter("50", into: app.textFields["transactionAmount"])
        enter("UI No Promotion", into: app.textFields["商户（可选）"])
        XCTAssertEqual(app.buttons["saveTransaction"].label, "保存交易")
        tap(app.buttons["saveTransaction"])
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.UI No Promotion"])
        XCTAssertTrue(app.staticTexts["本笔未计入促销"].waitForExistence(timeout: 10))
    }

    func testChangingCardPreservesEnteredAmountAndCurrencyThroughSave() {
        launch("core")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        enter("99.999", into: app.textFields["transactionAmount"])
        enter("UI Currency Protected", into: app.textFields["商户（可选）"])
        selectTransactionCard("UI Foreign")
        XCTAssertEqual(app.textFields["transactionAmount"].value as? String, "99.999")
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "CNY")
        tap(app.buttons["saveTransaction"])

        app.terminate()
        app.launch()
        openCard("UI Foreign")
        tap(app.buttons["card.transactions"])
        let transaction = app.buttons["transaction.UI Currency Protected"]
        XCTAssertTrue(transaction.waitForExistence(timeout: 10))
        XCTAssertTrue(transaction.label.contains("99.999 CNY"))
    }

    func testTransactionSaveFeedbackClosesAcrossNestedPresentations() {
        launch("core")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        enter("77", into: app.textFields["transactionAmount"])
        enter("UI Save Feedback", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])
        let feedback = app.buttons["transaction.saveFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertEqual(feedback.label, "已记录 77 CNY · 未计入活动")
        assertTouchTarget(feedback)
        feedback.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 2))

        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.UI Save Feedback"])
        tap(app.navigationBars["交易详情"].buttons["编辑"])
        let amount = app.textFields["transactionAmount"]
        tap(amount)
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "79")
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertEqual(feedback.label, "交易已更新 · 79 CNY · 未计入活动")
        captureScreenshot("嵌套编辑保存提示")
        // The presented detail and the root must both forget the confirmation.
        feedback.tap()
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 2))
        tap(app.navigationBars["交易详情"].buttons["完成"])
        XCTAssertFalse(feedback.exists)
        XCTAssertTrue(app.buttons["transaction.UI Save Feedback"].label.contains("79 CNY"))

        app.terminate()
        app.launch()
        openCard("UI Shared")
        tap(app.buttons["card.transactions"])
        XCTAssertTrue(app.buttons["transaction.UI Save Feedback"].label.contains("79 CNY"))
        XCTAssertFalse(feedback.exists)
    }

    func testTransactionSaveFeedbackExpiresAndClearsAfterBackgrounding() {
        launch("core")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        enter("9", into: app.textFields["transactionAmount"])
        tap(app.buttons["saveTransaction"])
        let feedback = app.buttons["transaction.saveFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertEqual(feedback.label, "已记录 9 CNY · 未计入活动")
        let normalHeight = feedback.frame.height
        captureScreenshot("交易保存提示")
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 12))

        tap(app.buttons["card.addTransaction"])
        enter("19", into: app.textFields["transactionAmount"])
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertEqual(feedback.label, "已记录 19 CNY · 未计入活动")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(feedback.exists)

        relaunchAtLargestTextSize()
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        enter("53", into: app.textFields["transactionAmount"])
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertEqual(feedback.label, "已记录 53 CNY · 未计入活动")
        XCTAssertGreaterThan(feedback.frame.height, normalHeight * 1.3)
        captureScreenshot("最大字号交易保存提示")
        feedback.tap()
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 2))
    }

    func testBlankTransactionFollowsCardDefaultUntilCurrencyIsExplicitlyChosen() {
        launch("core")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        selectTransactionCard("UI Foreign")
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "HKD")
        tap(app.buttons["transactionCurrency"])
        tap(app.buttons["currency.HKD"])
        selectTransactionCard("UI Shared")
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "HKD")

        tap(app.buttons["关闭"])
        tap(app.buttons["保留草稿并关闭"])
        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["记一笔"])
        tap(app.buttons["继续草稿"])
        // A recovered draft owns its currency even before any amount has been entered.
        selectTransactionCard("UI Primary")
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "HKD")
        XCTAssertFalse(app.buttons["saveTransaction"].isEnabled)
    }

    func testUntouchedTransactionClosesWithoutCreatingADraft() {
        launch("core")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        XCTAssertTrue(app.textFields["transactionAmount"].waitForExistence(timeout: 10))
        tap(app.buttons["关闭"])
        XCTAssertTrue(app.navigationBars["卡片详情"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["保留草稿并关闭"].exists)

        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["记一笔"])
        XCTAssertTrue(app.textFields["transactionAmount"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["继续草稿"].exists)
    }

    func testTransactionFilterChipsAreAccessibleAndRemoveTheirFilter() throws {
        launch("core")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        enter("12345.6789", into: app.textFields["transactionAmount"])
        enter("UI Accessibility Coffee", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(app.navigationBars["卡片详情"].waitForExistence(timeout: 10))
        tap(app.tabBars.buttons["交易"])
        let transaction = app.buttons["transaction.UI Accessibility Coffee"]
        XCTAssertTrue(transaction.waitForExistence(timeout: 10))
        XCTAssertTrue(transaction.label.contains("12,345.6789 CNY"))
        let normalAmountHeight = app.staticTexts["12,345.6789 CNY"].frame.height
        XCTAssertGreaterThan(normalAmountHeight, 0)
        let normalSearchHeight = app.searchFields["搜索交易"].frame.height
        XCTAssertGreaterThan(normalSearchHeight, 0)
        captureScreenshot("交易列表")
        try auditAccessibility(for: [.textClipped])

        relaunchAtLargestTextSize()
        tap(app.tabBars.buttons["交易"])
        reveal(transaction)
        XCTAssertGreaterThan(app.staticTexts["12,345.6789 CNY"].frame.height, normalAmountHeight * 1.3)
        XCTAssertGreaterThan(app.searchFields["搜索交易"].frame.height, normalSearchHeight * 1.3)
        captureScreenshot("最大字号交易列表")
        reveal(app.staticTexts["12,345.6789 CNY"], fullyVisible: true)
        captureScreenshot("最大字号精确金额")
        try auditAccessibility(for: [.textClipped])

        tap(app.searchFields["搜索交易"], scrollTowardTopWhenMissing: true)
        app.searchFields["搜索交易"].typeText("Coffee")
        XCTAssertEqual(app.searchFields["搜索交易"].value as? String, "Coffee")
        XCTAssertTrue(transaction.exists)
        tap(app.buttons["取消"])

        tap(app.buttons["transactions.filters"])
        tap(app.buttons["transactions.filter.kind"])
        tap(app.buttons["消费"])
        tap(app.buttons["完成"])
        let chip = app.buttons["移除筛选：消费"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        assertTouchTarget(chip)
        assertTouchTarget(app.buttons["transactions.filters.clear"])
        captureScreenshot("交易筛选标签")
        try auditAccessibility(for: [.hitRegion])
        // The text portion removes the filter too; the small cross is decorative.
        chip.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertFalse(chip.exists)
        XCTAssertFalse(app.buttons["transactions.filters.clear"].exists)
        XCTAssertTrue(app.buttons["transaction.UI Accessibility Coffee"].exists)
    }

    func testBillingSchedulesSupportAccessibleTextAndNavigationTargets() throws {
        launch("core")
        openCard("UI Primary")
        // SwiftUI also propagates the identifier to the combined header row.
        let title = app.staticTexts.matching(identifier: "card.detail.title")
            .matching(NSPredicate(format: "label == %@", "UI Primary")).element
        let normalTitleHeight = title.frame.height
        XCTAssertGreaterThan(normalTitleHeight, 0)
        let cycle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "billingCycle.")).firstMatch
        reveal(cycle)
        captureScreenshot("卡片账期日程")
        try auditAccessibility(for: [.textClipped])

        tap(app.tabBars.buttons["首页"])
        let schedule = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.billingCycle.")).firstMatch
        reveal(schedule)
        assertTouchTarget(schedule)
        captureScreenshot("首页账期日程")
        try auditAccessibility(for: [.hitRegion, .textClipped])

        relaunchAtLargestTextSize()
        openCard("UI Primary")
        XCTAssertGreaterThan(title.frame.height, normalTitleHeight * 1.3)
        reveal(cycle, fullyVisible: true)
        captureScreenshot("最大字号卡片账期日程")
        try auditAccessibility(for: [.textClipped])

        tap(app.tabBars.buttons["首页"])
        let promotion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.promotion.")).firstMatch
        reveal(promotion, fullyVisible: true)
        captureScreenshot("最大字号首页活动摘要")
        try auditAccessibility(for: [.textClipped])
        reveal(schedule, fullyVisible: true)
        assertTouchTarget(schedule)
        XCTAssertTrue(schedule.label.contains("UI Test Bank"))
        captureScreenshot("最大字号首页账期日程")
        // Audit text while the promotion is fully visible above. Repeating that
        // audit after scrolling reports the same offscreen promotion (iOS 18.5,
        // run 38074481288); check this viewport's target and navigation instead.
        try auditAccessibility(for: [.hitRegion])
        tap(schedule)
        XCTAssertTrue(app.navigationBars["账期详情"].waitForExistence(timeout: 10))
    }

    private func assertTouchTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // Accessibility bounds can contain subpixel floating-point rounding.
        XCTAssertGreaterThanOrEqual(element.frame.width + 0.001, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.001, 44, file: file, line: line)
    }

    private func relaunchAtLargestTextSize() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["卡片"].waitForExistence(timeout: 10))
    }

    private func auditAccessibility(for types: XCUIAccessibilityAuditType) throws {
        let original = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = original }
        try app.performAccessibilityAudit(for: types) { issue in
            let details = "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No associated element")"
            let attachment = XCTAttachment(string: details)
            attachment.name = "无障碍审计元素"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            // iOS 18.5 reports clipping for this native placeholder even when it
            // is fully visible at both sizes (run 38068318067). Keep the report;
            // check actual scaling, screenshots and search interaction separately.
            if issue.auditType == .textClipped,
               let element = issue.element,
               element.elementType == .searchField,
               element.label == "搜索交易" {
                return true
            }
            return false
        }
    }

    private func captureScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func selectTransactionCard(_ name: String) {
        tap(app.buttons["transactionCardPicker"], scrollTowardTopWhenMissing: true)
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch)
    }

    private func launch(_ scenario: String) {
        app.launchEnvironment["CARDPILOT_UI_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["卡片"].waitForExistence(timeout: 10))
    }

    private func openCard(_ name: String) {
        tap(app.tabBars.buttons["卡片"])
        tap(app.buttons["card.\(name)"])
    }

    private func enter(_ text: String, into element: XCUIElement) {
        tap(element)
        element.typeText(text)
    }

    private func tap(_ element: XCUIElement, scrollTowardTopWhenMissing: Bool = false) {
        reveal(element, scrollTowardTopWhenMissing: scrollTowardTopWhenMissing)
        element.tap()
    }

    private var contentBottom: CGFloat {
        var bottom = app.frame.maxY - 90
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
        for identifier in ["saveTransaction", "返回修改交易", "onboarding.advance", "onboarding.reminders.finish"] {
            let footer = app.buttons[identifier]
            if footer.exists { bottom = min(bottom, footer.frame.minY) }
        }
        return bottom
    }

    private func reveal(_ element: XCUIElement, scrollTowardTopWhenMissing: Bool = false, fullyVisible: Bool = false) {
        // SwiftUI can report a field behind the fixed footer as hittable.
        // Check its geometry as well; keep queries outside a polling predicate
        // because remote accessibility snapshots may take several seconds on CI.
        for _ in 0..<8 {
            // Lazy Form rows disappear from the accessibility tree offscreen.
            // A known first-row control must be approached from the top.
            var targetIsAbove = scrollTowardTopWhenMissing
            if element.exists || element.waitForExistence(timeout: 2) {
                if element.isHittable {
                    if fullyVisible {
                        if element.frame.minY >= app.navigationBars.firstMatch.frame.maxY,
                           element.frame.maxY < contentBottom { return }
                    } else if element.elementType != .textField || element.frame.maxY < contentBottom {
                        return
                    }
                }
                // After dismissing an editor, a previously visible row can be above
                // the viewport. Always swiping up would move it farther out of reach.
                let targetFrame = element.frame
                let contentTop = fullyVisible ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY + 110
                targetIsAbove = !targetFrame.isEmpty && targetFrame.minY < contentTop
            }
            let frame = app.frame
            let startY = min(frame.maxY - 100, contentBottom - 25)
            let endY = max(frame.minY + 160, startY - 240)
            // Use the list gutter so a drag never begins on a promotion switch.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let dragStartY = targetIsAbove ? endY : startY
            let dragEndY = targetIsAbove ? startY : endY
            origin.withOffset(CGVector(dx: frame.width * 0.03, dy: dragStartY - frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: frame.width * 0.03, dy: dragEndY - frame.minY)))
        }
        XCTFail("Expected an unobscured element: \(element)")
    }
}
