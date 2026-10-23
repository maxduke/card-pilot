import XCTest
import UIKit

@MainActor
final class CoreFlowsUITests: XCTestCase {
    private var app: XCUIApplication!
    private let allocationFeedbackFirstTitle = "星河信用卡境内外旅行住宿与日常消费累计达标返现活动"

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

    func testAccountBillingDateWheelsAtLargestTextSizeSaveAndPreserveRepayment() throws {
        // The two native selection pages and restart readback are one flow.
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        try verifyAccessibleBillingDateSave(accountEditor: true)
    }

    func testBillingCycleDateWheelsAtLargestTextSizeSaveAndPreserveRepayment() throws {
        // The complete navigation flow reached 175s in run 39537321815.
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        try verifyAccessibleBillingDateSave(accountEditor: false)
    }

    func testBillingMonthSelectionAtLargestTextSizePreservesCycleOverridesOnDiscard() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("billingDateFeedback")
        openBillingFeedbackAccount()
        tap(app.navigationBars["账户详情"].buttons["编辑"])
        let navigationBar = app.navigationBars["编辑信用卡账户"]
        let form = app.collectionViews["account.editor.form"]
        let picker = app.buttons["account.editor.override.cycle"]
        let currentMonth = futureRuleMonth(offset: 0)
        let nextMonth = futureRuleMonth(offset: 1)
        reveal(picker, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        XCTAssertEqual(picker.value as? String, currentMonth)
        captureScreenshot("最大字号所选账期完整月份")
        picker.tap()
        let monthNavigation = app.navigationBars["账期"]
        XCTAssertTrue(monthNavigation.waitForExistence(timeout: 10))
        let selected = app.buttons[currentMonth]
        // The long month list must open at the selection, without a test drag.
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertTrue(selected.isSelected)
        XCTAssertTrue(selected.isHittable)
        XCTAssertGreaterThanOrEqual(selected.frame.minY + 0.001, monthNavigation.frame.maxY)
        XCTAssertLessThanOrEqual(selected.frame.maxY, contentBottom)
        captureScreenshot("最大字号账期列表定位已选月份")
        let next = app.buttons[nextMonth]
        reveal(next, fullyVisible: true, navigationBar: monthNavigation)
        next.tap()
        XCTAssertTrue(monthNavigation.waitForNonExistence(timeout: 10))
        XCTAssertEqual(picker.value as? String, nextMonth)
        let statement = app.switches["account.editor.override.statement.enabled"]
        reveal(statement, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        XCTAssertEqual(statement.value as? String, "0")
        reveal(picker, scrollTowardTopWhenMissing: true, fullyVisible: true,
               navigationBar: navigationBar, contentContainer: form)
        picker.tap()
        XCTAssertTrue(monthNavigation.waitForExistence(timeout: 10))
        let previous = app.buttons[currentMonth]
        reveal(previous, scrollTowardTopWhenMissing: true, fullyVisible: true, navigationBar: monthNavigation)
        previous.tap()
        XCTAssertTrue(monthNavigation.waitForNonExistence(timeout: 10))
        XCTAssertEqual(picker.value as? String, currentMonth)
        reveal(statement, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        XCTAssertEqual(statement.value as? String, "1")
        captureScreenshot("最大字号切回账期保留日期覆盖")
        setBillingDateToggle("account.editor.override.repayment.enabled", enabled: false)
        navigationBar.buttons["取消"].tap()
        tap(app.buttons["放弃修改"])
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        openBillingFeedbackAccount()
        openBillingFeedbackCycle(offset: 0)
        assertBillingFeedbackDate("账单日", monthOffset: 0, day: 5)
        assertBillingFeedbackDate("还款日", monthOffset: 0, day: 15)
        let paid = app.staticTexts["状态、已还款"]
        reveal(paid, fullyVisible: true)
        XCTAssertTrue(paid.exists)
        captureScreenshot("最大字号账期选择放弃后读回")
    }

    func testBillingRulePickersAtLargestTextSizeSaveEffectiveMonth() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("billingDateFeedback")
        openBillingFeedbackAccount()
        tap(app.navigationBars["账户详情"].buttons["编辑"])
        let navigationBar = app.navigationBars["编辑信用卡账户"]
        let form = app.collectionViews["account.editor.form"]
        let dayPicker = app.buttons["account.editor.rule.statementDay"]
        reveal(dayPicker, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        dayPicker.tap()
        let dayNavigation = app.navigationBars["账单日"]
        XCTAssertTrue(dayNavigation.waitForExistence(timeout: 10))
        let day = app.buttons["每月 21 日"]
        reveal(day, fullyVisible: true, navigationBar: dayNavigation)
        assertTouchTarget(day)
        captureScreenshot("最大字号账单日完整选项")
        day.tap()
        if dayNavigation.exists { dayNavigation.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        XCTAssertEqual(dayPicker.value as? String, "每月 21 日")
        let effective = app.buttons["account.editor.rule.effectiveCycle"]
        reveal(effective, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        effective.tap()
        let monthNavigation = app.navigationBars["新规则生效账期"]
        XCTAssertTrue(monthNavigation.waitForExistence(timeout: 10))
        let initial = app.buttons[futureRuleMonth(offset: 1)]
        XCTAssertTrue(initial.waitForExistence(timeout: 10))
        XCTAssertTrue(initial.isSelected)
        XCTAssertTrue(initial.isHittable)
        captureScreenshot("最大字号生效月份完整选项")
        let chosenMonth = futureRuleMonth(offset: 2)
        let chosen = app.buttons[chosenMonth]
        reveal(chosen, fullyVisible: true, navigationBar: monthNavigation)
        chosen.tap()
        XCTAssertTrue(monthNavigation.waitForNonExistence(timeout: 10))
        reveal(effective, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        XCTAssertEqual(effective.value as? String, chosenMonth)
        captureScreenshot("最大字号规则生效月份修改")
        navigationBar.buttons["保存"].tap()
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        openBillingFeedbackAccount()
        let rule = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "account.rule.", chosenMonth
        ))
        let saved = rule.firstMatch
        reveal(saved, fullyVisible: true)
        XCTAssertEqual(rule.count, 1)
        XCTAssertTrue(saved.label.contains("每月 21 日出账"))
        captureScreenshot("最大字号规则生效月份保存读回")
        openBillingFeedbackCycle(offset: 0, scrollTowardTopWhenMissing: true)
        assertBillingFeedbackDate("账单日", monthOffset: 0, day: 5)
        assertBillingFeedbackDate("还款日", monthOffset: 0, day: 15)
        let paid = app.staticTexts["状态、已还款"]
        reveal(paid, fullyVisible: true)
        XCTAssertTrue(paid.exists)
    }

    func testAccountDateOverridesShowLocalErrorAndPreserveRepaymentOnSave() {
        verifyBillingDateFeedback(accountEditor: true, largestText: false)
    }

    func testAccountDateOverrideFeedbackAtLargestTextSizeAndDiscard() {
        // The complete correction/discard/restart flow took 179.973s in
        // run 39557142503. Keep it within the existing per-test maximum.
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyBillingDateFeedback(accountEditor: true, largestText: true)
    }

    func testBillingCycleDateFeedbackCorrectsAndPreservesSavedRepayment() {
        verifyBillingDateFeedback(accountEditor: false, largestText: false)
    }

    func testBillingCycleDateFeedbackAtLargestTextSizeAndDiscard() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyBillingDateFeedback(accountEditor: false, largestText: true)
    }

    func testFutureRuleConflictNamesAffectedCycleAndCorrectsWithinAccountEditor() {
        launch("futureRules")
        openCard("UI Foreign")
        tap(app.buttons["card.account"])
        let firstMonth = futureRuleMonth(offset: 1)
        let conflictMonth = futureRuleMonth(offset: 2)
        let laterMonth = futureRuleMonth(offset: 3)
        let first = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "account.rule.", firstMonth
        )).firstMatch
        tap(first)
        tap(app.buttons["account.rule.edit"])
        tap(app.buttons["account.editor.rule.statementDay"], scrollTowardTopWhenMissing: true)
        // The native menu initially shows days1–17. Drag within its visible
        // options; the generic Form-gutter drag would dismiss this popup.
        let menuStart = app.buttons["每月 16 日"]
        let menuEnd = app.buttons["每月 5 日"]
        XCTAssertTrue(menuStart.waitForExistence(timeout: 10))
        XCTAssertTrue(menuStart.isHittable)
        XCTAssertTrue(menuEnd.isHittable)
        let start = menuStart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = menuEnd.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        let selectedDay = app.buttons["每月 20 日"]
        XCTAssertTrue(selectedDay.waitForExistence(timeout: 10))
        XCTAssertTrue(selectedDay.isHittable)
        selectedDay.tap()
        let navigationBar = app.navigationBars["编辑信用卡账户"]
        let form = app.collectionViews["account.editor.form"]
        let ruleError = app.staticTexts["account.effectiveCycle.error"]
        XCTAssertFalse(ruleError.exists)
        navigationBar.buttons["保存"].tap()
        assertEditorFieldErrorVisible(app.buttons["account.editor.rule.effectiveCycle"], error: ruleError,
                                      navigationBar: navigationBar, form: form)
        XCTAssertEqual(ruleError.label, "错误：\(conflictMonth)账期的还款日不晚于账单日。请调整该账期日期，或修改规则。")
        captureScreenshot("规则冲突指出受影响账期")

        tap(app.buttons["account.editor.override.cycle"])
        tap(app.buttons[conflictMonth])
        let repayment = app.descendants(matching: .any).matching(identifier: "account.editor.override.repaymentDate").firstMatch
        let dateError = app.staticTexts["account.repaymentOverride.error"]
        XCTAssertTrue(dateError.waitForExistence(timeout: 10))
        XCTAssertFalse(ruleError.exists)
        navigationBar.buttons["保存"].tap()
        assertEditorFieldErrorVisible(repayment, error: dateError, navigationBar: navigationBar, form: form)
        XCTAssertTrue(dateError.label.contains(conflictMonth))
        captureScreenshot("规则冲突定位所选还款日期")
        setBillingDateToggle("account.editor.override.repayment.enabled", enabled: false)
        XCTAssertTrue(dateError.waitForNonExistence(timeout: 5))
        navigationBar.buttons["保存"].tap()
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        openCard("UI Foreign")
        tap(app.buttons["card.account"])
        let later = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "account.rule.", laterMonth
        )).firstMatch
        reveal(later, fullyVisible: true)
        XCTAssertTrue(later.label.contains("每月 10 日出账"))
        reveal(first, scrollTowardTopWhenMissing: true, fullyVisible: true)
        XCTAssertTrue(first.label.contains("每月 20 日出账"))
        captureScreenshot("规则纠正后版本读回")
        openBillingFeedbackCycle(offset: 2, scrollTowardTopWhenMissing: true)
        assertBillingFeedbackDate("账单日", monthOffset: 2, day: 20)
        assertBillingFeedbackDate("还款日", monthOffset: 2, day: 25)
        captureScreenshot("规则纠正后账期日期读回")
    }

    func testBankNameFeedbackCorrectsAndPreservesSavedValues() {
        verifyBankNameFeedback(largestText: false, discard: false)
    }

    func testBankNameFeedbackAtLargestTextSizeAndCorrectedSave() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyBankNameFeedback(largestText: true, discard: false)
    }

    func testBankNameFeedbackAndDiscardPreservesOriginalValues() {
        // The complete discard/relaunch flow exceeded 180s in run 39732539668.
        executionTimeAllowance = 240
        verifyBankNameFeedback(largestText: false, discard: true)
    }

    func testBankNameFeedbackAtLargestTextSizeAndDiscard() {
        // Same complete discard/readback flow, plus scroll-away at largest text.
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyBankNameFeedback(largestText: true, discard: true)
    }

    func testAccountEditorFieldFeedbackAndCorrectedSave() {
        verifyAccountEditorFieldFeedback(largestText: false)
    }

    func testAccountEditorFieldFeedbackAtLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyAccountEditorFieldFeedback(largestText: true)
    }

    func testCardEditorFieldFeedbackAndCorrectedSave() {
        verifyCardEditorFieldFeedback(largestText: false)
    }

    func testCardEditorFieldFeedbackAtLargestTextSizeAndDiscard() {
        // The simpler largest-text card save/readback already took 184s in
        // run 39089978347; this also checks three validation destinations.
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyCardEditorFieldFeedback(largestText: true)
    }

    func testAccountEditorNumericKeyboardPreservesSavedLimit() {
        verifyAccountEditorNumericKeyboard(largestText: false)
    }

    func testAccountEditorNumericKeyboardAtLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyAccountEditorNumericKeyboard(largestText: true)
    }

    func testCardEditorNumericKeyboardPreservesSavedLastFour() {
        verifyCardEditorNumericKeyboard(largestText: false)
    }

    func testCardEditorNumericKeyboardAtLargestTextSize() {
        // Native save/relaunch/readback took 184 seconds in run 39089978347.
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyCardEditorNumericKeyboard(largestText: true)
    }

    func testOnboardingCreditLimitFeedbackCorrectsAndPreservesSavedValues() {
        verifyOnboardingCreditLimitFeedback(largestText: false)
    }

    func testOnboardingCreditLimitFeedbackAtLargestTextSizeAndDiscard() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyOnboardingCreditLimitFeedback(largestText: true)
    }

    func testOnboardingCardIdentityFeedbackCorrectsAndPreservesSavedValues() {
        verifyOnboardingCardIdentityFeedback(largestText: false)
    }

    func testOnboardingCardIdentityFeedbackAtLargestTextSizeAndDiscard() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyOnboardingCardIdentityFeedback(largestText: true)
    }

    func testCardOnboardingNumericKeyboardPreservesSavedValues() {
        verifyCardOnboardingNumericKeyboard(largestText: false)
    }

    func testCardOnboardingNumericKeyboardAtLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyCardOnboardingNumericKeyboard(largestText: true)
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

    func testPromotionCreationTitleFeedbackCorrectsAndPersists() {
        verifyPromotionCreationTitleFeedback(largestText: false)
    }

    func testPromotionCreationTitleFeedbackAtLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyPromotionCreationTitleFeedback(largestText: true)
    }

    func testPromotionCollapsedAmountFeedbackRevealsFirstErrorAndPersists() {
        // The comparable full correction/save/relaunch promotion flow reached
        // 180.950s in run 39736406449; retain the existing 240s case budget.
        executionTimeAllowance = 240
        verifyPromotionAmountFieldFeedback(perTransaction: false)
    }

    func testPromotionPerTransactionFieldFeedbackAtLargestTextSize() {
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyPromotionAmountFieldFeedback(perTransaction: true)
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

    func testPromotionOptionalAmountsRevealInvalidFieldsAndPersistWhenCollapsed() {
        // This full correction/save/relaunch flow reached 180.950s including
        // teardown in run 39736406449, beyond the workflow's default budget.
        executionTimeAllowance = 240
        launch("core")
        openPromotion("UI Spend")
        openPromotionEditor("基本信息")
        let threshold = app.textFields["累计达标门槛（可选）"]
        replaceText("125.50", in: threshold)
        let dismissal = app.buttons["promotion.keyboard.dismiss"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        assertTouchTarget(dismissal)
        captureScreenshot("促销金额键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(threshold.value as? String, "125.50")
        XCTAssertTrue(app.navigationBars["编辑促销"].exists)
        let additionalAmounts = app.buttons["其他金额条件（可选）"]
        let cap = app.textFields["累计计入上限（可选）"]
        let perTransaction = app.textFields["单笔计入门槛（可选）"]
        XCTAssertFalse(cap.exists)
        tap(additionalAmounts)
        enter("0", into: cap)
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(cap.value as? String, "0")
        tap(additionalAmounts, scrollTowardTopWhenMissing: true)
        XCTAssertFalse(cap.exists)
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.staticTexts["错误：累计计入上限应为大于 0 的数字，或留空。"].waitForExistence(timeout: 10))
        reveal(cap)
        XCTAssertTrue(cap.isHittable)
        replaceText("5000", in: cap)
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(cap.value as? String, "5000")
        enter("100", into: perTransaction)
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(perTransaction.value as? String, "100")
        tap(additionalAmounts, scrollTowardTopWhenMissing: true)
        // Saving from another section must retain the collapsed amount bindings.
        selectPromotionEditorSection("报名与规则")
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.navigationBars["UI Spend"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        openPromotion("UI Spend")
        openPromotionEditor("基本信息")
        reveal(threshold)
        XCTAssertEqual(threshold.value as? String, "125.5")
        // Saved optional rules open automatically, even when they were
        // collapsed before Save. Their bindings never clear hidden values.
        reveal(cap)
        XCTAssertEqual(cap.value as? String, "5000")
        reveal(perTransaction)
        XCTAssertEqual(perTransaction.value as? String, "100")
        captureScreenshot("促销金额规则说明")
        tap(app.textFields["活动标题"], scrollTowardTopWhenMissing: true)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(dismissal.exists)
        tap(app.navigationBars["编辑促销"].buttons["取消"])
        XCTAssertFalse(app.buttons["放弃修改"].exists)
    }

    func testPromotionOptionalAmountExplanationAtLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("promotionAmounts")
        openPromotion("UI Spend")
        openPromotionEditor("基本信息")
        let cap = app.textFields["累计计入上限（可选）"]
        replaceText("5000.25", in: cap)
        let dismissal = app.buttons["promotion.keyboard.dismiss"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        assertTouchTarget(dismissal)
        XCTAssertTrue(dismissal.isHittable)
        XCTAssertTrue(app.frame.contains(dismissal.frame))
        XCTAssertGreaterThanOrEqual(cap.frame.minY, app.navigationBars["编辑促销"].frame.maxY)
        XCTAssertLessThanOrEqual(cap.frame.maxY, dismissal.frame.minY)
        captureScreenshot("最大字号促销金额键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(cap.value as? String, "5000.25")
        XCTAssertTrue(app.navigationBars["编辑促销"].exists)
        let explanation = app.staticTexts["例如仅前 5,000 CNY 可计入：这是上限，不是必须达到的金额。"]
        reveal(explanation, fullyVisible: true)
        XCTAssertTrue(explanation.isHittable)
        XCTAssertGreaterThanOrEqual(explanation.frame.minY, app.navigationBars["编辑促销"].frame.maxY)
        XCTAssertLessThan(explanation.frame.maxY, app.frame.maxY - 40)
        captureScreenshot("最大字号促销金额规则说明")
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.navigationBars["UI Spend"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openPromotion("UI Spend")
        openPromotionEditor("基本信息")
        reveal(cap)
        XCTAssertEqual(cap.value as? String, "5000.25")
    }

    func testPromotionNumericKeyboardAtLargestTextSizePreservesSavedRules() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("promotionOverview")
        openPromotion("UI Available")
        openPromotionEditor("基本信息")
        let limit = app.textFields["优惠笔数上限"]
        replaceText("5", in: limit)
        let dismissal = app.buttons["promotion.keyboard.dismiss"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        assertTouchTarget(dismissal)
        XCTAssertTrue(dismissal.isHittable)
        XCTAssertTrue(app.frame.contains(dismissal.frame))
        XCTAssertGreaterThanOrEqual(limit.frame.minY, app.navigationBars["编辑促销"].frame.maxY)
        XCTAssertLessThanOrEqual(limit.frame.maxY, dismissal.frame.minY)
        captureScreenshot("最大字号促销笔数键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(limit.value as? String, "5")

        let amount = app.textFields["单笔满足金额（可选）"]
        enter("125.50", into: amount)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        assertTouchTarget(dismissal)
        XCTAssertGreaterThanOrEqual(amount.frame.minY, app.navigationBars["编辑促销"].frame.maxY)
        XCTAssertLessThanOrEqual(amount.frame.maxY, dismissal.frame.minY)
        captureScreenshot("最大字号促销单笔金额键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "125.50")
        XCTAssertTrue(app.navigationBars["编辑促销"].exists)
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.navigationBars["UI Available"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        openPromotion("UI Available")
        openPromotionEditor("基本信息")
        reveal(limit)
        XCTAssertEqual(limit.value as? String, "5")
        reveal(amount)
        XCTAssertEqual(amount.value as? String, "125.5")
        captureScreenshot("最大字号促销数字规则保存读回")
    }

    func testPromotionOptionalRuleNotesPersistWhenCollapsed() {
        launch("core")
        openPromotion("UI Spend")
        openPromotionEditor("报名与规则")
        let ruleNotes = app.buttons["规则、排除项与备注（可选）"]
        let rules = app.descendants(matching: .any)
            .matching(identifier: "promotion.editor.rules").firstMatch
        XCTAssertFalse(rules.exists)
        tap(ruleNotes)
        enter("UI Manual Rules", into: rules)
        tap(ruleNotes, scrollTowardTopWhenMissing: true)
        XCTAssertFalse(rules.exists)
        // Exercise the same hidden-value contract independently of amount validation.
        selectPromotionEditorSection("基本信息")
        tap(app.buttons["promotion.editor.save"])
        XCTAssertTrue(app.navigationBars["UI Spend"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        openPromotion("UI Spend")
        openPromotionEditor("报名与规则")
        // Saved notes reopen without expanding the disclosure again.
        reveal(rules)
        XCTAssertEqual(rules.value as? String, "UI Manual Rules")
        captureScreenshot("促销奖励与可选规则")
        tap(app.navigationBars["编辑促销"].buttons["取消"])
        XCTAssertFalse(app.buttons["放弃修改"].exists)
    }

    func testPromotionCreationKeepsGuidanceAndEditingValidatesOtherSections() {
        launch("core")
        let promotionsTab = app.tabBars.buttons["促销"]
        reveal(promotionsTab)
        promotionsTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["促销"].waitForExistence(timeout: 10))
        XCTAssertTrue(promotionsTab.isSelected)
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
        tap(app.tabBars.buttons["促销"])
        let createdPromotion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI Created Promotion")).firstMatch
        reveal(createdPromotion)
        assertTouchTarget(createdPromotion)
        // This row also has a context menu. Specify a single short press when
        // reopening the saved value, then wait for the actual detail page.
        createdPromotion.press(forDuration: 0.05)
        XCTAssertTrue(app.navigationBars["UI Created Promotion"].waitForExistence(timeout: 10))
        captureScreenshot("促销校验后原值读回")
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

    func testPromotionAllocationSearchPreservesSelectionAndAmount() {
        verifyPromotionAllocationSearch(largestText: false)
    }

    func testPromotionAllocationSearchAtLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        verifyPromotionAllocationSearch(largestText: true)
    }

    func testNumericKeyboardDismissalPreservesDraftAndSavedAmounts() {
        launch("core")
        openCard("UI Primary")
        tap(app.buttons["card.addTransaction"])

        let amount = app.textFields["transactionAmount"]
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["transaction.keyboard.dismiss"]
        enter("125.50", into: amount)
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        XCTAssertEqual(dismissal.label, "收起键盘")
        XCTAssertTrue(dismissal.isHittable)
        assertTouchTarget(dismissal)
        captureScreenshot("交易金额键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "125.50")
        XCTAssertTrue(app.navigationBars["添加交易"].exists)

        // An ordinary text field must not show an inert numeric-only action.
        enter("UI Keyboard", into: app.textFields["商户（可选）"])
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(app.buttons["返回修改交易"].waitForExistence(timeout: 10))

        let allocation = app.textFields["allocation.amount.UI Spend"]
        reveal(allocation)
        XCTAssertEqual(allocation.value as? String, "125.5")
        replaceText("100.25", in: allocation)
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        XCTAssertEqual(dismissal.label, "收起键盘")
        XCTAssertTrue(dismissal.isHittable)
        assertTouchTarget(dismissal)
        captureScreenshot("促销计入金额键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(allocation.value as? String, "100.25")
        XCTAssertTrue(app.navigationBars["添加交易"].exists)
        XCTAssertTrue(app.buttons["saveTransaction"].isEnabled)

        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["记一笔"])
        XCTAssertTrue(app.buttons["继续草稿"].waitForExistence(timeout: 10))
        tap(app.buttons["继续草稿"])
        let restored = app.textFields["allocation.amount.UI Spend"]
        reveal(restored)
        XCTAssertEqual(restored.value as? String, "100.25")
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(app.navigationBars["添加交易"].waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        openCard("UI Primary")
        tap(app.buttons["card.transactions"])
        let saved = app.buttons["transaction.UI Keyboard"]
        reveal(saved)
        XCTAssertTrue(saved.label.contains("125.5 CNY"))
        XCTAssertEqual(app.buttons.matching(identifier: "transaction.UI Keyboard").count, 1)
        tap(saved)
        XCTAssertTrue(app.navigationBars["交易详情"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "促销 UI Spend", "100.25 CNY"
        )).firstMatch.waitForExistence(timeout: 10))
    }

    func testNumericKeyboardDismissalAtLargestTextSize() throws {
        // Both font audits change text sizes. Include restoring
        // and checking each screen within the workflow's existing maximum.
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("core")
        openCard("UI Primary")
        tap(app.buttons["card.addTransaction"])

        let amount = app.textFields["transactionAmount"]
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["transaction.keyboard.dismiss"]
        let navigationBar = app.navigationBars["添加交易"]
        // Reveal inputs within the same actual scroll viewport checked below;
        // the fixed footer starts above its buttons' accessibility frames.
        let form = app.descendants(matching: .any).matching(identifier: "transaction.form").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        let progress = app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        reveal(amount, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        amount.tap()
        amount.typeText("125.50")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        XCTAssertEqual(dismissal.label, "收起键盘")
        XCTAssertTrue(dismissal.isHittable)
        assertTouchTarget(dismissal)
        XCTAssertGreaterThanOrEqual(dismissal.frame.minY, navigationBar.frame.maxY)
        XCTAssertTrue(app.frame.contains(dismissal.frame))
        XCTAssertEqual(progress.label, "第 1 步，共 2 步：交易信息")
        XCTAssertTrue(app.frame.contains(progress.frame))
        // Typing can scroll a field under the fixed header as the keyboard opens.
        // Check the whole field before the screenshot, without a dismissing drag.
        XCTAssertEqual(amount.value as? String, "125.50")
        XCTAssertFalse(amount.frame.isEmpty)
        XCTAssertTrue(app.frame.contains(amount.frame))
        XCTAssertGreaterThanOrEqual(amount.frame.minY + 0.001, max(navigationBar.frame.maxY, progress.frame.maxY))
        XCTAssertLessThanOrEqual(amount.frame.maxY, min(contentBottom, form.frame.maxY))
        XCTAssertTrue(amount.isHittable)
        captureScreenshot("最大字号交易金额键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "125.50")
        XCTAssertTrue(navigationBar.exists)

        let save = app.buttons["saveTransaction"]
        XCTAssertGreaterThanOrEqual(progress.frame.minY + 0.001, navigationBar.frame.maxY)
        XCTAssertLessThanOrEqual(progress.frame.maxY, save.frame.minY)
        try app.performAccessibilityAudit(for: .textClipped)
        // The audit changes Dynamic Type and can return the Form to the top,
        // where the lazy amount row is below the viewport. Establish the known
        // card row before searching forward for the amount again.
        reveal(app.buttons["transactionCardPicker"], scrollTowardTopWhenMissing: true,
               fullyVisible: true, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        reveal(amount, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        XCTAssertEqual(amount.value as? String, "125.50")
        XCTAssertFalse(amount.frame.isEmpty)
        XCTAssertTrue(app.frame.contains(amount.frame))
        XCTAssertGreaterThanOrEqual(amount.frame.minY + 0.001, max(navigationBar.frame.maxY, progress.frame.maxY))
        XCTAssertLessThanOrEqual(amount.frame.maxY, min(contentBottom, form.frame.maxY))
        XCTAssertTrue(amount.isHittable)
        XCTAssertGreaterThanOrEqual(progress.frame.minY + 0.001, navigationBar.frame.maxY)
        XCTAssertLessThanOrEqual(progress.frame.maxY, save.frame.minY)
        XCTAssertTrue(save.isHittable)
        assertTouchTarget(save)
        XCTAssertTrue(app.frame.contains(save.frame))
        save.tap()
        let back = app.buttons["返回修改交易"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        let allocation = app.textFields["allocation.amount.UI Spend"]
        reveal(allocation, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        allocation.tap()
        let oldAllocationValue = allocation.value as? String ?? ""
        allocation.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldAllocationValue.count) + "100.25")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        XCTAssertEqual(dismissal.label, "收起键盘")
        XCTAssertTrue(dismissal.isHittable)
        assertTouchTarget(dismissal)
        XCTAssertGreaterThanOrEqual(dismissal.frame.minY, navigationBar.frame.maxY)
        XCTAssertTrue(app.frame.contains(dismissal.frame))
        XCTAssertEqual(progress.label, "第 2 步，共 2 步：确认促销")
        XCTAssertTrue(app.frame.contains(progress.frame))
        XCTAssertEqual(allocation.value as? String, "100.25")
        XCTAssertFalse(allocation.frame.isEmpty)
        XCTAssertTrue(app.frame.contains(allocation.frame))
        XCTAssertGreaterThanOrEqual(allocation.frame.minY + 0.001, max(navigationBar.frame.maxY, progress.frame.maxY))
        XCTAssertLessThanOrEqual(allocation.frame.maxY, min(contentBottom, form.frame.maxY))
        XCTAssertTrue(allocation.isHittable)
        captureScreenshot("最大字号促销计入金额键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(allocation.value as? String, "100.25")
        XCTAssertTrue(navigationBar.exists)

        reveal(allocation, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        XCTAssertEqual(allocation.value as? String, "100.25")
        XCTAssertTrue(back.isHittable)
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(save.isEnabled)
        assertTouchTarget(save)
        XCTAssertTrue(app.frame.contains(back.frame))
        XCTAssertTrue(app.frame.contains(save.frame))
        XCTAssertLessThanOrEqual(back.frame.maxY, save.frame.minY)
        XCTAssertGreaterThanOrEqual(progress.frame.minY + 0.001, navigationBar.frame.maxY)
        XCTAssertLessThanOrEqual(progress.frame.maxY, back.frame.minY)
        try app.performAccessibilityAudit(for: .textClipped)
        // The audit can leave an empty viewport at the old end of the Form;
        // its next layout returns to the beginning. Establish that known anchor
        // before searching forward for the later, lazy allocation row.
        reveal(app.staticTexts["本笔交易"], scrollTowardTopWhenMissing: true,
               fullyVisible: true, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        reveal(allocation, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        XCTAssertEqual(allocation.value as? String, "100.25")
        XCTAssertFalse(allocation.frame.isEmpty)
        XCTAssertTrue(app.frame.contains(allocation.frame))
        XCTAssertGreaterThanOrEqual(allocation.frame.minY + 0.001, max(navigationBar.frame.maxY, progress.frame.maxY))
        XCTAssertLessThanOrEqual(allocation.frame.maxY, min(contentBottom, form.frame.maxY))
        XCTAssertTrue(allocation.isHittable)
        XCTAssertTrue(navigationBar.exists)
        XCTAssertTrue(back.isHittable)
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(save.isEnabled)
        assertTouchTarget(save)
        XCTAssertTrue(app.frame.contains(progress.frame))
        XCTAssertTrue(app.frame.contains(back.frame))
        XCTAssertTrue(app.frame.contains(save.frame))
        XCTAssertLessThanOrEqual(back.frame.maxY, save.frame.minY)
        XCTAssertGreaterThanOrEqual(progress.frame.minY + 0.001, navigationBar.frame.maxY)
        XCTAssertLessThanOrEqual(progress.frame.maxY, back.frame.minY)
        captureScreenshot("最大字号收起键盘后促销确认")
    }

    func testAllocationErrorsLocateFirstInvalidAndClearWhenCorrectedOrDeselected() {
        // Corrections, reselection and readback after relaunch took 188.7s
        // including teardown on native CI; keep the complete flow together.
        executionTimeAllowance = 240
        launch("allocationFeedback")
        openCard("UI Primary")
        tap(app.buttons["card.addTransaction"])
        enter("125.50", into: app.textFields["transactionAmount"])
        enter("UI Allocation Feedback", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])

        let first = app.textFields["allocation.amount.\(allocationFeedbackFirstTitle)"]
        let second = app.textFields["allocation.amount.UI Second"]
        let firstError = allocationError(allocationFeedbackFirstTitle)
        let secondError = allocationError("UI Second")
        replaceText("0", in: first)
        XCTAssertFalse(firstError.exists)
        // Dismiss before searching for the next lazy row. A drag that both
        // dismisses the keyboard and scrolls can jump past that adjacent row.
        let dismissal = app.buttons["transaction.keyboard.dismiss"]
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        replaceText("0", in: second)
        XCTAssertFalse(secondError.exists)
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))

        reveal(app.textFields["allocation.amount.UI Last"])
        assertAllocationAmountOutsideContent(first)
        app.buttons["saveTransaction"].tap()
        assertAllocationErrorVisible(allocationFeedbackFirstTitle)
        XCTAssertEqual(first.value as? String, "0")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        captureScreenshot("首个计入金额错误定位")
        app.buttons["saveTransaction"].tap()
        assertAllocationErrorVisible(allocationFeedbackFirstTitle)

        replaceText("100.25", in: first)
        XCTAssertTrue(firstError.waitForNonExistence(timeout: 5))
        app.buttons["saveTransaction"].tap()
        assertAllocationErrorVisible("UI Second")
        captureScreenshot("下一项计入金额错误定位")
        let selection = app.switches["allocation.toggle.UI Second"]
        // SwiftUI exposes the labelled Toggle and its actual native switch.
        // Activate the switch rather than the centre of the label container.
        let control = selection.switches.firstMatch
        reveal(control, scrollTowardTopWhenMissing: true, fullyVisible: true, navigationBar: app.navigationBars["添加交易"],
               contentHeader: app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch)
        XCTAssertEqual(selection.value as? String, "1")
        control.tap()
        XCTAssertTrue(second.waitForNonExistence(timeout: 5))
        XCTAssertEqual(selection.value as? String, "0")
        XCTAssertTrue(secondError.waitForNonExistence(timeout: 5))
        control.tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertEqual(selection.value as? String, "1")
        XCTAssertEqual(second.value as? String, "0")
        replaceText("75.5", in: second)
        XCTAssertTrue(secondError.waitForNonExistence(timeout: 5))
        app.buttons["saveTransaction"].tap()
        XCTAssertTrue(app.navigationBars["添加交易"].waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        openCard("UI Primary")
        tap(app.buttons["card.transactions"])
        let saved = app.buttons["transaction.UI Allocation Feedback"]
        reveal(saved)
        XCTAssertTrue(saved.label.contains("125.5 CNY"))
        XCTAssertEqual(app.buttons.matching(identifier: "transaction.UI Allocation Feedback").count, 1)
        tap(saved)
        let firstSaved = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "促销 \(allocationFeedbackFirstTitle)", "100.25 CNY"
        )).firstMatch
        reveal(firstSaved)
        let secondSaved = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "促销 UI Second", "75.5 CNY"
        )).firstMatch
        reveal(secondSaved)
    }

    func testCorrectedAllocationDraftKeepsManualAmountAndAdvisoryWarning() {
        launch("core")
        openCard("UI Primary")
        tap(app.buttons["card.addTransaction"])
        enter("125.50", into: app.textFields["transactionAmount"])
        // Finish numeric editing before revealing another lazy Form row;
        // scrolling to dismiss the keyboard also changes that row's position.
        let dismissal = app.buttons["transaction.keyboard.dismiss"]
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let merchant = app.textFields["商户（可选）"]
        enter("UI Corrected Allocation", into: merchant)
        XCTAssertEqual(merchant.value as? String, "UI Corrected Allocation")
        captureScreenshot("计入金额草稿商户输入")
        tap(app.buttons["saveTransaction"])
        let allocation = app.textFields["allocation.amount.UI Spend"]
        let error = allocationError("UI Spend")
        replaceText("", in: allocation)
        app.buttons["saveTransaction"].tap()
        assertAllocationErrorVisible("UI Spend")
        replaceText("150.25", in: allocation)
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let warning = app.staticTexts["计入金额大于本笔交易金额。已确认的分配不会随交易修改自动更改，请核对银行认可金额；仍可手动保存。"]
        reveal(warning, fullyVisible: true,
               contentHeader: app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch)
        XCTAssertTrue(app.buttons["saveTransaction"].isEnabled)
        captureScreenshot("计入金额修正及核对提示")

        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["记一笔"])
        tap(app.buttons["继续草稿"])
        let restored = app.textFields["allocation.amount.UI Spend"]
        reveal(restored)
        XCTAssertEqual(restored.value as? String, "150.25")
        XCTAssertFalse(error.exists)
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(app.navigationBars["添加交易"].waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        openCard("UI Primary")
        tap(app.buttons["card.transactions"])
        let saved = app.buttons["transaction.UI Corrected Allocation"]
        reveal(saved)
        XCTAssertTrue(saved.label.contains("125.5 CNY"))
        XCTAssertEqual(app.buttons.matching(identifier: "transaction.UI Corrected Allocation").count, 1)
        tap(saved)
        let savedAllocation = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "促销 UI Spend", "150.25 CNY"
        )).firstMatch
        reveal(savedAllocation)
    }

    func testAllocationErrorLocationAndCompletePromptAtLargestTextSize() throws {
        // Native error navigation/audit completed at 212s in run 39188540056.
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch("allocationFeedback")
        openCard("UI Primary")
        tap(app.buttons["card.addTransaction"])
        let navigationBar = app.navigationBars["添加交易"]
        let progress = app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch
        let amount = app.textFields["transactionAmount"]
        reveal(amount, navigationBar: navigationBar, contentHeader: progress)
        amount.tap()
        amount.typeText("125.50")
        tap(app.buttons["saveTransaction"])
        let first = app.textFields["allocation.amount.\(allocationFeedbackFirstTitle)"]
        reveal(first, navigationBar: navigationBar, contentHeader: progress)
        first.tap()
        let oldValue = first.value as? String ?? ""
        first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + "0")
        let dismissal = app.buttons["transaction.keyboard.dismiss"]
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        reveal(app.textFields["allocation.amount.UI Last"], navigationBar: navigationBar, contentHeader: progress)
        assertAllocationAmountOutsideContent(first)
        app.buttons["saveTransaction"].tap()
        assertAllocationErrorVisible(allocationFeedbackFirstTitle)
        XCTAssertEqual(first.value as? String, "0")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let error = allocationError(allocationFeedbackFirstTitle)
        XCTAssertEqual(error.label, "错误：计入金额应为大于 0 的数字。")
        let save = app.buttons["saveTransaction"]
        let back = app.buttons["返回修改交易"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(back.isHittable)
        assertTouchTarget(save)
        assertTouchTarget(back)
        captureScreenshot("最大字号计入金额错误定位")
        let beforeAudit = XCTAttachment(string: app.debugDescription)
        beforeAudit.name = "计入金额裁切审计前层级"
        beforeAudit.lifetime = .keepAlways
        add(beforeAudit)
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            let details = "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No associated element")"
            let attachment = XCTAttachment(string: details)
            attachment.name = "计入金额完整裁切审计元素"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            // An issue can have no associated element. Preserve the live
            // callback context as well as the later teardown state, without
            // scrolling, querying hit points, or dismissing any audit issue.
            let screenshot = XCTAttachment(screenshot: self.app.screenshot())
            screenshot.name = "计入金额裁切审计回调画面"
            screenshot.lifetime = .keepAlways
            self.add(screenshot)
            let hierarchy = XCTAttachment(string: self.app.debugDescription)
            hierarchy.name = "计入金额裁切审计回调层级"
            hierarchy.lifetime = .keepAlways
            self.add(hierarchy)
            return false
        }
        let promotionTitle = app.switches["allocation.toggle.\(allocationFeedbackFirstTitle)"]
        reveal(promotionTitle, scrollTowardTopWhenMissing: true, fullyVisible: true,
               navigationBar: navigationBar, contentHeader: progress)
        captureScreenshot("最大字号完整促销活动名称")
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
        reveal(app.segmentedControls.buttons["退款"], fullyVisible: true,
               navigationBar: app.navigationBars["添加交易"],
               contentHeader: app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch)
        XCTAssertTrue(app.segmentedControls.buttons["退款"].isSelected)
        let original = app.buttons["transaction.original"]
        reveal(original)
        XCTAssertTrue((original.label + (original.value as? String ?? "")).contains("UI Original Purchase"))
        let originalSummary = app.staticTexts["transaction.original.summary"]
        reveal(originalSummary, fullyVisible: true)
        XCTAssertTrue(originalSummary.label.contains("UI Original Purchase"))
        XCTAssertTrue(originalSummary.label.contains("100 CNY"))
        XCTAssertTrue(originalSummary.label.contains("状态：有效"))
        captureScreenshot("从原消费记录退款")
        enter("20", into: amount)
        enter("UI Second Refund", into: app.textFields["商户（可选）"])
        tap(app.buttons["saveTransaction"])
        let allocation = app.textFields["allocation.amount.UI Spend"]
        reveal(allocation)
        XCTAssertEqual(allocation.value as? String, "20")
        tap(app.buttons["saveTransaction"])
        // The confirmation changes the detail's viewport and can evict a lazy
        // refund row between exists and frame. Close it before locating the row.
        let feedback = app.buttons["transaction.saveFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertEqual(feedback.label, "已记录退款 20 CNY · 计入 1 个活动")
        feedback.tap()
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 5))
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

    func testRefundOriginalSummaryUpdatesWithSelectionAndClearsWhenCardChanges() {
        let merchant = "星河百货中心生活用品与家居电器联合专柜"
        launch("refundIdentity")
        openCard("UI Foreign")
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.\(merchant)"])
        let recordRefund = app.buttons["transaction.recordRefund"]
        reveal(recordRefund, fullyVisible: true)
        tap(recordRefund)
        XCTAssertTrue(app.segmentedControls.buttons["退款"].isSelected)
        XCTAssertFalse(app.buttons["saveTransaction"].isEnabled)
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "CNY")
        // The initial amount focus moves lazy rows while the keyboard opens.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        tap(app.buttons["transaction.keyboard.dismiss"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let summary = app.staticTexts["transaction.original.summary"]
        reveal(summary, fullyVisible: true)
        XCTAssertEqual(summary.label, "原消费：2026年10月10日 · \(merchant) · 100.25 CNY · 状态：已冲正")
        captureScreenshot("完整原消费摘要")
        enter("7.25", into: app.textFields["transactionAmount"])
        reveal(summary, fullyVisible: true)
        XCTAssertTrue(summary.label.contains("100.25 CNY"))
        XCTAssertFalse(summary.label.contains("7.25"))

        let original = app.buttons["transaction.original"]
        // Revealing the summary can dismiss the keyboard through Form scrolling.
        // Restore editing before testing a single, unassisted selector tap.
        tap(app.textFields["transactionAmount"], scrollTowardTopWhenMissing: true)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(original.isHittable)
        assertTouchTarget(original)
        original.tap()
        XCTAssertTrue(app.navigationBars["选择原消费"].waitForExistence(timeout: 10))
        let selectedOriginal = app.buttons["2026年10月10日 · \(merchant) · 100.25 CNY"]
        XCTAssertTrue(selectedOriginal.isSelected)
        let alternate = app.buttons["2026年10月09日 · UI Alternate Original · 65.5 HKD"]
        reveal(alternate, fullyVisible: true)
        assertTouchTarget(alternate)
        captureScreenshot("原消费选择列表")
        tap(alternate)
        reveal(summary, fullyVisible: true)
        XCTAssertEqual(summary.label, "原消费：2026年10月09日 · UI Alternate Original · 65.5 HKD · 状态：有效")
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "CNY")
        XCTAssertFalse(app.staticTexts["原消费已冲正；退款仍是独立记录，请按银行记录确认退款及促销分配。"].exists)
        captureScreenshot("切换原消费后的摘要")
        tap(original)
        XCTAssertTrue(app.navigationBars["选择原消费"].waitForExistence(timeout: 10))
        XCTAssertTrue(alternate.isSelected)
        tap(app.buttons["不关联原消费（可选）"])
        reveal(original, fullyVisible: true)
        XCTAssertTrue((original.label + (original.value as? String ?? "")).contains("不关联原消费"))
        XCTAssertFalse(summary.exists)
        tap(original)
        XCTAssertTrue(app.navigationBars["选择原消费"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["不关联原消费（可选）"].isSelected)
        tap(app.buttons["2026年10月10日 · \(merchant) · 100.25 CNY"])
        reveal(summary, fullyVisible: true)
        XCTAssertTrue(summary.label.contains(merchant))
        XCTAssertTrue(summary.label.contains("状态：已冲正"))
        selectTransactionCard("UI Primary")
        reveal(original, fullyVisible: true)
        XCTAssertTrue((original.label + (original.value as? String ?? "")).contains("不关联原消费"))
        XCTAssertTrue(app.staticTexts["当前卡片暂无可关联的原消费，可稍后在详情中补充。"].exists)
        XCTAssertFalse(summary.exists)
        selectTransactionCard("UI Foreign")
        reveal(original, fullyVisible: true)
        XCTAssertTrue((original.label + (original.value as? String ?? "")).contains("不关联原消费"))
        XCTAssertFalse(summary.exists)
        reveal(app.textFields["transactionAmount"], scrollTowardTopWhenMissing: true)
        XCTAssertEqual(app.textFields["transactionAmount"].value as? String, "7.25")
        XCTAssertEqual(app.buttons["transactionCurrency"].value as? String, "CNY")
    }

    func testLongRefundOriginalSummaryAtLargestTextSize() throws {
        let merchant = "星河百货中心生活用品与家居电器联合专柜"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("refundIdentity")
        openCard("UI Foreign")
        tap(app.buttons["card.transactions"])
        tap(app.buttons["transaction.\(merchant)"])
        let recordRefund = app.buttons["transaction.recordRefund"]
        reveal(recordRefund, fullyVisible: true)
        tap(recordRefund)
        let original = app.buttons["transaction.original"]
        reveal(original, fullyVisible: true)
        assertTouchTarget(original)
        XCTAssertTrue(original.label.contains("更改原消费"))
        XCTAssertEqual(original.value as? String, "2026年10月10日 · \(merchant) · 100.25 CNY")
        let summary = app.staticTexts["transaction.original.summary"]
        reveal(summary, fullyVisible: true)
        XCTAssertEqual(summary.label, "原消费：2026年10月10日 · \(merchant) · 100.25 CNY · 状态：已冲正")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        captureScreenshot("最大字号完整原消费摘要")
        try auditAccessibility(for: [.textClipped])

        reveal(original, fullyVisible: true)
        tap(original)
        XCTAssertTrue(app.navigationBars["选择原消费"].waitForExistence(timeout: 10))
        let selectedOriginal = app.buttons["2026年10月10日 · \(merchant) · 100.25 CNY"]
        reveal(selectedOriginal, fullyVisible: true)
        XCTAssertEqual(selectedOriginal.label, "2026年10月10日 · \(merchant) · 100.25 CNY")
        XCTAssertTrue(selectedOriginal.isSelected)
        assertTouchTarget(selectedOriginal)
        captureScreenshot("最大字号原消费选择列表")
        try auditAccessibility(for: [.textClipped])
        // This sheet has no save footer; the covered editor's AX button still exists.
        app.swipeUp()
        let alternate = app.buttons["2026年10月09日 · UI Alternate Original · 65.5 HKD"]
        XCTAssertTrue(alternate.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(alternate.frame.minY, app.navigationBars["选择原消费"].frame.maxY)
        XCTAssertLessThan(alternate.frame.maxY, app.frame.maxY - 40)
        XCTAssertTrue(alternate.isHittable)
        assertTouchTarget(alternate)
        tap(alternate)
        reveal(summary, fullyVisible: true)
        XCTAssertEqual(summary.label, "原消费：2026年10月09日 · UI Alternate Original · 65.5 HKD · 状态：有效")
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
        let continueButton = app.buttons["saveTransaction"]
        var previousFrame: CGRect?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard continueButton.exists else { return false }
            let frame = continueButton.frame
            defer { previousFrame = frame }
            return !frame.isEmpty && frame == previousFrame
                && self.app.frame.contains(frame) && continueButton.isEnabled && continueButton.isHittable
        }, object: continueButton)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertEqual(continueButton.label, "继续确认促销")
        assertTouchTarget(continueButton)
        continueButton.tap()
        XCTAssertTrue(app.buttons["返回修改交易"].waitForExistence(timeout: 10))
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
        XCTAssertFalse(app.staticTexts["transaction.original.summary"].exists)
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
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("linkedRefunds")
        tap(app.tabBars.buttons["交易"])
        tap(app.buttons["transaction.UI Unlinked Refund"])
        reveal(app.staticTexts["未关联原消费"])
        XCTAssertFalse(app.buttons["transaction.recordRefund"].exists)
        tap(app.navigationBars["交易详情"].buttons["完成"])
        tap(app.buttons["transaction.UI Reversed Purchase"])
        XCTAssertTrue(app.staticTexts["UI Reversed Purchase"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["已冲正"].exists)
        let recordRefund = app.buttons["transaction.recordRefund"]
        reveal(recordRefund, fullyVisible: true)
        assertTouchTarget(recordRefund)
        captureScreenshot("最大字号原消费退款入口")
        tap(recordRefund)
        enter("10", into: app.textFields["transactionAmount"])
        tap(app.buttons["transaction.keyboard.dismiss"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        reveal(app.segmentedControls.buttons["退款"], fullyVisible: true,
               navigationBar: app.navigationBars["添加交易"],
               contentHeader: app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch)
        XCTAssertTrue(app.segmentedControls.buttons["退款"].isSelected)
        let original = app.buttons["transaction.original"]
        reveal(original, fullyVisible: true)
        XCTAssertTrue((original.label + (original.value as? String ?? "")).contains("UI Reversed Purchase"))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let reversedMessage = app.staticTexts["原消费已冲正；退款仍是独立记录，请按银行记录确认退款及促销分配。"]
        reveal(reversedMessage, fullyVisible: true)
        captureScreenshot("最大字号已冲正原消费退款说明")
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
        let relatedIdentifier = related.identifier
        let relatedFrame = related.frame
        tap(related)
        XCTAssertTrue(app.staticTexts["UI Reversed Original Refund"].waitForExistence(timeout: 10))
        let detailNavigation = app.navigationBars["交易详情"]
        tap(detailNavigation.buttons["交易详情"])
        XCTAssertTrue(detailNavigation.buttons["完成"].waitForExistence(timeout: 10))
        // Native back restores the purchase's scroll position at its refund row;
        // its header and status are lazy rows above the viewport at this size.
        XCTAssertTrue(recordRefund.exists)
        let restoredRelated = app.buttons[relatedIdentifier]
        reveal(restoredRelated, fullyVisible: true)
        XCTAssertEqual(restoredRelated.frame.minY, relatedFrame.minY, accuracy: 1)
        XCTAssertTrue(restoredRelated.label.contains("UI Reversed Original Refund"))
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
        let continueDraft = app.buttons["继续草稿"]
        var previousFrame: CGRect?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard continueDraft.exists else { return false }
            let frame = continueDraft.frame
            defer { previousFrame = frame }
            return !frame.isEmpty && frame == previousFrame
                && self.app.frame.contains(frame) && continueDraft.isHittable
        }, object: continueDraft)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        assertTouchTarget(continueDraft)
        tap(continueDraft)
        XCTAssertTrue(app.navigationBars["添加交易"].waitForExistence(timeout: 10))
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
        reveal(app.textFields["商户（可选）"],
               contentHeader: app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch)
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
        XCTAssertEqual(amount.value as? String, "79")
        let dismissal = app.buttons["transaction.keyboard.dismiss"]
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let save = app.buttons["saveTransaction"]
        var previousSaveFrame: CGRect?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard save.exists, save.isEnabled else { return false }
            let frame = save.frame
            defer { previousSaveFrame = frame }
            return !frame.isEmpty && frame == previousSaveFrame
                && self.app.frame.contains(frame) && save.isHittable
        }, object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        save.tap()
        XCTAssertTrue(app.navigationBars["编辑交易"].waitForNonExistence(timeout: 10))
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

    func testTransactionDateAndCurrencyPresetsKeepCounts() {
        launch("transactionFilters")
        tap(app.tabBars.buttons["交易"])
        let count = app.staticTexts["transactions.results.count"]
        XCTAssertEqual(count.label, "共 8 笔交易")
        tap(app.buttons["transactions.filters"])
        tap(app.buttons["transactions.filter.date"])
        tap(app.buttons["本月"])
        tap(app.buttons["transactions.filter.currency"])
        tap(app.buttons["CNY"])
        tap(app.navigationBars["筛选交易"].buttons["完成"])
        XCTAssertEqual(count.label, "共 2 笔交易")
        XCTAssertTrue(app.buttons["transaction.UI Current CNY"].exists)
        XCTAssertTrue(app.buttons["transaction.UI Current Refund"].exists)
        captureScreenshot("交易日期与币种筛选")

        tap(app.buttons["transactions.filters"])
        tap(app.buttons["transactions.filter.date"])
        tap(app.buttons["上月"])
        tap(app.navigationBars["筛选交易"].buttons["完成"])
        XCTAssertEqual(count.label, "共 2 笔交易")
        XCTAssertTrue(app.buttons["transaction.UI Previous Reversed"].exists)
    }

    func testTransactionStatusKindAndCurrencyFiltersKeepCountsAndClear() {
        launch("transactionFilters")
        tap(app.tabBars.buttons["交易"])
        let count = app.staticTexts["transactions.results.count"]
        XCTAssertEqual(count.label, "共 8 笔交易")
        tap(app.buttons["transactions.filters"])
        tap(app.buttons["transactions.filter.date"])
        tap(app.buttons["上月"])
        tap(app.buttons["transactions.filter.currency"])
        tap(app.buttons["CNY"])
        tap(app.navigationBars["筛选交易"].buttons["完成"])
        XCTAssertEqual(count.label, "共 2 笔交易")
        tap(app.buttons["transactions.filters"])
        tap(app.buttons["transactions.filter.status"])
        tap(app.buttons["有效"])
        tap(app.navigationBars["筛选交易"].buttons["完成"])
        XCTAssertEqual(count.label, "共 1 笔交易")
        XCTAssertTrue(app.buttons["transaction.UI Previous CNY"].exists)
        tap(app.buttons["transactions.filters"])
        tap(app.buttons["transactions.filter.currency"], scrollTowardTopWhenMissing: true)
        tap(app.buttons["HKD"])
        tap(app.buttons["transactions.filter.kind"])
        tap(app.buttons["消费"])
        tap(app.navigationBars["筛选交易"].buttons["完成"])
        XCTAssertEqual(count.label, "共 0 笔交易")
        XCTAssertTrue(app.staticTexts["没有匹配交易"].exists)
        tap(app.buttons["transactions.filters"])
        tap(app.navigationBars["筛选交易"].buttons["清除"])
        tap(app.navigationBars["筛选交易"].buttons["完成"])
        XCTAssertEqual(count.label, "共 8 笔交易")
        XCTAssertFalse(app.buttons["transactions.filters.date.clear"].exists)
        XCTAssertFalse(app.buttons["transactions.filters.currency.clear"].exists)
    }

    func testCustomTransactionDateRangeShowsFieldsAndKeepsCounts() {
        launch("transactionFilters")
        tap(app.tabBars.buttons["交易"])
        let count = app.staticTexts["transactions.results.count"]
        XCTAssertEqual(count.label, "共 8 笔交易")
        tap(app.buttons["transactions.filters"])
        tap(app.buttons["transactions.filter.date"])
        tap(app.buttons["自定义范围"])
        let start = app.descendants(matching: .any).matching(identifier: "transactions.filter.startDate").firstMatch
        let end = app.descendants(matching: .any).matching(identifier: "transactions.filter.endDate").firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(end.exists)
        captureScreenshot("自定义交易日期范围")
        tap(app.navigationBars["筛选交易"].buttons["完成"])
        XCTAssertEqual(count.label, "共 3 笔交易")
    }

    func testDateAndCurrencyFilterRemovalAtLargestTextSize() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("transactionFilters")
        tap(app.tabBars.buttons["交易"])
        tap(app.buttons["transactions.filters"])
        tap(app.buttons["transactions.filter.date"])
        tap(app.buttons["上月"])
        tap(app.buttons["transactions.filter.currency"])
        tap(app.buttons["CNY"])
        tap(app.navigationBars["筛选交易"].buttons["完成"])
        let count = app.staticTexts["transactions.results.count"]
        XCTAssertEqual(count.label, "共 2 笔交易")
        let date = app.buttons["transactions.filters.date.clear"]
        assertTouchTarget(date)
        captureScreenshot("最大字号日期与币种筛选")
        date.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertEqual(count.label, "共 5 笔交易")
        let currency = app.buttons["transactions.filters.currency.clear"]
        assertTouchTarget(currency)
        captureScreenshot("最大字号币种筛选移除")
        try auditAccessibility(for: [.hitRegion])
        tap(currency)
        XCTAssertEqual(count.label, "共 8 笔交易")
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

    func testAccountCycleHistoryFindsOlderPaidCyclesAndClearsFilters() {
        launch("accountHistory")
        openCard("UI Shared")
        tap(app.buttons["card.account"])
        let history = app.buttons["account.cycleHistory"]
        reveal(history, fullyVisible: true)
        assertTouchTarget(history)
        captureScreenshot("账户全部账期入口")
        tap(history)
        let count = app.staticTexts["account.history.count"]
        XCTAssertEqual(count.label, "共 23 个账期")
        let olderPaid = accountHistoryMonth(offset: -18)
        tap(app.buttons["account.history.year"], scrollTowardTopWhenMissing: true)
        tap(app.buttons[olderPaid.year])
        tap(app.buttons["account.history.month"], scrollTowardTopWhenMissing: true)
        tap(app.buttons[olderPaid.month])
        tap(app.buttons["account.history.status"], scrollTowardTopWhenMissing: true)
        tap(app.buttons["已还款"])
        XCTAssertEqual(count.label, "共 1 个账期")
        let paid = app.buttons["account.history.cycle.\(olderPaid.key)"]
        XCTAssertTrue(paid.label.contains("已还款"))
        captureScreenshot("第七个已处理账期查询")
        tap(paid)
        XCTAssertTrue(app.buttons["撤销已还款"].waitForExistence(timeout: 10))
        tap(app.navigationBars["账期详情"].buttons["全部账期"])
        XCTAssertEqual(count.label, "共 1 个账期")
        tap(app.buttons["account.history.clear"], scrollTowardTopWhenMissing: true)
        XCTAssertEqual(count.label, "共 23 个账期")
        XCTAssertFalse(app.buttons["account.history.clear"].exists)
    }

    func testAccountCycleHistoryPersistsOlderUnpaidCycleRepaymentAcrossSharedCards() {
        // Native shared-card repayment/readback reached teardown at 185.53s
        // in run 39330388648; keep the full flow within the existing maximum.
        executionTimeAllowance = 240
        launch("accountHistory")
        openCard("UI Shared")
        tap(app.buttons["card.account"])
        let history = app.buttons["account.cycleHistory"]
        reveal(history, fullyVisible: true)
        tap(history)
        let count = app.staticTexts["account.history.count"]
        XCTAssertEqual(count.label, "共 23 个账期")
        let unpaid = accountHistoryMonth(offset: -7)
        tap(app.buttons["account.history.year"], scrollTowardTopWhenMissing: true)
        tap(app.buttons[unpaid.year])
        tap(app.buttons["account.history.month"], scrollTowardTopWhenMissing: true)
        tap(app.buttons[unpaid.month])
        tap(app.buttons["account.history.status"], scrollTowardTopWhenMissing: true)
        tap(app.buttons["未还款"])
        XCTAssertEqual(count.label, "共 1 个账期")
        let row = app.buttons["account.history.cycle.\(unpaid.key)"]
        XCTAssertTrue(row.label.contains("已逾期"))
        captureScreenshot("第五个未还账期查询")
        tap(row)
        tap(app.buttons["标记已还"])
        tap(app.navigationBars["账期详情"].buttons["全部账期"])
        XCTAssertEqual(count.label, "共 0 个账期")
        XCTAssertTrue(app.staticTexts["没有匹配账期"].exists)
        app.terminate()
        app.launch()
        openCard("UI Primary")
        tap(app.buttons["card.account"])
        reveal(app.buttons["account.cycleHistory"], fullyVisible: true)
        tap(app.buttons["account.cycleHistory"])
        tap(app.buttons["account.history.year"], scrollTowardTopWhenMissing: true)
        tap(app.buttons[unpaid.year])
        tap(app.buttons["account.history.month"], scrollTowardTopWhenMissing: true)
        tap(app.buttons[unpaid.month])
        tap(app.buttons["account.history.status"], scrollTowardTopWhenMissing: true)
        tap(app.buttons["已还款"])
        XCTAssertEqual(count.label, "共 1 个账期")
        XCTAssertTrue(row.label.contains("已还款"))
    }

    func testAccountHistoryFiltersAndSavedFutureDatesAtLargestTextSize() throws {
        // All history checks finished at 179.45s; teardown crossed 180s
        // (run 39028286830). Keep the complete flow within the existing maximum.
        executionTimeAllowance = 240
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("accountHistory")
        tap(app.tabBars.buttons["卡片"])
        // Both fixture cards share this account. Use its existing direct row
        // so this history flow spends its time on history rather than card navigation.
        let sharedAccount = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "尾号 1234", "尾号 5678"
        )).firstMatch
        tap(sharedAccount)
        XCTAssertTrue(app.navigationBars["账户详情"].waitForExistence(timeout: 10))
        let history = app.buttons["account.cycleHistory"]
        reveal(history, fullyVisible: true)
        assertTouchTarget(history)
        captureScreenshot("最大字号全部账期入口")
        tap(history)
        let future = accountHistoryMonth(offset: 5)
        tap(app.buttons["account.history.year"], scrollTowardTopWhenMissing: true)
        tap(app.buttons[future.year])
        let month = app.buttons["account.history.month"]
        reveal(month, scrollTowardTopWhenMissing: true, fullyVisible: true)
        month.tap()
        tap(app.buttons[future.month])
        let status = app.buttons["account.history.status"]
        reveal(status, fullyVisible: true)
        assertTouchTarget(status)
        tap(status)
        let statusNavigation = app.navigationBars["还款状态"]
        XCTAssertTrue(statusNavigation.waitForExistence(timeout: 10))
        let unpaid = app.buttons["未还款"]
        reveal(unpaid, fullyVisible: true)
        assertTouchTarget(unpaid)
        captureScreenshot("最大字号账期状态选择")
        unpaid.tap()
        if statusNavigation.exists {
            tap(statusNavigation.buttons.element(boundBy: 0))
        }
        XCTAssertTrue(app.navigationBars["全部账期"].waitForExistence(timeout: 10))
        let count = app.staticTexts["account.history.count"]
        reveal(count)
        XCTAssertEqual(count.label, "共 1 个账期")
        let row = app.buttons["account.history.cycle.\(future.key)"]
        reveal(row, fullyVisible: true)
        assertTouchTarget(row)
        XCTAssertTrue(row.label.contains("03日"))
        XCTAssertTrue(row.label.contains("06日"))
        captureScreenshot("最大字号账期查询结果")
        try auditAccessibility(for: [.hitRegion])
        tap(row)
        XCTAssertTrue(app.navigationBars["账期详情"].waitForExistence(timeout: 10))
        // At accessibility XXXL, the account identity fills the first screen.
        // List actions are lazy; scroll to the real control before checking it.
        let adjustDates = app.buttons["调整本期日期"]
        reveal(adjustDates, fullyVisible: true)
        assertTouchTarget(adjustDates)
        tap(app.navigationBars["账期详情"].buttons["全部账期"])
        let clear = app.buttons["account.history.clear"]
        reveal(clear, scrollTowardTopWhenMissing: true, fullyVisible: true)
        assertTouchTarget(clear)
        tap(clear)
        reveal(count)
        XCTAssertEqual(count.label, "共 23 个账期")
        XCTAssertFalse(app.buttons["account.history.clear"].exists)
    }

    func testAccountHistoryPaidFilterShowsEmptyResultAtLargestTextSize() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("accountHistory")
        openCard("UI Shared")
        tap(app.buttons["card.account"])
        let history = app.buttons["account.cycleHistory"]
        reveal(history, fullyVisible: true)
        assertTouchTarget(history)
        tap(history)
        let future = accountHistoryMonth(offset: 5)
        tap(app.buttons["account.history.year"], scrollTowardTopWhenMissing: true)
        tap(app.buttons[future.year])
        let month = app.buttons["account.history.month"]
        reveal(month, scrollTowardTopWhenMissing: true, fullyVisible: true)
        month.tap()
        tap(app.buttons[future.month])
        let status = app.buttons["account.history.status"]
        reveal(status, fullyVisible: true)
        assertTouchTarget(status)
        tap(status)
        let statusNavigation = app.navigationBars["还款状态"]
        XCTAssertTrue(statusNavigation.waitForExistence(timeout: 10))
        let paid = app.buttons["已还款"]
        reveal(paid, fullyVisible: true)
        assertTouchTarget(paid)
        paid.tap()
        if statusNavigation.exists {
            tap(statusNavigation.buttons.element(boundBy: 0))
        }
        XCTAssertTrue(app.navigationBars["全部账期"].waitForExistence(timeout: 10))
        let count = app.staticTexts["account.history.count"]
        reveal(count)
        XCTAssertEqual(count.label, "共 0 个账期")
        let empty = app.staticTexts["没有匹配账期"]
        reveal(empty, fullyVisible: true)
        XCTAssertTrue(empty.exists)
        let explanation = app.staticTexts["可调整年份、月份或还款状态。"]
        reveal(explanation, fullyVisible: true)
        XCTAssertTrue(explanation.exists)
        let navigationBar = app.navigationBars["全部账期"]
        for text in [empty, explanation] {
            XCTAssertFalse(text.frame.isEmpty)
            XCTAssertTrue(app.frame.contains(text.frame))
            XCTAssertGreaterThanOrEqual(text.frame.minY + 0.001, navigationBar.frame.maxY)
            XCTAssertLessThanOrEqual(text.frame.maxY, contentBottom)
        }
        captureScreenshot("最大字号已还账期空结果")
        do {
            let originalContinueAfterFailure = continueAfterFailure
            continueAfterFailure = true
            defer { continueAfterFailure = originalContinueAfterFailure }
            try app.performAccessibilityAudit(for: .textClipped) { issue in
                let details = "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No associated element")"
                let attachment = XCTAttachment(string: details)
                attachment.name = "账期空结果文字审计元素"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return false
            }
        }
        let clear = app.buttons["account.history.clear"]
        reveal(clear, scrollTowardTopWhenMissing: true, fullyVisible: true)
        assertTouchTarget(clear)
        clear.tap()
        reveal(count)
        XCTAssertEqual(count.label, "共 23 个账期")
        XCTAssertFalse(clear.exists)
    }

    private func accountHistoryMonth(offset: Int) -> (key: Int, year: String, month: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(byAdding: .month, value: offset, to: Date())!
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return (year * 100 + month, String(year), "\(month) 月")
    }

    func testFutureRuleEditingSelectsRequestedVersionAndCancellationPersists() {
        launch("futureRules")
        openCard("UI Shared")
        tap(app.buttons["card.account"])
        let firstMonth = futureRuleMonth(offset: 1)
        let laterMonth = futureRuleMonth(offset: 3)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "account.rule.", firstMonth)).firstMatch
        reveal(first, fullyVisible: true)
        assertTouchTarget(first)
        tap(first)
        captureScreenshot("未来规则取消影响预览")
        tap(app.buttons["account.rule.edit"])
        let statement = app.buttons["account.editor.rule.statementDay"]
        reveal(statement, fullyVisible: true)
        XCTAssertTrue((statement.label + (statement.value as? String ?? "")).contains("每月 5 日"))
        let effective = app.buttons["account.editor.rule.effectiveCycle"]
        reveal(effective)
        XCTAssertEqual(effective.value as? String, firstMonth)
        tap(statement, scrollTowardTopWhenMissing: true)
        tap(app.buttons["每月 6 日"])
        tap(app.navigationBars["编辑信用卡账户"].buttons["保存"])
        let corrected = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "每月 6 日出账")).firstMatch
        reveal(corrected, scrollTowardTopWhenMissing: true, fullyVisible: true)
        XCTAssertTrue(corrected.exists)
        let cancel = app.buttons["account.rule.cancel"]
        reveal(cancel, fullyVisible: true)
        tap(cancel)
        tap(app.buttons["保留计划"])
        XCTAssertTrue(app.navigationBars["规则计划"].exists)
        tap(cancel)
        captureScreenshot("取消未来规则确认")
        tap(app.sheets.buttons["取消规则计划"])
        XCTAssertTrue(app.navigationBars["账户详情"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openCard("UI Shared")
        tap(app.buttons["card.account"])
        let later = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "account.rule.", laterMonth)).firstMatch
        reveal(later, fullyVisible: true)
        XCTAssertFalse(first.exists)
        XCTAssertTrue(later.label.contains("每月 10 日出账"))
    }

    func testInvalidFutureRuleCancellationExplainsAffectedCycleAtLargestTextSize() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("futureRules")
        openCard("UI Foreign")
        tap(app.buttons["card.account"])
        let firstMonth = futureRuleMonth(offset: 1)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "account.rule.", firstMonth)).firstMatch
        reveal(first, fullyVisible: true)
        assertTouchTarget(first)
        tap(first)
        let explanation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "请先调整该账期的日期")).firstMatch
        reveal(explanation, fullyVisible: true)
        XCTAssertTrue(explanation.label.contains(futureRuleMonth(offset: 2)))
        captureScreenshot("最大字号未来规则取消日期冲突")
        let cancel = app.buttons["account.rule.cancel"]
        reveal(cancel, fullyVisible: true)
        XCTAssertFalse(cancel.isEnabled)
        let adjust = app.buttons["调整相关账期"]
        reveal(adjust, scrollTowardTopWhenMissing: true, fullyVisible: true)
        assertTouchTarget(adjust)
        try auditAccessibility(for: [.hitRegion])
        tap(adjust)
        XCTAssertTrue(app.navigationBars["账期详情"].waitForExistence(timeout: 10))
        tap(app.navigationBars["账期详情"].buttons.firstMatch)
        tap(app.navigationBars["规则计划"].buttons.firstMatch)
        reveal(first, fullyVisible: true)
        XCTAssertTrue(first.exists)
        tap(first)
        XCTAssertTrue(app.navigationBars["规则计划"].waitForExistence(timeout: 10))
        // Returning to the plan resets its List position. At the largest size,
        // the cancel action is below the rule and date-conflict explanation.
        reveal(cancel, fullyVisible: true)
        XCTAssertFalse(cancel.isEnabled)
    }

    private func futureRuleMonth(offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(byAdding: .month, value: offset, to: Date())!
        return "\(calendar.component(.year, from: date))年\(calendar.component(.month, from: date))月"
    }

    func testBillingSchedulesSupportAccessibleTextAndNavigationTargets() throws {
        executionTimeAllowance = 240
        launch("core")
        openCard("UI Primary")
        // SwiftUI also propagates the identifier to the combined header row.
        let title = app.staticTexts.matching(identifier: "card.detail.title")
            .matching(NSPredicate(format: "label == %@", "UI Primary")).element
        let normalTitleHeight = title.frame.height
        XCTAssertGreaterThan(normalTitleHeight, 0)
        let cycle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "billingCycle.")).firstMatch
        reveal(cycle)
        for element in [title, cycle] {
            XCTAssertFalse(element.frame.isEmpty)
            XCTAssertTrue(app.frame.contains(element.frame))
            XCTAssertGreaterThanOrEqual(element.frame.minY + 0.001, app.navigationBars["卡片详情"].frame.maxY)
            XCTAssertLessThanOrEqual(element.frame.maxY, contentBottom)
        }
        captureScreenshot("卡片账期日程")
        // Audit after the combined header has scrolled entirely out of the
        // navigation bar, while the schedule and following promotion fit.
        let followingPromotion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "UI Spend、")).firstMatch
        let bank = app.staticTexts["银行、UI Test Bank"]
        reveal(bank, fullyVisible: true, navigationBar: app.navigationBars["卡片详情"])
        for element in [cycle, followingPromotion, bank] {
            XCTAssertFalse(element.frame.isEmpty)
            XCTAssertTrue(app.frame.contains(element.frame))
            XCTAssertGreaterThanOrEqual(element.frame.minY + 0.001, app.navigationBars["卡片详情"].frame.maxY)
            XCTAssertLessThanOrEqual(element.frame.maxY, contentBottom)
        }
        let header = app.staticTexts.matching(identifier: "card.detail.title")
            .matching(NSPredicate(format: "label CONTAINS %@", "UI Test Bank图标")).firstMatch
        if header.exists {
            XCTAssertLessThanOrEqual(header.frame.maxY, app.navigationBars["卡片详情"].frame.maxY)
        }
        captureScreenshot("普通字号账期审计阅读区域")
        try auditAccessibility(for: [.textClipped], captureFailureContext: true)

        tap(app.tabBars.buttons["首页"])
        let schedule = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.billingCycle.")).firstMatch
        reveal(schedule)
        assertTouchTarget(schedule)
        captureScreenshot("首页账期日程")
        try auditAccessibility(for: [.hitRegion, .textClipped])
    }

    func testBillingSchedulesAtLargestTextSizeSupportAccessibleTextAndNavigationTargets() throws {
        executionTimeAllowance = 240
        launch("core")
        openCard("UI Primary")
        let title = app.staticTexts.matching(identifier: "card.detail.title")
            .matching(NSPredicate(format: "label == %@", "UI Primary")).element
        let normalTitleHeight = title.frame.height
        XCTAssertGreaterThan(normalTitleHeight, 0)
        relaunchAtLargestTextSize()
        openCard("UI Primary")
        XCTAssertGreaterThan(title.frame.height, normalTitleHeight * 1.3)
        let cycle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "billingCycle.")).firstMatch
        reveal(cycle, fullyVisible: true)
        captureScreenshot("最大字号卡片账期日程")
        try auditAccessibility(for: [.textClipped], captureFailureContext: true)

        tap(app.tabBars.buttons["首页"])
        let pendingCycles = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "dashboard.action.billingCycle."
        ))
        let pendingIDs = (0..<pendingCycles.count).map { pendingCycles.element(boundBy: $0).identifier }
        var pendingTitles: [XCUIElement] = []
        // The core fixture's 21st-day repayment appears when overdue or within
        // seven days; audit every other checkpoint regardless.
        for identifier in pendingIDs {
            let pendingCycle = app.buttons[identifier]
            reveal(pendingCycle, fullyVisible: true, navigationBar: app.navigationBars["CardPilot"])
            assertTouchTarget(pendingCycle)
            XCTAssertTrue(pendingCycle.label.contains("UI Test Bank"))
            XCTAssertTrue(pendingCycle.label.contains("\(futureRuleMonth(offset: 0))账期"))
            let accountKind: String
            if pendingCycle.label.contains("UI Foreign") {
                XCTAssertTrue(pendingCycle.label.contains("尾号 9012"))
                accountKind = "独立账户"
            } else {
                XCTAssertTrue(pendingCycle.label.contains("UI Primary"))
                XCTAssertTrue(pendingCycle.label.contains("尾号 1234"))
                XCTAssertTrue(pendingCycle.label.contains("UI Shared"))
                XCTAssertTrue(pendingCycle.label.contains("尾号 5678"))
                accountKind = "共享账户"
            }
            let text = pendingCycle.staticTexts["查看账期"]
            XCTAssertTrue(text.isHittable)
            XCTAssertTrue(app.frame.contains(text.frame))
            XCTAssertGreaterThanOrEqual(text.frame.minY + 0.001, app.navigationBars["CardPilot"].frame.maxY)
            XCTAssertLessThanOrEqual(text.frame.maxY, contentBottom)
            captureScreenshot("最大字号首页待办\(accountKind)账期完整文字")
            pendingCycle.tap()
            XCTAssertTrue(app.navigationBars["账期详情"].waitForExistence(timeout: 10))
            tap(app.navigationBars["账期详情"].buttons.firstMatch)
            pendingTitles.append(text)
        }
        let promotion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.promotion.")).firstMatch
        reveal(promotion, fullyVisible: true)
        captureScreenshot("最大字号首页活动摘要")
        try auditAccessibility(for: [.textClipped], captureFailureContext: true, verifiedClippedTexts: pendingTitles)
        let schedule = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.billingCycle.")).firstMatch
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

    private func verifyPromotionCreationTitleFeedback(largestText: Bool) {
        let prefix = (largestText ? "最大字号" : "") + "创建促销"
        launch("core")
        openNewPromotionEditor()
        let navigationBar = app.navigationBars["添加促销"]
        let form = app.descendants(matching: .any).matching(identifier: "promotion.editor.form").firstMatch
        let title = app.textFields["promotion.title"]
        let error = app.staticTexts["promotion.error.title"]
        let advance = app.buttons["promotion.editor.advance"]
        let threshold = app.textFields["累计达标门槛（可选）"]

        if !largestText {
            // Merely revealing an error is not an edit and must not require
            // discarding an otherwise untouched new promotion.
            tap(title)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            advance.tap()
            assertEditorFieldErrorVisible(title, error: error, navigationBar: navigationBar, form: form)
            navigationBar.buttons["取消"].tap()
            XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))
            XCTAssertFalse(app.buttons["放弃修改"].exists)
            openNewPromotionEditor()
        }

        replacePromotionAmount("125.50", in: threshold, navigationBar: navigationBar, form: form)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if largestText {
            let frame = title.exists ? title.frame : .zero
            let top = max(navigationBar.frame.maxY, form.frame.minY)
            XCTAssertFalse(title.exists && !frame.isEmpty && frame.minY + 0.001 >= top
                           && frame.maxY <= min(contentBottom, form.frame.maxY))
        }
        advance.tap()
        assertEditorFieldErrorVisible(title, error: error, navigationBar: navigationBar, form: form)
        XCTAssertEqual(error.label, "错误：请先填写活动标题。")
        captureScreenshot("\(prefix)标题首错定位")
        title.tap()
        title.typeText(" UI Feedback ")
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, " UI Feedback ")
        captureScreenshot("\(prefix)标题纠正后错误消失")
        advance.tap()
        XCTAssertTrue(app.staticTexts["主办方"].waitForExistence(timeout: 10))
        advance.tap()
        let save = app.buttons["promotion.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.navigationBars["促销"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        openPromotion("UI Feedback")
        openPromotionEditor("基本信息")
        let editingNavigationBar = app.navigationBars["编辑促销"]
        XCTAssertEqual(title.value as? String, "UI Feedback")
        XCTAssertFalse(error.exists)
        captureScreenshot("\(prefix)保存标题读回")
        reveal(threshold, fullyVisible: true, navigationBar: editingNavigationBar, contentContainer: form)
        XCTAssertEqual(threshold.value as? String, "125.5")
        captureScreenshot("\(prefix)保存金额读回")
        editingNavigationBar.buttons["取消"].tap()
        XCTAssertFalse(app.buttons["放弃修改"].exists)
    }

    private func verifyPromotionAmountFieldFeedback(perTransaction: Bool) {
        let prefix = perTransaction ? "最大字号逐笔促销" : "累计促销"
        let name = perTransaction ? "UI Available" : "UI Spend"
        launch(perTransaction ? "promotionOverview" : "core")
        openPromotion(name)
        openPromotionEditor("基本信息")
        let navigationBar = app.navigationBars["编辑促销"]
        let form = app.descendants(matching: .any).matching(identifier: "promotion.editor.form").firstMatch
        let first = app.textFields[perTransaction ? "优惠笔数上限" : "累计计入上限（可选）"]
        let second = app.textFields[perTransaction ? "单笔满足金额（可选）" : "单笔计入门槛（可选）"]
        let firstError = app.staticTexts["promotion.error.\(perTransaction ? "benefitTransactionCap" : "qualifyingCap")"]
        let secondError = app.staticTexts["promotion.error.perTransactionThreshold"]
        let additional = app.buttons["其他金额条件（可选）"]
        if !perTransaction { tap(additional) }
        replacePromotionAmount("0", in: first, navigationBar: navigationBar, form: form)
        tap(app.buttons["promotion.keyboard.dismiss"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        replacePromotionAmount("0", in: second, navigationBar: navigationBar, form: form)
        tap(app.buttons["promotion.keyboard.dismiss"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        if !perTransaction {
            tap(additional, scrollTowardTopWhenMissing: true)
            XCTAssertFalse(first.exists)
        }
        selectPromotionEditorSection("适用范围")
        app.buttons["promotion.editor.save"].tap()
        assertEditorFieldErrorVisible(first, error: firstError, navigationBar: navigationBar, form: form)
        XCTAssertEqual(firstError.label, perTransaction ? "错误：优惠笔数上限应为大于 0 的整数。"
                       : "错误：累计计入上限应为大于 0 的数字，或留空。")
        captureScreenshot("\(prefix)金额首错定位")
        replacePromotionAmount(perTransaction ? "5" : "5000", in: first, navigationBar: navigationBar, form: form)
        XCTAssertTrue(firstError.waitForNonExistence(timeout: 5))
        captureScreenshot("\(prefix)首项纠正后错误消失")
        app.buttons["promotion.editor.save"].tap()
        assertEditorFieldErrorVisible(second, error: secondError, navigationBar: navigationBar, form: form)
        XCTAssertEqual(secondError.label, perTransaction ? "错误：单笔满足金额应为大于 0 的数字，或留空。"
                       : "错误：单笔计入门槛应为大于 0 的数字，或留空。")
        captureScreenshot("\(prefix)下一错误定位")
        replacePromotionAmount("100", in: second, navigationBar: navigationBar, form: form)
        XCTAssertTrue(secondError.waitForNonExistence(timeout: 5))
        captureScreenshot("\(prefix)金额纠正后错误消失")
        app.buttons["promotion.editor.save"].tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        openPromotion(name)
        openPromotionEditor("基本信息")
        XCTAssertEqual(app.textFields["promotion.title"].value as? String, name)
        reveal(first, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        XCTAssertEqual(first.value as? String, perTransaction ? "5" : "5000")
        XCTAssertFalse(firstError.exists)
        captureScreenshot("\(prefix)首项保存读回")
        reveal(second, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        XCTAssertEqual(second.value as? String, "100")
        XCTAssertFalse(secondError.exists)
        captureScreenshot("\(prefix)金额保存读回")
        navigationBar.buttons["取消"].tap()
        XCTAssertFalse(app.buttons["放弃修改"].exists)
    }

    private func openNewPromotionEditor() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let tab = app.tabBars.buttons["促销"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        XCTAssertTrue(tab.isEnabled && tab.isHittable)
        XCTAssertTrue(app.frame.contains(tab.frame))
        tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        XCTAssertTrue(app.navigationBars["促销"].waitForExistence(timeout: 10))
        tap(app.buttons["添加促销活动"])
        XCTAssertTrue(app.navigationBars["添加促销"].waitForExistence(timeout: 10))
    }

    private func replacePromotionAmount(_ text: String, in field: XCUIElement,
                                        navigationBar: XCUIElement, form: XCUIElement) {
        reveal(field, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        let old = field.value as? String ?? ""
        // Values here fit in the field. Place the caret after the actual text
        // before deleting, rather than deleting from a center-tap caret.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text)
        XCTAssertEqual(field.value as? String, text)
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

    func testBackupExportFilenameCancellationAndLargestTextRecord() throws {
        launch("core")
        tap(app.buttons["打开设置"])
        tap(app.buttons["settings.backup"])
        let navigationBar = app.navigationBars["完整备份与恢复"]
        let record = app.staticTexts["backup.lastSuccessfulExport"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        let previousRecord = record.label
        captureScreenshot("备份成功导出记录")
        let export = app.buttons["backup.export"]
        reveal(export, scrollTowardTopWhenMissing: true, fullyVisible: true, navigationBar: navigationBar)
        assertTouchTarget(export)
        tap(export)
        let picker = app.otherElements["Browse View (Picker)"]
        let filename = picker.textFields.firstMatch
        // In run 39768699985 the native picker first rendered its filename
        // about 46s after Export (recording at 59.72s, tap at 13.29s).
        // Wait for that real control without reopening or retrying the export.
        XCTAssertTrue(filename.waitForExistence(timeout: 60))
        XCTAssertTrue(picker.exists)
        // The native picker exposes an abbreviated value until editing starts.
        // Focus the real filename field without changing the proposed name.
        filename.tap()
        let proposedName = (filename.value as? String) ?? filename.label
        XCTAssertNotNil(proposedName.range(
            of: "^CardPilot-备份-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}(\\.json)?$",
            options: .regularExpression
        ))
        captureScreenshot("系统备份导出文件名")
        // This directory page shows Browse and Move. Return to Browse to use
        // the visible native Cancel button, rather than its hidden AX proxy.
        let browse = picker.navigationBars.buttons["浏览"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        browse.tap()
        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertEqual(record.label, previousRecord)
        XCTAssertFalse(app.alerts["备份与恢复"].exists)

        relaunchAtLargestTextSize()
        tap(app.buttons["打开设置"])
        tap(app.buttons["settings.backup"])
        reveal(record, fullyVisible: true, navigationBar: navigationBar)
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertEqual(record.label, previousRecord)
        captureScreenshot("最大字号取消导出后记录")
        try auditAccessibility(for: [.textClipped])
        reveal(export, scrollTowardTopWhenMissing: true, fullyVisible: true, navigationBar: navigationBar)
        assertTouchTarget(export)
        try auditAccessibility(for: [.hitRegion])

        // A read-only preference override exercises the longer date layout.
        // It does not simulate a file save or prove the export callback ran.
        app.terminate()
        app.launchArguments += ["-cardPilot.lastSuccessfulBackupExport", "1791633600"]
        app.launch()
        tap(app.buttons["打开设置"])
        tap(app.buttons["settings.backup"])
        reveal(record, fullyVisible: true, navigationBar: navigationBar)
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(record.label.contains("2026"))
        captureScreenshot("最大字号已有导出记录")
        try auditAccessibility(for: [.textClipped])
    }

    private func verifyPromotionAllocationSearch(largestText: Bool) {
        launch("core")
        openCard("UI Primary")
        tap(app.buttons["card.addTransaction"])
        let navigationBar = app.navigationBars["添加交易"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let progress = app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch
        let form = app.descendants(matching: .any).matching(identifier: "transaction.form").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.exists)
        // The fixed step header also covers the initial amount row after a
        // scroll; use the same viewport as the confirmation inputs below.
        let amount = app.textFields["transactionAmount"]
        reveal(amount, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        amount.tap()
        amount.typeText("125.50")
        tap(app.buttons["transaction.keyboard.dismiss"])
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(app.buttons["返回修改交易"].waitForExistence(timeout: 10))

        let search = app.textFields["allocation.search"]
        reveal(search, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        XCTAssertEqual(search.label, "搜索其他促销")
        search.tap()
        search.typeText("Spend")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertEqual(search.value as? String, "Spend")
        XCTAssertFalse(search.frame.isEmpty)
        XCTAssertTrue(search.isHittable)
        XCTAssertGreaterThanOrEqual(search.frame.minY + 0.001, max(navigationBar.frame.maxY, progress.frame.maxY))
        XCTAssertLessThanOrEqual(search.frame.maxY, min(contentBottom, form.frame.maxY))
        let searchLabel = app.staticTexts["搜索"]
        XCTAssertTrue(searchLabel.exists)
        XCTAssertGreaterThanOrEqual(searchLabel.frame.minY + 0.001, progress.frame.maxY)
        XCTAssertLessThanOrEqual(searchLabel.frame.maxY, min(contentBottom, form.frame.maxY))
        let prefix = largestText ? "最大字号" : ""
        captureScreenshot("\(prefix)促销搜索键盘输入")

        func dismissSearchKeyboard() {
            // Use the confirmation view's scroll-to-dismiss gesture in its gutter.
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.75))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        }
        dismissSearchKeyboard()
        reveal(app.staticTexts["促销分配"], scrollTowardTopWhenMissing: true, fullyVisible: true,
               navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        reveal(search, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        XCTAssertEqual(search.value as? String, "Spend")
        XCTAssertGreaterThanOrEqual(search.frame.minY + 0.001, progress.frame.maxY)
        XCTAssertLessThanOrEqual(search.frame.maxY, min(contentBottom, form.frame.maxY))
        captureScreenshot("\(prefix)促销搜索输入后提示")

        let selection = app.switches["allocation.toggle.UI Spend"]
        let control = selection.switches.firstMatch
        reveal(control, fullyVisible: true, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        XCTAssertEqual(selection.value as? String, "1")
        control.tap()
        XCTAssertEqual(selection.value as? String, "0")
        control.tap()
        XCTAssertEqual(selection.value as? String, "1")
        reveal(search, scrollTowardTopWhenMissing: true,
               navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        XCTAssertEqual(search.value as? String, "Spend")
        replaceText("", in: search)
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertEqual(search.value as? String, "")
        dismissSearchKeyboard()
        let allocation = app.textFields["allocation.amount.UI Spend"]
        reveal(allocation, navigationBar: navigationBar, contentHeader: progress, contentContainer: form)
        XCTAssertEqual(allocation.value as? String, "125.5")
        XCTAssertEqual(selection.value as? String, "1")
        XCTAssertTrue(app.buttons["saveTransaction"].isEnabled)
        captureScreenshot("\(prefix)促销搜索清空后保留计入金额")
    }

    private func verifyAccessibleBillingDateSave(accountEditor: Bool) throws {
        let prefix = "最大字号" + (accountEditor ? "账户编辑" : "账期编辑")
        launch("billingDateFeedback")
        openBillingFeedbackAccount()
        if accountEditor {
            tap(app.navigationBars["账户详情"].buttons["编辑"])
        } else {
            openBillingFeedbackCycle(offset: 0)
            tap(app.buttons["调整本期日期"])
        }
        let navigationBar = app.navigationBars[accountEditor ? "编辑信用卡账户" : "调整本期日期"]
        let form = app.collectionViews[accountEditor ? "account.editor.form" : "billingDates.form"]
        try adjustBillingDateDay(accountEditor ? "account.editor.override.statementDate" : "billingDates.statementDate",
                                 from: 5, to: 6, navigationBar: navigationBar, form: form,
                                 screenshot: "\(prefix)账单日期滚轮完整值", auditText: !accountEditor)
        try adjustBillingDateDay(accountEditor ? "account.editor.override.repaymentDate" : "billingDates.repaymentDate",
                                 from: 15, to: 16, navigationBar: navigationBar, form: form,
                                 screenshot: "\(prefix)还款日期滚轮完整值", auditText: !accountEditor)
        if !accountEditor {
            // Read the complete date summary and explanation after returning
            // from the two audited native date-selection pages.
            let explanation = app.staticTexts["billingDates.explanation"]
            reveal(explanation, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
            let repayment = app.buttons["billingDates.repaymentDate"]
            XCTAssertEqual(repayment.label, "还款日")
            XCTAssertTrue((repayment.value as? String ?? "").hasSuffix("16日"))
            for element in [repayment, explanation] {
                XCTAssertFalse(element.frame.isEmpty)
                XCTAssertTrue(app.frame.contains(element.frame))
                XCTAssertGreaterThanOrEqual(element.frame.minY + 0.001, navigationBar.frame.maxY)
                XCTAssertLessThanOrEqual(element.frame.maxY, min(contentBottom, form.frame.maxY))
            }
            captureScreenshot("最大字号账期日期及说明完整阅读")
        }
        navigationBar.buttons["保存"].tap()
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        openBillingFeedbackAccount()
        openBillingFeedbackCycle(offset: 0)
        assertBillingFeedbackDate("账单日", monthOffset: 0, day: 6)
        assertBillingFeedbackDate("还款日", monthOffset: 0, day: 16)
        let paid = app.staticTexts["状态、已还款"]
        reveal(paid, fullyVisible: true)
        XCTAssertTrue(paid.exists)
        captureScreenshot("\(prefix)滚轮日期保存读回")
        let undo = app.buttons["撤销已还款"]
        reveal(undo, fullyVisible: true)
        XCTAssertTrue(undo.exists)
        XCTAssertFalse(app.buttons["标记已还"].exists)
    }

    private func adjustBillingDateDay(_ identifier: String, from originalDay: Int, to changedDay: Int,
                                     navigationBar: XCUIElement, form: XCUIElement,
                                     screenshot: String, auditText: Bool) throws {
        let entry = app.buttons[identifier]
        reveal(entry, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        let field = identifier.contains("statement") ? "账单日" : "还款日"
        let title = identifier.hasPrefix("account.editor.") ? "实际" + field : field
        XCTAssertEqual(entry.label, title)
        XCTAssertTrue((entry.value as? String ?? "").hasSuffix(String(format: "%02d日", originalDay)))
        entry.tap()
        let selectionNavigation = app.navigationBars[title]
        XCTAssertTrue(selectionNavigation.waitForExistence(timeout: 10))
        let selectionForm = app.collectionViews["\(identifier).selection"]
        let picker = app.datePickers["\(identifier).wheel"]
        reveal(picker, fullyVisible: true, navigationBar: selectionNavigation, contentContainer: selectionForm)
        let wheels = picker.pickerWheels
        XCTAssertEqual(wheels.count, 3)
        let day = wheels.element(boundBy: 2)
        XCTAssertEqual(day.value as? String, "\(originalDay)日")
        // Native wheels report a taller AX frame than their DatePicker host.
        // Reveal that actual input too, using the unchanged viewport guards.
        reveal(day, fullyVisible: true, navigationBar: selectionNavigation, contentContainer: selectionForm)
        day.adjust(toPickerWheelValue: "\(changedDay)日")
        XCTAssertEqual(day.value as? String, "\(changedDay)日")
        XCTAssertTrue(selectionNavigation.staticTexts[title].exists)
        for element in [picker] + wheels.allElementsBoundByIndex {
            XCTAssertFalse(element.frame.isEmpty)
            XCTAssertTrue(app.frame.contains(element.frame))
            XCTAssertGreaterThanOrEqual(element.frame.minY + 0.001, selectionNavigation.frame.maxY)
            XCTAssertLessThanOrEqual(element.frame.maxY, min(contentBottom, selectionForm.frame.maxY))
        }
        for wheel in wheels.allElementsBoundByIndex {
            XCTAssertTrue(wheel.isHittable)
            assertTouchTarget(wheel)
        }
        captureScreenshot(screenshot)
        if auditText {
            try app.performAccessibilityAudit(for: .textClipped) { issue in
                let details = "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No associated element")"
                let attachment = XCTAttachment(string: details)
                attachment.name = "账期日期文字裁切审计元素"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                self.captureAccessibilityAuditContext("账期日期文字裁切审计回调")
                return false
            }
        }
        selectionNavigation.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(selectionNavigation.waitForNonExistence(timeout: 10))
        XCTAssertTrue(navigationBar.exists)
        reveal(entry, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        XCTAssertTrue((entry.value as? String ?? "").hasSuffix(String(format: "%02d日", changedDay)))
    }

    private func verifyBillingDateFeedback(accountEditor: Bool, largestText: Bool) {
        let prefix = (largestText ? "最大字号" : "") + (accountEditor ? "账户编辑" : "账期编辑")
        launch("billingDateFeedback")
        openBillingFeedbackAccount()
        if accountEditor {
            tap(app.navigationBars["账户详情"].buttons["编辑"])
        } else {
            openBillingFeedbackCycle(offset: 0)
            tap(app.buttons["调整本期日期"])
        }
        let navigationBar = app.navigationBars[accountEditor ? "编辑信用卡账户" : "调整本期日期"]
        let form = app.collectionViews[accountEditor ? "account.editor.form" : "billingDates.form"]
        let statementToggle = accountEditor ? "account.editor.override.statement.enabled" : "billingDates.statement.enabled"
        let repaymentToggle = accountEditor ? "account.editor.override.repayment.enabled" : "billingDates.repayment.enabled"
        let repayment = app.descendants(matching: .any).matching(identifier:
            accountEditor ? "account.editor.override.repaymentDate" : "billingDates.repaymentDate").firstMatch
        let error = app.staticTexts[accountEditor ? "account.repaymentOverride.error" : "billingDates.repayment.error"]
        setBillingDateToggle(statementToggle, enabled: false)
        XCTAssertFalse(error.exists)
        if accountEditor {
            reveal(app.textFields["信用额度（可选）"], scrollTowardTopWhenMissing: true, fullyVisible: true)
        } else {
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.2))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        navigationBar.buttons["保存"].tap()
        XCTAssertFalse(app.alerts["无法保存"].exists)
        assertEditorFieldErrorVisible(repayment, error: error, navigationBar: navigationBar, form: form)
        XCTAssertTrue(error.label.contains("还款日必须晚于账单日"))
        captureScreenshot("\(prefix)还款日期首错定位")
        setBillingDateToggle(repaymentToggle, enabled: false)
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertFalse(repayment.exists)
        captureScreenshot("\(prefix)恢复规则后错误消失")
        if largestText {
            navigationBar.buttons["取消"].tap()
            tap(app.buttons["放弃修改"])
        } else {
            navigationBar.buttons["保存"].tap()
        }
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        openBillingFeedbackAccount()
        openBillingFeedbackCycle(offset: 0)
        assertBillingFeedbackDate("账单日", monthOffset: 0, day: largestText ? 5 : 20)
        assertBillingFeedbackDate("还款日", monthOffset: largestText ? 0 : 1, day: 15)
        let status = app.staticTexts["状态、已还款"]
        reveal(status, fullyVisible: true)
        captureScreenshot("\(prefix)日期及已还款状态读回")
        let undo = app.buttons["撤销已还款"]
        reveal(undo, fullyVisible: true)
        XCTAssertTrue(undo.exists)
        XCTAssertFalse(app.buttons["标记已还"].exists)
    }

    private func setBillingDateToggle(_ identifier: String, enabled: Bool) {
        let toggle = app.switches[identifier]
        reveal(toggle, fullyVisible: true)
        XCTAssertEqual(toggle.value as? String, enabled ? "0" : "1")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0")
    }

    private func openBillingFeedbackAccount() {
        tap(app.tabBars.buttons["卡片"])
        let account = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "尾号 1234", "尾号 5678"
        )).firstMatch
        tap(account)
        XCTAssertTrue(app.navigationBars["账户详情"].waitForExistence(timeout: 10))
    }

    private func openBillingFeedbackCycle(offset: Int, scrollTowardTopWhenMissing: Bool = false) {
        let history = app.buttons["account.cycleHistory"]
        reveal(history, scrollTowardTopWhenMissing: scrollTowardTopWhenMissing, fullyVisible: true,
               navigationBar: app.navigationBars["账户详情"])
        history.tap()
        XCTAssertTrue(app.navigationBars["全部账期"].waitForExistence(timeout: 10))
        let month = accountHistoryMonth(offset: offset)
        tap(app.buttons["account.history.cycle.\(month.key)"])
        XCTAssertTrue(app.navigationBars["账期详情"].waitForExistence(timeout: 10))
    }

    private func assertBillingFeedbackDate(_ field: String, monthOffset: Int, day: Int) {
        let key = accountHistoryMonth(offset: monthOffset).key
        let text = String(format: "%04d年%02d月%02d日", key / 100, key % 100, day)
        // Native LabeledContent exposes its label and value as one AX text.
        let date = app.staticTexts["\(field)、\(text)"]
        reveal(date, fullyVisible: true)
        XCTAssertTrue(date.exists)
    }

    private func verifyAccountEditorFieldFeedback(largestText: Bool) {
        let prefix = largestText ? "最大字号" : ""
        launch("core")
        openCard("UI Primary")
        tap(app.buttons["card.account"])
        tap(app.navigationBars["账户详情"].buttons["编辑"])
        let navigationBar = app.navigationBars["编辑信用卡账户"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let form = app.collectionViews["account.editor.form"]
        let limit = app.textFields["信用额度（可选）"]
        let error = app.staticTexts.matching(identifier: "account.limit.error").firstMatch
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["account.keyboard.dismiss"]
        replaceText("0", in: limit)
        XCTAssertFalse(error.exists)
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        scrollEditorTowardBottom(form)
        if limit.exists {
            let frame = limit.frame
            let top = max(navigationBar.frame.maxY, form.frame.minY)
            let bottom = min(contentBottom, form.frame.maxY)
            XCTAssertFalse(!frame.isEmpty && frame.minY + 0.001 >= top && frame.maxY <= bottom,
                           "Start away from the invalid field")
        }
        navigationBar.buttons["保存"].tap()
        XCTAssertTrue(navigationBar.exists)
        assertEditorFieldErrorVisible(limit, error: error, navigationBar: navigationBar, form: form)
        XCTAssertEqual(limit.value as? String, "0")
        XCTAssertEqual(error.label, "错误：信用额度必须大于 0。")
        captureScreenshot("\(prefix)账户额度首错定位")

        replaceText("1.2.3", in: limit)
        XCTAssertEqual(error.label, "错误：信用额度格式不正确。")
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        assertEditorFieldErrorVisible(limit, error: error, navigationBar: navigationBar, form: form)
        captureScreenshot("\(prefix)账户额度格式错误更新")
        replaceText("", in: limit)
        XCTAssertTrue(error.waitForNonExistence(timeout: 5), "An optional empty limit is valid")
        replaceText("125.50", in: limit)
        XCTAssertFalse(error.exists)
        navigationBar.buttons["保存"].tap()
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        openCard("UI Shared")
        tap(app.buttons["card.account"])
        let saved = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "信用额度", "125.5 CNY"
        )).firstMatch
        reveal(saved, scrollTowardTopWhenMissing: true, fullyVisible: true)
        captureScreenshot("\(prefix)账户纠错后共享额度读回")
    }

    private func verifyCardEditorFieldFeedback(largestText: Bool) {
        let prefix = largestText ? "最大字号" : ""
        launch("core")
        openCard("UI Primary")
        tap(app.navigationBars["卡片详情"].buttons["编辑"])
        let navigationBar = app.navigationBars["编辑卡片"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let form = app.collectionViews["card.editor.form"]
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["card.keyboard.dismiss"]
        tap(app.buttons["其他"])
        let customNetwork = app.textFields["卡组织名称"]
        let customError = app.staticTexts.matching(identifier: "card.customNetwork.error").firstMatch
        let product = app.textFields["卡产品名称"]
        let productError = app.staticTexts.matching(identifier: "card.productName.error").firstMatch
        let lastFour = app.textFields["末四位"]
        let lastFourError = app.staticTexts.matching(identifier: "card.lastFour.error").firstMatch
        replaceText("", in: product)
        // Start inside the focused row: the Form's AX frame includes an outer
        // gutter where a drag may never reach the scroll view's pan recognizer.
        let contentTop = max(navigationBar.frame.maxY, form.frame.minY)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let productFrame = product.frame
        XCTAssertGreaterThan(productFrame.midY, contentTop)
        XCTAssertLessThan(productFrame.midY, keyboard.frame.minY)
        let dragX = productFrame.midX - app.frame.minX
        let startY = productFrame.midY - app.frame.minY
        let endY = contentTop + 24 - app.frame.minY
        origin.withOffset(CGVector(dx: dragX, dy: startY)).press(
            forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: dragX, dy: endY)),
            withVelocity: .slow, thenHoldForDuration: 0.2
        )
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        // Keyboard disappearance can precede the end of the Form's motion.
        // Establish a stable field before focusing the next keyboard type.
        reveal(lastFour, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        var previousFrame = lastFour.frame
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // Read only this field while polling. Repeated full-viewport AX
            // queries can consume the five-second wait before it returns.
            let frame = lastFour.frame
            defer { previousFrame = frame }
            return !frame.isEmpty
                && abs(frame.minX - previousFrame.minX) <= 0.001
                && abs(frame.minY - previousFrame.minY) <= 0.001
                && abs(frame.width - previousFrame.width) <= 0.001
                && abs(frame.height - previousFrame.height) <= 0.001
        }, object: lastFour)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        let fieldFrame = lastFour.frame
        XCTAssertGreaterThanOrEqual(fieldFrame.minY + 0.001, max(navigationBar.frame.maxY, form.frame.minY))
        XCTAssertLessThan(fieldFrame.maxY, min(contentBottom, form.frame.maxY))
        XCTAssertFalse(keyboard.exists)
        XCTAssertTrue(lastFour.isHittable)
        lastFour.tap()
        XCTAssertTrue(dismissal.waitForExistence(timeout: 5))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let previousLastFour = lastFour.value as? String ?? ""
        lastFour.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previousLastFour.count) + "123")
        XCTAssertEqual(lastFour.value as? String, "123")
        captureScreenshot("\(prefix)卡片末四位纠错准备")
        XCTAssertFalse(lastFourError.exists)
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        scrollEditorTowardBottom(form)
        navigationBar.buttons["保存"].tap()
        assertEditorFieldErrorVisible(customNetwork, error: customError, navigationBar: navigationBar, form: form)
        XCTAssertEqual(customError.label, "错误：请填写卡组织名称。")
        captureScreenshot("\(prefix)卡片卡组织首错定位")

        tap(app.buttons["Visa"], scrollTowardTopWhenMissing: true)
        XCTAssertTrue(app.buttons["Visa，已选择"].waitForExistence(timeout: 5))
        XCTAssertTrue(customError.waitForNonExistence(timeout: 5))
        navigationBar.buttons["保存"].tap()
        assertEditorFieldErrorVisible(product, error: productError, navigationBar: navigationBar, form: form)
        XCTAssertEqual(productError.label, "错误：卡产品名称不能为空。")
        captureScreenshot("\(prefix)卡片产品名称错误定位")
        replaceText("UI Fixed", in: product)
        XCTAssertTrue(productError.waitForNonExistence(timeout: 5))
        XCTAssertFalse(dismissal.exists, "Ordinary text does not show the numeric keyboard toolbar")
        navigationBar.buttons["保存"].tap()
        assertEditorFieldErrorVisible(lastFour, error: lastFourError, navigationBar: navigationBar, form: form)
        XCTAssertEqual(lastFour.value as? String, "123")
        XCTAssertEqual(lastFourError.label, "错误：末四位必须是 4 位数字。")
        captureScreenshot("\(prefix)卡片末四位错误定位")
        replaceText("0123", in: lastFour)
        XCTAssertTrue(lastFourError.waitForNonExistence(timeout: 5))
        if largestText {
            navigationBar.buttons["取消"].tap()
            tap(app.buttons["放弃修改"])
        } else {
            navigationBar.buttons["保存"].tap()
        }
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["卡片"])
        let search = app.searchFields["搜索银行、卡片或末四位"]
        tap(search, scrollTowardTopWhenMissing: true)
        let expectedName = largestText ? "UI Primary" : "UI Fixed"
        search.typeText(expectedName + "\n")
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        let saved = app.buttons["card.\(expectedName)"]
        reveal(saved, fullyVisible: true)
        XCTAssertTrue(saved.label.contains(largestText ? "1234" : "0123"))
        XCTAssertTrue(saved.label.contains("Visa"))
        XCTAssertEqual(app.buttons.matching(identifier: "card.\(expectedName)").count, 1)
        if largestText {
            XCTAssertFalse(app.buttons["card.UI Fixed"].exists)
        }
        captureScreenshot("\(prefix)卡片纠错后\(largestText ? "放弃修改读回" : "保存读回")")
    }

    private func scrollEditorTowardBottom(_ form: XCUIElement) {
        for _ in 0..<2 {
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    private func assertEditorFieldErrorVisible(
        _ field: XCUIElement,
        error: XCUIElement,
        navigationBar: XCUIElement,
        form: XCUIElement
    ) {
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        // Do not scroll here: these bounds verify the application's own
        // first-error navigation, including the complete nearby message.
        let top = max(navigationBar.frame.maxY, form.frame.minY)
        let bottom = min(contentBottom, form.frame.maxY)
        let fieldFrame = field.frame
        let errorFrame = error.frame
        for frame in [fieldFrame, errorFrame] {
            XCTAssertFalse(frame.isEmpty)
            XCTAssertGreaterThanOrEqual(frame.minY + 0.001, top)
            XCTAssertLessThanOrEqual(frame.maxY, bottom)
        }
        // AX can round the same shared edge differently by a subpixel.
        XCTAssertGreaterThanOrEqual(errorFrame.minY + 0.001, fieldFrame.maxY)
        XCTAssertTrue(field.isHittable)
    }

    private func verifyBankNameFeedback(largestText: Bool, discard: Bool) {
        let prefix = (largestText ? "最大字号" : "") + (discard ? "编辑银行" : "添加银行")
        let originalName = "UI Test Bank"
        let correctedName = "UI Bank"
        let noteText = (1...14).map { "UI note \($0)" }.joined(separator: "\n")
        launch("core")
        selectCardsTab()
        if discard {
            let edit = bankEditButtons(named: originalName).element
            reveal(edit, scrollTowardTopWhenMissing: true, fullyVisible: true)
            assertTouchTarget(edit)
            captureScreenshot("\(prefix)入口")
            edit.tap()
        } else {
            openNewBankEditor(screenshot: "\(prefix)入口")
        }
        let navigationBar = app.navigationBars[discard ? "编辑银行" : "添加银行"]
        let form = app.collectionViews["bank.editor.form"]
        let name = app.textFields["bank.name"]
        let notes = app.descendants(matching: .any).matching(identifier: "bank.notes").firstMatch
        let error = app.staticTexts["bank.name.error"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        XCTAssertFalse(error.exists)

        if !discard && !largestText {
            // Feedback alone is not an edit and must not require discarding.
            navigationBar.buttons["保存"].tap()
            assertEditorFieldErrorVisible(name, error: error, navigationBar: navigationBar, form: form)
            navigationBar.buttons["取消"].tap()
            XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))
            XCTAssertFalse(app.buttons["放弃修改"].exists)
            openNewBankEditor()
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
            XCTAssertFalse(error.exists)
        }

        if discard {
            let archived = app.switches["归档"]
            reveal(archived, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
            XCTAssertEqual(archived.value as? String, "0")
            archived.switches.firstMatch.tap()
            XCTAssertEqual(archived.value as? String, "1")
        }
        reveal(name, scrollTowardTopWhenMissing: true, navigationBar: navigationBar, contentContainer: form)
        if discard {
            XCTAssertEqual(name.value as? String, originalName)
            // The field's center can put the caret inside the existing name
            // at large text sizes. Its trailing edge is beyond this full name.
            name.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: originalName.count) + "   ")
        } else {
            replaceText("   ", in: name)
        }
        // The final screen was blank in run 39819298070, but an immediate AX
        // read still returned the intermediate deletion value "UI Te". Await
        // the exact input state, without tapping or typing a second time.
        let blankName = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "   "), object: name)
        XCTAssertEqual(XCTWaiter.wait(for: [blankName], timeout: 10), .completed)
        XCTAssertEqual(name.value as? String, "   ")
        reveal(notes, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        notes.tap()
        notes.typeText(noteText)
        XCTAssertFalse(error.exists)
        if largestText {
            // The Form's AX frame extends behind the keyboard. Begin the
            // dismissal drag above the focused input's actually clipped edge.
            let top = max(navigationBar.frame.maxY, form.frame.minY)
            let bottom = min(contentBottom, notes.frame.maxY)
            XCTAssertGreaterThan(bottom - top, 60)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = form.frame.minX + form.frame.width * 0.03
            origin.withOffset(CGVector(dx: x, dy: bottom - 25))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: top + 25)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            scrollEditorTowardBottom(form)
            if name.exists {
                let frame = name.frame
                XCTAssertFalse(!frame.isEmpty && frame.minY + 0.001 >= navigationBar.frame.maxY
                    && frame.maxY <= min(contentBottom, form.frame.maxY))
            }
        } else {
            // Saving must also dismiss a multiline text keyboard directly.
            XCTAssertTrue(app.keyboards.firstMatch.exists)
        }
        navigationBar.buttons["保存"].tap()
        assertEditorFieldErrorVisible(name, error: error, navigationBar: navigationBar, form: form)
        XCTAssertEqual(error.label, "错误：银行名称不能为空。")
        XCTAssertEqual(notes.value as? String, noteText)
        captureScreenshot("\(prefix)名称首错定位")

        replaceText(" \(correctedName) ", in: name)
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, " \(correctedName) ")
        XCTAssertEqual(notes.value as? String, noteText)
        captureScreenshot("\(prefix)名称纠正后错误消失")
        if discard {
            navigationBar.buttons["取消"].tap()
            tap(app.buttons["放弃修改"])
        } else {
            navigationBar.buttons["保存"].tap()
        }
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        selectCardsTab()
        let search = app.searchFields["搜索银行、卡片或末四位"]
        enter(discard ? originalName : correctedName, into: search)
        search.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        if discard {
            XCTAssertEqual(bankEditButtons(named: correctedName).count, 0)
        }
        let savedBanks = bankEditButtons(named: discard ? originalName : correctedName)
        XCTAssertEqual(savedBanks.count, 1)
        let savedBank = savedBanks.element
        reveal(savedBank, fullyVisible: true)
        savedBank.tap()
        let savedNavigation = app.navigationBars["编辑银行"]
        XCTAssertTrue(savedNavigation.waitForExistence(timeout: 10))
        XCTAssertEqual(name.value as? String, discard ? originalName : correctedName)
        if discard {
            XCTAssertTrue(["", "备注（可选）"].contains(notes.value as? String ?? ""))
        } else {
            XCTAssertEqual(notes.value as? String, noteText)
        }
        XCTAssertFalse(error.exists)
        captureScreenshot("\(prefix)\(discard ? "放弃后原值读回" : "保存后读回")")
        if discard {
            let archived = app.switches["归档"]
            reveal(archived, fullyVisible: true, navigationBar: savedNavigation,
                   contentContainer: app.collectionViews["bank.editor.form"])
            XCTAssertEqual(archived.value as? String, "0")
        }
        savedNavigation.buttons["取消"].tap()
        XCTAssertTrue(savedNavigation.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons["放弃修改"].exists)
    }

    private func bankEditButtons(named name: String) -> XCUIElementQuery {
        // Native section headers capitalize their accessibility labels.
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", "编辑银行 \(name)"))
    }

    private func selectCardsTab() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let tabBar = app.tabBars.firstMatch
        let cards = tabBar.buttons["卡片"]
        XCTAssertTrue(cards.waitForExistence(timeout: 10))
        XCTAssertTrue(cards.isEnabled)
        XCTAssertTrue(cards.isHittable)
        XCTAssertTrue(tabBar.frame.contains(cards.frame))
        cards.tap()
        let selection = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: cards)
        XCTAssertEqual(XCTWaiter.wait(for: [selection], timeout: 10), .completed)
        XCTAssertTrue(app.navigationBars["卡片"].waitForExistence(timeout: 10))
    }

    private func openNewBankEditor(screenshot: String? = nil) {
        let navigationBar = app.navigationBars["卡片"]
        let management = navigationBar.buttons["卡片与银行管理"]
        XCTAssertTrue(management.waitForExistence(timeout: 10))
        let isHittable = management.isHittable
        if !isHittable { captureAccessibilityAuditContext("银行管理入口") }
        XCTAssertTrue(isHittable)
        assertTouchTarget(management)
        XCTAssertTrue(navigationBar.frame.contains(management.frame))
        if let screenshot { captureScreenshot(screenshot) }
        // A fixed toolbar action does not belong to the scrolling viewport.
        management.tap()
        tap(app.buttons["添加银行"])
    }

    private func verifyAccountEditorNumericKeyboard(largestText: Bool) {
        let prefix = largestText ? "最大字号" : ""
        launch("core")
        tap(app.tabBars.buttons["卡片"])
        let sharedAccount = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "尾号 1234", "尾号 5678"
        )).firstMatch
        tap(sharedAccount)
        let details = app.navigationBars["账户详情"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        tap(details.buttons["编辑"])
        let navigationBar = app.navigationBars["编辑信用卡账户"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let form = app.collectionViews["account.editor.form"]
        let limit = app.textFields["信用额度（可选）"]
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["account.keyboard.dismiss"]
        enter("0", into: limit)
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(limit.value as? String, "0")

        replaceText("125.50", in: limit)
        assertEditorNumericKeyboardInput(limit, navigationBar: navigationBar, form: form, dismissal: dismissal)
        captureScreenshot("\(prefix)账户额度键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(limit.value as? String, "125.50")
        XCTAssertTrue(navigationBar.exists)

        let notes = app.descendants(matching: .any).matching(identifier: "account.notes").firstMatch
        reveal(notes, fullyVisible: true, navigationBar: navigationBar, contentContainer: form)
        notes.tap()
        notes.typeText("UI keyboard note")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertFalse(dismissal.exists)
        navigationBar.buttons["保存"].tap()
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        openCard("UI Shared")
        tap(app.buttons["card.account"])
        let savedLimit = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "信用额度", "125.5 CNY"
        )).firstMatch
        reveal(savedLimit, scrollTowardTopWhenMissing: true, fullyVisible: true)
        captureScreenshot("\(prefix)账户额度保存读回")
    }

    private func verifyCardEditorNumericKeyboard(largestText: Bool) {
        let prefix = largestText ? "最大字号" : ""
        let editedName = "UI Keyboard Edited"
        launch("core")
        openCard("UI Primary")
        tap(app.navigationBars["卡片详情"].buttons["编辑"])
        let navigationBar = app.navigationBars["编辑卡片"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let form = app.collectionViews["card.editor.form"]
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["card.keyboard.dismiss"]
        let product = app.textFields["卡产品名称"]
        replaceText(editedName, in: product)
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertFalse(dismissal.exists)
        // The candidate bar is above the Keyboard AX frame, and the Form AX
        // frame can extend behind it. Begin the dismissal drag in the middle
        // of the content above the keys, clear of the candidate bar.
        let contentTop = max(navigationBar.frame.maxY, form.frame.minY)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let gutterX = form.frame.minX + form.frame.width * 0.03 - app.frame.minX
        let startY = (contentTop + keyboard.frame.minY) / 2 - app.frame.minY
        let endY = contentTop + 24 - app.frame.minY
        origin.withOffset(CGVector(dx: gutterX, dy: startY)).press(
            forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: gutterX, dy: endY)),
            withVelocity: .slow, thenHoldForDuration: 0.2
        )
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        let lastFour = app.textFields["末四位"]
        reveal(lastFour, navigationBar: navigationBar, contentContainer: form)
        lastFour.tap()
        let oldLastFour = lastFour.value as? String ?? ""
        lastFour.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldLastFour.count) + "0123")
        assertEditorNumericKeyboardInput(lastFour, navigationBar: navigationBar, form: form, dismissal: dismissal)
        captureScreenshot("\(prefix)卡片末四位键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lastFour.value as? String, "0123")
        XCTAssertTrue(navigationBar.exists)
        reveal(product, scrollTowardTopWhenMissing: true, navigationBar: navigationBar, contentContainer: form)
        XCTAssertEqual(product.value as? String, editedName)
        navigationBar.buttons["保存"].tap()
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["卡片"])
        let search = app.searchFields["搜索银行、卡片或末四位"]
        tap(search, scrollTowardTopWhenMissing: true)
        search.typeText("0123\n")
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "0123")
        let savedCard = app.buttons["card.\(editedName)"]
        reveal(savedCard, fullyVisible: true)
        XCTAssertTrue(savedCard.label.contains("0123"))
        XCTAssertTrue(savedCard.label.contains("Visa"))
        XCTAssertEqual(app.buttons.matching(identifier: "card.\(editedName)").count, 1)
        captureScreenshot("\(prefix)卡片末四位保存读回")
    }

    private func assertEditorNumericKeyboardInput(
        _ field: XCUIElement,
        navigationBar: XCUIElement,
        form: XCUIElement,
        dismissal: XCUIElement
    ) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        XCTAssertEqual(dismissal.label, "收起键盘")
        XCTAssertTrue(dismissal.isHittable)
        assertTouchTarget(dismissal)
        XCTAssertTrue(app.frame.contains(dismissal.frame))
        XCTAssertGreaterThanOrEqual(dismissal.frame.minY, navigationBar.frame.maxY)
        XCTAssertLessThanOrEqual(dismissal.frame.maxY, keyboard.frame.minY)
        XCTAssertFalse(field.frame.isEmpty)
        XCTAssertTrue(field.isHittable)
        XCTAssertGreaterThanOrEqual(field.frame.minY + 0.001, max(navigationBar.frame.maxY, form.frame.minY))
        XCTAssertLessThanOrEqual(field.frame.maxY, min(form.frame.maxY, dismissal.frame.minY, keyboard.frame.minY))
    }

    private func openOnboardingBillingStep() {
        launch("core")
        tap(app.tabBars.buttons["卡片"])
        tap(app.buttons["添加信用卡"])
        let bank = app.buttons["bank.cn.icbc"]
        reveal(bank, fullyVisible: true)
        bank.tap()
        XCTAssertTrue(app.staticTexts["设置账务规则"].waitForExistence(timeout: 10))
    }

    private func restartAndSearchOnboardingCard(_ name: String) -> XCUIElement {
        app.terminate()
        app.launch()
        selectCardsTab()
        let search = app.searchFields["搜索银行、卡片或末四位"]
        tap(search, scrollTowardTopWhenMissing: true)
        search.typeText(name + "\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, name)
        return app.buttons["card.\(name)"]
    }

    private func verifyOnboardingDiscardedCard(_ name: String, screenshot: String) {
        let saved = restartAndSearchOnboardingCard(name)
        XCTAssertFalse(saved.exists)
        let search = app.searchFields["搜索银行、卡片或末四位"]
        replaceText("UI Primary", in: search)
        search.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let original = app.buttons["card.UI Primary"]
        reveal(original, fullyVisible: true)
        XCTAssertTrue(original.label.contains("1234"))
        XCTAssertEqual(app.buttons.matching(identifier: "card.UI Primary").count, 1)
        captureScreenshot(screenshot)
    }

    private func verifyOnboardingCreditLimitFeedback(largestText: Bool) {
        let prefix = largestText ? "最大字号" : ""
        let cardName = "UI Limit"
        openOnboardingBillingStep()
        let navigation = app.navigationBars["添加信用卡"]
        let form = app.scrollViews["onboarding.form"]
        let advance = app.buttons["onboarding.advance"]
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["onboarding.keyboard.dismiss"]
        let limit = app.textFields["信用额度（可选）"]
        let error = app.staticTexts["onboarding.creditLimit.error"]
        enter("0", into: limit)
        XCTAssertFalse(error.exists)
        advance.tap()
        assertEditorFieldErrorVisible(limit, error: error, navigationBar: navigation, form: form)
        XCTAssertEqual(error.label, "错误：信用额度应为空，或填写大于 0 的数字。")
        XCTAssertTrue(app.staticTexts["设置账务规则"].exists)
        XCTAssertFalse(app.staticTexts["录入卡片"].exists)
        captureScreenshot("\(prefix)添加卡片额度首错定位")

        replaceText("125.50", in: limit)
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 5))
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertEqual(limit.value as? String, "125.50")
        captureScreenshot("\(prefix)添加卡片额度纠正后错误消失")
        advance.tap()
        XCTAssertTrue(app.staticTexts["录入卡片"].waitForExistence(timeout: 10))
        enter(cardName, into: app.textFields["卡产品名称"])
        enter("0123", into: app.textFields["末四位"])
        XCTAssertTrue(dismissal.waitForExistence(timeout: 5))
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        tap(app.buttons["上一步"])
        XCTAssertTrue(app.staticTexts["设置账务规则"].waitForExistence(timeout: 10))
        XCTAssertEqual(limit.value as? String, "125.50")
        XCTAssertFalse(error.exists)

        if largestText {
            navigation.buttons["取消"].tap()
            tap(app.buttons["放弃修改"])
            XCTAssertTrue(navigation.waitForNonExistence(timeout: 10))
            verifyOnboardingDiscardedCard(cardName, screenshot: "最大字号添加卡片额度放弃后原卡读回")
        } else {
            advance.tap()
            XCTAssertTrue(app.staticTexts["录入卡片"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.textFields["卡产品名称"].value as? String, cardName)
            XCTAssertEqual(app.textFields["末四位"].value as? String, "0123")
            advance.tap()
            XCTAssertTrue(navigation.waitForNonExistence(timeout: 10))
            let saved = restartAndSearchOnboardingCard(cardName)
            reveal(saved, fullyVisible: true)
            XCTAssertTrue(saved.label.contains("0123"))
            XCTAssertEqual(app.buttons.matching(identifier: "card.\(cardName)").count, 1)
            saved.tap()
            tap(app.buttons["card.account"])
            let savedLimit = app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@", "信用额度", "125.5 CNY"
            )).firstMatch
            reveal(savedLimit, scrollTowardTopWhenMissing: true, fullyVisible: true)
            captureScreenshot("添加卡片额度纠正后保存读回")
        }
    }

    private func verifyOnboardingCardIdentityFeedback(largestText: Bool) {
        let prefix = largestText ? "最大字号" : ""
        let cardName = "UI Wizard"
        openOnboardingBillingStep()
        let navigation = app.navigationBars["添加信用卡"]
        let form = app.scrollViews["onboarding.form"]
        let advance = app.buttons["onboarding.advance"]
        advance.tap()
        XCTAssertTrue(app.staticTexts["录入卡片"].waitForExistence(timeout: 10))
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["onboarding.keyboard.dismiss"]
        let product = app.textFields["卡产品名称"]
        let lastFour = app.textFields["末四位"]
        let productError = app.staticTexts["onboarding.productName.error"]
        let lastFourError = app.staticTexts["onboarding.lastFour.error"]
        let networkError = app.staticTexts["onboarding.customNetwork.error"]
        enter("123", into: lastFour)
        XCTAssertTrue(dismissal.waitForExistence(timeout: 5))
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        let other = app.buttons["其他"]
        reveal(other, fullyVisible: true, navigationBar: navigation, contentContainer: form)
        other.tap()
        XCTAssertFalse(productError.exists)
        XCTAssertFalse(lastFourError.exists)
        XCTAssertFalse(networkError.exists)
        advance.tap()
        assertEditorFieldErrorVisible(product, error: productError, navigationBar: navigation, form: form)
        XCTAssertEqual(productError.label, "错误：卡产品名称不能为空。")
        captureScreenshot("\(prefix)添加卡片产品名称首错定位")

        replaceText(cardName, in: product)
        XCTAssertTrue(productError.waitForNonExistence(timeout: 5))
        XCTAssertFalse(dismissal.exists)
        advance.tap()
        assertEditorFieldErrorVisible(lastFour, error: lastFourError, navigationBar: navigation, form: form)
        XCTAssertEqual(lastFour.value as? String, "123")
        XCTAssertEqual(lastFourError.label, "错误：末四位必须是 4 位数字。")
        captureScreenshot("\(prefix)添加卡片末四位首错定位")

        replaceText("0123", in: lastFour)
        XCTAssertTrue(lastFourError.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 5))
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        advance.tap()
        let network = app.textFields["卡组织名称"]
        assertEditorFieldErrorVisible(network, error: networkError, navigationBar: navigation, form: form)
        XCTAssertEqual(networkError.label, "错误：请填写卡组织名称。")
        captureScreenshot("\(prefix)添加卡片卡组织首错定位")
        replaceText("UI Net", in: network)
        XCTAssertTrue(networkError.waitForNonExistence(timeout: 5))
        XCTAssertFalse(productError.exists)
        XCTAssertFalse(lastFourError.exists)
        XCTAssertFalse(dismissal.exists)

        if largestText {
            navigation.buttons["取消"].tap()
            tap(app.buttons["放弃修改"])
            XCTAssertTrue(navigation.waitForNonExistence(timeout: 10))
            verifyOnboardingDiscardedCard(cardName, screenshot: "最大字号添加卡片纠错放弃后原卡读回")
        } else {
            advance.tap()
            XCTAssertTrue(navigation.waitForNonExistence(timeout: 10))
            let saved = restartAndSearchOnboardingCard(cardName)
            reveal(saved, fullyVisible: true)
            XCTAssertTrue(saved.label.contains("0123"))
            XCTAssertTrue(saved.label.contains("UI Net"))
            XCTAssertEqual(app.buttons.matching(identifier: "card.\(cardName)").count, 1)
            captureScreenshot("添加卡片纠错后保存读回")
        }
    }

    private func verifyCardOnboardingNumericKeyboard(largestText: Bool) {
        let prefix = largestText ? "最大字号" : ""
        let cardName = "UI Keyboard Card"
        launch("core")
        tap(app.tabBars.buttons["卡片"])
        tap(app.buttons["添加信用卡"])
        let bank = app.buttons["bank.cn.icbc"]
        reveal(bank, fullyVisible: true)
        bank.tap()
        XCTAssertTrue(app.staticTexts["设置账务规则"].waitForExistence(timeout: 10))

        let navigationBar = app.navigationBars["添加信用卡"]
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["onboarding.keyboard.dismiss"]
        let limit = app.textFields["信用额度（可选）"]
        enter("0", into: limit)
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(limit.value as? String, "0")
        XCTAssertTrue(app.staticTexts["设置账务规则"].exists)

        replaceText("125.50", in: limit)
        assertCardOnboardingKeyboardInput(limit)
        captureScreenshot("\(prefix)添加卡片额度键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(limit.value as? String, "125.50")
        XCTAssertTrue(navigationBar.exists)
        tap(app.buttons["onboarding.advance"])
        XCTAssertTrue(app.staticTexts["录入卡片"].waitForExistence(timeout: 10))
        tap(app.buttons["上一步"])
        XCTAssertTrue(app.staticTexts["设置账务规则"].waitForExistence(timeout: 10))
        XCTAssertEqual(limit.value as? String, "125.50")
        XCTAssertFalse(dismissal.exists)
        tap(app.buttons["onboarding.advance"])

        let productName = app.textFields["卡产品名称"]
        enter(cardName, into: productName)
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertFalse(dismissal.exists)
        let lastFour = app.textFields["末四位"]
        enter("0123", into: lastFour)
        assertCardOnboardingKeyboardInput(lastFour)
        captureScreenshot("\(prefix)添加卡片末四位键盘收起入口")
        dismissal.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismissal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lastFour.value as? String, "0123")
        XCTAssertEqual(productName.value as? String, cardName)
        XCTAssertTrue(navigationBar.exists)
        XCTAssertTrue(app.staticTexts["录入卡片"].exists)
        tap(app.buttons["onboarding.advance"])
        XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["卡片"])
        // Bank UUID ordering can put the saved card below several large rows.
        // Use the existing card search before checking the complete saved row.
        let search = app.searchFields["搜索银行、卡片或末四位"]
        tap(search, scrollTowardTopWhenMissing: true)
        search.typeText(cardName + "\n")
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, cardName)
        let savedCard = app.buttons["card.\(cardName)"]
        reveal(savedCard, fullyVisible: true)
        XCTAssertTrue(savedCard.label.contains("0123"))
        XCTAssertEqual(app.buttons.matching(identifier: "card.\(cardName)").count, 1)
        savedCard.tap()
        tap(app.buttons["card.account"])
        let savedLimit = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "信用额度", "125.5 CNY"
        )).firstMatch
        reveal(savedLimit, scrollTowardTopWhenMissing: true, fullyVisible: true)
        captureScreenshot("\(prefix)添加卡片保存读回")
    }

    private func assertCardOnboardingKeyboardInput(_ field: XCUIElement) {
        let navigationBar = app.navigationBars["添加信用卡"]
        let keyboard = app.keyboards.firstMatch
        let dismissal = app.buttons["onboarding.keyboard.dismiss"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        XCTAssertEqual(dismissal.label, "收起键盘")
        XCTAssertTrue(dismissal.isHittable)
        assertTouchTarget(dismissal)
        XCTAssertTrue(app.frame.contains(dismissal.frame))
        XCTAssertGreaterThanOrEqual(dismissal.frame.minY, navigationBar.frame.maxY)
        let footerTop = app.buttons["onboarding.advance"].frame.minY - 10
        XCTAssertFalse(field.frame.isEmpty)
        XCTAssertTrue(app.frame.contains(field.frame))
        XCTAssertGreaterThanOrEqual(field.frame.minY + 0.001, navigationBar.frame.maxY)
        XCTAssertLessThanOrEqual(field.frame.maxY, min(footerTop, dismissal.frame.minY, keyboard.frame.minY))
        XCTAssertTrue(field.isHittable)
    }

    private func allocationError(_ title: String) -> XCUIElement {
        app.staticTexts.matching(identifier: "allocation.error.\(title)").firstMatch
    }

    private func assertAllocationAmountOutsideContent(_ amount: XCUIElement) {
        guard amount.exists else { return }
        let frame = amount.frame
        let progress = app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch
        let top = max(app.navigationBars["添加交易"].frame.maxY, progress.frame.maxY)
        XCTAssertFalse(!frame.isEmpty && frame.minY + 0.001 >= top && frame.maxY <= contentBottom)
    }

    private func assertAllocationErrorVisible(_ title: String) {
        let error = allocationError(title)
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        let amount = app.textFields["allocation.amount.\(title)"]
        let progress = app.descendants(matching: .any).matching(identifier: "transaction.steps").firstMatch
        let top = max(app.navigationBars["添加交易"].frame.maxY, progress.frame.maxY)
        let form = app.descendants(matching: .any).matching(identifier: "transaction.form").firstMatch
        XCTAssertTrue(form.exists)
        let bottom = min(contentBottom, form.frame.maxY)
        for element in [amount, error] {
            let frame = element.frame
            XCTAssertFalse(frame.isEmpty)
            XCTAssertTrue(app.frame.contains(frame))
            XCTAssertGreaterThanOrEqual(frame.minY + 0.001, top)
            XCTAssertLessThanOrEqual(frame.maxY, bottom)
        }
        XCTAssertTrue(amount.isHittable)
    }

    private func captureAccessibilityAuditContext(_ name: String) {
        captureScreenshot("\(name)画面")
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "\(name)层级"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func auditAccessibility(for types: XCUIAccessibilityAuditType, captureFailureContext: Bool = false,
                                    verifiedClippedTexts: [XCUIElement] = []) throws {
        let original = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = original }
        try app.performAccessibilityAudit(for: types) { issue in
            let details = "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No associated element")"
            let attachment = XCTAttachment(string: details)
            attachment.name = "无障碍审计元素"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            if captureFailureContext { self.captureAccessibilityAuditContext("无障碍审计回调") }
            // iOS 18.5 reports clipping for this native placeholder even when it
            // is fully visible at both sizes (run 38068318067). Keep the report;
            // check actual scaling, screenshots and search interaction separately.
            if issue.auditType == .textClipped,
               let element = issue.element,
               element.elementType == .searchField,
               element.label == "搜索交易" {
                return true
            }
            // iOS 18.5 gives this literal a full-button frame and reports clipping
            // while its native element PNG contains all four glyphs (39635652351).
            // Only the largest dashboard checkpoint supplies these exact titles,
            // after checking each complete label, viewport and navigation. Keep
            // the raw report and original element PNG for final visual acceptance.
            if UIDevice.current.systemVersion == "18.5",
               issue.auditType == .textClipped,
               let element = issue.element,
               element.elementType == .staticText,
               element.label == "查看账期",
               !element.frame.isEmpty, self.app.frame.contains(element.frame),
               element.frame.minY + 0.001 >= self.app.navigationBars["CardPilot"].frame.maxY,
               element.frame.maxY <= self.contentBottom,
               verifiedClippedTexts.contains(where: {
                   $0.label == element.label && $0.frame == element.frame && $0.isHittable
               }) {
                let screenshot = XCTAttachment(screenshot: element.screenshot())
                screenshot.name = "iOS18.5账期审计报告对应文字原图"
                screenshot.lifetime = .keepAlways
                self.add(screenshot)
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
        let promotion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        // A partly visible large-text row can report a hit point at the tab
        // bar boundary. Reveal the whole row before asking XCTest to tap it.
        reveal(promotion, fullyVisible: true)
        promotion.tap()
    }

    private func openPromotionEditor(_ section: String) {
        let navigationBar = app.navigationBars.containing(.button, identifier: "promotion.edit").firstMatch
        let edit = navigationBar.buttons["promotion.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        // A valid native tap point alone did not open the dialog in run
        // 39768699985. Require foreground readiness and stable navigation
        // geometry before the single activation; keep the result assertion.
        var previousEditFrame = edit.frame
        var previousNavigationFrame = navigationBar.frame
        let entryReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard self.app.state == .runningForeground, navigationBar.exists, edit.exists else { return false }
            let frame = edit.frame
            let navigationFrame = navigationBar.frame
            defer {
                previousEditFrame = frame
                previousNavigationFrame = navigationFrame
            }
            return !frame.isEmpty && frame == previousEditFrame && navigationFrame == previousNavigationFrame
                && self.app.frame.contains(frame) && navigationFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
                && edit.isEnabled && edit.isHittable
        }, object: edit)
        XCTAssertEqual(XCTWaiter.wait(for: [entryReady], timeout: 10), .completed)
        assertTouchTarget(edit)
        edit.tap()
        let options = app.sheets["编辑促销"]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        let option = options.buttons["编辑\(section)"]
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        // Native dialog actions can have invalid AX activation points despite
        // visible frames. Select one stable, enabled action at its real center.
        // Seed with a real snapshot: starting at nil forces a failed first
        // poll whose native debug capture consumed the entire 10s budget in
        // run 39812907310 before a second stability check could run.
        var previousFrame = option.frame
        var selectionPoint: CGVector?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard option.exists else { return false }
            let frame = option.frame
            defer { previousFrame = frame }
            let applicationFrame = self.app.frame
            guard !frame.isEmpty && frame == previousFrame,
                  applicationFrame.contains(frame), options.frame.contains(frame),
                  option.isEnabled else { return false }
            selectionPoint = CGVector(dx: frame.midX - applicationFrame.minX,
                                      dy: frame.midY - applicationFrame.minY)
            return true
        }, object: option)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        guard let selectionPoint else {
            XCTFail("Expected a stable, enabled promotion edit action")
            return
        }
        app.coordinate(withNormalizedOffset: .zero).withOffset(selectionPoint).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: options)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
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
            if footer.exists {
                // The save button's AX frame excludes its 10pt outer padding
                // and the footer divider. The Form ends above that whole bar.
                let topInset: CGFloat = identifier == "saveTransaction" ? 11 : 0
                bottom = min(bottom, footer.frame.minY - topInset)
            }
        }
        return bottom
    }

    private func reveal(
        _ element: XCUIElement,
        scrollTowardTopWhenMissing: Bool = false,
        fullyVisible: Bool = false,
        navigationBar: XCUIElement? = nil,
        contentHeader: XCUIElement? = nil,
        contentContainer: XCUIElement? = nil
    ) {
        // A footer button's AX frame can start below the actual Form viewport.
        var visibleBottom: CGFloat {
            guard let contentContainer else { return contentBottom }
            return min(contentBottom, contentContainer.frame.maxY)
        }
        // SwiftUI can report a field behind the fixed footer as hittable.
        // Check its geometry as well; keep queries outside a polling predicate
        // because remote accessibility snapshots may take several seconds on CI.
        let geometryTolerance: CGFloat = 0.001
        var geometryDescription = "Element missing"
        for _ in 0..<8 {
            // Lazy Form rows disappear from the accessibility tree offscreen.
            // A known first-row control must be approached from the top.
            var targetIsAbove = scrollTowardTopWhenMissing
            var scrollDistance: CGFloat = 240
            let frame = app.frame
            var viewportBottom: CGFloat?
            var settlesAtDestination = false
            if element.exists || element.waitForExistence(timeout: 2) {
                let targetFrame = element.frame
                let needsUnobscuredFrame = fullyVisible || element.elementType == .textField
                var contentTop = needsUnobscuredFrame ? (navigationBar ?? app.navigationBars.firstMatch).frame.maxY : frame.minY + 110
                if needsUnobscuredFrame, let contentHeader, contentHeader.exists {
                    // The editor's fixed step summary also obscures scrolled rows.
                    contentTop = max(contentTop, contentHeader.frame.maxY)
                }
                var frameIsVisible = !targetFrame.isEmpty && targetFrame.intersects(frame)
                settlesAtDestination = needsUnobscuredFrame && frameIsVisible
                if needsUnobscuredFrame {
                    let bottom = visibleBottom
                    viewportBottom = bottom
                    geometryDescription = "minY=\(targetFrame.minY), top=\(contentTop), maxY=\(targetFrame.maxY), bottom=\(bottom)"
                    // A row can meet the bar at a subpixel AX rounding boundary.
                    frameIsVisible = frameIsVisible && targetFrame.minY + geometryTolerance >= contentTop && targetFrame.maxY < bottom
                }
                // Querying hittability for a footer-clipped text field can throw
                // an XCTest activation-point error before it can return false.
                // Establish usable geometry first, then ask XCTest for hit points.
                if frameIsVisible && element.isHittable { return }
                // After dismissing an editor, a previously visible row can be above
                // the viewport. Always swiping up would move it farther out of reach.
                targetIsAbove = !targetFrame.isEmpty && targetFrame.minY + geometryTolerance < contentTop
                if !targetFrame.isEmpty && needsUnobscuredFrame {
                    let bottom = viewportBottom ?? visibleBottom
                    viewportBottom = bottom
                    let obscuredDistance = targetIsAbove
                        ? contentTop - targetFrame.minY
                        : targetFrame.maxY - bottom
                    // Large fields can straddle the footer. A fixed drag would
                    // overshoot them and alternate above and below the viewport.
                    scrollDistance = min(240, max(60, obscuredDistance + 24))
                }
            }
            let startY = min(frame.maxY - 100, (viewportBottom ?? visibleBottom) - 25)
            let endY = max(frame.minY + 160, startY - scrollDistance)
            // Use the list gutter so a drag never begins on a promotion switch.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let dragStartY = targetIsAbove ? endY : startY
            let dragEndY = targetIsAbove ? startY : endY
            let start = origin.withOffset(CGVector(dx: frame.width * 0.03, dy: dragStartY - frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.width * 0.03, dy: dragEndY - frame.minY))
            if settlesAtDestination {
                // A partly visible tall row needs precise alignment without
                // inertia. Keep the existing coarse search for offscreen rows.
                start.press(forDuration: 0.05, thenDragTo: end,
                            withVelocity: .slow, thenHoldForDuration: 0.2)
            } else {
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        XCTFail("Expected an unobscured element: \(element). \(geometryDescription)")
    }
}
