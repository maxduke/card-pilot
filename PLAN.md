# CardPilot 首版实施计划

## 目标与边界

构建一个 iPhone、iOS 17+ 的简体中文原生应用，使用 SwiftUI、SwiftData 和本地通知管理信用卡账户、卡片、账务日期、促销及手动促销分配。数据只保存在设备本地，不创建账号、后端或 CloudKit 容器。

首版只结构化计算累计消费促销。最低单笔、交易笔数、阶梯、周期上限和奖励金额计算保留为文字规则，由用户填写促销分配来反映银行最终认可的金额。

明确不做：银行接入、交易同步、短信/邮件解析、OCR、AI 提取、多用户、服务端、复杂财务分析、奖励到账追踪、复杂促销叠加策略、部分还款和独立共享额度关系。

## 实现原则

- `CONTEXT.md` 是领域语言的唯一来源，ADR 是已接受的高成本决策来源。
- 业务日期使用不含时分秒的 `LocalDate`；完成时间、归档时间等事件才使用 `Date`。
- 金额使用 `Decimal` 和 ISO 4217 币种代码，禁止 `Double` 参与金额计算。
- SwiftData 只负责持久化；日期和进度算法写成无 UI、无数据库依赖的纯 Swift 代码。
- 不增加第三方依赖、Repository 层、通用规则引擎或网络抽象。
- 所有持久化对象使用稳定 UUID；使用 SwiftData `VersionedSchema`，首版不添加空迁移。
- `ModelConfiguration(cloudKitDatabase: .none)` 明确关闭 CloudKit。
- 关系显式声明 inverse；历史对象之间使用本地 SwiftData `deny` 删除规则，并在 UI 写入路径再次验证，不依赖级联删除。
- 不创建完整卡号、CVV、银行登录凭据或对应输入框；日志不得输出金融字段。

## 最小项目结构

```text
CardPilot.xcodeproj
CardPilot/
  App/
    CardPilotApp.swift
    RootView.swift
  Domain/
    Models.swift
    LocalDate.swift
    BillingCalculator.swift
    PromotionCalculator.swift
  Services/
    NotificationScheduler.swift
    AppLockController.swift
  Features/
    Dashboard/DashboardView.swift
    Cards/CardsView.swift
    Promotions/PromotionsView.swift
    Transactions/TransactionsView.swift
    Settings/SettingsView.swift
  Resources/
    Localizable.xcstrings
CardPilotTests/
  BillingCalculatorTests.swift
  PromotionCalculatorTests.swift
  PersistenceTests.swift
  NotificationSchedulerTests.swift
  AppLockControllerTests.swift
CardPilotUITests/
  CoreFlowsUITests.swift
```

每个 feature 首先保持为一个视图文件，表单或子视图只有在文件明显难以阅读时再拆分。

## 持久化模型

### 参考与信用卡

| 模型 | 关键字段与关系 | 约束 |
|---|---|---|
| `Bank` | `id`, `name`, `notes`, `archivedAt` | 名称必填；有引用后只能归档；名称是当前规范显示名 |
| `CardNetwork` | `id`, 稳定 `code`, `displayName`, `isBuiltIn` | 预置银联、Visa、Mastercard、Amex、JCB；“其他”在选择器内创建，不做独立管理页 |
| `CreditCardAccount` | `id`, `bank`, `trackingStartCycleKey`, `creditLimit`, `limitCurrencyCode`, `status`, `closedOn`, `notes` | 追踪起始账期必须是有效 `YYYYMM`，新账户默认加入当月且首版不可编辑；额度可空，填写时必须大于零；active 必须无关闭日期，closed 必须有关闭日期，关闭动作原子更新两者 |
| `Card` | `id`, `account`, `productName`, `nickname`, `network`, `lastFour`, `status`, `notes` | 末四位严格为四位数字；停用卡保留历史并可显式选择 |

一个账户可以有多张卡；共享额度、账单日和还款日的卡放在同一账户，各自独立的卡使用不同账户。首版不拆出 `CreditLine`，因此不支持“共用额度但账单规则不同”。

编辑银行名称表示纠错或更新当前规范名称，所有引用统一显示新名称；归档保证历史关系和银行身份不丢失，但首版不保存名称版本快照。

### 账务规则与账期状态

