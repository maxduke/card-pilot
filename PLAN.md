# CardPilot 首版实施计划

## 当前 UX 第三十八批：小屏辅助字号交易录入（2026-10-31）

O18／O21 的逐项核对发现现有自动化没有明确设置深色模式。
[小屏深色专项](https://github.com/maxduke/card-pilot/actions/runs/41145215883) 使用已验证主线 `4cae6cb` 的原完整流程，
在 SE 3／iOS 18.5 一次执行三项：促销通过，交易金额输入可见区域和首页账期文字审计失败。
原图与层级确认交易固定步骤栏挤占空间：金额框高 73.5 点，可滚动区域只有 60.5 点。
当前辅助字号步骤标题采用紧凑计数和当前步骤，首步提交文字缩短，完整无障碍说明与原保存路径保留。
首次对照已完整显示第一步金额；第二步继续调整输入时的步骤栏留白，保留收键盘文字自然高度。
首页审计报告的是滚至导航栏下方的旧账期文字，尚需浅／深色对照，不据此改动页面或放宽审计。
专项与正式门禁待验证，实际证据见[第三十八批记录](docs/ux-small-screen-transaction-editor-2026-10-31.md)。

## 已完成交付补修：账期完整流程与单卡交易入口（2026-10-31）

第三十七批 [PR #73](https://github.com/maxduke/card-pilot/pull/73) 的 PR CI 完整通过 330 项，
合并提交 `8613064` 的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/41050284723) 首次为 329／330，
促销返回导航超时。原完整促销专项通过并验收十张原图后，一次受控完整重跑为 328／330：
促销用例通过，最大字号账期完整放弃／重启流程在 192 秒完成但超过 180 秒额度，
单卡交易入口合成点击后未进入历史列表。当前校准该账期用例至既有 240 秒额度，
单卡入口先验证稳定且未遮挡的真实位置，再单次点击并保留截图；全部原业务断言保留。
[两项原生专项](https://github.com/maxduke/card-pilot/actions/runs/41103624068) 已一次完整通过，
七张当前原图与四份几何记录已实际检查。
[PR #74](https://github.com/maxduke/card-pilot/pull/74) 的最终 HEAD `20ae382` 通过完整 330 项，
合并提交 `4cae6cb` 的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/41126304740)
同样完整通过 234＋96＝330 项，零失败、跳过、用例重执行、测试进程重启或超时；两次内部 AX 点击恢复单独保留。
主线已同步、对应两处临时 worktree 已清理，已核对的测试 IPA 与真机清单已提供；真实设备结果仍待反馈。
原生导航偶发超时的最终原因仍未确定。
实际失败与范围见[交付补修记录](docs/ux-native-billing-history-readiness-2026-10-31.md)。

## 已完成 UX 第三十七批：早期 V3 历史计入的备份兼容（2026-10-30）

O22 的发布记录核对发现，v0.1.2／v0.1.3 编辑器和模型允许零金额计入，之后的严格校验会阻止这类
历史账本导出与恢复。本批只让备份重建保留这些原值，创建／编辑仍要求正金额，不改动模型字段或格式。
使用实际 v0.1.3 源码生成含零计入的原生样本，比较九类模型的全部保存字段，并覆盖升级保存重开、
导出恢复后重启、恢复保存失败时保留原账本；v0.1.2 的模型与该来源相同。
新增三项原生兼容回归，保留现有 231 项单元／集成和 96 项 UI，正式门禁为 234＋96＝330 项。
本批及上述交付补修已由 `4cae6cb` 的完整主线 330 项确认，历史红色运行继续保留。
用户已确认 v0.1.0／v0.1.1 只有测试数据，无需兼容 V1／V2；支持范围从 V3 开始，原文件继续保留。
实现与原生证据边界见[第三十七批记录](docs/compatibility-early-v3-zero-allocations-2026-10-30.md)。

## 已完成 UX 第三十六批：交易查询与输入状态边界（2026-10-30）

保留原三个查询，将搜索、筛选和编辑状态与原界面移入私有内容视图，新增筛选内保存和重启读回回归。
[PR #72](https://github.com/maxduke/card-pilot/pull/72) HEAD `34ff480` 的
[PR CI](https://github.com/maxduke/card-pilot/actions/runs/40998049630) 和合并提交 `65c4f25` 的
[main CI](https://github.com/maxduke/card-pilot/actions/runs/41011018452) 均完整通过 327 项，零失败、跳过或用例重执行。
五张该次正式原图已实际验收，无待处理适用审查或可操作发现，干净 main 已同步，临时 worktree 已清理。
后置搜索采样的短窗口未再出现先前查询访问路径，不据此宣称整体提速或真机表现；内部 AX 恢复未概括为零。
范围与边界见[第三十六批记录](docs/ux-transaction-query-boundary-2026-10-30.md)。

## 已完成 UX 第三十五批：交易保存动作职责拆分（2026-10-30）

现有 `TransactionEditValues` 和 `TransactionEditActions` 的 131 行声明体逐字移入独立文件，
页面调用、校验、退款关系、手动分配、失败回滚和性能区间保留。
[PR #71](https://github.com/maxduke/card-pilot/pull/71) HEAD `daa2da3` 的
[PR CI](https://github.com/maxduke/card-pilot/actions/runs/40944273373) 与合并提交 `40428a5` 的
[main CI](https://github.com/maxduke/card-pilot/actions/runs/40966636975) 均完整通过 326 项，
零失败、跳过、用例重执行、workflow 重跑或进程重启；各自的一次促销保存内部 AX 点击恢复单独保留。
[Release／PERFORMANCE_TESTING 原生构建](https://github.com/maxduke/card-pilot/actions/runs/40965766565)
已编译两个模拟器架构的新文件，未执行测量。无待处理适用审查或可操作发现，原干净 main 已同步。
范围与验证边界见[第三十五批记录](docs/refactor-transaction-edit-actions-2026-10-29.md)。

## 已完成 UX 第三十四批：交易输入、草稿与保存测量（2026-10-27）

完成 O19 的 100／5000／20000 笔交易输入、草稿及保存基线；沿用隔离数据和既有业务路径。
[Release 写入运行](https://github.com/maxduke/card-pilot/actions/runs/40609227526) 完整通过十二项，
60 组指标各十个有效样本，24 张该次原图已逐张验收；实际测量源码 `636241a` 对应正式源码 `d80196c`，
只相差临时 workflow。普通／最大字号数字键盘沿用固定底栏，草稿恢复、精确输入、唯一保存及重启读回均保留。
测量、历史失败及边界见[第三十四批记录](docs/ux-transaction-writing-performance-2026-10-27.md)。

后续完整运行暴露的原生入口、输入准备及失败取证问题经过专项补修；原生导航超时的原因仍未确定。
最终 [PR #70](https://github.com/maxduke/card-pilot/pull/70) HEAD `575cbd0` 的
[PR CI](https://github.com/maxduke/card-pilot/actions/runs/40895928074) 与合并提交 `3713c1e` 的
[main CI](https://github.com/maxduke/card-pilot/actions/runs/40921083670) 均完整通过 231＋95＝326 项，
零失败、跳过、用例重执行、workflow 重跑、进程重启或测试超时；29 张当前绿色 PR HEAD 原图及
12 份几何／输入准备附件已实际验收。无待处理适用审查或可操作发现，原干净 main 已同步。
main 的采样命令超时且无采样文件，未推定原因或性能改善；真实失败继续保留在
[失败取证记录](docs/ux-native-failure-evidence-2026-10-28.md)与[入口就绪记录](docs/ux-tab-entry-readiness-2026-10-29.md)。

## 已完成 UX 第三十三批：完整编辑状态与账户标题（2026-10-27）

基于完整通过 322 项的主线 `9e9bdc5`，账户和卡片编辑器在辅助字号展开原生状态选项，普通字号保留菜单；账户辅助字号沿用原生内联标题，完整显示“编辑信用卡账户”。复用既有状态、关闭日期、保存与放弃，不改变业务规则。两机型三轮原生预检的 58 张原图已逐张实际检查，其中 52 张来自完整通过流程；真实失败保留。[PR #66](https://github.com/maxduke/card-pilot/pull/66) 的 HEAD `6c9678c` 在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/40471263109) 与合并提交 `2830567` 的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/40489498279) 均完整通过 231＋95＝326 项，零失败、跳过、重跑、进程重启或超时。17 张当前绿色 HEAD 原图已逐张验收，无未解决的适用审查或可操作发现，原干净 main 已快进同步。见[第三十三批记录](docs/ux-accessible-editor-status-2026-10-26.md)。

## 已完成 UX 第三十二批：辅助字号完整选择银行（2026-10-26）

账户辅助字号的银行名称完整换行，并进入保留选中标记和当前位置的原生列表；普通字号沿用菜单，选择复用原 UUID、筛选、保存及放弃。两机型专项 18 张、[PR #64](https://github.com/maxduke/card-pilot/pull/64) 绿色 HEAD 的九张原图已验收，PR 完整通过 322 项。首次合并主线的促销概览超时及补修 PR 首次的卡片键盘失败均保留；[补修 #65](https://github.com/maxduke/card-pilot/pull/65) 的最终 HEAD `38bb0c5` 在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/40444557384) 与合并提交 `9e9bdc5` 的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/40457020639) 均完整通过 231＋91＝322 项，零失败、跳过、用例／workflow 重跑、进程重启或超时。35 张当前绿色 HEAD 原图及五份几何附件已实际验收，无待处理适用审查或可操作发现，原干净 main 已快进同步。范围与真实失败见[第三十二批记录](docs/ux-account-bank-selection-2026-10-26.md)及[导航验证补修](docs/ux-native-promotion-navigation-2026-10-27.md)。

## 已完成 UX 第三十一批：账户名称与发布数据兼容（2026-10-26）

账户创建／编辑支持可选名称，列表、搜索、详情、账期及通知复用既有身份入口；辅助字号的账户与卡片行支持完整内容。V4 保留原库身份，v2 备份读取实际 v1，导入预览保留原格式。实际发布样本覆盖九类模型的原位升级、保存重开、完整恢复、草稿身份及失败保留；范围与真实补修见[第三十一批记录](docs/ux-account-names-and-released-data-2026-10-26.md)。

[PR #63](https://github.com/maxduke/card-pilot/pull/63) 的 HEAD `3a5b113` 在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/40257922719) 完整通过 231＋89＝320 项，19 张该次原图已逐张验收。合并提交 `c41feec` 的首次 main 为 319／320，一个既有促销概览用例等待辅助功能快照超时；同源码的[带采样专项](https://github.com/maxduke/card-pilot/actions/runs/40292516710) 两项通过，未复现原因。一次受控的[同提交完整重跑](https://github.com/maxduke/card-pilot/actions/runs/40277958504/attempts/2) 已通过 320 项，零失败、零跳过、无用例重执行、进程重启或超时；两次 XCTest 内部点击恢复及首次失败记录保留。无待处理适用审查或可操作发现，原干净 main 已快进同步，自动继续下一批。

## 已完成 UX 第三十批：促销列表完整辅助标签（2026-10-26）

促销自定义合并标签补入非空奖励和归档状态，保留日期、报名及进度；新增真实归档与重启读回回归。[PR #62](https://github.com/maxduke/card-pilot/pull/62) 的 HEAD `72070e7` 与合并提交 `244b106` 分别在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/40206225788) 和 [main CI](https://github.com/maxduke/card-pilot/actions/runs/40216476020) 完整通过 223＋87＝310 项，零失败、跳过、用例／workflow 重跑、进程重启或超时。三张当前绿色 HEAD 原图与实际归档前后及重启标签已验收，无待处理的适用审查或可操作发现，原干净 main 已快进同步。范围与边界见[第三十批记录](docs/ux-promotion-accessibility-summary-2026-10-25.md)。

## 已完成 UX 第二十九批：辅助字号促销概要（2026-10-25）

辅助字号下的促销标题与状态纵向排列，标题、奖励和主办方允许换行，状态标签保持单行，普通字号保留紧凑概要。[PR #61](https://github.com/maxduke/card-pilot/pull/61) 的 HEAD `bedbd21` 与合并提交 `9d9e6f4` 分别在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/40185765003) 和 [main CI](https://github.com/maxduke/card-pilot/actions/runs/40195197252) 完整通过 223＋86＝309 项，零失败、跳过、用例／workflow 重跑、进程重启或超时。目标概览用例均执行一次且没有内部重试，其他用例的 XCTest 点击恢复为 PR 三次、main 一次，已单独记录。八张两机型预检原图与四张当前绿色 HEAD 原图、原始点击几何已验收；无待处理的适用审查或可操作发现，原干净 main 已快进同步。范围与边界见[第二十九批记录](docs/ux-promotion-list-text-2026-10-25.md)。

## 已完成 UX 第二十八批：促销列表完整有效期（2026-10-25）

基于第二十七批已验证主线 `26a693d`，促销有效期独立成行并允许换行，沿用全部业务路径；超高行通过真实可见区域验证入口。SE 3 与 iPhone 16 Pro 均已通过完整预检，十五张成功运行原图已逐张检查。[PR #60](https://github.com/maxduke/card-pilot/pull/60) 的 HEAD `36bbfaf` 与合并提交 `eaa76f3` 分别在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/40166230796) 和 [main CI](https://github.com/maxduke/card-pilot/actions/runs/40174861027) 完整通过 223＋86＝309 项，零失败、跳过、用例／workflow 重跑、进程重启或超时。main 的另一个用例有一次 XCTest 内部点击恢复，目标概览用例只执行一次可见区域点击并完成全部原断言。四张当前绿色 HEAD 原图和实际点击几何已验收，无待处理的适用审查或可操作发现，原干净 main 已快进同步。真实失败、时限依据及边界见[第二十八批记录](docs/ux-promotion-list-dates-2026-10-25.md)。

## 已完成 UX 第二十七批：单卡交易历史复用分组（2026-10-25）

基于第二十六批已验证主线 `4de8323`，单卡历史列表读取该卡已有的交易关系，并在本次更新中分组一次，保留顺序、身份及完整编辑上下文。新增两万笔总账本、单卡一千笔下的查看、添加后即时刷新及卡片统计回归。[PR #59](https://github.com/maxduke/card-pilot/pull/59) 的 HEAD `21771a6` 与合并提交 `26a693d` 分别在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/40107990138) 和 [main CI](https://github.com/maxduke/card-pilot/actions/runs/40147208757) 完整通过 223＋86＝309 项，零失败、跳过、用例重跑、workflow 重试、超时或进程重启；原生测试的内部点击恢复为 PR 一次、main 两次，已单独记录。三张当前绿色 HEAD 原图已逐张验收，无待处理的适用审查或可操作发现，原干净 main 已快进同步。范围与真实超时、采样产物缺失边界见[第二十七批记录](docs/ux-card-history-grouping-2026-10-24.md)。

## 已完成 UX 第二十六批：Release 性能基线（2026-10-24）

基于完整验证主线 `aa9f1bc` 推进 O19：使用独立模拟器存储，在 100／5000／20000 笔交易、20 张卡、5 年账期和多期促销下记录启动、前台恢复、页面首次进入、搜索及滚动。首次两万笔原生预检在交易列表超时，系统采样指向逐个分组重复处理全量交易；修复仅在本次页面更新中复用筛选、分组结果。专用手动 workflow 使用实际 Release，保留原始样本、内存／滚动指标、工具链与数据报告；既有必跑 workflow 保持原样。

完整[性能运行](https://github.com/maxduke/card-pilot/actions/runs/40056599504) 已通过 21／21，81 组指标各有十个有效样本，零失败、跳过、重跑或测试进程重启；21 张该次运行的原始截图已逐张验收。实际测量源码为诊断提交 `def8052`，对应正式源码 `f5058f5`，两者只相差诊断 workflow；原始数值不冒记为后续 PR／main 提交的测量。快速输入／保存和真机性能另行有界测量，O19 的其他静态关注点继续按证据处理。范围、基线数值及限制见[第二十六批记录](docs/ux-performance-baseline-2026-10-23.md)。

[PR #58](https://github.com/maxduke/card-pilot/pull/58) 最终 HEAD `b04fcfa` 的[正式 CI](https://github.com/maxduke/card-pilot/actions/runs/40065050408) 和合并提交 `4de8323` 的[主线 CI](https://github.com/maxduke/card-pilot/actions/runs/40080130119) 均完整通过 223＋85＝308 项，零失败、跳过、重试、超时或测试进程重启。八张正式回归原图已逐张验收，无待处理的适用审查或可操作发现；原干净 main 已快进同步，自动继续第二十七批。

## 已完成 UX 第二十五批：促销字段反馈（2026-10-24）

基于 `31407599` 完善促销创建／分组编辑：错误就近显示，提交收起键盘、切回有错分组并定位首错，纠正后即时清除。原图发现的最大字号日期裁切和进度类型省略已通过复用现有日期控件及展开选项修复；存储、系列目标、校验与回滚保持原样。范围及真实失败见[第二十五批记录](docs/ux-promotion-field-feedback-2026-10-23.md)。

[PR #57](https://github.com/maxduke/card-pilot/pull/57) 的最终 HEAD `4d77726` 在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/40016320350) 完整通过 222＋85，81 张该运行的原始截图已逐张验收。合并提交 `aa9f1bc` 的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/40028930152) 同样通过 307 项，零失败、跳过、用例重跑、workflow 重试、超时或进程重启；main 的一次 XCTest 内部 AX 点击恢复已单独记录。无待处理的适用审查或可操作发现，原干净 main 已快进同步；按用户要求自动继续下一批，goal 保持运行。

## 已完成 UX 第二十四批（2026-10-23）

基于主线 `e6799dc` 完善银行编辑器：银行名称错误就近显示，保存时关闭文字键盘并定位无效名称，修正后即时清除；反馈状态不计作编辑。修正原生菜单标签落在外层包装按钮的问题，银行管理／编辑入口至少 44 点，银行标题支持换行。沿用现有错误样式、名称规则、保存／回滚和放弃修改保护，不增加表单框架。新增普通／最大字号的创建保存与编辑放弃四项 UI 流程，并重启读回银行名称、长备注及归档状态，范围见[第二十四批记录](docs/ux-bank-field-feedback-2026-10-22.md)。

[PR #55](https://github.com/maxduke/card-pilot/pull/55) 的绿色 HEAD `91dfdd6` 已验收十八张原图；首次合并主线的两项既有原生入口失败保留在[补修记录](docs/ux-native-presentation-readiness-2026-10-23.md)。补修 [PR #56](https://github.com/maxduke/card-pilot/pull/56) 的最终 HEAD `d013d4d` 与合并提交 `31407599` 分别在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/39841747727) 和 [main CI](https://github.com/maxduke/card-pilot/actions/runs/39860890395) 完整通过 222＋79，零失败、跳过、重试、超时或进程重启。该 HEAD 的十七张补修原图已逐张验收，无待处理的适用审查或发现；原干净 main 已同步。按用户最新要求持续自动推进，不自行暂停 goal。

## 已完成 UX 第二十三批（2026-10-22）

基于已验证主线 `9a807fd` 继续 O13：添加信用卡向导的额度、产品名称、末四位及自定义卡组织在提交后就近提示，定位当前步骤首错，修正后即时更新；步骤往返保留输入。沿用已建立的错误样式和数字键盘入口、原数据校验、保存与回滚，不增加表单框架。新增四项普通／最大字号纠错及保存／放弃后的重启读回，保留原有 70 项 UI 覆盖；既有账期审计拆成普通／最大字号两项，并保留 iOS 18.5 账期标题原生误报的原始证据与逐个元素检查。完整交付要求 222＋75、三十二张当前绿色 HEAD 全屏原图及报告对应元素原图、合并主线验证；范围与证据见[第二十三批记录](docs/ux-onboarding-field-feedback-2026-10-22.md)。

[PR #54](https://github.com/maxduke/card-pilot/pull/54) 已合并为 `e6799dc`。最终 HEAD `a0ef143` 的 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/39688922289) 与合并提交的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/39701153736) 均完整通过 222＋75，零失败、零跳过、无重试、超时或测试进程重启；三十二张全屏原图与一张审计元素原图已逐张验收，无待处理的适用审查或可操作发现。本批完成后已按要求暂停并同步原干净 main，现由用户恢复。

## 已完成 UX 第二十二批（2026-10-21）

[PR #53](https://github.com/maxduke/card-pilot/pull/53) 完成辅助字号日期选择页、完整月份入口及定位已选月份的列表、账单日原生导航选项，并修正卡片账期文字布局。最终 HEAD `346bfd8` 的 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/39571551893) 和合并提交 `9a807fd` 的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/39585961152) 均通过 222＋70，零失败、零跳过、无重试、超时或测试进程重启；二十七张该 HEAD 原图已逐张验收，无待处理的适用审查或可操作发现。原干净 main 已同步；本批完成后曾按用户要求暂停，现已恢复。实现及真实失败见[第二十二批记录](docs/ux-billing-date-accessibility-2026-10-20.md)。

## 已完成 UX 第二十一批（2026-10-20）

[PR #51](https://github.com/maxduke/card-pilot/pull/51) 完成账户与账期日期的就近错误、首错定位、实时纠正，以及明确指出冲突账期；[补修 #52](https://github.com/maxduke/card-pilot/pull/52) 让既有最大字号数字键盘用例按实际滚动区域定位。最终 HEAD `e3cc98d` 的 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/39388315594) 和合并提交 `48e9bbe` 的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/39399629277) 均完整通过 222＋66，零失败、零跳过、无超时、重试或测试进程重启。十八张功能与三张补修原图已实际检查；原工作区干净快进至验证主线。本批完成后曾按用户要求暂停，现已恢复。实现与真实失败见[第二十一批记录](docs/ux-billing-date-feedback-2026-10-20.md)。

## 后续优化顺序

账户命名 O09、银行选择、完整编辑状态及账户标题已交付；O22 的 V3 发布数据基线和早期零金额备份兼容已实现，当前等待主线完整门禁收尾。用户已确认 V1／V2 只有测试数据且无需兼容。O19 的读取与写入基线、交易查询边界已交付，后续按实际证据继续优化；O20 随相关模块拆分职责。O08 的导航方案仍需用户走查证据；O21 的真机验收继续逐项推进，不把模拟器结果当作真机验收。

## 已完成 UX 第二十批（2026-10-20）

[PR #48](https://github.com/maxduke/card-pilot/pull/48) 完成账户／卡片字段旁报错、实时纠正和首错定位，补修 [PR #49](https://github.com/maxduke/card-pilot/pull/49)、[PR #50](https://github.com/maxduke/card-pilot/pull/50) 处理原生商户输入准备与实测执行额度。最终 HEAD `a228e62` 的 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/39342143802) 和合并提交 `967b36f` 的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/39350400548) 均完整通过 219＋61，零失败、零跳过、无超时或测试进程重启；二十四张功能／回归原图与两张商户补修原图已实际验收。原工作区干净同步至验证后的主线。范围及真实失败见[字段反馈记录](docs/ux-editor-field-feedback-2026-10-19.md)和[原生验证补修记录](docs/ux-native-merchant-input-readiness-2026-10-20.md)。

## 已完成 UX 第十九批（2026-10-19）

[PR #46](https://github.com/maxduke/card-pilot/pull/46) 与补修 [PR #47](https://github.com/maxduke/card-pilot/pull/47) 完成账户／卡片数字键盘退出、计入金额定位及促销确认页布局。最终 HEAD `9aed83c` 的 [PR workflow](https://github.com/maxduke/card-pilot/actions/runs/39249253519) 与合并提交 `744aea9` 的 [main workflow](https://github.com/maxduke/card-pilot/actions/runs/39262050171) 均完整通过 219 项单元／集成与 57 项 UI，零失败、零跳过、无超时或 runner 重启；十五张当前绿色 HEAD 原始截图已逐张验收。原工作区已干净快进到验证后的主线。真实失败、原生控件对照、工具链迁移撤回与最终修复见[第十九批记录](docs/ux-account-card-numeric-keyboard-2026-10-18.md)。

## 已完成 UX 第十八批（2026-10-18）

[PR #43](https://github.com/maxduke/card-pilot/pull/43) 与补修 [PR #44](https://github.com/maxduke/card-pilot/pull/44)、[PR #45](https://github.com/maxduke/card-pilot/pull/45) 完成向导数字键盘退出、促销搜索标签和焦点滚动、原生金额高度，以及搜索 Form 边界／退款初始键盘的测试前置条件。最终 HEAD `01150bc` 的 [PR workflow](https://github.com/maxduke/card-pilot/actions/runs/39060784889) 与合并提交 `17d035c` 的 [main workflow](https://github.com/maxduke/card-pilot/actions/runs/39066447762) 均完整通过 219 项单元／集成与 53 项 UI，零失败／零跳过，无超时、重试或 runner 重启；应用相关二十四张与测试补修九张原图均已逐张验收。原工作区已干净快进到验证后的主线。历史失败与候选边界见[第十八批记录](docs/ux-onboarding-numeric-keyboard-2026-10-17.md)。

## 已完成 UX 第十七批（2026-10-17）

[PR #41](https://github.com/maxduke/card-pilot/pull/41) 与补修 [PR #42](https://github.com/maxduke/card-pilot/pull/42) 完成促销数字键盘退出、复杂纠错流程预算和校验更新后的滚动定位。最终 HEAD `bca63d3` 的 [PR workflow](https://github.com/maxduke/card-pilot/actions/runs/38936423337) 与合并提交 `7d17eda` 的 [main workflow](https://github.com/maxduke/card-pilot/actions/runs/38947269180) 均通过 219 项单元／集成与 49 项 UI，零失败／零跳过，无超时、重试或 runner 重启；此前功能的十四张与补修的九张原生截图均已逐张验收。原干净 main 已同步验证提交。真实失败、候选撤回与匿名报告的未确认边界见 [第十七批记录](docs/ux-promotion-numeric-keyboard-2026-10-16.md)。

## 已完成 UX 第十六批（2026-10-16）

[PR #39](https://github.com/maxduke/card-pilot/pull/39) 与 [PR #40](https://github.com/maxduke/card-pilot/pull/40) 完成促销计入金额的就近错误与首个错误定位，并补修字号切换的排版、原生菜单／退款操作和多次审计的预算。真实失败、对照边界及最终结果见 [第十六批记录](docs/ux-allocation-input-feedback-2026-10-13.md)。最终 HEAD `b41cd2f` 的 [PR workflow](https://github.com/maxduke/card-pilot/actions/runs/38774777944) 与合并提交 `cbbcf2e` 的 [main workflow](https://github.com/maxduke/card-pilot/actions/runs/38786292385) 均通过 219 项单元／集成及 48 项 UI，零失败、零跳过、无超时或 runner 重启；三十一张绿色 HEAD 原生截图已逐张检查。原干净 main 已快进至验证提交，之后开始第十七批。

## 已完成 UX 第十五批（2026-10-13）

[PR #37](https://github.com/maxduke/card-pilot/pull/37) 提供金额键盘退出、完整辅助字号步骤说明、原生账期状态选择及完整空结果。[PR #38](https://github.com/maxduke/card-pilot/pull/38) 合并既有备份面板的容器与字段等待，保留原有 35 秒总预算及全部断言。修复 HEAD `8f16f44` 的 [PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38402345605) 与合并提交 `f7263e1` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38412074291) 均通过 218 项单元／集成测试和 45 项 UI 测试，零失败、零跳过；十六张当前 HEAD 截图已逐张检查。真实失败及修复证据保留在 [第十五批记录](docs/ux-numeric-keyboard-2026-10-13.md) 与 [交付补修记录](docs/ux-native-backup-picker-readiness-2026-10-13.md)。

## 已完成 UX 第十四批（2026-10-12）

[PR #36](https://github.com/maxduke/card-pilot/pull/36) 完整显示退款原消费的日期、商户、精确金额／币种和状态，并使用支持长内容换行的原生选择列表，保留原有 UUID、退款输入、分配、草稿及保存路径。范围及真实失败修正见 [第十四批记录](docs/ux-refund-original-summary-2026-10-12.md)。最终 HEAD 的 [PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38265503571) 与合并提交 `b6bdaf7` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38273465910) 均通过 218 项单元／集成测试和 42 项 UI 测试，零失败、零跳过；十四张当前 HEAD 原生截图已检查。完整套件作业预算按实际取消证据调整至 75 分钟，单项测试时限和完整测试范围保留。

## 已完成 UX 第十三批（2026-10-12）

[PR #35](https://github.com/maxduke/card-pilot/pull/35) 处理 O17 的备份导出体验，提供日期时间文件名及仅在系统成功回调后更新的本机导出记录。实现、真实失败修正及验收边界见 [第十三批记录](docs/ux-backup-export-status-2026-10-11.md)。最终 HEAD 的 [PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38198185478) 与合并提交 `d3886aa` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38202008094) 均通过 216 项单元／集成测试和 39 项 UI 测试，零失败、零跳过；四张备份与两张促销金额说明原生截图已检查。系统实际保存、成功时间跨重启读回及恢复仍需 O21 真机验收，不能由取消和只读日期布局检查推定通过。

## 已完成 UX 第十二批（2026-10-12）

[PR #33](https://github.com/maxduke/card-pilot/pull/33) 处理 O16 的未来规则管理，提供点选修正、取消影响预览及日期冲突调整入口，保护历史、其他版本和已保存账期事实；账户摘要明确已还／未还。范围及真实失败修正记录见 [第十二批记录](docs/ux-future-rules-2026-10-11.md)。合并后补充 [PR #34](https://github.com/maxduke/card-pilot/pull/34)，修正最大字号 UI 测试对屏幕内目标的滚动过冲，保留原有粗定位、全部断言与审计。[最终 PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38184250840) 与已验证合并提交 `a9461d5` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38187087684) 均通过 216 项单元／集成测试和 38 项 UI 测试，零失败、零跳过；未来规则、确认取消、最大字号日期冲突、日期筛选及最大字号账期入口／结果的七张最终截图已检查。完整套件作业预算按实际取消证据调整至 60 分钟，单项测试时限和完整测试范围保留。

## 已完成 UX 第十一批（2026-10-12）

[PR #32](https://github.com/maxduke/card-pilot/pull/32) 处理 O16 的账期回查：增加全部账期入口，按年、月及还款状态查找，保留详情返回条件、共享账户还款事实与未来日期覆盖。范围与验证见 [第十一批记录](docs/ux-account-cycle-history-2026-10-11.md)。最终 HEAD 的 [PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38155681989/attempts/2) 与合并提交 `c0b460d` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38162416179) 均通过 209 项单元／集成测试和 32 项 UI 测试，零失败、零跳过；普通入口、较早已还／未还账期及最大字号入口／结果的五张截图已检查。最终 HEAD 首次完整运行中的既有促销 UI 超时及一次受控、不改代码的完整重跑记录保留在实施文档中。

## 已完成 UX 第十批（2026-10-11）

[PR #31](https://github.com/maxduke/card-pilot/pull/31) 处理 O15：日期和币种与现有条件共同筛选，显示结果笔数，支持自定义范围和移除条件。范围与验证见 [第十批记录](docs/ux-transaction-date-filters-2026-10-11.md)。[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38146385200) 与合并提交 `c940b26` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38149295591) 均通过 206 项单元／集成测试和 30 项 UI 测试，零失败、零跳过；普通、自定义日期与最大字号筛选移除的四张截图已检查。升级后的 v7 上传 Action 已实际生成可读取的原生产物。

## 已完成 UX 第九批（2026-10-11）

[PR #30](https://github.com/maxduke/card-pilot/pull/30) 处理 O14：从原消费记录退款，保留卡片、交易币种、独立退款事实及关联导航，继续共用草稿、促销分配和超额确认。范围与验证见 [第九批记录](docs/ux-linked-refunds-2026-10-11.md)。[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38139331222) 与合并提交 `10741e9` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38141813825) 均通过 203 项单元／集成测试和 28 项 UI 测试，零失败、零跳过；普通退款、累计超额确认及最大字号入口／完整冲正说明／关联行的六张截图已检查。

## 已完成 UX 第八批（2026-10-11）

[PR #29](https://github.com/maxduke/card-pilot/pull/29) 处理 O07：首页近期事项数量成为对应待办入口，保留详情返回筛选、还款撤销与共享账户去重。范围与验证见 [第八批记录](docs/ux-dashboard-actions-2026-10-11.md)。[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38123224818) 与合并提交 `ca319fd` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38125207500) 均通过 202 项单元／集成测试和 24 项 UI 测试，零失败、零跳过；20 张卡首页概览、今日待办及最大字号截图已检查。

## 已完成 UX 第七批（2026-10-11）

[PR #28](https://github.com/maxduke/card-pilot/pull/28) 处理 O10：金额规则保留标题与就近例子，可选条件按需展开，收起保留输入且校验能展开隐藏错误，奖励优先展示。范围与验证见 [第七批记录](docs/ux-promotion-rules-2026-10-11.md)。[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38119387661) 与合并提交 `b9e9c24` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38121228534) 均通过 200 项单元／集成测试和 23 项 UI 测试，零失败、零跳过；金额与文字保存读回、折叠状态及最大字号说明截图已检查。

## 已完成 UX 第六批（2026-10-11）

[PR #27](https://github.com/maxduke/card-pilot/pull/27) 处理 O12：促销详情优先显示进度、结束日期与完整奖励，区分金额达标和上限用完，并修复报名／资格选项的辅助字号省略。范围与验证见 [第六批记录](docs/ux-promotion-progress-2026-10-11.md)。[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38112669625) 与合并提交 `369a034` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38114282615) 均通过 200 项单元／集成测试和 22 项 UI 测试，零失败、零跳过；五种进度、最大字号进度与报名／资格保存读回截图已检查。

## 已完成 UX 第五批（2026-10-11）

[PR #26](https://github.com/maxduke/card-pilot/pull/26) 处理 O11 的促销分组编辑：从详情直接进入需要修改的内容，编辑时可切换分组并直接保存，保留创建引导、完整校验、系列编辑范围与取消保护。范围与验收见 [第五批记录](docs/ux-promotion-editing-2026-10-11.md)。[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38107044002) 与合并提交 `e42d959` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38108646074) 均通过 199 项单元／集成测试和 20 项 UI 测试，零失败、零跳过；普通编辑、校验、最大字号分组与选卡截图已检查。旧报名选项在最大字号下仍有省略，转入第六批处理。

## 已完成 UX 第四批（2026-10-11）

[PR #25](https://github.com/maxduke/card-pilot/pull/25) 改善 O04 的交易保存反馈：在编辑弹层关闭后显示，普通模式保留 8 秒，可手动关闭；适配 VoiceOver 与减少动态效果，修复导航遮挡和嵌套重复提示，范围与真机边界见 [第四批记录](docs/ux-save-feedback-2026-10-11.md)。[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38100343026) 与合并提交 `bdff161` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38101803684) 均通过 199 项单元／集成测试与 17 项 UI 测试，零失败、零跳过；原生提示和交易截图已检查。

## 已完成 UX 第三批（2026-10-10）

[PR #24](https://github.com/maxduke/card-pilot/pull/24) 处理 O04 中筛选点击区域、交易和账期的辅助字号布局，并补充原生无障碍审计与截图；保留现有业务口径、数据格式和页面结构，范围与审计边界见 [第三批记录](docs/ux-accessibility-2026-10-10.md)。[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38076341756) 与合并提交 `2b69748` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38077761105) 均通过 199 项单元／集成测试与 15 项 UI 测试，零失败、零跳过；九张原生截图已检查。

## 已完成 UX 第二批（2026-10-10）

[PR #23](https://github.com/maxduke/card-pilot/pull/23) 实现首次建卡后的提醒引导（O03）：卡片先保存，再提供设置／稍后操作；建卡与设置共用通知与提醒页面，明确权限、提醒开关和已安排计划。保持现有全局排程、通知路由和数据格式，记录见 [实施与验收](docs/ux-reminder-onboarding-2026-10-10.md)。[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38062447856) 与合并提交 `4e02dc0` 的 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38063324259) 均通过 199 项单元／集成测试与 13 项 UI 测试，零失败、零跳过。真实通知与 VoiceOver 仍需独立验收。

## 已完成 UX 第一批（2026-10-10）

第一批 [PR #22](https://github.com/maxduke/card-pilot/pull/22) 已合并到主线 `662fd4d`，[PR 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38056187342) 与 [main 原生 CI](https://github.com/maxduke/card-pilot/actions/runs/38059420884) 均通过 199 项单元／集成测试与 11 项 UI 测试，零失败。

按 [最新产品评估](docs/product-ux-review-2026-10-10.md) 开始分批实现。第一批保护换卡时的交易币种、精确金额展示，改善空表单关闭、草稿恢复摘要和首页还款反馈；保持持久化 Schema 与草稿格式。具体行为和验证边界见 [实施记录](docs/ux-input-feedback-2026-10-10.md)。本地隔离验证是补充；PR 原生验证已完成，真机与 VoiceOver 仍需独立验收。

此前 PR #21 已于 2026-09-30 合并；主线 `43795d6` 的 [iOS workflow](https://github.com/maxduke/card-pilot/actions/runs/36731841163) 已通过。下节的草稿／未合并描述属于当时记录，不代表当前远端状态。

## 当前修复批次（2026-09-29，尚未发布）

综合检查后的 Batch A 已完成实现与审查修复；功能提交 `664d1e3` 通过 [原生 iOS CI](https://github.com/maxduke/card-pilot/actions/runs/36709117235)：197 项单元／集成测试和 8 条 UI 测试全部通过。本地隔离测试 99 项通过。[Draft PR #21](https://github.com/maxduke/card-pilot/pull/21) 保持草稿，未合并或发布；范围、失败修复经过与真机验收边界见 [正确性修复记录](docs/review-batch-a-2026-09-29.md)。新账户覆盖上月仍未到还款日的账期，后续促销期不继承已报名事实，保留手动促销分配、已有账务历史与当前 Schema。自动化通过不代表全部真机体验或无障碍检查通过。

## 接续执行状态（2026-09-12）

最新完成的是 [PR #19](https://github.com/maxduke/card-pilot/pull/19) 的跨日与时区刷新：统一“今天”，覆盖常用时区午夜、后台返回、设置时区及系统时间变化，同步更新账期、促销与提醒，并保持导航和编辑状态。功能及 UI 回归修正提交 `788809b` 已通过 [完整原生 iOS CI](https://github.com/maxduke/card-pilot/actions/runs/34685495269)，Codex 评审完成，无未解决的有效发现。本轮交付版本为 **0.1.7**，先执行下文真机验收，再进行长期数据性能测量；发布状态以发布页和 Actions 为准。

此前已完成 PR #12、#13 的两批 UI/UX 改进、PR #14 的完整备份恢复、PR #15 的通知与账期闭环、PR #16 的核心 UI 自动化，以及 [0.1.5 发布](https://github.com/maxduke/card-pilot/releases/tag/v0.1.5)。这些已完成部分不再重复建设。IPA 构建和模拟器测试均不代表真机验收通过。

新 session 先阅读本节、`CONTEXT.md`、相关 ADR 和实施记录，从最新 `main` 创建分支继续。早期文档中的测试数量和“未运行原生测试”描述属于当时状态，最新验证以上述记录为准。不要重复实现已完成部分。

### 已完成：完整备份导出与安全恢复（PR #14）

- 设置页提供完整 JSON 备份与恢复，覆盖全部银行、卡组织、账户、卡片、规则版本、账期、促销系列、交易、退款及分配关系，包括归档和停用数据。格式独立版本化，保留稳定 UUID、自然日期和已保存的精确金额；设备设置不纳入备份。
- 恢复采用整库替换：完整校验、数量预览、明确确认、恢复前备份、独立新库保存与读回核对，最后原子切换。无法无损保存时拒绝恢复，原存储文件保留；支持找回恢复前备份及启动失败后的受应用锁保护恢复。
- 备份耗时工作移到后台，重建关系后校验；生成账期总量（含显式未还账期）有上限，历史规则匹配及页面账期查找已优化。设备认证不可用时恢复入口不会永久锁死。
- 往返、故障注入、关系重建、异步响应、并发拒绝、账期数量边界及应用锁回归测试已通过原生 CI。
- 已消除 PR push 的重复测试：iOS workflow 监听 PR 更新和 `main` push，功能分支提交仅产生一份 PR 测试。

恢复决策见 `docs/adr/0011-replace-backups-through-a-new-local-store.md`，文件约定、边界与验收步骤见 `docs/backup-restore-2026-09-08.md`。真机恢复、系统文件面板、设备认证与无障碍验收仍待执行，不视为已完成。交易 CSV 仍为后续便利导出，不代替完整备份；本批未引入云同步或后端。

### 已完成：通知与账期操作闭环（PR #15）

- 通知点击定位账户和具体账期；冷启动、后台和应用锁认证期间保留目标，现有编辑或嵌套 sheet 关闭后才打开，目标不存在时显示明确说明。
- 首页、卡片详情、账户详情共用账期详情，就地标记已还、撤销和调整日期；保存后重新安排提醒，保留共享账户状态、日期覆盖及稀疏记录约束。
- 设置页增加 5 秒测试提醒，独立固定槽位不占用 48 条账务计划，支持权限与安排失败反馈。
- 新增路由、冷启动双入口去重、认证等待、账期保存与回滚、保存后通知重排及测试提醒回归测试。原生 CI 发现并修复了失败插入的 SwiftData 关系残留：日期先以纯值校验，持久化失败时还原字段与双向关系；故障注入覆盖新增、修改、删除及重试。原生完整测试已通过，Linux 65 项隔离测试作为补充验证。

实现边界和待执行真机验收见 `docs/notification-billing-loop-2026-09-08.md`。核心流程 UI 自动化已在 PR #16 补齐；真实通知、认证和呈现动画仍需按记录验收。

### 已完成：核心流程 UI 自动化（PR #16）

已建立 `CardPilotUITests`、Debug 模拟器独立磁盘夹具、建卡/记账与活动计入/共享账户还款撤销/详情导航用例，并接入原生 iOS CI 与失败产物上传。四条 UI 用例覆盖真实保存与重启读回，夹具另有完整备份校验往返测试，内置卡组织使用规范 UUID。完整原生 CI 和最终评审已通过，无待处理发现。实现、运行方式与手动验收边界见 `docs/ui-automation-2026-09-09.md`。不得据此宣称真机通知、认证或无障碍验收通过。

### 已完成：新增交易草稿恢复（PR #18）

各新增交易入口共用本地草稿，支持重启后继续/丢弃、保留手动分配、保存去重和备份账本隔离。草稿引用卡片删除后可明确选择替代卡片；新表单改回初始状态不会留下空草稿；已保存交易的残留草稿清理失败不会阻止新建。银行菜单限定到银行标题，卡片操作位于卡片行。

新增 7 项草稿存储测试和 3 条 UI 回归，完整原生测试通过；评审发现均已修复和验证。实施、验证证据与边界见 [交易草稿记录](docs/transaction-drafts-2026-09-09.md)。编辑已有交易、建卡和促销编辑草稿仍未覆盖。

### 0.1.6 发布

[发布页](https://github.com/maxduke/card-pilot/releases/tag/v0.1.6) 提供本批新增交易草稿恢复与菜单修复的 unsigned IPA 和 SHA-256 文件。发布流程先验证版本更新后的 PR CI，再合并并验证主线 CI，最后打标签、构建及核对附件；当前发布状态以该发布页和对应 Actions 结果为准。IPA 需要自行签名，最低 iOS 17。

0.1.6 对应 PR #18 的新增交易草稿恢复。PR #19 已合并，相关分支已清理。

### 已完成：跨日与时区刷新（PR #19）

根页面统一持有可观察日期状态，按常用时区日历计算下个自然日边界，支持夏令时、跨月跨年、后台多日返回及系统时间回拨。首页、卡片／账户／账期详情、促销和月份窗口随日期更新，提醒同步重建；不重建导航或编辑表单，也不改写已保存自然日期。

新增 7 项时钟测试和 2 项领域集成测试。原生 CI 通过，涵盖 148 项单元／集成测试与 7 条核心 UI 回归；同时修复 UI 测试辅助函数无法找回屏幕上方按钮的问题。最终 Codex 评审完成，无未解决发现。实现、验证证据与待执行真机验收见 [跨日刷新记录](docs/day-refresh-2026-09-12.md)。

### 0.1.7 发布与验收

0.1.7 包含 PR #19 的跨日与时区刷新，以及核心 UI 回归滚动辅助函数修正。发布说明及本轮真机检查步骤见 [0.1.7 发布记录](docs/releases/0.1.7.md)。[发布页](https://github.com/maxduke/card-pilot/releases/tag/v0.1.7) 用于获取 unsigned IPA 和 SHA-256 文件，实际发布完成状态以该页面和 Actions 为准。

本轮授权范围包括版本更新 PR、CI 通过后合并、主线 CI 验证、打 v0.1.7 标签、构建与核对发布附件，以及清理对应已合并分支。先完成发布和真机验收，再根据问题反馈进入下一批；不将 IPA 构建或模拟器测试视为真机验收通过。

### 后续顺序

1. **0.1.7 真机验收**：检查午夜刷新、后台跨日返回、常用时区切换、编辑输入保留与实际提醒，发现的问题优先修复。
2. **长期数据性能**：用 20 张卡、数年账期、数千笔交易测量 Release 首屏、搜索、保存、滚动与内存，再按测量结果优化。
3. **体验扩展与验收**：按使用反馈扩展已有交易、建卡和促销编辑草稿；补齐浅色、深色、大字号与 VoiceOver 验收。

每批独立实现、评审和验证，再按当前 AGENTS.md 工作流交付 PR。真机通知、认证、备份恢复、锁屏文件保护和呈现动画仍待验收；不得由合并、模拟器测试或 IPA 生成推定通过。

## 目标与边界

构建一个 iPhone、iOS 17+ 的简体中文原生应用，使用 SwiftUI、SwiftData 和本地通知管理信用卡账户、卡片、账务日期、单期或按月循环促销及手动促销分配。数据只保存在设备本地，不创建账号、后端或 CloudKit 容器。

首版结构化计算累计消费促销的累计达标门槛、累计计入上限和单笔计入门槛，以及逐笔优惠促销的已用和剩余笔数。累计笔数达标、阶梯、分类或分周期上限和奖励金额计算保留为文字规则，由用户确认的促销分配反映银行最终认可的促销事实。

明确不做：银行接入、交易同步、短信/邮件解析、OCR、AI 提取、多用户、服务端、复杂财务分析、奖励到账追踪、复杂促销叠加策略、部分还款和独立共享额度关系。

## 实现原则

- `CONTEXT.md` 是领域语言的唯一来源，ADR 是已接受的高成本决策来源。
- 业务日期使用不含时分秒的 `LocalDate`；完成时间、归档时间等事件才使用 `Date`。
- 金额使用 `Decimal` 和 ISO 4217 币种代码，禁止 `Double` 参与金额计算。
- SwiftData 只负责持久化；日期和进度算法写成无 UI、无数据库依赖的纯 Swift 代码。
- 不增加第三方依赖、Repository 层、通用规则引擎或网络抽象。
- 所有持久化对象使用稳定 UUID；使用 SwiftData `VersionedSchema`，首版不添加空迁移。
- 当前仍处于预发布测试阶段；本轮促销金额规则和卡片—卡组织关系重构允许清空一次本地测试数据，不为旧测试 Schema 编写迁移。此授权不适用于发布后的用户数据。
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
| `Bank` | `id`, 可选 `presetCode`, `name`, `notes`, `archivedAt` | 内置银行使用稳定 `presetCode` 保留图标与默认币种身份，每个代码最多一个 `Bank`；自定义银行不设置；名称必填；有引用后只能归档 |
| `CardNetwork` | `id`, 稳定 `code`, `displayName`, `isBuiltIn` | 预置银联、Visa、Mastercard、Amex、JCB；“其他”在选择器内创建，不做独立管理页 |
| `CreditCardAccount` | `id`, `bank`, `trackingStartCycleKey`, `creditLimit`, `limitCurrencyCode`, `status`, `closedOn`, `notes` | 追踪起始账期必须是有效 `YYYYMM`，新账户默认加入当月，或规则推算还款日尚未过去的最早账期，且首版不可编辑；额度可空，填写时必须大于零；active 必须无关闭日期，closed 必须有关闭日期，关闭动作原子更新两者 |
| `Card` | `id`, `account`, `productName`, `nickname`, `networks`, `lastFour`, `status`, `notes` | 卡组织至少一个；两个时只允许银联 + Visa、银联 + Mastercard 或银联 + JCB；末四位严格为四位数字；停用卡保留历史并可显式选择 |

一个账户可以有多张卡；共享额度、账单日和还款日的卡放在同一账户，各自独立的卡使用不同账户。首版不拆出 `CreditLine`，因此不支持“共用额度但账单规则不同”。

内置银行目录是非持久化的静态值列表，包含稳定代码、中英文显示名、大陆或香港地区、默认币种、图标资产名和显示顺序；只有用户选中时才创建或复用 `Bank`。编辑银行名称表示纠错或更新当前显示名，`presetCode` 不变；归档保证历史关系和银行身份不丢失，但首版不保存名称版本快照。

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
| `Promotion` | `id`, 可选 `seriesID`, 可选 `seriesIndex`, `title`, `startOn`, `endOn`, `organizingBanks`, `organizingNetworks`, `eligibleCards`, `enrollmentStatus`, `enrolledOn`, `enrollmentDeadline`, `qualificationDateBasis`, `stackingAllowed`, `qualificationThreshold`, `qualifyingCap`, `perTransactionThreshold`, `benefitTransactionCap`, `progressCurrencyCode`, `rules`, `exclusions`, `rewardDescription`, `notes`, `archivedAt` | 起止日包含边界；相同 `seriesID` 的各期仍是独立促销并按 `seriesIndex` 排序；金额规则均可选且填写时必须大于零；优惠笔数上限可选且必须是正整数，可与单笔计入门槛并用，但不可与累计达标门槛或累计计入上限并用；主办方或适用卡可以暂时为空，但为空时不会产生候选交易 |
| `PromotionAllocation` | `id`, `transaction`, `promotion`, `qualifyingAmount`, `currencyCode` | 金额必须是促销进度币种下的正数，零金额不保存为分配；每个“交易 × 促销”最多一条；币种必须与促销一致 |

银行主办方与卡组织主办方分别使用结构化关系，并与具体适用卡列表完全独立。主办方只推荐候选适用卡：同类主办方取并集，银行与卡组织之间取交集；候选项默认不确认，只有用户明确勾选后才进入适用卡列表。归档促销退出推荐和 Dashboard，但可以显式打开并修正或补录历史分配。

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

- 账单提醒提前天数，允许 `0...365`，默认 `[7, 3, 1, 0]`；
- 还款提醒提前天数，允许 `0...365`，默认 `[7, 3, 1, 0]`；
- 账单日、还款日提醒各自独立启停，默认开启；关闭后保留原提前天数；
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
- 进度为全部贡献的真实净合计，不在达标门槛或计入上限处封顶。
- 发现分配币种与促销进度币种不一致时返回数据错误，不参与静默汇总。
- 达标剩余金额为 `max(qualificationThreshold - progress, 0)`；可计入剩余金额为 `max(qualifyingCap - progress, 0)`，只在各自规则存在时显示。
- 同币种消费勾选促销时，单笔金额达到门槛则默认填交易总额，并按当前可计入剩余金额截取；未达门槛则不默认勾选并显示警告。用户始终可以手动勾选并填写银行认可的正金额。
- 跨币种不自动判断单笔门槛或默认分配，必须由用户填写促销币种下银行认可的合格金额；不保存汇率。
- 退款关联原消费时预选原交易涉及的促销，用户确认每项扣减金额。
- 退款只能关联同一卡片的消费；同币种累计退款超过原消费、或退款分配超过原促销分配余额时显示强警告但允许用户确认，跨币种不做数值上限推断。
- 逐笔优惠的已用笔数是具有正金额促销分配的不同、未冲正消费交易数；同一交易对同一促销最多计一笔。旧版遗留的零金额分配不计入金额或笔数进度。
- 退款分配不自动减少已用笔数；取消原消费的促销分配或将原消费标记为已冲正才释放一笔。
- 逐笔优惠只显示已用和剩余笔数，不根据奖励说明计算返现、积分或其他奖励。
- “特定消费”的商户、渠道或分类条件保留为规则说明，不做自动资格识别；记账时由用户确认促销分配，系统只对日期、适用卡和单笔金额给出可靠的候选与警告。
- 卡片、日期、报名或不可叠加冲突只产生警告，不阻止保存。

### 按月促销系列

- 首期起止日每次从原始锚点整体增加月份，不以上一期结果继续计算，避免月末逐期漂移。
- 同时支持自然月和跨月周期，例如 15 日至次月 14 日；不存在的名义日按该月月末处理。
- 创建时一次生成 `endOn <= repeatUntil` 的所有完整期，不截短最后一期，也不在后台隐式创建。
- 每期独立保存进度、报名状态、适用卡和交易分配；系列只表达连续关系。
- 有限系列在创建时已经完整生成，因此首版只用 `seriesID + seriesIndex` 分组，不增加没有独立状态的 `PromotionSeries` 持久化对象。
- 编辑时提供“仅本期”和“本期及以后”；后者覆盖共同条款及适用卡，但保留其他各期的日期、报名事实、归档状态与已有分配，历史期不允许批量改写。
- 单期促销提供“复制到下个月”，创建一个不属于系列的独立副本并按相同锚点规则平移日期；副本和新系列后续各期不继承已报名事实，需要报名时从尚未报名开始，报名日期为空。

### 候选促销

- 卡片必须在具体适用卡列表内，促销不得已归档。
- `transactionDate`：交易日期位于包含边界的促销期内。
- `postingDate`：有入账日期且该日期位于促销期内；缺少入账日期时显示“需补入账日期”，不自动分配。
- `unknown`：交易日期或已有入账日期任一符合即可。
- 候选列表之外仍提供搜索入口；手动促销分配始终是进度事实来源。

## 页面与交互

账户、促销和交易共用一个原生币种选择页：顶部显示最近使用，常用区优先显示 CNY、HKD、USD、EUR、JPY 和 GBP，并可按本地化名称或代码搜索 Foundation 提供的全部 ISO 4217 币种。ISO 代码是每项的主要身份，符号只作辅助；常用项使用 `CNY ¥`、`HKD HK$`、`USD $` 等不混淆的组合，不再用一列相同的 `$` 代表不同币种。大陆内置银行的新账户默认 CNY，香港内置银行默认 HKD，交易默认所选账户的额度币种。不使用长滚轮，不引入第三方币种数据。

### 视觉系统与外观

- 全局采用克制的原生 iOS 视觉：用清晰的信息层级、留白和系统控件建立品质感，不用装饰性渐变、拟物信用卡皮肤或大面积品牌色制造视觉噪音。
- 全局跟随 iOS 系统的浅色或深色外观，不增加 App 内独立主题开关。
- 背景、分组容器、文字、分隔线和状态优先使用 SwiftUI/iOS 语义颜色；唯一自定义品牌强调色在 Asset Catalog 提供浅色、深色和增强对比度变体。
- 银行与卡组织品牌色只用于识别徽标或局部卡片点缀，不承担文字可读性或业务状态语义。
- App Icon 使用“象牙白卡片 + 斜向航线 + 珊瑚色切角”；提交 1024×1024 Default 源图，Dark 和灰度 Tinted 由 iOS 自动派生，不将系统圆角烘进图片。
- 验收覆盖浅色、深色、增强对比度与 Dynamic Type；重要状态不得只靠颜色区分。

### 根导航

底部使用首页、卡片、促销、交易四个内容 Tab，并在正中保留“记一笔”动作项。动作项直接打开交易录入 sheet，不增加覆盖内容的第二层底栏；关闭后停留在原页面。交易页保留历史、筛选与编辑。设置由首页右上角按钮打开，不占底部核心位置。

桌面长按 App 图标只提供两个快捷操作：“记一笔”直达交易录入，并沿用上次使用卡的现有默认规则；“查看促销进度”直达促销页的进行中区域。已启用 App 锁时先验证再执行暂存的快捷操作，不得绕过锁屏。

### 首页

首页以消费后快速记账和处理日期事项为主，同时为消费前选卡提供低干扰的进度参考。顶部先按真实待办汇总“逾期 / 今天 / 未来 7 天”的事项数；“待处理”显示逾期、即将还款和临近报名截止，并同时显示相对与绝对日期；随后默认展开“继续完成”，只显示有明确剩余目标的进行中促销；再按账户聚合账期、账单日、还款日和状态。七天是首版集中定义、可直接修改但不暴露设置的默认阈值。

“继续完成”不任意截取前几个：累计达标门槛尚未达到，或逐笔优惠笔数上限尚未用完的活动全部以紧凑行展示，临近结束状态直接标在对应活动上，不再复制到“待处理”。每行显示活动名、适用卡、“还差金额”或“已用 / 上限笔数”、结束日期，点击直达促销期。已达标、已用完笔数、只有累计计入上限或只有文字规则的活动不进入该区域，仍可在促销页查看。

账户卡片显示银行标志、账户名、格式化后的“2026年9月账期”、账单日和还款日，不直接插值 `YYYYMM` 整数。还款操作使用明确的“标记已还”，完成后给出可撤销反馈；账单日不再用透明操作列占位。

不创建“需要关注的卡片”布尔字段或重复区域；每个项目直接展示原因和动作。整体使用原生 iOS 信息层级、语义材质和克制品牌色，不用装饰性渐变或卡片皮肤掩盖状态。

### 卡片

- 列表按银行和共享账户组织卡片；账户行只说明独立或共享账单关系，卡片行突出卡名、卡组织、末四位和下一还款时间，避免把配置规则铺在日常列表。
- 点击账户或卡片先进入只读详情，编辑放在右上角次级入口。卡片详情提供预选当前卡的“记一笔”、该卡交易、明确适用的活动和共享账期；账户详情展示当前规则、按生效月份标注的未来规则、近期账期及已还款记录。
- 主入口只显示“添加卡片”：按银行、卡片身份、账务信息的顺序引导，一次保存原子创建所需的银行、信用卡账户和卡片。
- 银行是单选步骤：点击内置银行后立即进入下一步，不再要求再次点击“继续”；自定义银行在名称有效后保留明确的继续动作。
- 内置可搜索的中国大陆常见全国性发卡行与香港主要发卡行；内置项使用本地品牌标志与品牌色，自定义银行使用文字徽标。“其他银行”固定置底并允许输入名称；首版不置大量地方银行。
- 大陆首批目录：工商银行、农业银行、中国银行、建设银行、交通银行、邮储银行、招商银行、中信银行、光大银行、民生银行、浦发银行、兴业银行、平安银行、广发银行、华夏银行、浙商银行、恒丰银行、渤海银行。
- 香港首批目录：汇丰、恒生、中银香港、渣打香港、东亚银行、花旗香港、星展香港、大新银行、中信银行（国际）、建行亚洲、工银亚洲。渣打香港和东亚银行补用现有 IconGo/bank-logos 来源中的 `sc.svg` 和 `hkbea.svg`；只捆绑来源与使用权清晰的品牌资产，其他情况使用文字徽标。
- 卡组织使用带本地真实品牌标志的固定选项网格：五种单标、银联 + Visa、银联 + Mastercard、银联 + JCB，以及固定置底的“其他”。五种内置标志统一使用现有 Apache-2.0 资产库的透明 `logo` 变体，在固定尺寸容器中保持原始比例和安全留白，不再使用银联带整块白底的 `flat` 变体，也不叠加额外白底。禁止用文字、圆形或色块近似重绘；自定义卡组织才使用文字徽标。不开放任意多选；双标卡并列显示两个真实标志。
- 同一银行已有卡片时，询问新卡是“独立账单与额度”还是“与已有卡共享账单与额度”；前者创建新账户，后者加入选定的已有账户。
- 银行管理从卡片页二级入口进入，提供编辑、归档和无引用删除；不要求用户预先创建银行。
- 首张卡跳过账户选择；共用已有账户时跳过账务录入。新账户在引导内录入初始规则，直接选择日期并预览本期账单与还款日期，可标记本期已还款；规则变更要求选择首个受影响账期并新增版本。
- 账户详情管理卡片、账期日期覆盖、还款完成记录、关闭账户。
- 新账户追踪起始账期默认加入当月；更早账期的还款日尚未过去时，从其中最早一期开始，并明确显示账期月份与已还款确认。首版不可编辑，不自动修改已有账户起点；Dashboard 从该账期生成至当前日期后两个月，并合并保存的未还账期。
- 默认隐藏停用卡；“显示停用卡”可用于历史交易录入。

### 促销

- 促销页回答“我有哪些活动、各期进度如何”，负责浏览和管理完整活动库，不复制首页的待办流。
- 顶层按“进行中、即将开始、历史”分区；进行中按最近结束日期排序，历史默认收起并支持搜索。归档项归入历史并保留状态标识，不再单设一个占据主层级的模式。
- 单期活动各占一张卡片；促销系列在顶层只占一张卡片，默认展示当前促销期，没有当前期时展示最近的下一期或最后一期。系列详情可在本期、往期和后续期之间切换，每个促销期仍保留独立进度、报名状态和适用卡。
- 列表卡片显示状态、当前或最近促销期的有效期和进度摘要；首页的“继续完成”与报名待处理项直达具体促销期，促销页的系列卡片进入系列详情。
- 表单包含多个银行/卡组织主办方、具体适用卡、报名信息、资格日期依据、叠加开关、说明字段，以及互斥的“累计消费”和“逐笔优惠”进度选项；两者都可使用单笔计入门槛，逐笔优惠只额外填写优惠笔数上限。
- 有达标门槛时，促销页详情显示达标进度和“还差”；有优惠笔数上限时，笔数为主进度并显示“已用 / 剩余”。只有计入上限时显示“已计入 / 剩余可计入”；达标门槛与计入上限都有时以达标进度为主、上限信息为辅；都没有时不显示误导性进度条，只显示净计入金额。
- 详情保留全部分配和规则说明。
- 有分配时只能归档；归档详情仍允许修正或补录分配。
- 选择主办方后显示“推荐适用卡”与匹配原因，提供“全选推荐”和逐张确认；推荐项默认不勾选，修改主办方也不静默删除用户已确认的适用卡。
- 搜索适用卡时，“全选搜索结果”只选择当前可见的推荐卡，避免搜索后误选隐藏项。
- 新建时可开启“每月重复”并选择系列结束日期，保存前预览将创建的完整期数；各促销期沿用活动标题，由系列详情中的日期和期次区分。
- 单期提供“复制到下个月”；系列期编辑时选择“仅本期”或“本期及以后”。

### 交易

- 按交易日期倒序分组展示，同一天使用稳定 UUID 排序但不表达真实先后；不新增交易发生时刻字段。月份变化处提供清晰分隔，退款和已冲正状态直接体现在金额与状态标签上。
- 顶部保留搜索，卡片、类型和促销条件收进统一筛选入口；启用筛选时显示可逐个移除的条件标签和“清除全部”，避免筛选控件长期占据导航栏。
- 每行只突出商户与金额，第二层显示卡片身份；没有促销分配时不占位，只有一项时显示促销名，多项时压缩为“已计入 N 个促销”。点击交易进入只读详情查看完整字段、促销分配、退款与冲正关系，编辑使用详情页中的显式操作。
- 交易录入按“当前卡片摘要 → 大金额输入 → 商户与日期 → 折叠的其他字段”排列。没有候选、已选活动或待补入账日期的活动时，明确显示“本笔不计入活动”并直接保存，同时保留手动选择活动入口。有相关活动时进入第二步确认，完整显示交易摘要、候选促销、计入金额和警告；确认保存后才写入交易及分配。
- 确认页只在已报名或无需报名的普通累计促销与交易币种一致、单笔金额达到门槛且建议计入金额大于零时默认勾选并填写建议金额；多个自动候选中有不可叠加活动时，由用户手动选择；逐笔优惠始终作为未勾选候选，由用户确认“特定消费”后勾选。没有已选促销时仍显示“本笔未计入促销”，并提供搜索全部促销的入口。
- 点击卡片摘要打开选择页，顶部显示最近使用，随后按银行分组，并可搜索银行、昵称、产品名或末四位；选择后立即返回。卡片项同时显示银行徽标、昵称或产品名、末四位和卡组织图标，适合 10–20 张卡且避免同名卡片混淆。
- 新交易默认选择上次成功记账使用的仍活跃卡片，该 ID 仅保存在 `AppStorage`；不存在时回退到第一张活跃卡。
- 从卡片详情记账时优先选择当前卡，包括停用卡的历史补录；保存后显示金额、退款类型及计入活动数量的短暂反馈并触发成功触感。
- 交易页在没有任何卡片时直接提供“添加信用卡”入口，不显示无法使用的空白添加操作。
- 金额使用大字号单行输入和系统十进制键盘，币种为可点按的紧凑选择项；未输入有效正数时底部保存或继续动作不可用。
- 选择卡片后默认账户额度币种，并列出候选促销。
- 可一次勾选多个促销；同币种默认全额，金额可内联修改；最近使用的分类提供自动补全。
- 非候选促销仍可搜索选择；所有冲突以明确警告显示但允许确认保存。
- 退款从原交易发起时自动建立关联并预选原促销；冲正是原交易动作，不是删除。

### 设置

- 账单日与还款日提醒分别显示为可点按的摘要行；编辑页提供“当天、提前 1 天、3 天、7 天”等常用选项和自定义提前天数，自动去重并从远到近排序，不再要求用户输入逗号分隔文本。
- 全局提醒时刻使用系统时分选择器，不再输入 `HH:mm` 文本。
- 常用时区固定解释账务日期与提醒，不随旅行自动改变；选择页置顶显示当前常用时区和设备时区，提供带 UTC 偏移与本地化城市名的可搜索列表，不再要求输入 IANA 标识符。
- 提醒计划显示已安排条数、下一次提醒与最早未安排时间，支持手动刷新；
- 通知权限状态与跳转系统设置，返回前台时刷新权限；
- 应用锁开关；
- 关于与隐私说明，明确“不保存完整卡号或 CVV”。

## 本地通知

实现一个 `NotificationScheduler` 和可替换的最小 `NotificationClient` 协议，生产实现包装 `UNUserNotificationCenter`，测试使用内存假实现。

- 使用不可重复的一次性 `UNCalendarNotificationTrigger`，避免规则变更和账期覆盖留下错误的重复通知。
- 请求标识固定为 `cardpilot.<accountID>.<cycleKey>.<statement|repayment>.<offset>`，重复调度幂等。
- 每次启动、回到前台、修改账务规则/覆盖/提醒设置、关闭账户或标记已还款后重新计算。
- 全部请求按触发时间排序，同一时刻优先还款；最多安排最早的 48 个，保证截断前没有更早遗漏。重建串行执行并以最新配置为准；先移除不再需要的自有请求，仍有效的请求在添加失败时保留。
- 标记已还款立即取消该账期尚未触发的还款提醒；Apple 官方支持按标识取消待处理请求：[本地通知文档](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)。
- 通知被拒绝时首页持续显示非阻塞提示，Dashboard 日期仍完全可用。
- 截断时不得静默：调度器返回下一次提醒、最早未安排日期与未安排数量，首页明确显示从哪一天起存在未安排请求，并建议减少提醒节点或稍后刷新。
- `ponytail:` 在 48 请求上限处记录：只有真实用户持续耗尽滚动窗口时才增加 `BGAppRefreshTask`；首版不引入不能保证运行的后台刷新。

## 应用锁与隐私

- `AppLockController` 使用 `LocalAuthentication` 的设备所有者认证：Face ID/Touch ID 优先，系统设备密码回退，不保存自定义 PIN。
- 启用前检查设备是否可认证；不可认证时禁止开启并解释原因。
- 离开 active 时立即显示覆盖页面和 sheet 的独立锁屏窗口；保留底层导航及编辑状态，禁用底层交互与无障碍访问；回到 active 时认证成功才移除。设备认证自身导致的 inactive 不重复锁定。
- 编辑页有未保存修改时禁止下滑关闭，点击取消需确认放弃；锁屏解锁保留输入。进程被系统终止后的磁盘草稿恢复尚未实现。账户编辑中撤销已还款只暂存，点击保存后统一提交。
- 从通知深链进入也必须先通过锁屏，认证后再导航。
- UI、模型、测试夹具和日志中均不得出现模拟完整 PAN 或 CVV；测试卡只使用末四位。
- “不存储完整卡号或 CVV”的边界落实在数据模型和专用输入界面；普通自由文本不做内容猜测或扫描，隐私说明提醒用户不要主动写入敏感认证信息。

## 实施顺序

### 1. 项目与持久化骨架

- 创建 iOS 17+、iPhone、SwiftUI App 生命周期项目和测试 targets。
- 加入简体中文 String Catalog、四个主页面加底部正中“记一笔”动作项的根导航，以及显式本地 `ModelContainer`。
- 实现 `LocalDate`、`VersionedSchema`、上述 SwiftData 模型及内存容器测试。
- 验收：干净安装可启动；无 iCloud entitlement、网络权限或第三方包。

### 2. 信用卡与账务引擎

- 完成 Bank、CreditCardAccount、Card CRUD 与安全删除/归档规则。
- 实现规则版本、账期计算、单期覆盖和还款完成记录。
- 先完成账务算法测试，再接卡片页和表单。
- 验收：共享账户与独立账户均可表达；规则变化不改写旧账期。

### 3. 促销基础

- 完成结构化多主办方、候选适用卡推荐、按月系列、复制、报名、日期依据、叠加标记和三种可选金额规则 CRUD。
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
- 完成 Default、Dark、Tinted App Icon 以及浅色/深色品牌颜色资产。
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
- 进度超过达标门槛或计入上限不封顶；退款后可重新变为未达标并恢复可计入额度；
- 归档促销不再推荐但允许历史修正。
- 候选适用卡的同类并集、跨类交集、默认不确认、全选推荐和主办方变化后保留已确认选择；
- 按月系列的自然月、跨月周期、月末钳制、锚点防漂移、完整末期边界、仅本期与本期及以后；
- 单笔门槛上下边界、累计计入上限的截取建议、手动覆盖、跨币种不自动建议，以及退款恢复可计入额度；
- 逐笔优惠的笔数上限边界、同一交易只计一笔、退款不释放与取消分配/冲正释放笔数；
- 逐笔优惠可与单笔门槛并用，但与累计达标门槛和累计计入上限互斥；
- 新分配拒绝零金额、旧零金额分配不计进度、未达单笔门槛不默认勾选，以及逐笔优惠候选默认不勾选；
- 只有达标门槛、只有计入上限、两者都有和两者都没有时的进度展示模型。
- 首页“继续完成”只纳入有明确剩余目标的进行中活动，完成后即使尚未到结束日也退出该区域；

### 数据完整性、安全与通知

- 有引用的银行/账户/卡片/促销无法硬删除；交易关联需显式解除；
- 内置银行代码唯一且大陆/香港默认币种正确；卡组织只允许五种单标和三种双标组合，“其他”始终置底；
- 模型 Schema 不含 PAN、CVV 或银行凭据字段；末四位验证拒绝非四位数字；
- 通知标识幂等、排序稳定、上限明确，完成还款会取消对应请求；
- 通知超过 48 条时按时间连续截断，同一时刻还款优先；最早未安排日期准确，交错重建以最新请求集合为准，失败保留有效请求；
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
