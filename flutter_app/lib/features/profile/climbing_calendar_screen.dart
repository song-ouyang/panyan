import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/profile_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/profile_repository.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';

class ClimbingCalendarScreen extends StatefulWidget {
  const ClimbingCalendarScreen({
    super.key,
    required this.api,
    this.repository,
    this.initialMonth,
  });

  final ApiClient api;
  final ProfileRepository? repository;
  final DateTime? initialMonth;

  @override
  State<ClimbingCalendarScreen> createState() => _ClimbingCalendarScreenState();
}

class _ClimbingCalendarScreenState extends State<ClimbingCalendarScreen> {
  late final ProfileRepository _repository;
  late DateTime _visibleMonth;
  MonthDashboard? _dashboard;
  DateTime? _selectedDay;
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ProfileRepository(widget.api);
    final initial = widget.initialMonth ?? _shanghaiNow();
    _visibleMonth = DateTime(initial.year, initial.month);
    widget.api.climbingActivity.addListener(_handleActivityChanged);
    _loadMonth();
  }

  @override
  void dispose() {
    widget.api.climbingActivity.removeListener(_handleActivityChanged);
    super.dispose();
  }

  void _handleActivityChanged() {
    if (mounted) _loadMonth();
  }

  Future<void> _loadMonth() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await _repository.getMonthDashboard(
        _monthKey(_visibleMonth),
      );
      if (!mounted || requestId != _requestId) return;
      if (dashboard.month != _monthKey(_visibleMonth)) {
        throw const FormatException('Unexpected calendar month');
      }
      final datedRecords =
          dashboard.days
              .where((item) => item.day != null && item.sends > 0)
              .toList(growable: false)
            ..sort((a, b) => a.day!.compareTo(b.day!));
      final today = DateUtils.dateOnly(_shanghaiNow());
      final todayHasRecord = datedRecords.any(
        (item) => DateUtils.isSameDay(item.day, today),
      );
      setState(() {
        _dashboard = dashboard;
        _selectedDay =
            _selectedDay != null && _isSameMonth(_selectedDay!, _visibleMonth)
            ? _selectedDay
            : _isSameMonth(today, _visibleMonth)
            ? today
            : todayHasRecord
            ? today
            : datedRecords.isEmpty
            ? DateTime(_visibleMonth.year, _visibleMonth.month, 1)
            : DateUtils.dateOnly(datedRecords.last.day!);
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = '这个月的攀岩记录暂时没有加载出来';
      });
    }
  }

  void _changeMonth(int offset) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    final now = _shanghaiNow();
    final current = DateTime(now.year, now.month);
    if (next.isAfter(current)) return;
    setState(() {
      _visibleMonth = next;
      _selectedDay = null;
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('攀岩日历')),
      body: AnimatedSwitcher(
        duration: WanpanMotion.duration(context, WanpanMotion.enter),
        switchInCurve: WanpanMotion.curve(context),
        switchOutCurve: WanpanMotion.curve(context),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        key: ValueKey('calendar-loading'),
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    }
    if (_error != null || _dashboard == null) {
      return _CalendarError(
        key: const ValueKey('calendar-error'),
        message: _error ?? '这个月的攀岩记录暂时没有加载出来',
        onRetry: _loadMonth,
      );
    }

    final dashboard = _dashboard!;
    final recordsByDay = <DateTime, List<MonthlyDayStat>>{};
    for (final record in dashboard.days) {
      final date = record.day;
      if (date == null || record.sends <= 0) continue;
      recordsByDay
          .putIfAbsent(DateUtils.dateOnly(date), () => <MonthlyDayStat>[])
          .add(record);
    }
    final selectedRecords = _selectedDay == null
        ? const <MonthlyDayStat>[]
        : recordsByDay[_selectedDay] ?? const <MonthlyDayStat>[];

    return RefreshIndicator(
      key: ValueKey('calendar-${dashboard.month}'),
      onRefresh: _loadMonth,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _MonthHero(
            summary: dashboard.summary,
            monthHasRecords: recordsByDay.isNotEmpty,
          ),
          const SizedBox(height: 14),
          _CalendarCard(
            month: _visibleMonth,
            recordsByDay: recordsByDay,
            selectedDay: _selectedDay,
            canGoNext: !_isCurrentMonth(_visibleMonth),
            onPrevious: () => _changeMonth(-1),
            onNext: () => _changeMonth(1),
            onSelect: (day) => setState(() => _selectedDay = day),
          ),
          if (recordsByDay.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SelectedDayCard(day: _selectedDay, records: selectedRecords),
          ],
          if (dashboard.byGrade.isNotEmpty || dashboard.byGym.isNotEmpty) ...[
            const SizedBox(height: 14),
            _MonthBreakdown(grades: dashboard.byGrade, gyms: dashboard.byGym),
          ],
        ],
      ),
    );
  }
}