| 模型 | 关键字段与关系 | 约束 |
|---|---|---|
| `BillingRuleVersion` | `id`, `account`, 可选 `effectiveCycleKey`, `statementDay`, `repaymentKind`, `repaymentValue` | 每个账户恰有一个无生效下界的基线版本；后续版本按生效账期排序；账单日和固定还款日为 1...31；“N 天后”要求 N ≥ 1 |
| `BillingCycleRecord` | `id`, `account`, `cycleKey`, `statementDateOverride`, `repaymentDateOverride`, `repaidAt` | 稀疏保存：只有发生覆盖或还款完成时才建记录；每账户每账期最多一条 |

`cycleKey` 是名义账单月份 `YYYYMM`，即使本期覆盖日期跨月也不改变。账户从追踪起始账期到当前日期后两个月生成 Dashboard 账期，并合并明确保存的未还账期，避免无限历史和旧未还账期消失；追踪起始账期之前的普通未持久化账期首版不生成。基线规则用于首个有日期版本之前的账期，保证月中首次录入时仍能计算当前待还事项；未持久化的账期由规则即时计算。已保存的规则版本不得原地改写或删除已生效历史，银行变更必须新增仅从未来账期生效的版本，当前或历史个别纠错使用账期覆盖。

每个账户恰有一个 `effectiveCycleKey == nil` 的基线版本；新增或删除规则版本时先查询验证。`BillingCycleRecord` 和 `PromotionAllocation` 的复合唯一性同样由保存前查询与单元测试保证；SwiftData/iOS 17 不为此引入额外兼容层。

### 促销

| 模型 | 关键字段与关系 | 约束 |
|---|---|---|
| `Promotion` | `id`, `title`, `startOn`, `endOn`, `organizingBanks`, `organizingNetworks`, `eligibleCards`, `enrollmentStatus`, `enrolledOn`, `enrollmentDeadline`, `qualificationDateBasis`, `stackingAllowed`, `targetAmount`, `progressCurrencyCode`, `rules`, `exclusions`, `rewardDescription`, `notes`, `archivedAt` | 起止日包含边界；目标金额大于零；主办方或适用卡可以暂时为空，但为空时不会产生候选交易 |
| `PromotionAllocation` | `id`, `transaction`, `promotion`, `qualifyingAmount`, `currencyCode` | 金额为记录时促销进度币种下的非负数；每个“交易 × 促销”最多一条；币种必须与促销一致 |

银行主办方与卡组织主办方分别使用结构化关系，并与具体适用卡列表完全独立。归档促销退出推荐和 Dashboard，但可以显式打开并修正或补录历史分配。

促销已有任何分配后，`progressCurrencyCode` 不可修改；无分配时可修改。分配同时保存币种快照并在计算时验证一致，禁止把既有数字静默解释成另一币种。

报名状态约束：不需要报名或尚未报名时 `enrolledOn` 为空；已报名时日期可选；报名截止日只允许出现在需要报名的促销上。

### 交易

| 模型 | 关键字段与关系 | 约束 |
|---|---|---|
| `Transaction` | `id`, `card`, `kind`, `transactionOn`, `postingOn`, `amount`, `currencyCode`, `merchant`, `category`, `notes`, `originalTransaction`, `status` | 金额始终大于零；`kind` 区分消费与退款；退款只能关联同一卡片的消费；冲正保留记录 |

删除交易只用于纠正误录：存在促销分配时先移除分配，存在关联退款时先删除退款或解除关联。不得隐式级联删除历史事实。

关系删除规则写死为：Bank 被账户或促销主办方引用时 `deny`；Account 被卡片引用时 `deny`，账户拥有的规则版本和账期记录使用 `cascade`；Card 被交易或促销适用卡引用时 `deny`；Promotion 和 Transaction 被分配引用时 `deny`；原消费被退款引用时 `deny`。所有写入在主 actor 的单个 `ModelContext` 中完成，UI 检查负责解释原因，SwiftData `deny` 负责最后防线，账户内部记录随账户级联删除。

### 设置

以下个人设备设置使用 `AppStorage`，不进入 SwiftData：

- 账单提醒提前天数，默认 `[7, 3, 1, 0]`；
- 还款提醒提前天数，默认 `[7, 3, 1, 0]`；
- 全局提醒时刻，默认 09:00；
- 常用时区，首次启动取当前系统时区，之后不随旅行自动变化；
- 应用锁是否启用。

## 纯领域计算

### `LocalDate`

