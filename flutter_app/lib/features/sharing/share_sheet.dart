import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/models/profile_models.dart';
import '../../core/repositories/share_repository.dart';
import '../../core/services/share_service.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import 'monthly_share_preview.dart';

class SharePreview {
  const SharePreview({
    required this.title,
    required this.summary,
    this.routeId,
    this.month,
    this.dashboard,
  }) : assert((routeId == null) != (month == null));

  factory SharePreview.route(ClimbingRoute route) => SharePreview(
    routeId: route.id,
    title: '${route.grade} · ${route.name}',
    summary: [
      if (route.gymName?.isNotEmpty == true) route.gymName!,
      '查看岩壁照片与线路标点',
    ].join(' · '),
  );

  factory SharePreview.monthly(MonthDashboard dashboard) {
    final month = DateTime.parse('${dashboard.month}-01');
    final summary = dashboard.summary;
    return SharePreview(
      month: dashboard.month,
      dashboard: dashboard,
      title: '${month.year} 年 ${month.month} 月攀岩记录',
      summary: summary.sends == 0
          ? '这个月还没有完攀记录，新的进步会在这里更新。'
          : '${summary.climbingDays} 天攀岩 · 完攀 ${summary.sends} 条 · '
                '最高 V${summary.maxGrade}',
    );
  }

  final String title;
  final String summary;
  final String? routeId;
  final String? month;
  final MonthDashboard? dashboard;
  bool get isMonthly => month != null;
}

Future<void> showWanpanShareSheet({
  required BuildContext context,
  required SharePreview preview,
  required ShareRepository repository,
  ShareService service = const ShareService(),
}) {
  if (preview.isMonthly) {
    return showDialog<void>(
      context: context,
      builder: (context) => MonthlySharePreviewDialog(
        month: preview.month!,
        title: preview.title,
        summary: preview.summary,
        dashboard: preview.dashboard,
        service: service,
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => WanpanShareSheet(
      preview: preview,
      repository: repository,
      service: service,
    ),
  );
}

enum _ShareAction { share, copy, preview }

class WanpanShareSheet extends StatefulWidget {
  const WanpanShareSheet({
    required this.preview,
    required this.repository,
    this.service = const ShareService(),
    super.key,
  });

  final SharePreview preview;
  final ShareRepository repository;
  final ShareService service;

  @override
  State<WanpanShareSheet> createState() => _WanpanShareSheetState();
}

class _WanpanShareSheetState extends State<WanpanShareSheet> {
  final _shareButtonKey = GlobalKey();
  String? _error;
  String? _feedback;
  bool _busy = false;
  VoidCallback? _retry;

  Future<void> _perform(_ShareAction action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
    });
    try {
      final preview = widget.preview;
      final url = widget.repository.routeUrl(preview.routeId!);
      String? feedback;
      switch (action) {
        case _ShareAction.share:
          // Measure the button after the busy state has been laid out.
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
          final box =
              _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize || !box.attached) {
            throw StateError('Share button is unavailable');
          }
          final result = await widget.service.share(
            url: url,
            title: '${preview.title} | 完攀日记',
            origin: box.localToGlobal(Offset.zero) & box.size,
          );
          feedback = switch (result) {
            ShareResultStatus.dismissed => '已取消发送，可以随时再次分享',
            ShareResultStatus.success => '已交给所选应用分享',
            ShareResultStatus.unavailable => '也可以复制链接后发送给朋友',
          };
        case _ShareAction.copy:
          await widget.service.copy(url);
          feedback = '链接已复制，可以粘贴到微信或其他应用';
        case _ShareAction.preview:
          await widget.service.preview(url);
      }
      if (mounted) setState(() => _feedback = feedback);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '暂时没能完成，请重试或复制链接';
        _retry = () => _perform(action);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final enabled = !_busy;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '分享线路',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: '关闭分享',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: WanpanColors.coralSoft,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: WanpanColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(preview.summary),
                  const SizedBox(height: 12),
                  Text(
                    '朋友无需登录即可预览，也能从页面下载完攀日记。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('点击「分享给朋友」，在手机分享面板选择微信或其他已安装的应用。'),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: WanpanColors.danger)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy ? null : _retry,
                  child: const Text('重试'),
                ),
              ),
            ],
            if (_feedback != null) ...[
              Semantics(liveRegion: true, child: Text(_feedback!)),
              const SizedBox(height: 12),
            ],
            WanpanButton(
              key: _shareButtonKey,
              label: '分享给朋友',
              icon: const Icon(Icons.ios_share_rounded),
              loading: _busy,
              onPressed: enabled ? () => _perform(_ShareAction.share) : null,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: enabled ? () => _perform(_ShareAction.copy) : null,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制链接'),
                ),
                TextButton.icon(
                  onPressed: enabled
                      ? () => _perform(_ShareAction.preview)
                      : null,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: const Text('预览分享页'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
