# 桌面端手动更新开发计划

## 目标与范围

为 macOS 和 Windows 桌面应用提供由用户主动触发的版本检查与更新能力。

本计划分三个阶段实施：

1. 应用内展示当前版本，手动检查 GitHub 正式 Release，发现新版后打开浏览器下载。
2. 接入 Sparkle/WinSparkle，在应用内完成下载、校验、安装和重启。
3. 通过 Git tag 和 CI 自动构建、签名、发布并生成更新源。

不在当前范围内：移动端、强制更新、后台定时检查、灰度发布和数据格式降级。

## 基本约定

- `pubspec.yaml` 是应用版本的唯一来源。
- Git tag 与 Release 使用 `v主版本.次版本.修订版本`，例如 `v0.2.0`。
- build number 必须递增，例如 `0.2.0+2`。
- 正式版本来自 `lmyybh/best_todo_list` 的最新非草稿、非预发布 GitHub Release。
- 更新失败不得修改应用文件或用户 SQLite 数据。

## 第一阶段：检查并跳转下载

### 功能

- 左侧导航栏提供“关于与更新”入口。
- 弹窗展示当前版本和 build number。
- 用户点击“检查更新”后请求 GitHub 最新正式 Release。
- 最新版本较新时展示版本号和发布说明，并提供“前往下载”。
- 已是最新版、尚无 Release、网络错误和响应异常均显示明确结果。
- “前往下载”使用系统默认浏览器打开 Release 页面。

### 技术设计

- `package_info_plus`：读取当前应用版本。
- `http`：访问 GitHub Releases API。
- `url_launcher`：打开 HTTPS Release 页面。
- `UpdateService`：隔离平台信息、网络请求和外部 URL 打开操作。
- 版本标签只接受 `vX.Y.Z` 或 `X.Y.Z`，按三个数字段比较。
- macOS DebugProfile 和 Release entitlement 允许出站网络访问。

### 验收标准

- `v0.2.0` 相对 `0.1.0` 被识别为新版。
- 相同或更低版本显示“已是最新版本”。
- GitHub 返回 404 时显示“尚未发布可用版本”。
- 网络或非法响应不会关闭弹窗或影响现有数据。
- 发现新版后能够打开对应 GitHub Release 页面。
- 格式化、静态分析和全部自动化测试通过。

## 第二阶段：应用内安装

### 阶段 2A：Windows 安装器

- 使用 Inno Setup 生成单文件 Setup EXE，不发布 ZIP。
- 采用当前用户安装，固定路径为
  `%LOCALAPPDATA%\Programs\BestTodoList`，不要求管理员权限。
- 使用固定 AppId 支持原地覆盖升级，并创建开始菜单与卸载入口。
- 安装器只管理程序目录；Windows 数据库独立保存在
  `%LOCALAPPDATA%\BestTodoList\data\best_todo_list.sqlite`，不随覆盖升级或卸载删除。
- 通过 `scripts/build_windows_installer.ps1` 自动读取应用版本、构建 Flutter
  Release 并输出版本化安装器。

### 功能

- 使用 `auto_updater` 对接 macOS Sparkle 和 Windows WinSparkle。
- 用户确认后下载安装包、退出应用、安装并重新启动。
- 保持手动检查，不启用启动检查或后台计划任务。

### 发布产物

- macOS：Developer ID 筿名、公证并带 Sparkle EdDSA 签名的 ZIP 或 PKG。
- Windows：带 Authenticode 签名的 Inno Setup、MSI 或 NSIS 安装器。
- 分平台提供 `appcast-macos.xml` 和 `appcast-windows.xml`，全部通过 HTTPS 发布。

### 安全要求

- 更新归档必须通过 Sparkle/WinSparkle 签名验证。
- 私钥只能保存在开发机安全存储或 CI Secret，不得提交到仓库。
- App 内不得嵌入 GitHub Token。
- 必须从上一个正式版本执行真实升级测试。

## 第三阶段：发布自动化

- 推送正式 Git tag 后分别在 macOS 和 Windows runner 构建。
- 执行平台代码签名和 macOS 公证。
- 创建 GitHub Release 并上传平台安装包。
- 生成、签名并部署两个 appcast 文件。
- 发布任务在任一步失败时不得更新 appcast，避免客户端发现不完整版本。

## 回滚策略

- GitHub Release 资产保持不可变；修复版本使用新的版本号重新发布。
- appcast 在第二阶段保留最近若干正式版本，紧急情况下指向已验证的新修复版本。
- 数据库迁移保持只向前且兼容旧数据；程序更新流程不直接操作数据库文件。
