**CardPilot 产品、UI 与 UX Review · 2026-09-05**

实施进度见 [首批实现记录](ui-ux-implementation-2026-09-05.md)；下文保留改动前的审查结论与基线行号。

审查基线：`624aebe`，项目版本 `0.1.4`。本次检查了根导航、首页、卡片、交易、促销、设置、提醒、应用锁、持久化及现有测试，并参考了 `PLAN.md`、`CONTEXT.md` 和 ADR。

总体判断：产品的核心价值清楚，账户与卡片分离、手动确认促销进度、本地优先都适合多卡用户。下一轮最值得投入的是保护用户已经输入的内容、让提醒状态可信、降低常用任务的操作成本，并建立更鲜明的信息层级。

当前环境是 Linux，没有 Xcode、Swift 或 iOS 模拟器，仓库没有界面截图。本报告属于代码与交互路径审查；没有执行 iOS 构建、XCTest、VoiceOver 或真机视觉验收。下面明确区分确定的实现问题、设计改进建议与待测风险。这里只检查了与使用体验有关的隐私和数据保护路径，不构成完整安全审计。

**值得保留的基础**

- 已有首次添加信用卡引导、无卡状态的行动入口，以及银行与卡片搜索。
- 交易记忆最近使用卡片，支持币种搜索、消费与退款、促销确认及冲正状态。
- 促销按系列组织，历史默认收起，支持复制到下个月和分期编辑。
- 首页“标记已还”已有撤销入口，删除关联数据有保护，保存失败有回滚。
- 大量使用系统文字样式和语义颜色，品牌色已有浅色、深色与增强对比度变体。这些是不错的基础，但组合后的可读性仍需检查。

**优先处理的六项问题**

P1 表示应优先于下一轮视觉打磨处理；P2 表示后续体验迭代。优先级针对用户影响，不代表每项都已在真机复现。

| 编号 | 优先级 | 问题 | 判断依据 |
| --- | --- | --- | --- |
| R01 | P1 | 开启应用锁后，切换应用会中断并丢失未保存表单 | 确定的状态清理路径，待真机复现 |
| R02 | P1 | 通知“安排至某日”无法表达真实覆盖范围 | 代码确认，并做了等价排序模拟 |
| R03 | P1 | 同银行多账户在还款操作与通知中难以区分 | 确定的显示字段缺失 |
| R04 | P1 | 适用卡为空显示“未限定”，与候选匹配语义不一致 | 确定的文案与逻辑矛盾 |
| R05 | P1 | VoiceOver 丢失账务日期，深色步骤数字对比度不足 | 代码确认与颜色计算 |
| R06 | P2 | 编辑页内的“撤销已还款”立即保存，取消编辑也无法取消该动作 | 确定的保存路径 |

**R01 · 保存填写进度，再处理应用锁**

典型场景：用户录入促销到第三步，切去银行 App 查条款，再回来解锁。`RootView` 锁定时用 `LockShield` 替换整个内容分支，并把卡片引导、交易编辑的展示状态清空；编辑器本身主要依赖局部 `@State`，没有草稿恢复机制。控制中心等触发的 `.inactive` 也会进入锁定判断。

建议把草稿和编辑会话放到不会随锁定视图销毁的状态层。锁屏遮住敏感内容并阻止交互，解锁后恢复原页面、步骤和输入；对于系统终止应用，再提供本地草稿恢复。主动取消或下滑关闭有修改的表单时，提供“保留草稿 / 放弃修改”。

验收：添加卡、录交易、编辑促销分别在中途切后台、锁屏、认证失败后重试；回来后内容和所处步骤都保留，锁定期间没有内容闪现。

证据：[根视图锁定分支](/home/maxduke/projects/card-pilot/CardPilot/App/RootView.swift:44)、[锁定时关闭编辑器](/home/maxduke/projects/card-pilot/CardPilot/App/RootView.swift:122)、[交易编辑状态](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:653)。

**R02 · 通知覆盖提示需要真实反映遗漏**

调度器先为每个账户挑选两类事件，再按账户轮流补充，只保存前 48 条。`lastScheduledDate` 取已安排通知的最大日期，但该日期之前可能还有未安排的通知，因此“通知仅安排至 X 日”容易被理解成 X 日前已经完整覆盖。

