# todo

一款使用 Flutter 构建的 macOS 本地事件树 Todo 应用。节点没有固定的“事件”或“任务”类型：有子节点时是事件，没有子节点时就是可完成的任务。

界面基于 Material 3 和 Flutter 官方自适应控件，使用桌面响应式双栏外壳。当前只维护 macOS 运行目标；组件边界为后续 Windows、Linux 桌面适配保留扩展点，暂不考虑手机端。

## v1 功能

- 创建、编辑和软删除任意深度节点
- 事件树展开、折叠、同级排序和跨父节点拖放
- 叶子任务完成/取消完成，事件状态由所有叶子实时汇总
- 可选的分钟级截止时间
- 今天、明天、本周、其他四个时间线入口
- 删除后短暂撤销
- 本地 SQLite 持久化
- 浅色、深色及跟随系统主题

v1 不包含账号、同步、提醒、搜索、标签、优先级、备注、重复任务和附件。

## 运行

环境要求：Flutter 3.44 或兼容的稳定版本、macOS 桌面开发工具链。

```sh
flutter pub get
flutter run -d macos
```

## 检查与测试

```sh
flutter analyze
flutter test
flutter build macos --release
```

测试覆盖领域规则、时间线边界、SQLite 重开恢复及核心 Widget 流程。

## 项目结构

```text
lib/
  app/       应用控制器、主题和入口
  data/      SQLite 数据库与 Repository
  domain/    Node 模型、事件树规则和时间线查询
  ui/        事件视图、时间线、桌面自适应层和公共组件
```

产品规则见 [docs/target.md](docs/target.md)，执行计划见 [docs/v1-development-plan.md](docs/v1-development-plan.md)，HTML 视觉原型位于 [prototype/index.html](prototype/index.html)。
