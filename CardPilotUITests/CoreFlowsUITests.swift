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

    func testPromotionSectionsSaveAndCancelWithoutRepeatingCreation() {
        launch("core")
        openPromotion("UI Spend")
        openPromotionEditor("报名与规则")
        XCTAssertFalse(app.buttons["promotion.editor.advance"].exists)
        XCTAssertTrue(app.buttons["promotion.editor.save"].isHittable)
        captureScreenshot("促销分组编辑")
        let reward = app.descendants(matching: .any).matching(identifier: "promotion.editor.reward").firstMatch
        enter("UI Rule Reward", into: reward)
        selectPromotionEditorSection("基本信息")
        replaceText("UI Edited", in: app.textFields["活动标题"])
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.navigationBars["UI Edited"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        openPromotion("UI Edited")
        openPromotionEditor("报名与规则")
        reveal(reward)
        XCTAssertEqual(reward.value as? String, "UI Rule Reward")
        replaceText("UI Cancelled Reward", in: reward)
        tap(app.navigationBars["编辑促销"].buttons["取消"])
        tap(app.buttons["放弃修改"])
        XCTAssertTrue(app.navigationBars["UI Edited"].waitForExistence(timeout: 10))
        openPromotionEditor("报名与规则")
        reveal(reward)
        XCTAssertEqual(reward.value as? String, "UI Rule Reward")
        tap(app.navigationBars["编辑促销"].buttons["取消"])
        XCTAssertFalse(app.buttons["放弃修改"].exists)
    }

    func testPromotionOptionalRulesKeepValuesAndRevealInvalidFields() {
        launch("core")
        openPromotion("UI Spend")
        openPromotionEditor("基本信息")
        let additionalAmounts = app.buttons["其他金额条件（可选）"]
        let cap = app.textFields["累计计入上限（可选）"]
        let perTransaction = app.textFields["单笔计入门槛（可选）"]
        XCTAssertFalse(cap.exists)
        tap(additionalAmounts)
        enter("0", into: cap)
        tap(additionalAmounts, scrollTowardTopWhenMissing: true)
        XCTAssertFalse(cap.exists)
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.staticTexts["错误：累计计入上限应为大于 0 的数字，或留空。"].waitForExistence(timeout: 10))
        reveal(cap)
        XCTAssertTrue(cap.isHittable)
        replaceText("5000", in: cap)
        enter("100", into: perTransaction)
        tap(additionalAmounts, scrollTowardTopWhenMissing: true)
        selectPromotionEditorSection("报名与规则")
        let ruleNotes = app.buttons["规则、排除项与备注（可选）"]
        let rules = app.descendants(matching: .any)
            .matching(identifier: "promotion.editor.rules").firstMatch
        XCTAssertFalse(rules.exists)
        tap(ruleNotes)
        enter("UI Manual Rules", into: rules)
        tap(ruleNotes, scrollTowardTopWhenMissing: true)
        XCTAssertFalse(rules.exists)
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.navigationBars["UI Spend"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        openPromotion("UI Spend")
        openPromotionEditor("基本信息")
        // Saved optional rules open automatically, even when they were
        // collapsed before Save. Their bindings never clear hidden values.
        reveal(cap)
        XCTAssertEqual(cap.value as? String, "5000")
        reveal(perTransaction)
        XCTAssertEqual(perTransaction.value as? String, "100")
        captureScreenshot("促销金额规则说明")
        selectPromotionEditorSection("报名与规则")
        reveal(rules)
        XCTAssertEqual(rules.value as? String, "UI Manual Rules")
        captureScreenshot("促销奖励与可选规则")
        tap(app.navigationBars["编辑促销"].buttons["取消"])
        XCTAssertFalse(app.buttons["放弃修改"].exists)

        relaunchAtLargestTextSize()
        openPromotion("UI Spend")
        openPromotionEditor("基本信息")
        let explanation = app.staticTexts["例如仅前 5,000 CNY 可计入：这是上限，不是必须达到的金额。"]
        reveal(explanation, fullyVisible: true)
        XCTAssertTrue(explanation.isHittable)
        XCTAssertGreaterThanOrEqual(explanation.frame.minY, app.navigationBars["编辑促销"].frame.maxY)
        XCTAssertLessThan(explanation.frame.maxY, app.frame.maxY - 40)
        captureScreenshot("最大字号促销金额规则说明")
    }

    func testPromotionCreationKeepsGuidanceAndEditingValidatesOtherSections() {
        launch("core")
        tap(app.tabBars.buttons["促销"])
        tap(app.buttons["添加促销活动"])
        XCTAssertFalse(app.buttons["promotion.editor.section"].exists)
        XCTAssertFalse(app.buttons["promotion.editor.save"].exists)
        tap(app.buttons["promotion.editor.advance"])
        XCTAssertTrue(app.staticTexts["错误：请先填写活动标题。"].exists)
        enter("UI Created Promotion", into: app.textFields["活动标题"])
        tap(app.buttons["promotion.editor.advance"])
        XCTAssertTrue(app.buttons["搜索并选择适用卡"].exists)
        tap(app.buttons["promotion.editor.advance"])
        XCTAssertFalse(app.buttons["promotion.editor.advance"].exists)
        tap(app.buttons["promotion.editor.save"])
        openPromotion("UI Created Promotion")
        openPromotionEditor("基本信息")
        replaceText("", in: app.textFields["活动标题"])
        selectPromotionEditorSection("报名与规则")
        tap(app.buttons["promotion.editor.save"])
        // Save checks fields outside the selected section and returns to the
        // section that needs correction, without mutating the stored promotion.
        XCTAssertTrue(app.staticTexts["错误：活动标题不能为空。"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["活动标题"].exists)
        captureScreenshot("促销编辑校验")
        tap(app.navigationBars["编辑促销"].buttons["取消"])
        tap(app.buttons["放弃修改"])
        app.terminate()
        app.launch()
        openPromotion("UI Created Promotion")
        XCTAssertTrue(app.navigationBars["UI Created Promotion"].exists)
    }

    func testPromotionSectionNavigationSupportsLargestTextSize() {
        launch("core")
        openPromotion("UI Spend")
        openPromotionEditor("适用范围")
        let section = app.buttons["promotion.editor.section"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))
        let normalHeight = section.frame.height
        tap(app.navigationBars["编辑促销"].buttons["取消"])

        relaunchAtLargestTextSize()
        openPromotion("UI Spend")
        openPromotionEditor("报名与规则")
        XCTAssertTrue(section.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(section.frame.height, normalHeight * 1.3)
        assertTouchTarget(section)
        captureScreenshot("最大字号促销分组编辑")
        selectPromotionEditorSection("适用范围")
        // At the largest size, this lazy Form row is below the first viewport.
        let cardPicker = app.buttons["搜索并选择适用卡"]
        reveal(cardPicker)
        XCTAssertTrue(cardPicker.isHittable)
        captureScreenshot("最大字号促销适用范围")
        selectPromotionEditorSection("基本信息")
        replaceText("UI Large Promotion", in: app.textFields["活动标题"])
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.navigationBars["UI Large Promotion"].waitForExistence(timeout: 10))
    }

    func testPromotionOverviewPrioritizesProgressAndDistinguishesLimits() throws {
        launch("promotionOverview")
        let examples = [
            ("UI Spend", "还需 1,000 CNY"),
            ("UI Reached", "已达标"),
            ("UI Amount Cap", "剩余可计入 500 CNY"),
            ("UI Available", "剩余可用 2 次"),
            ("UI Exhausted", "优惠次数已用完")
        ]
        var normalHeight: CGFloat = 0
        for (name, expected) in examples {
            openPromotion(name)
            let remaining = app.staticTexts["promotion.remaining.\(name)"]
            XCTAssertTrue(remaining.waitForExistence(timeout: 10))
            XCTAssertEqual(remaining.label, expected)
            // These assertions deliberately precede any scrolling: ordinary
            // detail pages must show the result and deadline on their first screen.
            XCTAssertTrue(remaining.isHittable)
            let endDate = app.staticTexts["promotion.endDate"]
            XCTAssertTrue(endDate.isHittable)
            XCTAssertTrue(endDate.label.contains("结束日期"))
            XCTAssertGreaterThanOrEqual(endDate.frame.minY, app.navigationBars[name].frame.maxY)
            XCTAssertLessThan(endDate.frame.maxY, app.tabBars.firstMatch.frame.minY)
            let record = app.buttons["recordPromotionTransaction"]
            XCTAssertTrue(record.exists)
            XCTAssertLessThan(remaining.frame.maxY, record.frame.minY)
            if name == "UI Spend" {
                normalHeight = remaining.frame.height
                XCTAssertTrue(app.staticTexts["达标奖励以银行规则为准"].isHittable)
                try auditAccessibility(for: [.textClipped])
            }
            if name == "UI Available" || name == "UI Exhausted" {
                XCTAssertFalse(app.staticTexts["已达标"].exists)
            }
            captureScreenshot("促销详情-\(name)")
            tap(app.navigationBars[name].buttons["促销"])
        }

        relaunchAtLargestTextSize()
        openPromotion("UI Spend")
        let remaining = app.staticTexts["promotion.remaining.UI Spend"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 10))
        XCTAssertTrue(remaining.isHittable)
        XCTAssertGreaterThan(remaining.frame.height, normalHeight * 1.3)
        captureScreenshot("最大字号促销进度")
    }

    func testPromotionLargeTextOptionsRemainReadableAndPersist() {
        launch("core")
        relaunchAtLargestTextSize()
        openPromotion("UI Spend")
        openPromotionEditor("报名与规则")
        let pending = app.descendants(matching: .any)
            .matching(identifier: "promotion.editor.enrollment.pending").firstMatch
        reveal(pending, fullyVisible: true)
        XCTAssertEqual(pending.label, "尚未报名")
        XCTAssertGreaterThanOrEqual(pending.frame.minY, app.navigationBars["编辑促销"].frame.maxY)
        captureScreenshot("最大字号报名选项")
        pending.tap()
        let basis = app.descendants(matching: .any)
            .matching(identifier: "promotion.editor.basis.unknown").firstMatch
        reveal(basis, fullyVisible: true)
        XCTAssertEqual(basis.label, "未知（交易日或入账日）")
        XCTAssertGreaterThanOrEqual(basis.frame.minY, app.navigationBars["编辑促销"].frame.maxY)
        XCTAssertLessThan(basis.frame.maxY, app.frame.maxY - 40)
        basis.tap()
        captureScreenshot("最大字号资格日期选项")
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.navigationBars["UI Spend"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        openPromotion("UI Spend")
        let status = app.descendants(matching: .any)
            .matching(identifier: "promotion.enrollmentStatus").firstMatch
        reveal(status, fullyVisible: true)
        XCTAssertTrue(status.label.contains("尚未报名"))
        let savedBasis = app.descendants(matching: .any)
            .matching(identifier: "promotion.qualificationBasis").firstMatch
        reveal(savedBasis, fullyVisible: true)
        XCTAssertTrue(savedBasis.label.contains("交易日期或入账日期"))
        captureScreenshot("最大字号报名与资格详情")
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

    func testLinkedRefundPrefillsOriginalCurrencyAndPreservesPartialRefundNavigation() {
        launch("linkedRefunds")
        openCard("UI Foreign")
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.UI Original Purchase"])
        let recordRefund = app.buttons["transaction.recordRefund"]
        reveal(recordRefund, fullyVisible: true)
        tap(recordRefund)
        let amount = app.textFields["transactionAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["saveTransaction"].isEnabled)
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "CNY")
        XCTAssertTrue(app.segmentedControls.buttons["退款"].isSelected)
        let original = app.buttons["transaction.original"]
        reveal(original)
        XCTAssertTrue((original.label + (original.value as? String ?? "")).contains("UI Original Purchase"))
        captureScreenshot("从原消费记录退款")
        enter("20", into: amount)
        enter("UI Second Refund", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])
        let allocation = app.textFields["allocation.amount.UI Spend"]
        reveal(allocation)
        XCTAssertEqual(allocation.value as? String, "20")
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(app.navigationBars["交易详情"].waitForExistence(timeout: 10))
        let related = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction.related."))
        let second = related.matching(NSPredicate(format: "label CONTAINS %@", "UI Second Refund")).firstMatch
        reveal(second, fullyVisible: true)
        XCTAssertTrue(second.label.contains("−20 CNY"))
        assertTouchTarget(second)
        captureScreenshot("原消费关联退款")
        tap(second)
        XCTAssertTrue(app.staticTexts["UI Second Refund"].waitForExistence(timeout: 10))
        let originalLink = related.matching(NSPredicate(format: "label CONTAINS %@", "UI Original Purchase")).firstMatch
        tap(originalLink)
        XCTAssertTrue(app.staticTexts["UI Original Purchase"].waitForExistence(timeout: 10))
        // Each related detail belongs to the same native navigation stack.
        tap(app.navigationBars["交易详情"].buttons.firstMatch)
        XCTAssertTrue(app.staticTexts["UI Second Refund"].waitForExistence(timeout: 10))
        tap(app.navigationBars["交易详情"].buttons.firstMatch)
        app.terminate()
        app.launch()
        openCard("UI Foreign")
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.UI Original Purchase"])
        XCTAssertTrue(app.staticTexts["100 CNY"].waitForExistence(timeout: 10))
        for (merchant, amountText) in [("UI Earlier Refund", "−40 CNY"), ("UI Second Refund", "−20 CNY")] {
            let row = related.matching(NSPredicate(format: "label CONTAINS %@", merchant)).firstMatch
            reveal(row)
            XCTAssertTrue(row.label.contains(amountText))
        }
    }

    func testLinkedRefundExcessAmountsRequireConfirmationAndRetainOriginal() {
        launch("linkedRefunds")
        openCard("UI Foreign")
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.UI Original Purchase"])
        let recordRefund = app.buttons["transaction.recordRefund"]
        reveal(recordRefund, fullyVisible: true)
        tap(recordRefund)
        enter("70", into: app.textFields["transactionAmount"])
        enter("UI Excess Refund", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])
        let allocation = app.textFields["allocation.amount.UI Spend"]
        reveal(allocation)
        XCTAssertEqual(allocation.value as? String, "60")
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(app.alerts["退款超出可退范围"].waitForExistence(timeout: 10))
        captureScreenshot("累计退款超额确认")
        tap(app.alerts.buttons["取消"])
        XCTAssertTrue(app.buttons["saveTransaction"].exists)
        tap(app.buttons["saveTransaction"])
        tap(app.alerts.buttons["仍然保存"])
        app.terminate()
        app.launch()
        openCard("UI Foreign")
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.UI Original Purchase"])
        XCTAssertTrue(app.staticTexts["100 CNY"].waitForExistence(timeout: 10))
        let excess = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "transaction.related.", "UI Excess Refund")).firstMatch
        reveal(excess)
        XCTAssertTrue(excess.label.contains("−70 CNY"))
        tap(excess)
        let savedAllocation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "促销 UI Spend", "60 CNY")).firstMatch
        reveal(savedAllocation)
        XCTAssertTrue(savedAllocation.exists)
    }

    func testRefundEntryPreservesUnrelatedDraftAndStartsOnlyAfterDiscard() {
        launch("linkedRefunds")
        openCard("UI Shared")
        tap(app.buttons["card.addTransaction"])
        enter("17", into: app.textFields["transactionAmount"])
        enter("UI Unrelated Draft", into: app.textFields["商户（可选）"])
        tap(app.buttons["关闭"])
        tap(app.buttons["保留草稿并关闭"])
        tap(app.navigationBars["卡片详情"].buttons.firstMatch)
        openCard("UI Foreign")
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.UI Original Purchase"])
        let recordRefund = app.buttons["transaction.recordRefund"]
        reveal(recordRefund, fullyVisible: true)
        tap(recordRefund)
        XCTAssertTrue(app.staticTexts["transactionDraftSummary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["transactionDraftSummary"].label.contains("UI Unrelated Draft"))
        tap(app.buttons["继续草稿"])
        XCTAssertEqual(app.textFields["transactionAmount"].value as? String, "17")
        XCTAssertTrue(app.segmentedControls.buttons["消费"].isSelected)
        XCTAssertFalse(app.buttons["transaction.original"].exists)
        tap(app.buttons["关闭"])
        tap(app.buttons["保留草稿并关闭"])
        tap(recordRefund)
        tap(app.buttons["丢弃草稿并新建"])
        XCTAssertFalse(app.buttons["saveTransaction"].isEnabled)
        XCTAssertTrue(app.segmentedControls.buttons["退款"].isSelected)
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "CNY")
        selectTransactionCard("UI Primary")
        selectTransactionCard("UI Foreign")
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "CNY")
        tap(app.buttons["关闭"])
        tap(app.buttons["丢弃草稿"])
        tap(recordRefund)
        XCTAssertTrue(app.textFields["transactionAmount"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["继续草稿"].exists)
        tap(app.buttons["关闭"])
        XCTAssertFalse(app.buttons["保留草稿并关闭"].exists)
        XCTAssertTrue(app.navigationBars["交易详情"].waitForExistence(timeout: 10))
    }

    func testReversedPurchaseRefundAndRelatedNavigationAtLargestTextSize() throws {
        launch("linkedRefunds")
        relaunchAtLargestTextSize()
        openCard("UI Shared")
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.UI Unlinked Refund"])
        reveal(app.staticTexts["未关联原消费"])
        XCTAssertFalse(app.buttons["transaction.recordRefund"].exists)
        tap(app.navigationBars["交易详情"].buttons["完成"])
        tap(app.buttons["transaction.UI Reversed Purchase"])
        let recordRefund = app.buttons["transaction.recordRefund"]
        reveal(recordRefund, fullyVisible: true)
        assertTouchTarget(recordRefund)
        captureScreenshot("最大字号原消费退款入口")
        tap(recordRefund)
        XCTAssertTrue(app.segmentedControls.buttons["退款"].isSelected)
        let original = app.buttons["transaction.original"]
        reveal(original, fullyVisible: true)
        XCTAssertTrue((original.label + (original.value as? String ?? "")).contains("UI Reversed Purchase"))
        let reversedMessage = app.staticTexts["原消费已冲正；退款仍是独立记录，请按银行记录确认退款及促销分配。"]
        reveal(reversedMessage, fullyVisible: true)
        captureScreenshot("最大字号已冲正原消费退款说明")
        enter("10", into: app.textFields["transactionAmount"])
        enter("UI Reversed Original Refund", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])
        let feedback = app.buttons["transaction.saveFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertTrue(feedback.label.contains("已记录退款 10 CNY"))
        tap(feedback)
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 5))
        let related = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction.related.")).firstMatch
        reveal(related, fullyVisible: true)
        assertTouchTarget(related)
        XCTAssertTrue(related.label.contains("UI Reversed Original Refund"))
        XCTAssertTrue(related.label.contains("状态：有效"))
        captureScreenshot("最大字号关联退款")
        try auditAccessibility(for: [.hitRegion])
        tap(related)
        XCTAssertTrue(app.staticTexts["UI Reversed Original Refund"].waitForExistence(timeout: 10))
        tap(app.navigationBars["交易详情"].buttons.firstMatch)
        XCTAssertTrue(app.staticTexts["UI Reversed Purchase"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["已冲正"].exists)
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
        let confirmation = app.descendants(matching: .any).matching(identifier: "transaction.saveFeedback").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        XCTAssertEqual(confirmation.elementType, .button)
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
        XCTAssertEqual(app.buttons.matching(identifier: "transaction.saveFeedback").count, 1)
        XCTAssertGreaterThanOrEqual(app.navigationBars["交易详情"].frame.minY, feedback.frame.maxY)
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
        XCTAssertGreaterThanOrEqual(app.navigationBars["卡片详情"].frame.minY, feedback.frame.maxY)
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
        XCTAssertGreaterThanOrEqual(app.navigationBars["卡片详情"].frame.minY, feedback.frame.maxY)
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

    func testDashboardMetricsOpenMatchingActionsAndPreserveRepaymentUndo() throws {
        launch("dashboardActions")
        tap(app.tabBars.buttons["首页"])
        let overdue = app.buttons["dashboard.actions.overdue"]
        let today = app.buttons["dashboard.actions.today"]
        let upcoming = app.buttons["dashboard.actions.nextSevenDays"]
        let billing = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.action.billingCycle."))
        let enrollment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.enrollment."))
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertEqual(overdue.label, "逾期，1 项待办")
        XCTAssertEqual(today.label, "今天，2 项待办")
        XCTAssertEqual(upcoming.label, "未来 7 天，2 项待办")
        assertTouchTarget(today)
        captureScreenshot("二十张卡首页待办概览")

        reveal(today, fullyVisible: true)
        today.tap()
        XCTAssertTrue(app.staticTexts["今天待办"].waitForExistence(timeout: 10))
        XCTAssertEqual(billing.count, 1)
        XCTAssertTrue(billing.firstMatch.label.contains("UI Today"))
        XCTAssertEqual(enrollment.count, 1)
        XCTAssertTrue(enrollment.firstMatch.label.contains("UI Spend"))
        captureScreenshot("首页今日待办")
        tap(billing.firstMatch)
        XCTAssertTrue(app.navigationBars["账期详情"].waitForExistence(timeout: 10))
        tap(app.navigationBars["账期详情"].buttons.firstMatch)
        XCTAssertTrue(app.staticTexts["今天待办"].waitForExistence(timeout: 10))

        reveal(upcoming, scrollTowardTopWhenMissing: true, fullyVisible: true)
        upcoming.tap()
        XCTAssertTrue(app.staticTexts["未来 7 天待办"].waitForExistence(timeout: 10))
        XCTAssertEqual(billing.count, 1)
        XCTAssertTrue(billing.firstMatch.label.contains("UI Next Week"))
        XCTAssertEqual(enrollment.count, 1)
        XCTAssertTrue(enrollment.firstMatch.label.contains("UI Upcoming Enrollment"))
        tap(enrollment.firstMatch)
        XCTAssertTrue(app.navigationBars["UI Upcoming Enrollment"].waitForExistence(timeout: 10))
        tap(app.navigationBars["UI Upcoming Enrollment"].buttons.firstMatch)

        reveal(overdue, scrollTowardTopWhenMissing: true, fullyVisible: true)
        overdue.tap()
        XCTAssertTrue(app.staticTexts["逾期待办"].waitForExistence(timeout: 10))
        XCTAssertEqual(billing.count, 1)
        XCTAssertTrue(billing.firstMatch.label.contains("UI Primary"))
        XCTAssertEqual(enrollment.count, 0)
        let repay = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.action.repay.")).firstMatch
        tap(repay)
        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["没有逾期待办"].exists)
        tap(app.buttons["撤销"])
        XCTAssertEqual(billing.count, 1)
        let clear = app.buttons["dashboard.actions.clear"]
        assertTouchTarget(clear)
        tap(clear)
        XCTAssertTrue(app.staticTexts["待处理"].waitForExistence(timeout: 10))
        XCTAssertEqual(billing.count, 3)
        XCTAssertEqual(enrollment.count, 2)

        relaunchAtLargestTextSize()
        tap(app.tabBars.buttons["首页"])
        reveal(today, scrollTowardTopWhenMissing: true, fullyVisible: true)
        assertTouchTarget(today)
        assertTouchTarget(upcoming)
        captureScreenshot("最大字号首页待办入口")
        tap(today)
        reveal(clear, fullyVisible: true)
        assertTouchTarget(clear)
        XCTAssertEqual(billing.count, 1)
        XCTAssertEqual(enrollment.count, 1)
        captureScreenshot("最大字号首页今日待办")
        try auditAccessibility(for: [.hitRegion])
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

    private func openPromotion(_ name: String) {
        tap(app.tabBars.buttons["促销"])
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch)
    }

    private func openPromotionEditor(_ section: String) {
        XCTAssertTrue(app.buttons["promotion.edit"].waitForExistence(timeout: 10))
        assertTouchTarget(app.buttons["promotion.edit"])
        tap(app.buttons["promotion.edit"])
        tap(app.buttons["编辑\(section)"])
        XCTAssertTrue(app.navigationBars["编辑促销"].waitForExistence(timeout: 10))
    }

    private func selectPromotionEditorSection(_ section: String) {
        tap(app.buttons["promotion.editor.section"], scrollTowardTopWhenMissing: true)
        tap(app.buttons[section])
    }

    private func replaceText(_ text: String, in element: XCUIElement) {
        tap(element)
        let oldValue = element.value as? String ?? ""
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + text)
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
        // A presented detail has no tab bar. Keep a conservative home-indicator
        // margin there; use the actual visible tab bar on the main pages.
        var bottom = app.frame.maxY - 40
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists && tabBar.isHittable { bottom = min(bottom, tabBar.frame.minY) }
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
            var scrollDistance: CGFloat = 240
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
                if !targetFrame.isEmpty && (fullyVisible || element.elementType == .textField) {
                    let obscuredDistance = targetIsAbove
                        ? contentTop - targetFrame.minY
                        : targetFrame.maxY - contentBottom
                    // Large fields can straddle the footer. A fixed drag would
                    // overshoot them and alternate above and below the viewport.
                    scrollDistance = min(240, max(60, obscuredDistance + 24))
                }
            }
            let frame = app.frame
            let startY = min(frame.maxY - 100, contentBottom - 25)
            let endY = max(frame.minY + 160, startY - scrollDistance)
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