本次用 Python 等价模拟了选择顺序：10 个账户，账单日分别为 10–19 日，还款日为 20–29 日，提醒节点为提前 7、3、1 天及当天；在 2026-09-05 生成 9–12 月计划。结果安排 48 条，最晚为 9 月 22 日 09:00；但 9 月 18 日起已有遗漏，最晚日期之前共遗漏 13 条，其中 11 条为还款提醒。这是算法模拟，不是 iOS 通知实测。

另外，通知均为不重复的一次性请求，补充发生在应用活跃和配置变化时。用户长期不打开应用会耗尽已排计划；单纯再次打开，也不代表账户较多时所有近期遗漏都会补齐。

建议明确展示“下次提醒”和“最早未安排提醒”，以实际遗漏计算需要再次刷新计划的时间；优先确保近期还款事项，再处理账单日及重复提前提醒。可评估同日摘要以降低条数。后台补充只能作为改善，不能依赖它作出持续覆盖保证。还应串行处理通知重建，避免多个异步重建交错删除、添加请求。

验收：1、10、20 个账户以及大量自定义提醒节点；覆盖提示与待调度请求逐条一致；已还款后没有旧提醒被后续重建重新加入；加入重建失败与交错执行的测试。

证据：[48 条限制与重建](/home/maxduke/projects/card-pilot/CardPilot/Services/LocalNotificationScheduler.swift:19)、[选取顺序](/home/maxduke/projects/card-pilot/CardPilot/Services/LocalNotificationScheduler.swift:134)、[覆盖提示](/home/maxduke/projects/card-pilot/CardPilot/Services/LocalNotificationScheduler.swift:185)、[重建触发](/home/maxduke/projects/card-pilot/CardPilot/App/RootView.swift:140)。交错重建属于待测风险，本次未复现。

**R03 · 所有还款操作都必须能辨认具体账户**

首页待处理行主要展示银行名和账期，按钮的无障碍名称也是银行名加账期；通知的账户名称只传入银行名。同一家银行下有两个独立账户，尤其日期相同时，用户无法可靠判断应该标记哪一个。标记错误会停止该账期的还款提醒。

建议统一账户显示名称，例如“招商银行 · 日常账户 · 尾号 1234”，并在首页、撤销反馈、通知及通知跳转目的页保持一致。共用账户下多张卡不能被表现成多笔独立还款义务。可先复用卡片页现有末四位摘要，再考虑可编辑账户昵称。

验收：同银行、同账期、同还款日的两个独立账户，视觉和 VoiceOver 都能区分，撤销提示也能准确指出对象。

证据：[待处理行和还款按钮](/home/maxduke/projects/card-pilot/CardPilot/Features/Dashboard/DashboardView.swift:453)、[通知账户名](/home/maxduke/projects/card-pilot/CardPilot/App/RootView.swift:231)、[现有账户摘要](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:1012)。

**R04 · 空适用卡应显示“尚未选择”，并解释影响**

新建促销时，空适用卡显示“未限定适用卡”，保存摘要显示“未限定”，详情也延续该表述。但交易候选匹配和分配候选匹配都要求卡片属于 `eligibleCards`；空集合不会自动匹配任何卡。手动搜索和分配仍然允许，不应把这个问题解释为“完全无法使用”。

建议统一为“尚未选择适用卡”，辅以“本活动不会出现在自动推荐中，你仍可手动计入交易”，并提供“选择适用卡”。如果未来要支持“全部卡片”，应作为明确的资格设置重新设计，避免让空值同时表示未设置与全部适用。

验收：不选卡保存、选择一张卡、搜索手动计入、后续新增卡这四种场景，文案与候选行为一致。

证据：[编辑器摘要](/home/maxduke/projects/card-pilot/CardPilot/Features/Promotions/PromotionsView.swift:797)、[详情说明](/home/maxduke/projects/card-pilot/CardPilot/Features/Promotions/PromotionsView.swift:1663)、[交易候选](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:728)、[分配候选判断](/home/maxduke/projects/card-pilot/CardPilot/Domain/PromotionCalculator.swift:239)。

**R05 · 无障碍需要补齐内容与颜色组合**

