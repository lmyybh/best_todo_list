import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout, kDoubleTapSlop;
import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:kalender/kalender.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../domain/deadline.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import '../common/formatters.dart';
import '../common/event_color.dart';
import 'calendar_create_task_dialog.dart';
import 'timeline_view.dart';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const _rangeLabelStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  letterSpacing: 0,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// Tasks without a selected time range use a 30-minute display footprint.
class DeadlineCalendarEvent extends KalenderEvent {
  DeadlineCalendarEvent({
    required this.node,
    required this.path,
    required this.complete,
    required this.color,
    required super.start,
    required super.end,
    required super.isAllDay,
  }) : super(id: node.id);

  final TodoNode node;
  final String path;
  final bool complete;
  final Color color;

  @override
  DeadlineCalendarEvent copyWithData({
    required DateTime start,
    required DateTime end,
  }) => DeadlineCalendarEvent(
    node: node,
    path: path,
    complete: complete,
    color: color,
    start: start,
    end: end,
    isAllDay: isAllDay,
  );

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is DeadlineCalendarEvent &&
      other.node == node &&
      other.path == path &&
      other.complete == complete &&
      other.color == color;

  @override
  int get hashCode => Object.hash(super.hashCode, node, path, complete, color);
}

List<DeadlineCalendarEvent> calendarDeadlineEvents(NodeTree tree) => [
  for (final node in tree.nodes.values)
    if (tree.isLeaf(node.id) &&
        node.deadline != null &&
        !node.isDeleted &&
        !tree.isEffectivelyAbandoned(node.id))
      DeadlineCalendarEvent(
        node: node,
        path: tree.pathFor(node.id).join(' / '),
        complete: tree.isComplete(node.id),
        color: eventColor(_rootFor(tree, node)),
        start: node.deadline is TimedDeadline
            ? node.scheduledStart?.toLocal() ??
                  (node.deadline! as TimedDeadline).localTime.subtract(
                    const Duration(minutes: 30),
                  )
            : node.deadline!.calendarDate,
        end: node.deadline is TimedDeadline
            ? (node.deadline! as TimedDeadline).localTime
            : DateTime(
                node.deadline!.calendarDate.year,
                node.deadline!.calendarDate.month,
                node.deadline!.calendarDate.day + 1,
              ),
        isAllDay: node.deadline is DateOnlyDeadline,
      ),
];

TodoNode _rootFor(NodeTree tree, TodoNode node) {
  var current = node;
  while (current.parentId != null) {
    current = tree.nodes[current.parentId]!;
  }
  return current;
}

class _TaskLayoutStrategy extends SideBySideLayoutStrategy {
  const _TaskLayoutStrategy();

  @override
  EventLayoutDelegate createDelegate({
    required Iterable<KalenderEvent> events,
    required FloatingDateTime date,
    required KalenderTimeRange timeOfDayRange,
    required double heightPerMinute,
    required double? minimumTileHeight,
    required EventLayoutDelegateCache? cache,
    required Location? location,
  }) => _TaskLayoutDelegate(
    events: events,
    date: date,
    timeOfDayRange: timeOfDayRange,
    heightPerMinute: heightPerMinute,
    minimumTileHeight: minimumTileHeight,
    layoutCache: cache ?? EventLayoutDelegateCache(),
    location: location,
  );
}

class _TaskLayoutDelegate extends SideBySideLayoutDelegate {
  _TaskLayoutDelegate({
    required super.events,
    required super.date,
    required super.timeOfDayRange,
    required super.heightPerMinute,
    required super.minimumTileHeight,
    required super.layoutCache,
    required super.location,
  });

