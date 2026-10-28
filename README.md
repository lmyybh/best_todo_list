# todo

一款使用 Flutter 构建的 macOS 与 Windows 本地事件树 Todo 应用。节点没有固定的“事件”或“任务”类型：有子节点时是事件，没有子节点时就是可完成的任务。

界面基于 Material 3 和 Flutter 官方控件，采用暖灰纸张与深青绿的浅色桌面设计。当前维护 macOS 与 Windows 桌面运行目标，暂不考虑手机端。

## 当前功能

### 事件总览

- 同时展示多个顶层事件卡片，窗口宽度变化时自动调整为 1～4 列
- 使用“今日”快速聚焦包含今天截止或逾期未完成任务的事件，并保留任务所在的祖先分支
- 在卡片中查看任务树、展开或折叠分支，并直接完成叶子任务
- 卡片默认预览三层任务结构；更深层级可进入详情继续查看和编辑
- 从卡片底部快速添加直接子任务，也可以在任意任务行上继续添加子任务
- 把任意子任务直接拖到其他事件或任务下，并自动阻止循环嵌套
- 双击任务标题或按 `F2` 原地重命名；顶层事件可通过卡片菜单重命名
- 拖动顶层卡片调整事件顺序；任务行的同一拖拽柄可调整顺序或父子层级
- 删除节点时软删除整棵子树

### 节点详情

- 点击事件或任务标题打开右侧详情面板，点击面板外空白处或“关闭详情”返回总览
- 编辑标题和备注，查看创建时间、完成时间及任务进度
- 设置仅日期的截止期限，或进一步指定精确到分钟的时间
- 快速添加、打开、完成及拖动排序直接子任务
- 叶子任务可以完成或取消完成；事件状态由所有后代叶子任务自动汇总

### 日程

- 日历仅展示有截止日期的叶子任务，父级信息通过悬停面包屑呈现
- 默认周视图，右上角独立按钮切换日／周／月；点击日期字段按当前模式选择单日／整周／月份，前后翻页按钮独立显示，提示随模式显示上一／下一天、周或月；离开今天所在日／周／月时显示“回到今天”
- 日期字段按日／周／月各自固定格式和宽度：`YYYY.MM.DD 周几`、`YYYY.MM.DD — YYYY.MM.DD`、`YYYY.MM`；月日补零，跨月跨年不改变宽度
- 日期弹层复用 Apache-2.0 开源组件 `calendar_date_picker2` 3.0.0，提供中文日期网格与年月快速选择
- 日／周视图顶部展示日期期限，时间轴按保存的起止时间显示拖选任务；未指定开始时间的任务以截止前 30 分钟显示。月视图展示整月事项，密集日期可展开更多条目
- 日／周时间轴可用鼠标拖选时段新建任务，按 15 分钟吸附并保存完整区间；弹窗只填写名称和必填的所属事件，输入不存在的事件名称时与任务一并创建，不重复设置时间
- 月视图双击日期格空白处可复用同一弹窗新建任务，默认安排在该格日期的 12:00–12:30，同样必填所属事件
- 月视图每项任务独立显示为紧凑任务行，使用浅色背景和细色条；按单元格高度显示任务，余下条目通过小号灰色“+N 项”按实际任务数展开
- “+N 项”在日期格旁打开紧凑白色任务列表，显示日期、实际任务数、完成状态、事件色点和时间；按时间排序，任务逐项列出，支持内部滚动、点击详情及点击外部关闭
- 悬停日历条目可查看完整父级面包屑、当前任务状态与备注（有备注时显示）
- 日／周视图中同一天时间重叠的任务按创建时间从左到右独立并列显示，自动分配宽度并填满日期列；空闲列可自动扩宽，保留每项任务的颜色、悬停信息及详情入口；拖拽选择时段的预览始终占满日期列，不参与任务分列
- 日历条目沿用所属顶层事件的颜色；已完成事项在原截止日期显示完成标记
- 点击日历条目在当前日程右侧打开共用详情；编辑标题、期限和完成状态后两边同步
- 事件详情的“在日程中查看”定位并高亮截止事项；详情中的祖先路径可返回事件树并展开定位
- 两个视图分别保留滚动、展开、日历模式与日期位置
- 日视图日期旁展示星期；周视图日期表头仅用于展示，月视图可点击日期标题进入当天视图
- 通过“任务列表”返回原有树状日程，查看逾期汇总、未定日期和实际完成／放弃记录

任务列表保留以下功能：

- 使用“完整一周 + 更晚”的日期条浏览任务
- 按周向前或向后切换，并可随时回到今天
- 今天的列表会将逾期未完成任务单独置顶
- 日期内按事件树展示相关任务，自动补齐祖先上下文，并支持逐层或全部展开折叠
- 已完成任务按实际完成日期归档，并按完成时间倒序显示
- “更晚”包含当前日期窗口之后的未完成任务，以及未设置截止日期的叶子任务
- 日程中的条目保留所属路径；点击后会跳转到对应节点详情

### 本地数据