账户行使用 `.accessibilityElement(children: .ignore)`，自定义标签只包含银行、账户、关闭状态和额度；屏幕上显示的账单规则、下次账单、下次还款及逾期情况没有进入标签。VoiceOver 用户因此缺少这条摘要最有价值的信息。

交易编辑器的步骤数字使用固定白色文字和品牌色背景。根据 Asset Catalog 的 sRGB 值计算，深色背景配白字对比度约为 **2.67:1**，深色增强对比度约为 **2.05:1**。这是指定颜色的计算结果，并非截图采样。建议定义成对的按钮背景与前景色，避免把用于深色界面链接文字的亮品牌色直接当成白字背景。本报告采用普通小文字 4.5:1 作为可读性验收参考，参见 [W3C Contrast Minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)。

金额输入固定 34 pt、步骤圆点固定 22×22，以及多处水平排列和单行截断也需要大字体验验证。优先使用随系统缩放的文字样式，大字时改为纵向排列；不要用缩小文字来维持原布局。Apple 的 [Dynamic Type 指南](https://developer.apple.com/videos/play/wwdc2024/10074/)提供了对应的字体与布局适配方法。

验收：VoiceOver 可读出账户日期和逾期状态；浅色、深色及增强对比度都检查文字与底色组合；最大辅助字号下金额、日期、动作仍可完整访问；主要动作以至少 44×44 pt 的可点击区域作为产品验收目标，实际区域须用检查器确认。

证据：[账户行无障碍覆盖](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:1001)、[步骤数字颜色](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:897)、[固定金额字号](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:927)、[品牌色定义](/home/maxduke/projects/card-pilot/CardPilot/Assets.xcassets/AccentColor.colorset/Contents.json)。

**R06 · 编辑页的“取消”应有一致含义**

账户编辑器中的“撤销已还款”直接修改记录并保存；用户随后点击导航栏“取消”，还款状态仍然已经改变。它与同页其他等待“保存”的字段具有不同提交时机，目前没有就地成功反馈或反向撤销入口。

建议把动作移到账期详情，执行后给出反馈与撤销；或者在当前编辑会话中暂存，到点击“保存”时统一提交。

验收：编辑其他字段并撤销已还款后取消，结果与界面承诺一致；若动作立即生效，操作前后都能清楚辨认，且可恢复。

证据：[动作所在编辑表单](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:1305)、[立即保存实现](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:1468)。

**R07 · P2：首次添加卡片应尽快产生可确认的结果**

当前引导固定四步。首张卡的“账户”步骤只是告知会创建账户；共用已有账户时，“账务规则”步骤也只是解释沿用规则。这些步骤可以按情境跳过。账单日和还款日从 1 开始，用 Stepper 输入 25 日等值需要多次递增，两个字段的成本会叠加。

建议默认采用“银行与卡片 → 账单与还款 → 确认结果”；只有同银行已有账户时才询问“这张卡与现有卡共用账单吗？”。日期使用可直接选择 1–31 日的控件，按天数规则支持数字输入。保存前展示最近一期真实计算结果，例如“本期账单 9 月 10 日，还款 9 月 28 日”。

引导还应确认当前账期是否已经处理。现在追踪从加入当月开始，没有还款记录且已过还款日就派生为逾期；已经在银行还过款的新用户仍会看到逾期。不要自动替用户判定已还，可以在结果页让其确认。

证据：[四步定义](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:414)、[账户步骤](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:632)、[日期输入](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:724)、[追踪起点](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:873)、[还款状态派生](/home/maxduke/projects/card-pilot/CardPilot/Domain/BillingCalculator.swift:129)。这是对现有产品流程的改进建议。

**R08 · P2：为普通记账减少无用步骤，保留促销确认**

当前所有新增和编辑交易都固定经过两步。即使没有任何促销，第一步仍是“继续确认促销”；而促销确认页没有完整重复卡片、金额、日期，用户核对交易本身需要返回。

建议在完全没有候选、已选活动或待补入账日活动时，允许“保存交易”，附近明确显示“本笔不计入活动”和手动选择入口。涉及促销时保留明确确认，顶部增加“卡片 · 金额 · 日期”摘要，活动行展示本次计入金额和保存后的进度预览。不能为了减少点击而默默保存自动勾选的分配。

入口默认聚焦金额；消费类型可紧凑放在金额附近，商户提供最近使用建议，“入账日期、分类、备注”渐进展示。保存后给出“已记录 128 CNY，计入 2 个活动”的反馈。错误显示在相关字段附近，并将焦点移到首个错误；目前多个编辑器把错误追加在表单底部。

证据：[固定两步操作](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:794)、[第一步字段](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:911)、[确认页](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:994)、[保存后直接关闭](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:1470)。两步确认是现有计划中的明确选择，本项是针对无活动情形的流程调整建议。

**R09 · P2：促销页应围绕“还差多少、用哪张卡、下一步做什么”**

目前列表有进度、状态和报名标记，但奖励说明在详情较后面。只修改报名状态也需要进入三步编辑器。详情的“添加第一笔分配”在没有交易时进入一个仅提示“请先添加交易”的表单，缺少接续动作。

建议活动卡片优先展示标题、奖励摘要、还差金额或剩余优惠笔数、剩余天数和适用卡。详情提供“记录消费”和“计入已有交易”两个入口，前者预填当前活动；待报名时提供“标记已报名”。外部报名需有用户录入的真实活动链接，不能把本地状态修改说成已经完成银行报名。

普通累计活动的默认勾选目前不检查报名状态和叠加冲突；界面确实有警告，但可能位于较长列表底部。建议把这类活动置于“需要确认”，默认不勾选或就地要求确认，并把冲突数量置于提交按钮附近。继续允许用户明确覆盖警告，保留已有手动分配事实。

规则表单可用简短例子区分“累计满多少才达标”“最多多少参与计算”“每笔至少多少”；将“促销分配”改为面向用户的“计入活动的交易”，将“高置信候选”改为“根据卡片和日期找到的活动”。

证据：[详情结构](/home/maxduke/projects/card-pilot/CardPilot/Features/Promotions/PromotionsView.swift:1533)、[无交易时仅提示](/home/maxduke/projects/card-pilot/CardPilot/Features/Promotions/PromotionsView.swift:2010)、[自动勾选条件](/home/maxduke/projects/card-pilot/CardPilot/Domain/PromotionCalculator.swift:183)、[现有冲突警告](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:1126)。

**R10 · P2：记账操作应从当前页面直接弹出**

当前底部“记一笔”实际是一个 `Color.clear` Tab。点击后先选择交易 Tab，再展示编辑器，关闭时恢复原 Tab。代码明确引入了页面切换；是否出现短暂闪动、返回时是否丢滚动位置，需要运行验证。

建议四个稳定页面：首页、卡片、促销、交易；记账作为独立可达操作，由根视图直接呈现编辑器，保留当前导航上下文。若继续保留中央突出按钮，它应当具有按钮语义并直接触发操作。Apple 的 [Tab bars 指南](https://developer.apple.com/design/human-interface-guidelines/tab-bars)把 Tab 用于顶层导航。当前中央入口是 `PLAN.md` 的产品选择，本项不是“没按计划实现”的缺陷。

验收：从首页、促销详情、交易筛选结果分别打开并关闭记账，原来的页面、滚动位置和筛选都保持；VoiceOver 不会选中一个空页面。

证据：[空 Tab 与切换逻辑](/home/maxduke/projects/card-pilot/CardPilot/App/RootView.swift:65)。

**R11 · P2：首页突出时间与行动，减少用户自行计算**

已有“待处理 / 继续完成 / 账户日程”是合理起点，但待处理里还款与报名分别追加；日期主要使用完整年月日，促销剩余金额和结束日期多为小字。用户需要自己计算还有几天、哪个动作最急。

建议首屏先给出“今天 1 项 · 未来 7 天 3 项”这类基于真实事项的摘要。待办按逾期、今天、近日排序；同时显示“明天到期 · 9 月 6 日”，每项只有一个主要动作。账户日程放在后面，支持查看已处理记录，避免已还款事项消失后难以查证。

“继续完成”当前有意排除只有累计计入上限、没有达标门槛的促销。若要帮助用户使用剩余额度，可以新增“仍可使用的优惠”，显示“还可计入 800 CNY”；不要把上限改称达标目标，也不要只为更丰富的首页捏造还款总额或累计收益。

证据：[首页排序结构](/home/maxduke/projects/card-pilot/CardPilot/Features/Dashboard/DashboardView.swift:57)、[继续完成筛选](/home/maxduke/projects/card-pilot/CardPilot/Features/Dashboard/DashboardView.swift:278)、[日期与动作](/home/maxduke/projects/card-pilot/CardPilot/Features/Dashboard/DashboardView.swift:458)。

**R12 · P2：卡片页增加日常查看层，降低账户配置的存在感**

现在银行分组下展开账户行及卡片行，账户摘要包含多行规则和日期；点击账户或卡片都直接打开编辑表单。对于 10–20 张卡，列表容易偏向配置管理，用户不能从卡片自然进入其交易和活动。

建议卡片列表突出“银行 / 卡名 / 末四位 / 下次还款”，账户规则放到详情。点击打开只读卡片详情，提供“记一笔、查看交易、适用活动、账单日程”，编辑作为次级动作。共享账户关系仍需清楚展示，避免重复还款。

账户详情把“单期日期覆盖”改成“调整本期日期”，把长期变更入口改为“修改以后的账单规则”；底层保留现有规则版本模型。对于未来已经排定的规则，展示其生效月份及当前生效规则，避免用户把最新未来版本误当成当前配置。

证据：[银行、账户、卡片展开列表](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:44)、[点击直接编辑](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:998)、[编辑器采用最新规则](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:1208)、[日期覆盖表单](/home/maxduke/projects/card-pilot/CardPilot/Features/Cards/CardsView.swift:1287)。

**R13 · P2：把通知设置做成可理解、可检查的完整流程**

目前通知授权操作位于设置页，首页在尚未授权时显示提示。建议在首次添加账户并确认日期后，提供“开启还款提醒”，同时预览下一次提醒的日期和时间；这种上下文请求也符合 Apple 的[通知授权建议](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)。拒绝后继续提供日期管理，用户需要时可以再次进入系统设置。

账单与还款默认各有 4 个节点。10 个账户的完整单月配置可能产生 80 条通知，既增加打扰也消耗调度窗口。提醒编辑器至少要求保留一个节点，缺少单独关闭账单提醒、只保留还款提醒的选项。建议提供“仅还款 / 账单与还款”预设及类别开关，再按使用反馈调整默认节点。

设置中增加下一次实际已安排提醒、覆盖状态和用户主动触发的测试提醒。实现通知到具体账户账期的跳转，认证后恢复目标；目前只有桌面快捷操作路由，未发现通知响应代理。促销报名和到期目前是首页信息，调度器只安排账单与还款，应在用户文案中区分，或另行设计活动提醒。

证据：[授权入口](/home/maxduke/projects/card-pilot/CardPilot/Features/Settings/SettingsView.swift:153)、[至少保留一个节点](/home/maxduke/projects/card-pilot/CardPilot/Features/Settings/SettingsView.swift:274)、[通知事件类型](/home/maxduke/projects/card-pilot/CardPilot/Services/LocalNotificationScheduler.swift:177)、[当前快捷操作路由](/home/maxduke/projects/card-pilot/CardPilot/App/CardPilotApp.swift:6)。

**R14 · P2：视觉打磨优先统一层级、字重与组件**

建议维持现有克制的原生风格，以珊瑚色作为操作强调色；业务风险使用图标和文字共同表达。当前进行中活动用绿色徽标，达标也使用绿色；可把进行中降为中性，让完成状态更突出。首页多种毛玻璃卡片与其他页的分组列表需要在真机上检查背景、边框和留白是否连贯，不能仅凭代码断言观感好坏。

建议建立统一的账户身份摘要、活动进度摘要、状态标签、字段错误、空状态、底部主动作和保存反馈组件。间距可先约束为 4/8/12/16/24，容器圆角采用少量层级，再按真实页面调整。数字对齐使用等宽数字，不必让所有标签都等宽。

日期按场景格式化：列表用“9 月 5 日”，临近节点用“明天 · 9 月 6 日”，跨年或详情再展示年份。当前完整日期范围与主办方挤在同一行并截断，值得优先调整。金额保留明确币种，跨币种并列时不能只显示 ¥ 或 $。

交易和促销空状态增加就地“记录第一笔 / 添加活动”按钮。首页、卡片引导、交易编辑与促销编辑统一主动作位置、返回方式和错误呈现；轻触反馈只用于成功保存、还款完成等重要结果。

证据：[完整日期格式](/home/maxduke/projects/card-pilot/CardPilot/Features/Shared/Formatting.swift:361)、[活动列表单行日期](/home/maxduke/projects/card-pilot/CardPilot/Features/Promotions/PromotionsView.swift:377)、[通用空状态无动作](/home/maxduke/projects/card-pilot/CardPilot/Features/Shared/Formatting.swift:428)、[活动状态色](/home/maxduke/projects/card-pilot/CardPilot/Features/Promotions/PromotionsView.swift:436)。所有间距、密度和动效建议均需视觉验证。

**R15 · P2，真实用户发布前提高优先级：本地数据要可恢复**

设置页没有应用内导出、导入和恢复入口；本地容器创建失败会 `fatalError`。对于持续手动录入的产品，这意味着用户投入越多，越需要清晰的数据可携带性和故障恢复路径。

建议先支持完整备份导出与恢复，包含版本信息、账户、卡片、日期规则、促销系列、交易和分配关系；另提供便于查看的交易 CSV。导入前预览数量和冲突，恢复失败不得破坏已有数据。启动存储失败展示可操作的恢复界面，保留原文件。

ADR 明确允许预发布测试阶段切换存储身份，且不主动删除旧文件；这是已知的阶段性决定，本次没有发现代码在升级时主动清空正式用户数据。转向真实长期使用前，应制定版本迁移与恢复验收。应用内备份缺失也不等于 iOS 系统备份一定不包含数据，系统行为本次未验证。

证据：[设置页范围](/home/maxduke/projects/card-pilot/CardPilot/Features/Settings/SettingsView.swift:20)、[启动失败路径](/home/maxduke/projects/card-pilot/CardPilot/App/CardPilotApp.swift:113)、[当前持久化配置](/home/maxduke/projects/card-pilot/CardPilot/Domain/Models.swift:795)、[预发布存储决定](/home/maxduke/projects/card-pilot/docs/adr/0009-reset-prerelease-store-for-schema-redesign.md)。

**R16 · P2：数据量增长的性能风险应先测量，再优化**

首页的 `billingItems` 在多处计算属性中反复生成，每个账户都会从追踪起始月遍历到未来两个月，并查找历史记录。交易页全量读取交易，分组结果又在列表构建时反复访问。促销分组、进度计算和候选筛选也有多次遍历；格式化金额每次创建 `NumberFormatter`。这些是代码中的成本来源，本次没有测得卡顿或内存峰值。

建议每次更新只生成一份页面展示数据，对账户账期、交易日期分组和促销进度建立可正确失效的索引或缓存，长交易列表再评估按月查询。重构不能删除历史未还账期或破坏退款回落等业务语义。为“今天”提供明确刷新时机，检查常用时区跨午夜、后台跨日返回时的状态是否及时更新。

用 20 张卡、数年账期、数千笔交易和较多循环活动做 Release 配置测量，记录首屏、搜索、保存后进度更新及内存。将 1600–2200 行的 feature 文件按页面、编辑器和计算逻辑拆分，有助于保持多入口交互一致；文件长度本身不作为性能证据。

证据：[首页反复派生账务事项](/home/maxduke/projects/card-pilot/CardPilot/Features/Dashboard/DashboardView.swift:164)、[交易分组访问](/home/maxduke/projects/card-pilot/CardPilot/Features/Transactions/TransactionsView.swift:67)、[活动分组](/home/maxduke/projects/card-pilot/CardPilot/Features/Promotions/PromotionsView.swift:270)、[金额格式化](/home/maxduke/projects/card-pilot/CardPilot/Features/Shared/Formatting.swift:375)。

**R17 · P2：把核心体验放进自动化与真机验收**

仓库中有 74 个以 `test` 命名的单元测试方法，包含账务日期、退款、活动系列、筛选、通知计划和快捷操作等；本次没有运行。`CardPilotUITests` 目录为空，共享 scheme 只列出单元测试 target。因此现有代码和 CI 配置不能证明关键 UI 流程、大字号、键盘与锁屏恢复已经通过。

建议优先补充少量完整流程测试：首次添加卡、保存交易并确认促销进度、标记已还并撤销、编辑中锁屏后恢复、通知到目标账期。对通知调度增加可替换客户端，用确定性的失败和交错执行测试验证最终请求集合。视觉基线覆盖关键页面及最易出错状态，避免只截图无数据的首页。

证据：[测试目录](/home/maxduke/projects/card-pilot/CardPilotTests)、[共享 scheme](/home/maxduke/projects/card-pilot/CardPilot.xcodeproj/xcshareddata/xcschemes/CardPilot.xcscheme)、[当前 CI](/home/maxduke/projects/card-pilot/.github/workflows/ios.yml)。

**建议的页面职责**

| 页面 | 第一眼应回答 | 主要内容与动作 |
| --- | --- | --- |
| 首页 | 我现在有什么需要处理？ | 今天/近日待办、明确账户、相对日期、标记已还、活动下一步 |
| 卡片 | 我有哪些卡，这张卡关联什么？ | 清晰身份、共享账户关系、下次还款、卡片详情及交易/活动入口 |
| 记账 | 花了多少，哪张卡，计入哪些活动？ | 金额优先、最近卡片、简洁日期、必要时确认分配、保存反馈 |
| 促销 | 还差多少，剩几天，用哪张卡？ | 奖励摘要、进度、适用卡、报名与记录交易入口、收起历史 |
| 设置 | 提醒和数据是否在我的控制之下？ | 提醒预览及覆盖、类别开关、应用锁、备份恢复 |

**建议实施顺序**

| 批次 | 范围 | 完成标准 |
| --- | --- | --- |
| 第一批：可信与可恢复 | R01–R06，加入对应回归测试 | 输入不中断丢失、账户不会混淆、提醒覆盖准确、无障碍关键内容可达、取消语义清楚 |
| 第二批：缩短核心任务 | R07–R13 | 首次建卡、日常记账、报名状态更新和活动补录可以顺畅完成 |
| 第三批：统一质感与长期使用 | R14–R17；备份在真实用户发布前完成 | 多状态视觉一致，Release 性能数据可接受，有恢复和 UI 验收证据 |

**真机与用户测试矩阵**

下列时间指标是拟定的产品目标，尚未测量，也不作为已经达到的成绩。

| 场景 | 验收重点 |
| --- | --- |
| 首次添加一张卡 | 熟悉卡片信息的用户争取在 60 秒内完成，能看懂最近一次还款日期 |
| 日常记录一笔无活动消费 | 从入口到保存争取在 10 秒内完成，无无效确认步骤 |
| 一笔交易计入两个活动 | 能看懂各自计入金额、冲突、保存后的进度变化 |
| 活动没有适用卡、没有交易 | 不误解为自动适用所有卡，能从空状态继续完成任务 |
| 同银行两个独立账户 | 不依赖列表位置或猜测即可选对还款对象 |
| 退款、冲正、撤销还款 | 进度和提醒正确更新，结果有解释、可追溯 |
| 编辑中查银行 App、控制中心、锁屏 | 内容保留，认证后回到原步骤 |
| 通知拒绝、超出调度窗口、长期不打开 | 提示与真实请求一致，不给出不存在的覆盖承诺 |
| 最小支持屏幕与最大辅助字号 | 金额、日期、底部动作可达；键盘不妨碍完成任务 |
| 浅色、深色、增强对比度、VoiceOver | 可读内容一致，风险不只靠颜色表达 |
| 常用时区跨午夜、旅行时区变化 | 业务日期与提醒保持预期，过期/临近状态及时更新 |
| 20 张卡和数千笔交易 | Release 下实测首屏、搜索、保存和滚动；依据测量处理瓶颈 |

本次交付仅新增审查报告，没有修改应用行为。后续视觉验收需要在 iOS 模拟器或真机上完成，尤其是字体截断、按钮实际点击区域、键盘遮挡、导航动画和锁屏恢复。
