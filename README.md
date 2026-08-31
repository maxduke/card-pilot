# CardPilot

CardPilot 是一个本地优先的 iPhone 信用卡、账单日期、还款提醒和促销进度管理工具。

- SwiftUI + SwiftData，最低 iOS 17
- 数据仅保存在设备本地；首版没有账号、后端或银行接入
- 只记录卡片末四位，不提供完整卡号或 CVV 字段

在 Xcode 中打开 `CardPilot.xcodeproj`，选择 `CardPilot` scheme 后运行。测试也会在公开仓库的 GitHub Actions macOS runner 上执行。

## 获取 IPA

GitHub Actions 的 `Unsigned IPA` workflow 支持手动运行，成功后会上传保留 7 天的 unsigned artifact。推送严格格式的版本标签（例如 `v0.1.0`）还会创建对应的 GitHub Release，并附带 IPA 和 SHA-256 校验文件。

unsigned IPA 没有 Apple 签名，不能直接安装到 iPhone。下载后请使用 Sideloadly、AltStore/SideStore 等工具，或使用自己的 Apple Developer 签名进行 sideload；具体安装限制由 Apple 账号类型和工具决定。应用最低支持 iOS 17。