class _MonthHero extends StatelessWidget {
  const _MonthHero({required this.summary, required this.monthHasRecords});

  final MonthlySummary summary;
  final bool monthHasRecords;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('calendar-month-hero'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: WanpanColors.coralSoft,
        borderRadius: BorderRadius.circular(WanpanRadii.large),
        border: Border.all(color: const Color(0x33F2674F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!monthHasRecords)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '这个月，也在认真上墙',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '这个月还没有记录，\n完成一条线路后就会亮起来。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Image.asset(
                      AppAssets.routeMapCat,
                      width: 112,
                      height: 80,
                      cacheWidth: 336,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: WanpanColors.coral,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '这个月，也在认真上墙',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已经点亮 ${summary.climbingDays} 天',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth <
                      MediaQuery.textScalerOf(context).scale(4 * 64)
                  ? 2
                  : 4;
              return Wrap(
                runSpacing: 12,
                children: [
                  for (final stat in [
                    _HeroStat(value: '${summary.climbingDays}', label: '攀爬天数'),
                    _HeroStat(value: '${summary.sends}', label: '完成线路'),
                    _HeroStat(value: 'V${summary.maxGrade}', label: '最高难度'),
                    _HeroStat(value: '${summary.videos}', label: '视频记录'),
                  ])
                    SizedBox(
                      width: constraints.maxWidth / columns,
                      child: stat,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: WanpanColors.coralStrong),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.month,
    required this.recordsByDay,
    required this.selectedDay,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  static const _weekdays = ['日', '一', '二', '三', '四', '五', '六'];

  final DateTime month;
  final Map<DateTime, List<MonthlyDayStat>> recordsByDay;
  final DateTime? selectedDay;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month);
    final leading = firstDay.weekday % 7;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final today = DateUtils.dateOnly(_shanghaiNow());

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('calendar-previous-month'),
                  tooltip: '上个月',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '${month.year} 年 ${month.month} 月',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('calendar-next-month'),
                  tooltip: '下个月',
                  onPressed: canGoNext ? onNext : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: _weekdays
                  .map(
                    (weekday) => Expanded(
                      child: Center(
                        child: Text(
                          weekday,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 44 + MediaQuery.textScalerOf(context).scale(26),
                mainAxisSpacing: 4,
                crossAxisSpacing: 2,
              ),
              itemCount: leading + days,
              itemBuilder: (context, index) {
                if (index < leading) return const SizedBox.shrink();
                final day = DateTime(
                  month.year,
                  month.month,
                  index - leading + 1,
                );
                final records = recordsByDay[day] ?? const <MonthlyDayStat>[];
                return _CalendarDay(
                  day: day,
                  isSelected: DateUtils.isSameDay(day, selectedDay),
                  isToday: DateUtils.isSameDay(day, today),
                  sends: records.fold(0, (sum, item) => sum + item.sends),
                  maxGrade: _highestGrade(records),
                  onTap: day.isAfter(today) ? null : () => onSelect(day),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.sends,
    required this.maxGrade,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final int sends;
  final int maxGrade;
  final VoidCallback? onTap;

  bool get hasRecord => sends > 0;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected
        ? Colors.white
        : hasRecord
        ? WanpanColors.coralStrong
        : WanpanColors.inkSecondary;
    return Semantics(
      button: onTap != null,
      selected: isSelected,
      onTap: onTap,
      excludeSemantics: true,
      label: hasRecord
          ? '${day.month}月${day.day}日，完成$sends条线路，最高V$maxGrade'
          : '${day.month}月${day.day}日，无攀岩记录',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('calendar-day-${_dateKey(day)}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              AnimatedContainer(
                duration: WanpanMotion.duration(context, WanpanMotion.press),
                curve: WanpanMotion.curve(context),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? WanpanColors.coral
                      : hasRecord
                      ? WanpanColors.coralSoft
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: isToday
                      ? Border.all(color: WanpanColors.coral, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: hasRecord ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
              if (hasRecord) ...[
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$sends条',
                    key: Key('calendar-day-count-${_dateKey(day)}'),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      height: 1.2,
                      color: WanpanColors.inkSecondary,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'V$maxGrade',
                    key: Key('calendar-day-grade-${_dateKey(day)}'),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: WanpanColors.coralStrong,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedDayCard extends StatelessWidget {
  const _SelectedDayCard({required this.day, required this.records});

  final DateTime? day;
  final List<MonthlyDayStat> records;

  @override
  Widget build(BuildContext context) {
    if (day == null || records.isEmpty) {
      return Container(
        height: 178,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: WanpanColors.surface.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(WanpanRadii.large),
          border: Border.all(color: WanpanColors.border),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -12,
              bottom: -12,
              width: 220,
              height: 160,
              child: Image.asset(
                AppAssets.routeMapCat,
                cacheWidth: 620,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
            Positioned(
              left: 24,
              top: 42,
              right: 185,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: WanpanColors.gold,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '这一天还没有记录，\n换一天看看吧。',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final sends = records.fold(0, (sum, item) => sum + item.sends);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day!.month} 月 ${day!.day} 日 · 完成 $sends 条',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '最高难度 V${_highestGrade(records)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < records.length; index++) ...[
              _DayRecord(record: records[index]),
              if (index != records.length - 1) const Divider(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayRecord extends StatelessWidget {
  const _DayRecord({required this.record});

  final MonthlyDayStat record;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WanpanColors.coralSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            record.grade,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: WanpanColors.coralStrong),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            record.gymName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        Text(
          '${record.sends} 条',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _MonthBreakdown extends StatelessWidget {
  const _MonthBreakdown({required this.grades, required this.gyms});

  final List<GradeSummary> grades;
  final List<GymSummary> gyms;

  @override
  Widget build(BuildContext context) {
    if (grades.isEmpty && gyms.isEmpty) return const SizedBox.shrink();
    final maxSends = grades.fold<int>(1, (max, item) {
      return item.sends > max ? item.sends : max;
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (grades.isNotEmpty) ...[
              Text('难度分布', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              for (final grade in grades) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        grade.grade,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(WanpanRadii.pill),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: grade.sends / maxSends,
                          backgroundColor: WanpanColors.surfaceMuted,
                          color: WanpanColors.coral,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${grade.sends}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ],
            if (grades.isNotEmpty && gyms.isNotEmpty) const Divider(height: 24),
            if (gyms.isNotEmpty) ...[
              Text('去过的岩馆', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              for (final gym in gyms)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 19,
                        color: WanpanColors.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          gym.gymName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        '${gym.sends} 条',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CalendarError extends StatelessWidget {
  const _CalendarError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              size: 52,
              color: WanpanColors.muted,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}

int _highestGrade(List<MonthlyDayStat> records) => records.fold(0, (max, item) {
  final grade =
      int.tryParse(item.grade.replaceFirst(RegExp(r'^[Vv]'), '')) ?? 0;
  return item.sends > 0 && grade > max ? grade : max;
});

bool _isCurrentMonth(DateTime month) {
  final now = _shanghaiNow();
  return month.year == now.year && month.month == now.month;
}

DateTime _shanghaiNow() => DateTime.now().toUtc().add(const Duration(hours: 8));

bool _isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

String _dateKey(DateTime date) =>
    '${_monthKey(date)}-${date.day.toString().padLeft(2, '0')}';