- 以 `YYYYMMDD` 整数作为可排序持久化表示，以 `YYYYMM` 表示账期键。
- 所有日历运算显式使用 Gregorian Calendar 和常用时区。
- 提供比较、月份加减、自然日加减、月末日数和 `DateComponents` 转换。
- 修改常用时区只重新安排通知，不改变已存自然日期。

### `BillingCalculator`

输入账户、规则版本、可选账期记录和“今天”，输出一个不可变 `BillingCycle` 值：

1. 按 `cycleKey` 选择最后一个已生效的规则版本。
2. 账单名义日不存在时取月末；后续月份恢复名义日。
3. 应用本期账单日覆盖。
4. 固定日还款先在账单所在月把指定日解析为名义日或月末；只有结果严格晚于账单日才使用，否则到下个月重新解析。例如账单日为 2 月 28 日、固定还款日为 31 日时，本月解析结果相等，因此还款日为 3 月 31 日。
5. “N 天后”使用自然日，账单日当天不计入 N，不调整周末或节假日。
6. 基于覆盖后的账单日计算还款日，再应用本期还款日覆盖。
7. 有 `repaidAt` 为已还款；否则按还款日与今天派生待还或逾期。
8. 关闭日期后的账期不生成；关闭前已有待还账期继续存在。

计算器不根据交易日期或入账日期推断交易所属账期。

### `PromotionCalculator`

- 消费分配贡献 `+qualifyingAmount`；退款分配贡献 `-qualifyingAmount`；已冲正交易贡献 `0`。
- 进度为全部贡献的真实净合计，不在目标处封顶。
- 发现分配币种与促销进度币种不一致时返回数据错误，不参与静默汇总。
- 剩余金额为 `max(target - progress, 0)`；达标状态每次动态派生。
- 同币种消费勾选促销时默认填交易总额；跨币种必须由用户填写促销币种金额，不保存汇率。
- 退款关联原消费时预选原交易涉及的促销，用户确认每项扣减金额。
- 退款只能关联同一卡片的消费；同币种累计退款超过原消费、或退款分配超过原促销分配余额时显示强警告但允许用户确认，跨币种不做数值上限推断。
- 卡片、日期、报名或不可叠加冲突只产生警告，不阻止保存。

### 候选促销

- 卡片必须在具体适用卡列表内，促销不得已归档。
- `transactionDate`：交易日期位于包含边界的促销期内。
- `postingDate`：有入账日期且该日期位于促销期内；缺少入账日期时显示“需补入账日期”，不自动分配。
- `unknown`：交易日期或已有入账日期任一符合即可。
- 候选列表之外仍提供搜索入口；手动促销分配始终是进度事实来源。

## 页面与交互

### 根导航

使用一个 `TabView`，顺序固定为：首页、卡片、促销、交易。设置由首页右上角按钮以 sheet 或导航页打开，不占主 Tab。

### 首页

按行动优先级显示：

1. 已逾期且未完成的还款；
2. 所有账户尚未完成的下一还款事项，包括关闭前产生的账期；
3. 各未关闭账户下一次账单日；
4. 需要报名且临近报名截止日的促销；
5. 七个自然日内结束且尚未达标的促销；七天是首版集中定义、可直接修改但不暴露设置的默认阈值；
6. 活跃促销进度。

不创建“需要关注的卡片”布尔字段或重复区域；每个项目直接展示原因和动作。还款项目可直接标记已还款，促销项目可进入详情或记录交易。

### 卡片

- 账户列表显示银行、额度、下一账单日、下一还款日和账户下卡片。
- 银行管理从卡片页工具栏进入，提供创建、编辑、归档和无引用删除。
- 账户表单同时录入初始账务规则；规则变更要求选择首个受影响账期并新增版本。
- 账户详情管理卡片、账期日期覆盖、还款完成记录、关闭账户。
- 账户追踪起始账期默认加入当月，首版不可编辑；Dashboard 从该账期生成至当前日期后两个月，并合并保存的未还账期。
- 默认隐藏停用卡；“显示停用卡”可用于历史交易录入。

### 促销

- 活跃、即将开始、已结束、已归档分段筛选。
- 表单包含多个银行/卡组织主办方、具体适用卡、报名信息、资格日期依据、叠加开关、累计目标和说明字段。
- 详情显示真实进度、剩余金额、全部分配和规则说明。
- 有分配时只能归档；归档详情仍允许修正或补录分配。

