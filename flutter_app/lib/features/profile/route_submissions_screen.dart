import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/route_submission_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/route_submission_repository.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_states.dart';

class RouteSubmissionsScreen extends StatefulWidget {
  const RouteSubmissionsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<RouteSubmissionsScreen> createState() => _RouteSubmissionsScreenState();
}

class _RouteSubmissionsScreenState extends State<RouteSubmissionsScreen> {
  late final RouteSubmissionRepository _repository;
  List<RouteSubmission> _submissions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = RouteSubmissionRepository(widget.api);
    _load();
  }

  Future<void> _load() async {
    if (!_loading) {
      setState(() => _error = null);
    }
    try {
      final submissions = await _repository.mine();
      if (!mounted) return;
      setState(() {
        _submissions = submissions;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '发布记录暂时没有加载出来';
      });
    }
  }

  Future<void> _createSubmission() async {
    final created = await context.push<bool>('/route-submissions/new');
    if (created == true) await _load();
  }

  void _openSubmission(RouteSubmission submission) {
    final routeId = submission.publishedRouteId;
    if (submission.isApproved && routeId != null) {
      context.push('/routes/$routeId');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('线路发布记录'),
      actions: [
        IconButton(
          tooltip: '发布新线路',
          onPressed: _createSubmission,
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: AnimatedSwitcher(
      duration: WanpanMotion.duration(context, WanpanMotion.exit),
      switchInCurve: WanpanMotion.curve(context),
      child: _content(),
    ),
  );

  Widget _content() {
    if (_loading) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    }
    if (_error != null) {
      return WanpanErrorState(
        key: const ValueKey('error'),
        title: _error!,
        onRetry: _load,
      );
    }
    if (_submissions.isEmpty) {
      return WanpanEmptyState(
        key: const ValueKey('empty'),
        title: '还没有发布线路',
        description: '拍下岩壁，标记起点、途经点和终点，提交后就会成为正式线路。',
        actionLabel: '发布第一条线路',
        onAction: _createSubmission,
      );
    }

    final pending = _submissions.where((item) => item.isPending).length;
    final approved = _submissions.where((item) => item.isApproved).length;
    final rejected = _submissions.where((item) => item.isRejected).length;

    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        itemCount: _submissions.length + 1,
        separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 18 : 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _SubmissionSummary(
              pending: pending,
              approved: approved,
              rejected: rejected,
            );
          }
          final submission = _submissions[index - 1];
          return _SubmissionCard(
            submission: submission,
            onTap: submission.isApproved && submission.publishedRouteId != null
                ? () => _openSubmission(submission)
                : null,
          );
        },
      ),
    );
  }
}

class _SubmissionSummary extends StatelessWidget {
  const _SubmissionSummary({
    required this.pending,
    required this.approved,
    required this.rejected,
  });

  final int pending;
  final int approved;
  final int rejected;

  @override
  Widget build(BuildContext context) => WanpanCard(
    color: WanpanColors.surfaceSoft,
    borderColor: Colors.transparent,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    child: Row(
      children: [
        Expanded(
          child: _SummaryValue(value: pending, label: '历史处理中'),
        ),
        const SizedBox(height: 38, child: VerticalDivider()),
        Expanded(
          child: _SummaryValue(value: approved, label: '已发布'),
        ),
        const SizedBox(height: 38, child: VerticalDivider()),
        Expanded(
          child: _SummaryValue(value: rejected, label: '历史未发布'),
        ),
      ],
    ),
  );
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$value', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 2),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.submission, this.onTap});

  final RouteSubmission submission;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = _SubmissionStatus.from(submission.status);
    final location = [
      submission.gymName ?? '未知岩馆',
      if (submission.wallZone?.trim().isNotEmpty == true)
        submission.wallZone!.trim(),
    ].join(' · ');

    return WanpanCard(
      onTap: onTap,
      semanticLabel: onTap == null ? null : '查看${submission.name}正式线路',
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(WanpanRadii.medium),
                child: Image.network(
                  submission.coverUrl,
                  width: 88,
                  height: 104,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 88,
                    height: 104,
                    color: WanpanColors.surfaceSoft,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.landscape_outlined,
                      color: WanpanColors.muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            submission.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _GradePill(grade: submission.grade),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    _StatusPill(status: status),
                    if (submission.createdAt != null) ...[
                      const SizedBox(height: 7),
                      Text(
                        '${_formatDate(submission.createdAt!)} 发布',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (submission.reviewNote?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: status.background,
                borderRadius: BorderRadius.circular(WanpanRadii.small),
              ),
              child: Text(
                '处理说明：${submission.reviewNote!.trim()}',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: status.foreground),
              ),
            ),
          ],
          if (submission.isApproved) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  submission.publishedRouteId == null
                      ? Icons.sync_rounded
                      : Icons.arrow_forward_rounded,
                  size: 18,
                  color: WanpanColors.success,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    submission.publishedRouteId == null
                        ? '已发布，正在同步线路信息'
                        : '已发布，点击查看正式线路',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: WanpanColors.success),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GradePill extends StatelessWidget {
  const _GradePill({required this.grade});

  final String grade;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: WanpanColors.coralSoft,
      borderRadius: BorderRadius.circular(WanpanRadii.pill),
    ),
    child: Text(
      grade,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: WanpanColors.coralStrong,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final _SubmissionStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: status.background,
      borderRadius: BorderRadius.circular(WanpanRadii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(status.icon, size: 14, color: status.foreground),
        const SizedBox(width: 5),
        Text(
          status.label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: status.foreground, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _SubmissionStatus {
  const _SubmissionStatus({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  factory _SubmissionStatus.from(String value) => switch (value) {
    'pending' => const _SubmissionStatus(
      label: '历史处理中',
      icon: Icons.schedule_rounded,
      foreground: Color(0xFF9A6A08),
      background: WanpanColors.goldSoft,
    ),
    'approved' => const _SubmissionStatus(
      label: '已发布',
      icon: Icons.check_circle_rounded,
      foreground: WanpanColors.success,
      background: Color(0xFFEAF6EF),
    ),
    'rejected' => const _SubmissionStatus(
      label: '历史未发布',
      icon: Icons.info_rounded,
      foreground: WanpanColors.danger,
      background: WanpanColors.coralSoft,
    ),
    _ => const _SubmissionStatus(
      label: '处理中',
      icon: Icons.more_horiz_rounded,
      foreground: WanpanColors.inkSecondary,
      background: WanpanColors.surfaceSoft,
    ),
  };

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}.$month.$day';
}
