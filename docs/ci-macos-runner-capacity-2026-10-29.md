# 常规 iOS CI 的 runner 容量恢复

[PR #68](https://github.com/maxduke/card-pilot/pull/68) 的 `8398d9d` 在
[40701211159](https://github.com/maxduke/card-pilot/actions/runs/40701211159) 完整通过 231 项单元／集成和 95 项 UI，
零失败、跳过、用例重执行、workflow 重跑、测试进程重启或测试超时；两个通过用例中的内部点击恢复单独保留。
20 张相关原图已逐张实际验收，随后合并为 `737ffb9`。

该合并提交的 [main 40725364813](https://github.com/maxduke/card-pilot/actions/runs/40725364813) 两次均在 15 分 02 秒后取消。
两次检查注释均指出 hosted runner 多次分配失败，并明确提示 macOS arm64 容量受限；没有 runner、步骤、测试或产物，
日志 ZIP 为空。第二次是一次基础设施恢复，没有重试任何用例。仓库 Actions 已开启，没有竞争的 main 任务，
没有取消者记录；GitHub 总体状态正常也不能证明此资源池有可用容量。没有再启动第三次相同资源池的任务。

本次把常规 `.github/workflows/ios.yml` 的 runner 从 `macos-15` 改为 `macos-15-intel`。
[GitHub 的标准 runner 表](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) 明确区分这两个架构；
[macOS 15 Intel 镜像清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
列出现用的 `/Applications/Xcode_16.4.app`、iOS 18.5 runtime 和 iPhone 16 Pro。
宿主架构由 ARM64 变为 x86_64，完整 PR／main CI 需要在新宿主上重新通过，不能把此前 ARM 运行计为本次 Intel 结果。

实际 workflow 调整 runner 标签，并输出宿主架构和版本，便于核对真实执行环境；完整 326 项、Xcode 路径、模拟器、串行执行、执行额度、取证及退出状态均沿用原配置。
性能测量的独立 workflow 继续使用原 ARM 环境；本次不重测或重标已有读取／写入基线，不宣称性能或原生返回卡住有所改善。
本地检查核对 YAML 只有该参数和两条宿主日志命令变化、Xcode 项目没有阻止 x86_64 模拟器的架构限制及差异格式。
当前待本次 HEAD 的完整 PR CI、相关原图、适用审查与合并后的完整主线；镜像清单只证明兼容性预期，不代替实际执行结果。