### 交易

- 默认按交易日期倒序；提供卡片、商户和分类的轻量筛选。
- 交易表单选择卡片后默认账户额度币种，并列出候选促销。
- 可一次勾选多个促销；同币种默认全额，金额可内联修改；最近使用的分类提供自动补全。
- 非候选促销仍可搜索选择；所有冲突以明确警告显示但允许确认保存。
- 退款从原交易发起时自动建立关联并预选原促销；冲正是原交易动作，不是删除。

### 设置

- 账单与还款提醒提前量；
- 全局提醒时刻和常用时区；
- 通知权限状态与跳转系统设置；
- 应用锁开关；
- 关于与隐私说明，明确“不保存完整卡号或 CVV”。

## 本地通知

实现一个 `NotificationScheduler` 和可替换的最小 `NotificationClient` 协议，生产实现包装 `UNUserNotificationCenter`，测试使用内存假实现。

- 使用不可重复的一次性 `UNCalendarNotificationTrigger`，避免规则变更和账期覆盖留下错误的重复通知。
- 请求标识固定为 `cardpilot.<accountID>.<cycleKey>.<statement|repayment>.<offset>`，重复调度幂等。
- 每次启动、回到前台、修改账务规则/覆盖/提醒设置、关闭账户或标记已还款后重新计算。
- 先移除 CardPilot 自己的待处理标识；先保证每个账户下一账期的账单与还款提醒，再按触发时间填充后续请求，总计最多安排 48 个。
- 标记已还款立即取消该账期尚未触发的还款提醒；Apple 官方支持按标识取消待处理请求：[本地通知文档](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)。
- 通知被拒绝时首页持续显示非阻塞提示，Dashboard 日期仍完全可用。
- 截断时不得静默：调度器返回最后已安排日期和未安排数量，首页显示“通知仅安排至某日，请打开 CardPilot 刷新”的提示。
- `ponytail:` 在 48 请求上限处记录：只有真实用户持续耗尽滚动窗口时才增加 `BGAppRefreshTask`；首版不引入不能保证运行的后台刷新。

## 应用锁与隐私

- `AppLockController` 使用 `LocalAuthentication` 的设备所有者认证：Face ID/Touch ID 优先，系统设备密码回退，不保存自定义 PIN。
- 启用前检查设备是否可认证；不可认证时禁止开启并解释原因。
- `scenePhase` 离开 active 时立刻显示不含数据的遮罩；回到 active 时认证成功才移除。
- 从通知深链进入也必须先通过锁屏，认证后再导航。
- UI、模型、测试夹具和日志中均不得出现模拟完整 PAN 或 CVV；测试卡只使用末四位。
- “不存储完整卡号或 CVV”的边界落实在数据模型和专用输入界面；普通自由文本不做内容猜测或扫描，隐私说明提醒用户不要主动写入敏感认证信息。

## 实施顺序

### 1. 项目与持久化骨架

- 创建 iOS 17+、iPhone、SwiftUI App 生命周期项目和测试 targets。
- 加入简体中文 String Catalog、四 Tab 根导航和显式本地 `ModelContainer`。
- 实现 `LocalDate`、`VersionedSchema`、上述 SwiftData 模型及内存容器测试。
- 验收：干净安装可启动；无 iCloud entitlement、网络权限或第三方包。

### 2. 信用卡与账务引擎

- 完成 Bank、CreditCardAccount、Card CRUD 与安全删除/归档规则。
- 实现规则版本、账期计算、单期覆盖和还款完成记录。
- 先完成账务算法测试，再接卡片页和表单。
- 验收：共享账户与独立账户均可表达；规则变化不改写旧账期。

### 3. 促销基础

- 完成结构化多主办方、适用卡、报名、日期依据、叠加标记和累计目标 CRUD。
- 实现促销生命周期、归档规则和进度纯计算。
- 验收：活动边界、超额达标、退款回落和冲正归零均有单元测试。

### 4. 交易与快捷分配

- 完成消费、退款、冲正、可选入账日期及安全删除。
- 在交易表单内实现候选促销、多选、默认金额、跨币种手填和警告确认。
- 实现促销详情中的历史分配修正。
- 验收：一笔交易可计入零到多个促销，每个促销使用独立合格金额且不会重复计数。

### 5. Dashboard 与通知

