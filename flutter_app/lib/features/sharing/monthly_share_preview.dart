import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/profile_models.dart';
import '../../core/services/share_service.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_pressable.dart';

/// The visible poster is also the exported image; opening it publishes nothing.
class MonthlySharePreviewDialog extends StatefulWidget {
  const MonthlySharePreviewDialog({
    required this.month,
    required this.title,
    required this.summary,
    required this.service,
    this.dashboard,
    super.key,
  });

  final String month;
  final String title;
  final String summary;
  final MonthDashboard? dashboard;
  final ShareService service;

  @override
  State<MonthlySharePreviewDialog> createState() =>
      _MonthlySharePreviewDialogState();
}

class _MonthlySharePreviewDialogState extends State<MonthlySharePreviewDialog> {
  final _posterKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  Future<void>? _artReady;
  bool _busy = false;
  String? _feedback;
  bool _failed = false;

  // A popped dialog remains mounted during its exit animation.
  bool get _canShare => mounted && (ModalRoute.of(context)?.isCurrent ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _artReady ??= precacheImage(
      const AssetImage(AppAssets.routeMapCat),
      context,
    );
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _feedback = null;
      _failed = false;
    });
    try {
      await _artReady;
      if (!_canShare) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!_canShare) return;
      final boundary =
          _posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || !boundary.attached) {
        throw StateError('Share poster is unavailable');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      late final ByteData? data;
      try {
        data = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (!_canShare) return;
      if (data == null) throw StateError('Cannot encode share poster');
      final box =
          _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) {
        throw StateError('Share button is unavailable');
      }
      final result = await widget.service.shareImage(
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        title: '${widget.title} | 完攀日记',
        fileName: 'wanpan-month-${widget.month}.png',
        origin: box.localToGlobal(Offset.zero) & box.size,
      );
      if (!mounted) return;
      setState(() {
        _feedback = switch (result) {
          ShareResultStatus.dismissed => '已取消发送，可以随时再次分享',
          ShareResultStatus.success => '已交给所选应用分享',
          ShareResultStatus.unavailable => '暂时无法打开分享，请重试',
        };
        _failed = result == ShareResultStatus.unavailable;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feedback = '暂时没能分享，请重试';
        _failed = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '分享预览',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭分享',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.contain,
                child: RepaintBoundary(
                  key: _posterKey,
                  child: MonthlySharePoster(
                    key: const Key('monthly-share-poster'),
                    month: widget.month,
                    title: widget.title,
                    summary: widget.summary,
                    dashboard: widget.dashboard,
                  ),
                ),
              ),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _feedback!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _failed ? WanpanColors.danger : WanpanColors.muted,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            WanpanButton(
              key: _shareButtonKey,
              label: '分享给朋友',
              icon: const Icon(Icons.ios_share_rounded),
              loading: _busy,
              onPressed: _busy ? null : _share,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Fixed artwork dimensions keep the exported PNG independent of device size.
class MonthlySharePoster extends StatelessWidget {
  const MonthlySharePoster({
    required this.month,
    required this.title,
    required this.summary,
    this.dashboard,
    super.key,
  });

  final String month;
  final String title;
  final String summary;
  final MonthDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final stats = dashboard?.summary;
    final date = DateTime.parse('$month-01');
    final sendsByDay = <int, int>{};
    for (final record in dashboard?.days ?? const <MonthlyDayStat>[]) {
      final day = record.day;
      if (day == null ||
          day.year != date.year ||
          day.month != date.month ||
          record.sends <= 0) {
        continue;
      }
      sendsByDay.update(
        day.day,
        (sends) => sends + record.sends,
        ifAbsent: () => record.sends,
      );
    }
    final firstWeekday = date.weekday % 7;
    final dayCount = DateTime(date.year, date.month + 1, 0).day;
    return MediaQuery.withNoTextScaling(
      child: Container(
        width: 360,
        height: 560,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: WanpanColors.canvas,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: WanpanColors.border),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: WanpanColors.ink,
            fontSize: 14,
            height: 1.3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                stats == null
                    ? summary
                    : stats.sends == 0
                    ? '这个月还没有完攀记录，下一次上墙见。'
                    : '每一次上墙，都算数。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WanpanColors.inkSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 6,
                ),
                decoration: BoxDecoration(
                  color: WanpanColors.sunflowerSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    _PosterStat('${stats?.climbingDays ?? 0}', '攀爬天数'),
                    _PosterStat('${stats?.sends ?? 0}', '完成线路'),
                    _PosterStat(
                      stats == null || stats.sends == 0
                          ? '--'
                          : 'V${stats.maxGrade}',
                      '最高难度',
                    ),
                    _PosterStat('${dashboard?.completionPoints ?? 0}', '积分'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  for (final day in ['日', '一', '二', '三', '四', '五', '六'])
                    Expanded(
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: WanpanColors.inkSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (var week = 0; week < 6; week++)
                Row(
                  children: [
                    for (var weekday = 0; weekday < 7; weekday++)
                      Expanded(
                        child: _PosterDay(
                          day: week * 7 + weekday - firstWeekday + 1,
                          dayCount: dayCount,
                          sends:
                              sendsByDay[week * 7 +
                                  weekday -
                                  firstWeekday +
                                  1] ??
                              0,
                        ),
                      ),
                  ],
                ),
              const Spacer(),
              const Row(
                children: [
                  Icon(Icons.circle, size: 8, color: WanpanColors.sunflower),
                  SizedBox(width: 6),
                  Text(
                    '上墙的日子',
                    style: TextStyle(
                      fontSize: 11,
                      color: WanpanColors.inkSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '完攀日记',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '把热爱，一次次记下来。',
                          style: TextStyle(
                            fontSize: 11,
                            color: WanpanColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Image.asset(
                    AppAssets.routeMapCat,
                    width: 96,
                    height: 64,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterStat extends StatelessWidget {
  const _PosterStat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: WanpanColors.coralStrong,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

class _PosterDay extends StatelessWidget {
  const _PosterDay({
    required this.day,
    required this.dayCount,
    required this.sends,
  });

  final int day;
  final int dayCount;
  final int sends;

  @override
  Widget build(BuildContext context) {
    if (day < 1 || day > dayCount) return const SizedBox(height: 34);
    return Semantics(
      label: sends > 0 ? '$day 日，完攀 $sends 条' : '$day 日',
      excludeSemantics: true,
      child: SizedBox(
        height: 34,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: sends > 0
                ? const BoxDecoration(
                    color: WanpanColors.sunflower,
                    shape: BoxShape.circle,
                  )
                : null,
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 14,
                fontWeight: sends > 0 ? FontWeight.w800 : FontWeight.w500,
                color: sends > 0 ? WanpanColors.ink : WanpanColors.inkSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
