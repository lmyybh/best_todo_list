# 桌面应用更新

## 用户体验

- 手动检查始终可用；自动检查默认关闭，可在“关于与更新”开启。
- 开启后，启动 20 秒后及每 12 小时检查。没有新版或网络不可用时不弹窗。
- 新版提示出现在侧栏底部。用户确认下载后，在应用内显示字节进度。
- 弹窗关闭不取消下载，再次打开保留进度；可明确取消并重新下载。
- 下载完成先校验，再显示“重启并更新”。不自动退出、不自动安装。
- 已完成的下载跨启动保存，恢复及安装前都会重新验签和校验文件。
- 安装失败时保留下载包，显示错误详情与手动下载入口。
- 旧 Release 没有签名清单，或当前应用没有嵌入公钥时，保留 Windows
  WinSparkle / macOS 浏览器下载作为兼容路径，不降级为执行未验证的安装包。

## 更新信任链

正式构建通过 `--dart-define=UPDATE_PUBLIC_KEY=<base64 Ed25519 公钥>` 固定可信公钥。
GitHub Release 提供 `update-windows.json` 和 `update-macos.json`，格式为
`{"payload":"base64 原始 JSON 字节","signature":"base64 Ed25519 签名"}`。
载荷包含 `version`、`platform`、`url`、`length`、`sha256`。

客户端首先验证载荷签名，再检查版本、平台和仓库内的固定版本 HTTPS 下载地址，
最后流式下载并校验文件长度及 SHA-256。私钥只用于发布，不进入应用或仓库。
签名错误、断流、超时、取消和文件被篡改都不能产生可安装状态。

首次配置时，在仓库外创建签名种子：

```bash
dart run scripts/sign_update.dart --generate-key /secure/path/update-seed
```

命令输出公钥。将公钥配置为 GitHub Actions repository variable
`UPDATE_PUBLIC_KEY`，种子文件的内容配置为 secret `UPDATE_SIGNING_SEED`。
备份种子并限制读取权限。公钥一经发布应保持稳定；更换公钥需要另外设计可信迁移，
不能直接覆盖变量后期望旧客户端接受新签名。

## 安装与数据

Windows 使用当前用户 Inno Setup 安装器，不请求管理员权限。
仅支持已安装在 `%LOCALAPPDATA%\Programs\BestTodoList` 的正式应用原地更新。
退出前等待 SQLite 写入队列清空，保存失败会阻止重启。独立助手收到明确提交信号并
等待旧进程退出后，执行静默安装，禁止重启系统、禁止强制关闭其他应用，然后启动应用。
安装助手不能启动或无法完成退出准备时，当前应用继续运行。

macOS 使用经过 Developer ID 签名、公证并装订票据的通用 ZIP。
客户端再检查代码签名、Gatekeeper 评估、TeamIdentifier 和 bundle identifier。
安装前先在同一磁盘准备替换包，助手等待旧进程退出后重命名替换并重新启动。
替换或启动命令失败时尝试恢复旧包。之前的应用包保留为隐藏的 `.todo-update-*.app.backup`
供手动恢复；不保证检测新进程启动之后的崩溃，不做数据库版本回退。
应用所在目录不可写、应用仍在 DMG 中或签名不一致时拒绝自动替换，提供手动下载。

此发行方式使用 Developer ID，不使用 App Sandbox；沙盒应用不能自行替换应用包。
macOS 数据库迁移到 `getApplicationSupportDirectory()/data/best_todo_list.sqlite`，
迁移来源为此前 sqflite FFI 使用的当前启动目录下 `.dart_tool` 数据库，原文件保留。
如果旧版本曾以不同工作目录启动，应先定位旧库并备份，再迁移到此固定路径。
Windows 数据库继续独立存放在 `%LOCALAPPDATA%\BestTodoList\data`。
更新缓存与自动检查设置位于应用支持目录下 `updates/`，不与任务数据库混用。

已有编辑器在失焦时提交修改，更新弹窗会转移焦点；安装前再次等待写入队列。
尚未提交的新任务草稿需要用户提交或放弃后再重启。

## 发布流程

`.github/workflows/desktop-release.yml` 在推送 `vX.Y.Z` tag 时执行，也支持选择该 tag 手动运行。
`pubspec.yaml` 的版本必须和 tag 一致。Flutter 固定为 3.47.2。

1. 静态分析与全部测试通过。
2. Windows 和 macOS 分别构建、平台签名、生成并自验签更新清单。
3. 两个平台都成功后创建 draft Release，上传完整产物，再公开并标为 latest。
4. 已有 Release 的资产禁止覆盖。任一构建失败不发布新版，也不改变最新更新源。

除了更新签名种子，Actions 需要以下 secrets：

| 平台 | Secrets |
|---|---|
| macOS | `MACOS_CERTIFICATE_P12`（P12 的 base64）、`MACOS_CERTIFICATE_PASSWORD`、`MACOS_SIGNING_IDENTITY`、`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD` |
| Windows | `WINDOWS_CERTIFICATE_PFX`（PFX 的 base64）、`WINDOWS_CERTIFICATE_PASSWORD`、`WINSPARKLE_DSA_PRIVATE_KEY`（兼容旧客户端的原 DSA PEM） |

Windows runner 需要 Windows SDK signtool、Inno Setup 6 和 OpenSSL。
macOS runner 使用临时钥匙串导入证书，以 notarytool 公证，stapler 装订后重新打包并签署清单。
`build_macos_update.sh`、`build_windows_update.ps1` 也可本地运行，参数见脚本。
旧客户端的 `appcast-windows.xml` 继续生成，其安装包链接已固定到对应版本。

## 发布验收

本地自动化覆盖验签、文件篡改、下载取消与重试、缓存恢复、进度、自动检查、弹窗关闭继续下载、
安装准备失败及写入等待。它们不能代替真实系统上的签名安装和跨版本升级测试。

发布前仍需实际配置证书与 secrets，从前一个正式版本在 Windows/macOS 各升级一次，
验证已有任务、日期、备注保留，重启后版本变化，取消及离线重试正常。
证书、Apple 公证账户、GitHub secrets 和真实跨版本验收不由本地代码变更自动完成。
