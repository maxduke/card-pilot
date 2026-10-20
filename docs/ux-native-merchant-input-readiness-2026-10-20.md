# 原生商户输入验证补修 · 2026-10-20

[PR #48](https://github.com/maxduke/card-pilot/pull/48) 合并后的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/39303226952) 未完成门禁。219 项单元／集成全部通过；既有 `testCorrectedAllocationDraftKeepsManualAmountAndAdvisoryWarning` 在输入商户时报告没有键盘焦点，随后完整作业达到 90 分钟上限取消。原工作区保留上次已验证的 `744aea9`，没有将取消视为成功，也没有重跑失败提交。

## 输入准备

操作日志显示，输入金额 `125.50` 后测试为寻找商户行执行一次滚动，该动作同时收起数字键盘。随后测试点击商户，但打字时商户未取得焦点；事件快照保留正确金额和空商户。取消后的 xcresult 缺少完成元数据，原图无法提取，因此不据此推定应用数据丢失或某个确切误点位置。

只调整这项用例的准备步骤：输入金额后真实点击已有“收起键盘”，等待键盘消失，再显露和填写商户；断言商户值并保留该步骤截图。后续无效分配、就近错误、`150.25` 手动金额、核对提示、草稿重启、实际保存和唯一交易读回的断言不变。应用及通用测试助手没有改动，也没有增加点击重试或固定延迟。

## 作业预算

取消前已完成 56／61 项 UI，其中 55 项通过、上述一项失败，UI 累计用时 5126.613 秒；第 57 项 `testTransactionSaveFeedbackClosesAcrossNestedPresentations` 仍在执行。作业未跑完最后五项便用尽 90 分钟，不能只靠修正单项输入认定预算足够。GitHub 完整测试作业调整至 120 分钟，保留 Xcode 16.4／iOS 18.5、串行、默认 180／最大 240 秒、全部 219＋61 项和原生产物导出。

## 交付验证

本地执行 Swift 语法、差异和原有断言保留检查；原生构建与实际交互仍由 GitHub workflow 验证。补修要求 PR 与合并主线均完整 280 项通过，零失败、零跳过、无超时或 runner 重启。检查当前绿色补修 HEAD 的“计入金额草稿商户输入”和“计入金额修正及核对提示”两张原图。第二十批应用代码未变，已验收的二十四张原图无需重复检查。

## 共享账期用例执行额度

[PR #49](https://github.com/maxduke/card-pilot/pull/49) 的 HEAD `107acb0` 在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/39317404272) 完整通过 280／280，两张受影响原图已实际验收；合并为 `a5ce697`。随后的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/39330388648) 在另一项既有用例 `testAccountCycleHistoryPersistsOlderUnpaidCycleRepaymentAcrossSharedCards` 达到默认 180 秒上限。日志显示 180 秒后仍继续操作还款状态筛选，读取数量及已还账期，185.53 秒进入清理；此前没有断言失败。原始查询截图和层级保留正确的历史账期，不能把超时诊断中的可能挂起视为已证实的应用挂起。

该用例含历史查询、实际还款、跨重启和另一张共享卡片的读回，仅为它设置已有的 240 秒最大额度。操作、断言、通用助手、应用代码、完整 280 项范围、默认 180 秒及全局最大 240 秒均保留。再次要求补修 PR 与合并主线完整绿色，不能以超时后重启继续的运行充当通过。此修改只涉及执行额度，不新增画面或交互，沿用已有原图验收；最终原生结果必须包含全部 61 项 UI 且没有超时或测试进程重启。

## 完成交付

[PR #50](https://github.com/maxduke/card-pilot/pull/50) 的 HEAD `a228e62` 在 [PR CI](https://github.com/maxduke/card-pilot/actions/runs/39342143802) 完整通过 280／280；合并提交 `967b36f` 的 [main CI](https://github.com/maxduke/card-pilot/actions/runs/39350400548) 同样完整通过，零失败、零跳过，无超时或测试进程重启。账期用例分别用时 49.963 秒和 48.879 秒。适用评审及未解决发现检查完成，原工作区在主线绿色后干净快进至该提交。
