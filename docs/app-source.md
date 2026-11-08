# CardPilot 软件源

- 安装入口：<https://maxduke.github.io/card-pilot/>
- 固定源地址：<https://maxduke.github.io/card-pilot/source.json>
- 支持 SideStore 和 AltStore Classic 的 AltSource 格式，提供一键添加和手动复制地址。

首次使用在工具的“软件源 / Sources”中点“＋”并粘贴地址，或用 iPhone 打开安装入口。软件源提供未签名 IPA；安装、续签及 Apple 账号限制仍由相应工具管理。

## 自动更新

`App source` 工作流在 `Unsigned IPA` 成功完成后生成并发布软件源。它读取默认分支的可信源码和已公开的 GitHub Releases，不执行触发它的构建分支代码、不下载该构建的工作流 artifact。这样也能接续由 `GITHUB_TOKEN` 创建的 Release，避免仅监听 `release: published` 时不触发的问题。

软件源只展示最新完整正式版，按数字版本排序；忽略草稿、预发布和缺少 IPA／SHA-256 的版本。下载地址固定到对应版本标签，不使用会随发布变化的 `latest/download`。重复构建旧标签不会将软件源退回旧版本。

发布前会核对 GitHub 资产大小和可用的资产摘要、实际 IPA 与校验文件、ZIP 完整性，以及包内版本、build、Bundle ID、iPhoneOS 平台与最低系统版本。隐私权限从包内 Info.plist 提取；当前为 Face ID 描述，未签名 IPA 没有附加签名权限。出现嵌套应用／扩展或不支持的权限格式时停止发布，需要先更新权限提取逻辑，不发布不完整的权限清单。

生成内容为 `source.json`、安装页与现有 AppIcon，通过 GitHub Pages 发布；不修改正式版标签、IPA 或主分支文件。生成或核验失败时不部署新站点，保留上一份有效软件源。

源生成脚本、安装页或工作流更新合入 `main` 时也会发布。需要手动刷新时运行：

```sh
gh workflow run app-source.yml --ref main
```

首次启用需要将本仓库 GitHub Pages 的发布方式设为 GitHub Actions（`build_type: workflow`）。工作流只有发布 job 拥有 `pages: write` 与 `id-token: write`；PR 只运行生成器测试。

## 本地验证

```sh
python3 -m unittest discover -s scripts/tests -p test_app_source.py -v
python3 scripts/build_app_source.py select --releases releases.json --output selected-release.json
python3 scripts/build_app_source.py build --release selected-release.json \
  --ipa CardPilot-unsigned.ipa --checksum CardPilot-unsigned.ipa.sha256 \
  --base-url https://maxduke.github.io/card-pilot --output /tmp/cardpilot-app-source
```

格式与添加链接依据 [AltStore 源规范](https://faq.altstore.io/developers/make-a-source)、[SideStore 软件源说明](https://docs.sidestore.io/docs/advanced/app-sources)及 [SideStore URL Scheme](https://docs.sidestore.io/docs/advanced/url-schema)。实际 iPhone 中添加和签名安装仍需设备验证，公开 JSON、下载资产和浏览器检查各自单独记录。
