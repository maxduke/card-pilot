# 核心流程 UI 自动化（2026-09-09）

## 范围

`CardPilotUITests/CoreFlowsUITests.swift` 通过 XCUITest 操作真实 SwiftUI 页面与 SwiftData 保存路径：

- 空库从“记一笔”进入建卡，选择内置银行、沿用默认账务规则、填写产品与末四位；重启后打开卡片详情和空交易历史。
- 卡片详情记账：125 CNY 消费默认建议计入累计活动，手动改为 100 CNY 后确认；重启后从交易详情检查分配，进入活动详情检查 100 / 1,000 CNY 进度。
- 同一账户两张卡：第一张标记账期已还，重启后从另一张的账户详情打开相同已还账期并撤销，再重启确认原卡显示未还操作。
- 无适用活动的卡直接保存 50 CNY 消费，检查交易详情无促销分配；空金额时保存不可用。

测试使用显式控件标识、状态等待和有上限的滚动，不依赖固定 sleep。失败保留截图与无障碍层级。当前控件标识中的名称仅用于定位受控夹具，不要求业务名称唯一。

## 测试隔离

`UITestBootstrap` 仅在 `DEBUG && targetEnvironment(simulator)` 编译。只有合法场景（`empty` / `core`）和 UUID session 同时存在才启用，Release 和真机版本没有此入口。

每条用例生成独立 UUID，在模拟器临时目录创建独立磁盘库与恢复目录。首次启动播种，后续启动读取同库，便于验证持久化；不清除用户数据库。测试 runner 通过进程参数覆盖语言、时区、应用锁、提醒开关与最近使用卡，不删除持久化偏好。夹具只有末四位，不含完整卡号或 CVV。核心夹具日期相对启动当天生成，活动覆盖前 7 天至后 30 天，账户从当前月份追踪；不依赖固定日历日期。临时库由模拟器临时目录生命周期管理。

## 运行与 CI

共享 `CardPilot` scheme 包含单元测试和 UI target。选择实际存在的 iPhone 模拟器：

```bash
xcrun simctl list devices available
xcodebuild test -project CardPilot.xcodeproj -scheme CardPilot \
  -destination 'platform=iOS Simulator,id=<available-device-UUID>' \
  -only-testing:CardPilotUITests -parallel-testing-enabled NO \
  -resultBundlePath TestResults.xcresult CODE_SIGNING_ALLOWED=NO
```

不添加 `-only-testing` 即运行完整测试。iOS CI 串行运行、放宽单条用例超时以容纳启动与输入，并始终上传 `.xcresult`（7 天）。Linux Docker Swift 6.1 已通过源码语法解析，scheme XML、项目对象引用与 `git diff --check` 通过；这些不能替代原生编译和模拟器测试，原生 CI 结果在 PR 交付中记录。

## 保留手动验收

- 按 `notification-billing-loop-2026-09-08.md` 执行真实通知授权、5 秒测试提醒、前后台与冷启动通知定位，覆盖打开编辑 sheet 时的呈现顺序。
- 真机开启应用锁，验证 Face ID / Touch ID / 设备密码成功与失败、后台遮罩、锁定期间通知等待，以及解锁后的输入保留。
- 检查建卡与交易键盘、sheet 动画、浅色/深色、大字号及 VoiceOver；UI 测试通过不等同于这些体验验收通过。
- 完整备份与系统文件面板继续按 `backup-restore-2026-09-08.md` 验收。

四条 UI 用例及新增夹具完整备份校验往返测试已通过原生 CI [run 34311465007](https://github.com/maxduke/card-pilot/actions/runs/34311465007)。最终评审指出夹具的内置 Visa 必须使用规范 UUID，已改为 `CardNetwork.makeBuiltIns()` 并新增校验；滚动手势位于列表边缘，并避开键盘与固定按钮栏，防止误触活动开关。