- 使用 SQLite 文件 `best_todo_list.sqlite` 持久化节点、层级、排序、备注、截止时间和完成状态
- 数据保存在本机，不需要账号或网络连接
- macOS 关闭最后一个窗口后应用仍会运行，可重新点击应用恢复窗口，并使用 `Command+Q` 完全退出；Windows 关闭窗口即退出应用

## 常用操作

| 操作 | 鼠标 / 键盘 |
| --- | --- |
| 新建顶层事件 | 点击左侧导航栏的 `+`，或事件总览末尾的“新建事件”卡片 |
| 快速添加子任务 | 点击卡片底部“添加任务”，或悬停任务行后点击 `+` |
| 完成任务 | 点击叶子任务前的圆点 |
| 打开详情 | 点击事件卡片标题或任务行 |
| 原地重命名任务 | 双击任务标题，或聚焦任务行后按 `F2` |
| 保存 / 取消内联编辑 | `Enter` / `Esc` |
| 调整事件顺序 | 拖动卡片标题区；聚焦后按 `Option`（macOS）或 `Alt`（Windows）+ 方向键移动一步，增加 `Shift` 移到首尾 |
| 调整任务位置 | 拖动任务行手柄；放到行的上下边缘调整顺序，放到行中部成为其子任务，放到卡片任务列表成为该事件的直接子任务 |
| 切换日程日期 | `←` / `→` |
| 取消正在进行的拖动 | `Esc` |

## 当前不包含

账号与同步、提醒、搜索、标签、优先级、重复任务、附件、导入导出、回收站，以及日程拖拽改期。目前也没有手机或平板布局。

## 运行

环境要求：

- macOS 及 Xcode，或 Windows 及 Visual Studio 的“使用 C++ 的桌面开发”工作负载
- Flutter 3.44 或兼容的稳定版本
- Dart 3.12 或兼容版本（见 `pubspec.yaml`）

开发调试并实时查看改动：

```sh
flutter pub get
flutter run -d macos   # macOS
flutter run -d windows # Windows
```

应用运行后，在终端按 `r` 热重载，按 `R` 热重启，按 `q` 退出。

macOS 上预览构建后的开发版，请使用：

```sh
bash scripts/run_macos_preview.sh
```

脚本将应用复制到独立临时目录再启动，后续构建不会覆盖运行中的 SQLite 动态库。请避免直接运行 `build/macos/Build/Products/Debug/todo.app` 后继续构建；这会使运行中的原生库被替换，导致下次保存或关闭数据库时闪退。

## 构建桌面应用

在项目根目录执行 Release 构建：

```sh
flutter pub get
flutter build macos --release   # macOS
flutter build windows --release # Windows
```

构建产物位于：

```text
macOS:   build/macos/Build/Products/Release/todo.app
Windows: build/windows/x64/runner/Release/
```

Windows 可以进一步构建当前用户安装器。安装
[Inno Setup](https://jrsoftware.org/isinfo.php) 后，在项目根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_windows_installer.ps1
```

安装器输出到 `build/installer/`，默认安装到
`%LOCALAPPDATA%\Programs\BestTodoList`，不需要管理员权限。
Windows 数据库独立保存在
`%LOCALAPPDATA%\BestTodoList\data\best_todo_list.sqlite`，覆盖升级和卸载不会删除任务数据。

macOS 可以使用以下命令直接打开：

```sh
open build/macos/Build/Products/Release/todo.app
```

macOS 也可以生成用于本地安装测试的 DMG（需要在 macOS 上执行）：

```sh
chmod +x scripts/build_macos_dmg.sh
scripts/build_macos_dmg.sh
```

DMG 输出到 `build/installer/best_todo_list-<version>-macos.dmg`。该产物未经
Developer ID 签名、公证或 Sparkle 更新签名，不能直接用于公开发布。如果已经有
版本与 `pubspec.yaml` 一致的 Release 构建，可跳过 Flutter 构建步骤：

```sh
scripts/build_macos_dmg.sh --skip-flutter-build
```

## 检查与测试

应用内更新支持后台下载、验签、重启安装和可选的自动检查。正式发布需要固定的
更新公钥及平台签名证书；配置、构建命令和 GitHub Actions secrets 见
[桌面应用更新](docs/desktop-update-plan.md)。未配置公钥的开发构建使用兼容更新流程。

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build macos --release   # 在 macOS 上执行
flutter build windows --release # 在 Windows 上执行
```

自动化测试覆盖节点树规则、同级排序、时间线日期边界、SQLite 升级与重开恢复，以及事件总览、详情和截止日期等核心 Widget 流程。

## 项目结构

```text
lib/
  app/       应用入口、状态控制器和主题
  data/      SQLite 数据库与 Repository 实现
  domain/    Node 模型、事件树规则和时间线查询
  ui/        事件总览与详情、时间线、桌面外壳和公共组件
test/        领域、数据、控制器和 Widget 测试
docs/        产品目标与开发计划
prototype/   HTML/CSS 视觉原型
```

更多背景资料：

- [目标设计](docs/target.md)
- [v2 开发计划](docs/v2-development-plan.md)
- [HTML 视觉原型](prototype/boards.html)
