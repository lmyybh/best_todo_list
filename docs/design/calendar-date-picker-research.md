# 日程日期导航组件调研

调研日期：2026-10-26。目标是复用现成日期选择器，把日程日期、日／周／月视图切换和前后翻页集中到同一处；不替换已有 Kalender 日程主体。

## 推荐

复用 `calendar_date_picker2: 3.0.0`，直接使用其 `CalendarDatePicker2` 小部件嵌入日期字段下方的弹层。日期网格、月份翻页、年月快捷选择由组件提供，选中日期后交给现有 Kalender 导航。根据用户后续确认，日／周／月切换保留原来右上角的独立分段按钮，不放入日期弹层。前后按钮根据用户后续反馈独立于日期字段显示，今天按钮紧邻。这样只需少量连接代码，不必自行实现日期网格。

该包支持中文、本周起始日配置和字号、颜色、间距等外观配置。组件内部的 `day/month/year/scroll` 指日期选择面板层级，不能直接当作主日程的日／周／月模式。当前集成在周模式中通过自定义日单元高亮和悬停预览整周，选择后定位所在周；月模式复用组件月份网格，通过 `monthBuilder` 内的点击处理直接确认月份，配合独立年份翻页。[官方说明](https://pub.dev/packages/calendar_date_picker2/versions/3.0.0)、[配置 API](https://pub.dev/documentation/calendar_date_picker2/3.0.0/calendar_date_picker2/CalendarDatePicker2Config-class.html)。

### 版本选择

官方包 API 核实最新版本为 4.0.0，发布于 2026-10-09；搜索索引仍可能显示 3.0.0。4.0.0 更新记录要求 Flutter 3.47+，3.0.0 对应 Flutter 3.35+，本项目 Flutter 3.44 更适合固定 3.0.0。[官方版本 API](https://pub.dev/api/packages/calendar_date_picker2)、[更新记录](https://pub.dev/packages/calendar_date_picker2/changelog)。

下载官方 3.0.0 和 4.0.0 发布源码进行对比：日期选择器主体和配置文件的变化是将 `package:flutter/material.dart` 导入改为 `package:material_ui/material_ui.dart`。4.0.0 增加 `material_ui ^1.0.0` 依赖，3.0.0 仅依赖 Flutter 与 intl。没有为了本需求升级 Flutter 或额外引入这套 UI 依赖的必要。[3.0.0 发布清单](https://pub.dev/api/packages/calendar_date_picker2/versions/3.0.0)、[4.0.0 发布清单](https://pub.dev/api/packages/calendar_date_picker2/versions/4.0.0)。

## 候选比较

| 候选 | 许可与版本 | 适配情况 | 结论 |
| --- | --- | --- | --- |
| CalendarDatePicker2 | Apache-2.0；推荐固定 3.0.0 | 官方列出 macOS 等桌面平台，支持中文、周一起始、自定义单元和年月选择 | 最符合紧凑日期弹层需求 |
| TableCalendar | Apache-2.0；3.3.0 | 支持中文、周一起始、月／双周／周格式及事件标记；3.3.0 依赖 intl >=0.20.3 <0.21.0 | 更偏小型事件日历，年月快速选择仍需额外实现；此处收益较小 |
| Flutter CalendarDatePicker | Flutter BSD-3-Clause；随 SDK | 无新增依赖，提供月网格、月份前后翻页和年份选择；样式配置与单元自定义能力较有限 | 简单单日选择可以使用，此处不如前者方便 |
| 已有 Kalender 0.33.0 | MIT；项目已固定使用 | 擅长日／周／月日程、事件排布；核查该版本本地 `lib/kalender.dart` 的公共导出，没有独立日期选择器 | 保留为主日程，配合专用 picker |

比较依据：[CalendarDatePicker2 许可](https://pub.dev/packages/calendar_date_picker2/license)、[TableCalendar 官方说明](https://pub.dev/packages/table_calendar)、[TableCalendar 许可](https://pub.dev/packages/table_calendar/license)、[TableCalendar 发布清单](https://pub.dev/api/packages/table_calendar/versions/3.3.0)、[Flutter 日期选择器 API](https://api.flutter.dev/flutter/material/CalendarDatePicker-class.html)、[Flutter 许可](https://github.com/flutter/flutter/blob/master/LICENSE)、[Kalender 公共 API 源码](https://github.com/werner-scholtz/kalender/blob/main/lib/kalender.dart)。

## 集成边界

- 只改变日程导航，不改任务截止日期编辑器。
- 日期字段在三个主视图都可点击。日模式提供单日选择，周模式提供整周选择，月模式直接选择月份。切换主视图保留当前日期。
- 日期选择器的月份翻页只是浏览候选日期，不能将每次翻页误当成用户完成选择。
- 3.0.0 源码中选月份或年份仅更新显示月份并返回日网格；真正选择日期才调用 `onValueChanged`。如需月模式下点击月份立即确认，需另做明确交互，不能误用 `onDisplayedMonthChanged`。
- 现有周表头点击不进入日视图的行为继续保留。
