# 第二十六批：Release 性能基线

O19 指出了全量交易查询、交易分组、重复账期计算、逐次草稿写盘和金额格式化等静态关注点。本批先建立可复现的测量，首次原生预检暴露了交易列表中的大量重复计算；据此先做单次页面更新内的计算复用。

## 首次原生预检与针对性修复

[运行 39842446195](https://github.com/maxduke/card-pilot/actions/runs/39842446195) 使用源码 `e7faa4c`、诊断 HEAD `fa76b65` 的实际 Release，在两万笔场景的准备阶段点击交易页后无法完成 AX 快照；三项均失败，且发生测试进程重启／重执行。它没有进入有效采样，指标 JSON 为空，不能作为正常启动、搜索或滚动的性能数值。

两份保留的系统 spindump 分别记录了 `6248.33 MB` 和 `7051.86 MB` 的 App footprint。主线程样本包括 `TransactionsView.body` 的分组闭包 → `transactionSections` → `groupedTransactionsByDate` → 全量分组与 UUID 排序。源码确认每次读取 `transactionSections[sectionIndex]` 都会重新筛选、分组及排序全部交易；分组越多，重复工作越多。记录能够支持这个具体热点，但不表示已经排除了全部性能原因。

修复仅在 `TransactionsView.body` 本次更新中保存筛选结果，并在有结果的分支中计算一次分组，供所有 Section 使用；结果数也读取同一份筛选结果。没有跨更新缓存、后台模型传递或新的状态层；原筛选口径、日期及 UUID 顺序、Section 索引身份和全部业务动作保持不变。新一轮原生预检仍使用相同的两万笔场景、十个有效样本、断言和 600 秒专用用例时限，验证是否解决该热点。

第一次导出还因测试超时后模拟器处于 Shutdown 而无法调用 `get_app_container`，未取得数据报告和有效界面原图。导出改为读取本次已记录的模拟器 `dataPath` 下的隔离报告；不为导出重启模拟器或重跑测试。原失败的日志、xcresult、spindump 和空指标均保留。

## 场景与隔离

三个场景分别含 100、5000、20000 笔交易，均有 10 家银行、10 个共享账户、20 张卡、5 年追踪范围内的 610 个显式账期，以及两个各含 12 期的月度促销系列。历史账期均标记已还，当前期保留未还；消费均为 CNY，日期均匀分布，近期消费具有合法促销分配。它们是明确的合成场景，不代表用户真实数据分布。

每项测试使用独立 UUID 的模拟器临时存储；第一次启动完成造数、保存、关系／领域校验及实际查询数量、日期范围和搜索命中数的报告，然后才测量。重新启动复用同一存储。缺少完成报告的性能存储拒绝复用，避免把未完整准备的数据当作基线。普通存储、Schema、备份和草稿格式均不变。

新增一项 Debug 原生回归，在月末和年末日期通过完整备份验证及恢复，检查共享账户、历史还款、跨五年日期和当前期分配。较大场景的实际数量与领域校验在各自原生准备阶段执行，并随结果保存。

## 测量边界

专用 `CardPilotPerformance` scheme 使用 Release、关闭调试器、代码覆盖和运行时 sanitizer。只有专用工作流显式定义 `PERFORMANCE_TESTING`，让模拟器 Release 可以使用同一套隔离存储入口；没有向 Release 添加 `DEBUG`，没有开启 `ENABLE_TESTABILITY`。未定义该标记的发布版仍使用原来的存储入口。

21 项性能用例覆盖每种规模的七条路径：

- 已造数存储的进程冷启动：记录 Apple 的首次响应 launch metric，以及启动到实际首页账期行就绪的时钟时间。
- 进程仍在后台时恢复前台：计时前确认后台状态，记录恢复到首页就绪的时间。
- 卡片、促销、交易页各自的首次进入：每个样本重新启动，确认首页就绪后再计时，直到目标页真实卡片／促销行或交易数和最新交易出现。
- 交易搜索：从空查询输入固定五位数字，直到完整命中数显示。清空查询和恢复全列表在计时外完成。
- 交易滚动：每次从新启动的列表顶部执行两个相同速度的原生手势，保留系统滚动／减速指标，检查列表确实离开顶部。

每项采集十个有效样本，XCTest 额外的首轮预热不计入。交互同时记录目标 App 内存指标；以原生导出中的指标名称和单位解释增长、峰值等含义。准备、造数、页面复位、截图均在计时外。进程冷启动不等于清除操作系统缓存的设备冷启动，首次进入也可能复用内核文件缓存。

时钟窗口包含 XCTest 输入、快照与就绪断言的开销，是固定工具链下的端到端基线，不能直接解释为纯 App 主线程耗时。搜索 p50／p95 应由原始十个样本计算并标注样本数和分位数算法；十个样本对尾延迟的判断有限。发现差异后需用 Instruments 缩小实际耗时来源，再实施生产优化。

## GitHub workflow 与验收

新增手动触发的 `.github/workflows/ios-performance.yml`，固定 macOS 15、Xcode 16.4、iPhone 16 Pro／iOS 18.5，并在同一宿主串行执行三个规模。它先保存并检查构建设置中的 Release、`-O` 和不含 `DEBUG` 的标记，再保存版本、宿主硬件、设备、源码提交、时间、原生 xcresult、指标 JSON、会话、数据报告和实际界面截图。暂不设置没有测量依据的性能阈值，也不加入每个 PR 的必跑门禁。

既有 `.github/workflows/ios.yml` 和 `CardPilot` scheme 保持原样。普通回归不会发现被专用编译标记隔离的 21 项性能测试；本批增加一项夹具完整性回归。交付时先完成前两批依赖集成，再运行当前 HEAD 的正式原生回归和完整性能采样；预检与最终基线分别记录源码，不能把旧二进制数据写成新 HEAD 结果。

当前代码已完成本地 Swift 语法、scheme／YAML 结构及 shell 校验；Linux 不能验证 SwiftData、XCTest UI 和系统测量的原生行为。首次原生失败的证据见上；修复后的完整样本、指标格式与实际画面仍待 GitHub workflow 验证，不能据此宣称性能改善或 O19 已全部完成。快速输入、草稿写盘、保存及真机性能是后续有界测量范围。

## 依据

- [Apple：编写和运行性能测试](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)：Release、调试／诊断设置和指标测量。
- [Apple：采样次数](https://developer.apple.com/documentation/xctest/xctmeasureoptions/iterationcount)：预热轮和有效样本的区别。
- [Apple：应用启动指标](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric/init(waituntilresponsive:))：首次响应边界。
- [Apple：滚动与减速指标](https://developer.apple.com/documentation/xctest/xctossignpostmetric/scrollinganddecelerationmetric)：原生滚动测量。
- [Apple：Xcode 16.3 发布说明](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes)：原生指标 JSON 导出命令。