  @override
  void performLayout(Size size) {
    final items = events.toList();
    final data = calculateVerticalLayoutData(size);
    void place(VerticalLayoutData item, double left, double width) {
      if (!hasChild(item.id)) return;
      layoutChild(
        item.id,
        BoxConstraints.tightFor(width: width, height: item.height),
      );
      positionChild(item.id, Offset(left, item.top));
    }

    // New selections are plain KalenderEvents and always cover the whole day column.
    for (final item in data.where(
      (item) => items[item.id] is! DeadlineCalendarEvent,
    )) {
      place(item, 0, size.width);
    }
    final tasks =
        data.where((item) => items[item.id] is DeadlineCalendarEvent).toList()
          ..sort((a, b) => a.top.compareTo(b.top));
    final groups = <List<VerticalLayoutData>>[];
    var bottom = double.negativeInfinity;
    for (final item in tasks) {
      if (groups.isEmpty || item.top >= bottom) {
        groups.add([]);
        bottom = item.bottom;
      } else if (item.bottom > bottom) {
        bottom = item.bottom;
      }
      groups.last.add(item);
    }
    for (final group in groups) {
      group.sort((a, b) {
        final first = (items[a.id] as DeadlineCalendarEvent).node;
        final second = (items[b.id] as DeadlineCalendarEvent).node;
        final order = first.createdAt.compareTo(second.createdAt);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
      final columns = <int, int>{};
      var count = 1;
      for (final item in group) {
        var column = 0;
        for (final previous in group) {
          final occupied = columns[previous.id];
          if (occupied != null &&
              previous.overlaps(item) &&
              occupied >= column) {
            column = occupied + 1;
          }
        }
        columns[item.id] = column;
        if (column >= count) count = column + 1;
      }
      for (final item in group) {
        final column = columns[item.id]!;
        var end = count;
        for (final other in group) {
          final occupied = columns[other.id]!;
          if (occupied > column && occupied < end && other.overlaps(item)) {
            end = occupied;
          }
        }
        place(
          item,
          size.width * column / count,
          size.width * (end - column) / count,
        );
      }
    }
  }
}

class _TaskHoverCard extends StatefulWidget {
  const _TaskHoverCard({required this.cardBuilder, required this.childBuilder});
  final Widget Function(VoidCallback close) cardBuilder;
  final Widget Function(VoidCallback show) childBuilder;

  @override
  State<_TaskHoverCard> createState() => _TaskHoverCardState();
}

class _TaskHoverCardState extends State<_TaskHoverCard> {
  final _overlay = OverlayPortalController();
  Timer? _timer;

  void _hide() {
    _timer?.cancel();
    _overlay.hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 350), () {
        if (mounted) _overlay.show();
      });
    },
    onExit: (_) => _hide(),
    child: Listener(
      onPointerDown: (_) {
        _timer?.cancel();
        _hide();
      },
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _overlay,
        overlayChildBuilder: (context, info) => IgnorePointer(
          ignoring: true,
          child: CustomSingleChildLayout(
            delegate: _TaskHoverLayout(
              MatrixUtils.transformRect(
                info.childPaintTransform,
                Offset.zero & info.childSize,
              ),
            ),
            child: MouseRegion(
              onEnter: (_) => _timer?.cancel(),
              onExit: (_) => _hide(),
              child: Material(
                type: MaterialType.transparency,
                child: widget.cardBuilder(_hide),
              ),
            ),
          ),
        ),
        child: widget.childBuilder(_overlay.show),
      ),
    ),
  );
}

class _MonthDayTaskList extends StatefulWidget {
  const _MonthDayTaskList({required this.children});
  final List<Widget> children;

  @override
  State<_MonthDayTaskList> createState() => _MonthDayTaskListState();
}

class _MonthDayTaskListState extends State<_MonthDayTaskList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawScrollbar(
    key: const ValueKey('calendar-month-day-scrollbar'),
    controller: _scroll,
    thumbVisibility: true,
    thickness: 3,
    radius: const Radius.circular(3),
    crossAxisMargin: 0,
    mainAxisMargin: 2,
    thumbColor: AppColors.of(context).muted.withValues(alpha: 0.28),
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        key: const ValueKey('calendar-month-day-list'),
        controller: _scroll,
        primary: false,
        padding: const EdgeInsets.only(right: 14),
        child: Column(children: widget.children),
      ),
    ),
  );
}

class _TaskHoverLayout extends SingleChildLayoutDelegate {
  const _TaskHoverLayout(
    this.anchor, {
    this.maxWidth = 220,
    this.maxHeight = double.infinity,
  });
  final Rect anchor;
  final double maxWidth;
  final double maxHeight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - 16).clamp(0, maxWidth),
        maxHeight: (constraints.maxHeight - 16).clamp(0, maxHeight),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final right = anchor.right + 10;
    final x = right + childSize.width <= size.width - 8
        ? right
        : anchor.left - childSize.width - 10;
    return Offset(
      x.clamp(8, (size.width - childSize.width - 8).clamp(8, double.infinity)),
      anchor.top.clamp(
        8,
        (size.height - childSize.height - 8).clamp(8, double.infinity),
      ),
    );
  }

  @override
  bool shouldRelayout(_TaskHoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      maxWidth != oldDelegate.maxWidth ||
      maxHeight != oldDelegate.maxHeight;
}

enum _CalendarMode { day, week, month }

class _HourlyLines extends HourLines {
  const _HourlyLines({
    required super.timeOfDayRange,
    required super.heightPerMinute,
  });

  @override
  int segmentDuration(
    KalenderTimeRange range,
    double scale,
    double itemHeight,
  ) => 60;
}

class _HourlyTimeline extends TimeLine {
  const _HourlyTimeline({
    required super.timeOfDayRange,
    required super.heightPerMinute,
    required super.eventBeingDragged,
    required super.visibleDateTimeRange,
  });

  @override
  int segmentDuration(
    KalenderTimeRange range,
    double scale,
    double itemHeight,
  ) => 60;
}

class CalendarTimelineView extends StatefulWidget {
  const CalendarTimelineView({required this.controller, super.key});
  final AppController controller;

  @override
  State<CalendarTimelineView> createState() => _CalendarTimelineViewState();
}

