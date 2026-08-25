# Todo 事件树

该领域用于组织具有层级关系的事件与任务，并按截止期限和完成状态安排执行。

## 截止期限

**截止期限 (Deadline)**:
节点可选的时间约束，分为日期期限和定时期限。
_Avoid_: 截止时间、deadline 时间

**日期期限 (Date-only Deadline)**:
仅指定设备本地日历日的截止期限；更换时区不改变该日期。
_Avoid_: 全天任务、零点时间

**定时期限 (Timed Deadline)**:
指定到分钟的真实时间点；更换时区后按设备当地时间显示。
_Avoid_: 日期期限、本地浮动时间

## 时间线

**时间线经验 (Timeline Experience)**:
集中管理时间线的当前时间、日期选择、可见窗口、导航与任务分组投影。
_Avoid_: Timeline Query、时间线页面状态

**时间线窗口 (Timeline Window)**:
从周一开始连续展示的六个日历日；窗口之后的任务归入“更晚”。
_Avoid_: 完整周、七天窗口

## 节点写入

**节点写入结果 (Node Write Result)**:
一次节点变更及其后数据重载的整体结果，明确分为成功与失败。
_Avoid_: nullable 成功值、通过全局 error 猜测结果

## 桌面更新与发布

**更新会话 (Update Session)**:
一次手动更新检查的状态与动作，包括当前版本、可用 Release、错误以及下载或安装选择。
_Avoid_: Dialog 更新状态、GitHub 弹窗状态

**Windows 发布元数据 (Windows Release Metadata)**:
由 `pubspec.yaml` 版本派生的 Windows 安装包名、路径与输出目录。
_Avoid_: 在每个脚本内分别拼装产物名