- 用账务和促销纯计算组装行动优先的 Dashboard。
- 请求通知权限，完成确定性标识、滚动调度、重排和完成后取消。
- 验收：更改规则、覆盖日期、时区、提醒提前量或还款状态后，假通知客户端中的请求完全匹配新状态。

### 6. 应用锁、设置与收尾

- 完成应用锁、后台遮罩、设置页和通知权限提示。
- 补齐 VoiceOver 标签、Dynamic Type、空状态、错误说明和危险操作确认。
- 执行完整单元测试、UI 冒烟测试和手工隐私检查。

## 必须覆盖的测试矩阵

### 账务日期

- 名义日 28、29、30、31 在普通二月、闰年二月、四月和五月；
- 固定还款日在账单日前、后、同日及目标月缺日；
- N 天后跨月、跨年、闰日和夏令时边界；
- 账单覆盖后重新推算还款，再由还款覆盖最终替换；
- 新规则从指定账期生效，旧账期结果不变；
- 每个账户只能保存一个基线规则，缺失或重复时保存失败且计算器返回明确错误；
- Dashboard 从追踪起始账期生成至当前日期后两个月，合并保存的未还账期；更早未保存账期不生成，非法或未来起始账期不会导致历史反向生成；
- 账户关闭前的未还账期保留，关闭后不再生成；
- active/closed 与关闭日期组合不一致时保存失败；
- 到期日当天仍为待还，下一自然日才为逾期；标记完成后为已还。

### 促销与交易

- 促销开始日、结束日均可成为候选；七日“即将结束”阈值在第 7 天内包含边界、第 8 天不命中；
- 报名截止日在今天至未来七天（含边界）的未归档、未报名促销进入 Dashboard，即使活动尚未开始；
- 三种资格日期依据及缺少入账日期；
- 非适用卡、未报名、日期冲突和不可叠加只警告；
- 同一交易向多个促销分配不同金额；同一交易与促销不能重复分配；
- 促销存在分配后不能修改进度币种，分配币种不一致时计算失败而非重解释；
- 外币交易不自动换算；同币种默认全额；
- 部分/全部退款降低进度，结束后的退款仍可关联原促销；退款不得关联退款或其他卡片，同币种超额退款给出强警告；
- 冲正交易贡献为零；
- 进度超过目标不封顶，退款后可重新变为未达标；
- 归档促销不再推荐但允许历史修正。

### 数据完整性、安全与通知

- 有引用的银行/账户/卡片/促销无法硬删除；交易关联需显式解除；
- 模型 Schema 不含 PAN、CVV 或银行凭据字段；末四位验证拒绝非四位数字；
- 通知标识幂等、排序稳定、上限明确，完成还款会取消对应请求；
- 通知超过 48 条时，每个账户的下一账期优先，截断数量与最后安排日期可见且有测试；
- 权限拒绝不影响 Dashboard；时区变化重排通知但不改业务日期；
- 后台遮罩无敏感数据，认证失败时无法进入内容界面。

## 验证命令

实现完成后至少运行：

```bash
xcodebuild -project CardPilot.xcodeproj -scheme CardPilot -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CardPilot.xcodeproj -scheme CardPilot -destination 'platform=iOS Simulator,name=<available iPhone>,OS=latest' test CODE_SIGNING_ALLOWED=NO
```

先用 `xcrun simctl list devices available` 选择实际存在的 iPhone 模拟器，不能把不存在的设备名当成 CI 失败。

## 对抗式评审清单

- 是否错误地把卡片字段、账户字段、全局提醒配置混在一起？
- 是否有任何代码按交易日期自动归属账期？若有，删除。
- 是否有任何代码未经促销分配就自动增加进度？若有，删除。
- 日期是否被 `Date`/系统旅行时区悄悄移动一天？
- 金额是否经过 `Double`、隐式汇率或币种不匹配计算？
- 规则变化是否重算历史，覆盖优先级是否与领域术语一致？
- 删除是否会隐式级联丢失历史，归档数据是否仍可追溯？
- 退款、冲正、跨币种、超额达标和退款回落是否都有可运行测试？
- 通知是否能在数据变更和标记已还后确定性重排/取消？
- 应用切后台、通知深链和认证失败时是否可能短暂泄露内容？
- 是否引入了首版未要求的后台、同步、规则引擎、分析或第三方依赖？

全部检查通过后，首版才可视为完成。