class _CalendarTimelineViewState extends State<CalendarTimelineView> {
  final _events = DefaultEventsController();
  final _idleTimelineEvent = ValueNotifier<KalenderEvent?>(null);
  late final KalenderController _calendar;
  late DateTime _anchor;
  _CalendarMode _mode = _CalendarMode.week;
  bool _list = false;
  List<TodoNode> _nodes = [];
  int _navigationRevision = 0;
  String? _highlightId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _anchor = widget.controller.now;
    _calendar = KalenderController(viewConfiguration: _configuration(_mode));
    _syncEvents();
    widget.controller.addListener(_syncEvents);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.calendarNavigationRevision == 0) {
        _calendar.animateToDateTime(
          _initialScrollDateTime(),
          scrollDuration: const Duration(milliseconds: 1),
          pageDuration: const Duration(milliseconds: 1),
        );
      }
    });
  }

  DateTime _initialScrollDateTime() {
    final weekStart = DateTime(
      _anchor.year,
      _anchor.month,
      _anchor.day - _anchor.weekday + 1,
    );
    final weekEnd = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 7,
    );
    final minutes =
        _events.events
            .where((event) => !event.isAllDay)
            .map((event) => event.start.toLocal())
            .where(
              (start) => !start.isBefore(weekStart) && start.isBefore(weekEnd),
            )
            .map((start) => start.hour * 60 + start.minute)
            .toList()
          ..sort();
    final minute = minutes.isEmpty
        ? 7 * 60 + 45
        : (minutes.first - 30).clamp(0, 1439);
    return DateTime(_anchor.year, _anchor.month, _anchor.day, 0, minute);
  }

  ViewConfiguration _configuration(_CalendarMode mode) {
    final range = KalenderDateTimeRange(
      start: DateTime(1900),
      end: DateTime(2200),
    );
    return switch (mode) {
      _CalendarMode.day => MultiDayViewConfiguration.singleDay(
        displayRange: range,
        initialDateTime: _anchor,
        dateResolver: (_) => FloatingDateTime.fromExternal(_anchor),
        nowCallback: () => widget.controller.now,
        initialTimeOfDay: const KalenderTime(hour: 8, minute: 0),
        initialHeightPerMinute: 1.6 * 2 / 3,
      ),
      _CalendarMode.week => MultiDayViewConfiguration.week(
        displayRange: range,
        initialDateTime: _anchor,
        dateResolver: (_) => FloatingDateTime.fromExternal(_anchor),
        nowCallback: () => widget.controller.now,
        initialTimeOfDay: const KalenderTime(hour: 8, minute: 0),
        initialHeightPerMinute: 1.6 * 2 / 3,
      ),
      _CalendarMode.month => MonthViewConfiguration.singleMonth(
        displayRange: range,
        initialDateTime: _anchor,
        dateResolver: (_) => FloatingDateTime.fromExternal(_anchor),
        nowCallback: () => widget.controller.now,
      ),
    };
  }

  void _syncEvents() {
    final controller = widget.controller;
    if (controller.view != AppView.timeline) _calendar.hideDayOverlay();
    if (_navigationRevision != controller.calendarNavigationRevision) {
      _navigationRevision = controller.calendarNavigationRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigateToRequest());
    }
    final next = controller.nodes;
    if (next.length == _nodes.length &&
        List.generate(
          next.length,
          (i) => identical(next[i], _nodes[i]),
        ).every((same) => same)) {
      return;
    }
    _nodes = next;
    _events.replaceEvents(calendarDeadlineEvents(controller.tree));
  }

  Future<void> _navigateToRequest() async {
    if (!mounted) return;
    final revision = _navigationRevision;
    _calendar.hideDayOverlay();
    final id = widget.controller.calendarFocusId;
    final events = calendarDeadlineEvents(widget.controller.tree);
    final matches = events.where((event) => event.node.id == id).toList();
    final target = matches.isNotEmpty ? matches.first : null;
    _highlightTimer?.cancel();
    setState(() {
      _list = false;
      _highlightId = target?.node.id;
    });
    if (target != null) {
      _anchor = target.start.toLocal();
      await _calendar.animateToDateTime(
        _anchor,
        pageDuration: const Duration(milliseconds: 180),
        scrollDuration: const Duration(milliseconds: 180),
      );
    }
    if (!mounted || revision != _navigationRevision) return;
    if (target != null &&
        matches.isNotEmpty &&
        _mode == _CalendarMode.month &&
        widget.controller.view == AppView.timeline) {
      await _calendar.showDayOverlay(_anchor);
    }
    if (!mounted) return;
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _monthTapTimer?.cancel();
    widget.controller.removeListener(_syncEvents);
    _calendar.dispose();
    _idleTimelineEvent.dispose();
    _events.dispose();
    super.dispose();
  }

  void _open(DeadlineCalendarEvent event) {
    _calendar.hideDayOverlay();
    widget.controller.select(event.node.id);
  }

  bool _creatingTask = false;

  Future<void> _createFromSelection(KalenderEvent event) async {
    if (_mode == _CalendarMode.month) return;
    await _showCreateTaskDialog(event.start.toLocal(), event.end.toLocal());
  }

  Future<void> _showCreateTaskDialog(DateTime start, DateTime end) async {
    if (_creatingTask) return;
    _creatingTask = true;
    _calendar.clearNewEvent();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => CalendarCreateTaskDialog(
          controller: widget.controller,
          start: start,
          end: end,
        ),
      );
    } finally {
      _creatingTask = false;
    }
  }

  Timer? _monthTapTimer;
  DateTime? _monthTapDate;
  Offset? _monthTapPosition;

  void _onCalendarTapped(TapDetail detail) {
    if (_mode != _CalendarMode.month || detail is! MultiDayDetail) return;
    final date = detail.dateTimeRange.start;
    final doubleTap =
        _monthTapTimer?.isActive == true &&
        DateUtils.isSameDay(_monthTapDate, date) &&
        (_monthTapPosition! - detail.localOffset).distance <= kDoubleTapSlop;
    _monthTapTimer?.cancel();
    if (doubleTap) {
      _monthTapDate = null;
      final start = DateTime(date.year, date.month, date.day, 12);
      unawaited(
        _showCreateTaskDialog(start, start.add(const Duration(minutes: 30))),
      );
    } else {
      _monthTapDate = date;
      _monthTapPosition = detail.localOffset;
      _monthTapTimer = Timer(kDoubleTapTimeout, () => _monthTapDate = null);
    }
  }

  Widget _tile(
    BuildContext context,
    KalenderEvent raw,
    KalenderDateTimeRange range,
  ) {
    // Kalender can reuse a cached tile during rapid event replacements.
    final current = _events.byId(raw.id) ?? raw;
    final event = current as DeadlineCalendarEvent;
    final colors = AppColors.of(context);
    final compact = _mode == _CalendarMode.month;
    return _TaskHoverCard(
      cardBuilder: (_) => _hoverSurface(context, _hoverCard(context, event)),
      childBuilder: (_) => Material(
        key: ValueKey('calendar-tile-${event.node.id}'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: _highlightId == event.node.id
                ? AppTheme.accent
                : Colors.transparent,
            width: 2,
          ),
        ),
        color: event.color.withValues(
          alpha: compact
              ? (event.complete ? 0.06 : 0.12)
              : (event.complete ? 0.10 : 0.20),
        ),
        child: InkWell(
          onTap: () => _open(event),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: event.color, width: compact ? 2 : 3),
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: 5,
              vertical: compact ? 0 : 2,
            ),
            child: Text(
              '${event.complete ? '✓ ' : ''}${event.node.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                color: event.complete
                    ? colors.muted
                    : Theme.of(context).colorScheme.onSurface,
                decoration: event.complete ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hoverSurface(
    BuildContext context,
    Widget child, {
    EdgeInsets padding = const EdgeInsets.fromLTRB(12, 12, 20, 12),
  }) {
    final colors = AppColors.of(context);
    return IntrinsicWidth(
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _monthDayOverlay(
    BuildContext context, {
    required DateTime date,
    required List<KalenderEvent> events,
    required double tileHeight,
    required OverlayPortalController portalController,
    required RenderBoxCallback getMultiDayEventLayoutRenderBox,
    required RenderBoxCallback getOverlayPortalRenderBox,
    required MultiDayOverlayEventTileBuilder overlayTileBuilder,
  }) {
    final colors = AppColors.of(context);
    final tasks =
        <DeadlineCalendarEvent>[
          for (final raw in events)
            (_events.byId(raw.id) ?? raw) as DeadlineCalendarEvent,
        ]..sort((a, b) {
          if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
          final time = (a.node.scheduledStart ?? a.end).compareTo(
            b.node.scheduledStart ?? b.end,
          );
          return time != 0
              ? time
              : a.node.manualOrder.compareTo(b.node.manualOrder);
        });
    final anchor = getOverlayPortalRenderBox();
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('calendar-month-day-barrier'),
            behavior: HitTestBehavior.opaque,
            onTap: portalController.hide,
          ),
        ),
        CustomSingleChildLayout(
          delegate: _TaskHoverLayout(
            anchor.localToGlobal(Offset.zero) & anchor.size,
            maxWidth: 300,
            maxHeight: 360,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: 300,
              child: _hoverSurface(
                context,
                Column(
                  key: const ValueKey('calendar-month-day-popup'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${date.month} 月 ${date.day} 日 ${_weekdays[date.weekday - 1]}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${tasks.length} 项任务',
                          style: TextStyle(fontSize: 10, color: colors.muted),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: '关闭当天任务',
                          onPressed: portalController.hide,
                          icon: const Icon(Icons.close, size: 14),
                          color: colors.muted,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 22,
                            height: 22,
                          ),
                        ),
                      ],
                    ),
                    Divider(height: 12, color: colors.borderSoft),
                    Flexible(
                      child: _MonthDayTaskList(
                        children: [
                          for (final task in tasks)
                            _monthDayTask(
                              context,
                              task,
                              date,
                              portalController.hide,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _monthDayTask(
    BuildContext context,
    DeadlineCalendarEvent task,
    DateTime date,
    VoidCallback close,
  ) {
    final colors = AppColors.of(context);
    String time(DateTime value) => DateUtils.isSameDay(value.toLocal(), date)
        ? formatTime(value)
        : '${formatDate(value).replaceAll('/', '.')} ${formatTime(value)}';
    final label = task.isAllDay
        ? '当天截止'
        : task.node.scheduledStart != null
        ? '${time(task.start)} — ${time(task.end)}'
        : time(task.end);
    return Tooltip(
      message: task.path,
      child: InkWell(
        key: ValueKey('calendar-month-day-task-${task.node.id}'),
        onTap: () {
          close();
          _open(task);
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                task.complete
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 14,
                color: task.complete ? const Color(0xFF4F806B) : colors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: task.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task.node.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: task.complete ? colors.muted : null,
                              decoration: task.complete
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.only(left: 11),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hoverCard(
    BuildContext context,
    DeadlineCalendarEvent event, {
    bool showBreadcrumb = true,
  }) {
    final tree = widget.controller.tree;
    final colors = AppColors.of(context);
    final parents = tree.pathFor(event.node.id)..removeLast();
    final notes = event.node.notes.trim();
    return DefaultTextStyle(
      style: TextStyle(
        fontSize: 11,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      child: Column(
        key: ValueKey('calendar-hover-${event.node.id}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBreadcrumb) ...[
            _breadcrumb(context, parents, event.color),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Center(
                  child: Icon(
                    event.complete
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 13,
                    color: event.complete ? colors.completion : colors.muted,
                    semanticLabel: event.complete ? '已完成' : '未完成',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  event.node.title,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: event.complete
                        ? FontWeight.w400
                        : FontWeight.w500,
                    color: event.complete ? colors.muted : null,
                    decoration: event.complete
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(
              formatDeadline(event.node.deadline),
              style: TextStyle(color: colors.muted, fontSize: 8),
            ),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: colors.borderSoft),
            const SizedBox(height: 6),
            Text(
              notes,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted, fontSize: 11, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _breadcrumb(BuildContext context, List<String> parents, Color color) {
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            parents.isEmpty ? '顶层事件' : parents.join('  ›  '),
            style: TextStyle(color: colors.muted, fontSize: 10, height: 1.35),
            softWrap: true,
          ),
        ),
      ],
    );
  }

  Widget _dateHeader(BuildContext context, DateTime date) {
    final colors = AppColors.of(context);
    if (_mode == _CalendarMode.day) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text(
            '当日截止',
            style: TextStyle(fontSize: 10, color: colors.muted),
          ),
        ),
      );
    }
    final today = DateUtils.isSameDay(date, widget.controller.now);
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: today ? colors.accentSoft.withValues(alpha: 0.38) : null,
        border: Border(
          bottom: BorderSide(
            color: today ? AppTheme.accent : colors.borderSoft,
            width: today ? 2 : 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _weekdays[date.weekday - 1],
            style: TextStyle(
              fontSize: 11,
              color: today ? AppTheme.accent : colors.muted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: today ? AppTheme.accent : null,
            ),
          ),
        ],
      ),
    );
  }

  final _dateMenu = MenuController();

  void _showDate(DateTime date, _CalendarMode mode) {
    setState(() {
      _anchor = DateUtils.dateOnly(date);
      if (mode != _mode) {
        _mode = mode;
        _calendar.viewConfiguration = _configuration(mode);
      } else {
        _calendar.jumpToDate(_anchor);
      }
    });
  }

  Widget _dateNavigator() {
    final colors = AppColors.of(context);
    final labelMeasure = TextPainter(
      text: TextSpan(
        text: switch (_mode) {
          _CalendarMode.day => '2000.00.00 周三',
          _CalendarMode.week => '2000.00.00 — 2000.00.00',
          _CalendarMode.month => '2000.00',
        },
        style: Theme.of(context).textTheme.labelLarge?.merge(_rangeLabelStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Measure a fixed format, never the selected dates. Include padding and icon.
    final fieldWidth = labelMeasure.width.ceilToDouble() + 40;
    labelMeasure.dispose();
    Widget arrow(bool previous) => IconButton(
      tooltip: switch (_mode) {
        _CalendarMode.day => previous ? '上一天' : '下一天',
        _CalendarMode.week => previous ? '上一周' : '下一周',
        _CalendarMode.month => previous ? '上一月' : '下一月',
      },
      onPressed: previous
          ? _calendar.animateToPreviousPage
          : _calendar.animateToNextPage,
      icon: Icon(previous ? Icons.chevron_left : Icons.chevron_right, size: 18),
      color: colors.muted,
      constraints: const BoxConstraints.tightFor(width: 30, height: 32),
      padding: EdgeInsets.zero,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SizedBox(
            width: fieldWidth,
            child: MenuAnchor(
              controller: _dateMenu,
              onOpen: () => setState(() {}),
              style: MenuStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
                backgroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.surface,
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: colors.borderSoft),
                  ),
                ),
              ),
              menuChildren: [
                SizedBox(
                  key: const ValueKey('calendar-date-picker'),
                  width: 300,
                  child: _datePicker(),
                ),
              ],
              builder: (context, menu, _) => TextButton(
                key: const ValueKey('calendar-date-menu'),
                onPressed: () {
                  if (menu.isOpen) {
                    menu.close();
                  } else {
                    menu.open();
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(child: _rangeLabel()),
                    const SizedBox(width: 6),
                    Icon(Icons.expand_more, size: 16, color: colors.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        arrow(true),
        arrow(false),
      ],
    );
  }

  Widget _datePicker() {
    final colors = AppColors.of(context);
    var year = _anchor.year;
    DateTime? hoveredWeek;
    void choose(DateTime date) {
      _showDate(date, _mode);
      _dateMenu.close();
    }

    return StatefulBuilder(
      builder: (context, updatePicker) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_mode == _CalendarMode.month)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: '上一年',
                  onPressed: year > 1900
                      ? () => updatePicker(() => year--)
                      : null,
                  icon: const Icon(Icons.chevron_left, size: 18),
                ),
                Text(
                  '$year 年',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: '下一年',
                  onPressed: year < 2199
                      ? () => updatePicker(() => year++)
                      : null,
                  icon: const Icon(Icons.chevron_right, size: 18),
                ),
              ],
            ),
          PrimaryScrollController.none(
            child: CalendarDatePicker2(
              key: ValueKey('calendar-picker-${_mode.name}-$year'),
              config: CalendarDatePicker2Config(
                firstDate: DateTime(1900),
                lastDate: DateTime(2199, 12, 31),
                currentDate: widget.controller.now,
                calendarViewMode: _mode == _CalendarMode.month
                    ? CalendarDatePicker2Mode.month
                    : CalendarDatePicker2Mode.day,
                firstDayOfWeek: 1,
                controlsHeight: _mode == _CalendarMode.month ? 0 : 42,
                modePickerBuilder: _mode == _CalendarMode.month
                    ? ({
                        required viewMode,
                        required monthDate,
                        isMonthPicker,
                      }) => const SizedBox.shrink()
                    : null,
                modePickersGap: 0,
                customModePickerIcon: const Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                ),
                dayMaxWidth: 36,
                dayTextStyle: const TextStyle(fontSize: 12),
                weekdayLabelTextStyle: TextStyle(
                  fontSize: 11,
                  color: colors.muted,
                ),
                controlsTextStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                selectedDayHighlightColor: AppTheme.accent,
                selectedDayTextStyle: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                ),
                monthTextStyle: const TextStyle(fontSize: 12),
                monthBuilder: _mode == _CalendarMode.month
                    ? ({
                        required month,
                        textStyle,
                        decoration,
                        isSelected,
                        isDisabled,
                        isCurrentMonth,
                      }) => InkWell(
                        key: ValueKey('calendar-pick-month-$month'),
                        onTap: () => choose(DateTime(year, month)),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: decoration,
                          child: Text('$month 月', style: textStyle),
                        ),
                      )
                    : null,
                dayBuilder: _mode == _CalendarMode.week
                    ? ({
                        required date,
                        textStyle,
                        decoration,
                        isSelected,
                        isDisabled,
                        isToday,
                      }) {
                        bool sameWeek(DateTime other) {
                          final start = DateTime(
                            other.year,
                            other.month,
                            other.day - other.weekday + 1,
                          );
                          return !date.isBefore(start) &&
                              date.isBefore(
                                DateTime(
                                  start.year,
                                  start.month,
                                  start.day + 7,
                                ),
                              );
                        }

                        final selected = sameWeek(_anchor);
                        final hovered =
                            hoveredWeek != null && sameWeek(hoveredWeek!);
                        return MouseRegion(
                          onEnter: (_) =>
                              updatePicker(() => hoveredWeek = date),
                          onExit: (_) => updatePicker(() => hoveredWeek = null),
                          child: Container(
                            key: ValueKey(
                              'calendar-pick-week-${date.year}-${date.month}-${date.day}',
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? colors.accentSoft
                                  : hovered
                                  ? colors.accentSoft.withValues(alpha: 0.5)
                                  : null,
                              borderRadius: BorderRadius.horizontal(
                                left: date.weekday == 1
                                    ? const Radius.circular(6)
                                    : Radius.zero,
                                right: date.weekday == 7
                                    ? const Radius.circular(6)
                                    : Radius.zero,
                              ),
                            ),
                            child: Text(
                              '${date.day}',
                              style: TextStyle(
                                fontSize: 12,
                                color: selected || isToday == true
                                    ? AppTheme.accent
                                    : Theme.of(context).colorScheme.onSurface,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      }
                    : null,
                allowSameValueSelection: true,
                disableVibration: true,
              ),
              value: [_anchor],
              displayedMonthDate: DateTime(year, _anchor.month, _anchor.day),
              onValueChanged: (dates) {
                if (dates.isNotEmpty) choose(dates.first);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeLabel() => ValueListenableBuilder(
    valueListenable: _calendar.floatingVisibleRange,
    builder: (context, range, _) {
      final start = range.start;
      final end = range.end.subtract(const Duration(days: 1));
      final month = range.dominantMonthDate;
      String twoDigits(int value) => value.toString().padLeft(2, '0');
      String date(int year, int month, int day) =>
          '$year.${twoDigits(month)}.${twoDigits(day)}';
      final label = switch (_mode) {
        _CalendarMode.month => '${month.year}.${twoDigits(month.month)}',
        _CalendarMode.day =>
          '${date(start.year, start.month, start.day)} ${_weekdays[start.weekday - 1]}',
        _CalendarMode.week =>
          '${date(start.year, start.month, start.day)} — ${date(end.year, end.month, end.day)}',
      };
      return Text(
        label,
        key: const ValueKey('calendar-range'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _rangeLabelStyle,
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tiles = TileComponents(
      tileBuilder: _tile,
      dropTargetTile: (context, event) => Container(
        key: const ValueKey('calendar-create-preview'),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: colors.accentSoft.withValues(alpha: colors.accentSoft.a * 0.5),
          border: Border.all(color: AppTheme.accent),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${formatTime(event.start)} — ${formatTime(event.end)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: AppTheme.accent),
        ),
      ),
    );
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: colors.muted,
      textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11),
      minimumSize: const Size(42, 30),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                const Text(
                  '日程',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 14),
                Tooltip(
                  message: '查看逾期、未定日期和完成记录',
                  child: TextButton(
                    key: const ValueKey('calendar-task-list'),
                    style: buttonStyle,
                    onPressed: () => setState(() => _list = !_list),
                    child: Text(_list ? '返回日历' : '任务列表'),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 150,
                  height: 32,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: CupertinoSlidingSegmentedControl<_CalendarMode>(
                      groupValue: _mode,
                      backgroundColor: const Color(0xFFECEDE9),
                      thumbColor: const Color(0xFFC9DED9),
                      padding: const EdgeInsets.all(2),
                      onValueChanged: (mode) {
                        if (mode == null) return;
                        setState(() => _list = false);
                        _showDate(_anchor, mode);
                      },
                      children: {
                        for (final mode in _CalendarMode.values)
                          mode: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              switch (mode) {
                                _CalendarMode.day => '日',
                                _CalendarMode.week => '周',
                                _CalendarMode.month => '月',
                              },
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _mode == mode
                                    ? AppTheme.accent
                                    : colors.muted,
                              ),
                            ),
                          ),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_list)
          Expanded(child: TimelineView(controller: widget.controller))
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(
              children: [
                Flexible(child: _dateNavigator()),
                ValueListenableBuilder(
                  valueListenable: _calendar.floatingVisibleRange,
                  builder: (context, range, _) {
                    final today = DateUtils.dateOnly(widget.controller.now);
                    final month = range.dominantMonthDate;
                    final start = DateTime(
                      range.start.year,
                      range.start.month,
                      range.start.day,
                    );
                    final end = DateTime(
                      range.end.year,
                      range.end.month,
                      range.end.day,
                    );
                    final includesToday = _mode == _CalendarMode.month
                        ? month.year == today.year && month.month == today.month
                        : !today.isBefore(start) && today.isBefore(end);
                    if (includesToday) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TextButton(
                        style: buttonStyle,
                        onPressed: () =>
                            _showDate(widget.controller.now, _mode),
                        child: const Text('回到今天'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: colors.borderSoft),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: KalenderTheme(
                  data: KalenderThemeData(
                    timelineStyle: TimelineStyle(
                      textStyle: TextStyle(
                        fontSize: 10,
                        color: colors.faint,
                        fontWeight: FontWeight.w400,
                      ),
                      textPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 52,
                      ),
                    ),
                    hourLinesStyle: HourLinesStyle(
                      color: colors.borderSoft.withValues(alpha: 0.65),
                      thickness: 0.5,
                    ),
                    daySeparatorStyle: DaySeparatorStyle(
                      color: colors.borderSoft,
                      width: 0.5,
                    ),
                    monthGridStyle: MonthGridStyle(
                      color: colors.borderSoft,
                      thickness: 0.5,
                    ),
                    weekDayHeaderStyle: WeekDayHeaderStyle(
                      textStyle: TextStyle(fontSize: 11, color: colors.muted),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    monthDayHeaderStyle: const MonthDayHeaderStyle(
                      numberTextStyle: TextStyle(fontSize: 12),
                      buttonSize: Size(24, 24),
                      margin: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    ),
                    dayNumberStyle: DayNumberStyle(
                      todayBackgroundColor: colors.accentSoft,
                      todayForegroundColor: AppTheme.accent,
                    ),
                    timeIndicatorStyle: const TimeIndicatorStyle(
                      lineColor: AppTheme.accent,
                      thickness: 1,
                      circleSize: Size(5, 5),
                    ),
                  ),
                  child: KalenderView(
                    eventsController: _events,
                    kalenderController: _calendar,
                    locale: const Locale('zh', 'CN'),
                    callbacks: KalenderCallbacks(
                      onTappedWithDetail: _onCalendarTapped,
                      onEventCreated: (event) =>
                          unawaited(_createFromSelection(event)),
                      dateLabel: _mode == _CalendarMode.week
                          ? null
                          : GestureCallbacks(
                              onTap: (detail) =>
                                  _showDate(detail.date, _CalendarMode.day),
                            ),
                      onPageChanged: (range) {
                        if (_anchor.isBefore(range.start) ||
                            !_anchor.isBefore(range.end)) {
                          final date = _mode == _CalendarMode.month
                              ? _calendar
                                    .floatingVisibleRange
                                    .value
                                    .dominantMonthDate
                              : range.start.toLocal();
                          _anchor = DateTime(date.year, date.month, date.day);
                        }
                      },
                    ),
                    interaction: KalenderInteraction(
                      allowResizing: false,
                      allowRescheduling: false,
                      allowEventCreation: false,
                    ),
                    components: KalenderComponents(
                      monthComponents: MonthComponents(
                        bodyComponents: MonthBodyComponents(
                          overlayBuilders: OverlayBuilders(
                            multiDayOverlayBuilder: _monthDayOverlay,
                            multiDayPortalOverlayButtonBuilder:
                                (context, portal, count) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: MultiDayPortalOverlayButton(
                                    portalController: portal,
                                    numberOfHiddenRows: count,
                                    stringBuilder: (context, count) =>
                                        '+$count 项',
                                    style: MultiDayPortalOverlayButtonStyle(
                                      textStyle: TextStyle(
                                        fontSize: 11,
                                        color: colors.muted,
                                      ),
                                      textPadding: const EdgeInsets.only(
                                        left: 7,
                                        right: 5,
                                      ),
                                      textOverflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                          ),
                          monthDayHeaderBuilder: (context, date) => Align(
                            alignment: Alignment.centerLeft,
                            heightFactor: 1,
                            child: MonthDayHeader(date: date),
                          ),
                        ),
                      ),
                      multiDayComponents: MultiDayComponents(
                        headerComponents: MultiDayHeaderComponents(
                          dayHeaderBuilder: _dateHeader,
                          weekNumberBuilder: (context, range) => SizedBox(
                            height: 48,
                            child: Center(
                              child: Text(
                                '截止',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.faint,
                                ),
                              ),
                            ),
                          ),
                        ),
                        bodyComponents: MultiDayBodyComponents(
                          hourLines: (context, scale, range) => _HourlyLines(
                            timeOfDayRange: range,
                            heightPerMinute: scale,
                          ),
                          timeline:
                              (context, scale, range, dragging, visible) =>
                                  _HourlyTimeline(
                                    timeOfDayRange: range,
                                    heightPerMinute: scale,
                                    // Keep axis labels static during selection.
                                    eventBeingDragged: _idleTimelineEvent,
                                    visibleDateTimeRange: visible,
                                  ),
                          timelineWidth: (context, range) => 52,
                          timelineStringBuilder: (context, time) =>
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                      overlayBuilders: OverlayBuilders(
                        multiDayPortalOverlayButtonStringBuilder:
                            (context, count) => '还有 $count 项',
                      ),
                    ),
                    views: [
                      MultiDayViewParts(
                        header: MultiDayHeader(
                          tileComponents: tiles,
                          configuration: const MultiDayHeaderConfiguration(
                            maximumNumberOfVerticalEvents: 3,
                          ),
                        ),
                        body: MultiDayBody(
                          tileComponents: tiles,
                          interaction: KalenderInteraction(
                            allowResizing: false,
                            allowRescheduling: false,
                            allowEventCreation: true,
                            createEventGesture: EventInteractionGesture.tap,
                          ),
                          snapping: const KalenderSnapping(
                            snapIntervalMinutes: 15,
                            snapToTimeIndicator: false,
                            snapToOtherEvents: false,
                          ),
                          configuration: const MultiDayBodyConfiguration(
                            eventLayoutStrategy: _TaskLayoutStrategy(),
                            horizontalPadding: EdgeInsets.zero,
                            minimumTileHeight: 0,
                          ),
                        ),
                      ),
                      MonthViewParts(
                        body: MonthBody(
                          tileComponents: tiles,
                          configuration: const MonthBodyConfiguration(
                            tileHeight: 22,
                            eventPadding: EdgeInsets.fromLTRB(0, 0, 4, 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
