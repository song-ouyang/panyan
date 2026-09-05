import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import 'wanpan_pressable.dart';

Future<bool> showWanpanDeletePostConfirmation(
  BuildContext context, {
  bool isCheckin = false,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('删除这条动态？', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              isCheckin
                  ? '这条完攀记录及动态中的点赞、评论会一并删除，攀岩日历和成绩统计也会更新。线路仍会保留，删除后无法恢复。'
                  : '这条动态及其点赞、评论会一并删除，删除后无法恢复。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            WanpanButton(
              label: '确认删除',
              style: WanpanButtonStyle.danger,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
            WanpanButton(
              label: '取消',
              style: WanpanButtonStyle.quiet,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ) ??
    false;

class WanpanReportReason {
  const WanpanReportReason({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String value;
  final String label;
  final String description;
  final IconData icon;
}

const wanpanReportReasons = <WanpanReportReason>[
  WanpanReportReason(
    value: 'spam',
    label: '垃圾广告',
    description: '营销、刷屏或无关内容',
    icon: Icons.campaign_outlined,
  ),
  WanpanReportReason(
    value: 'abuse',
    label: '不友善内容',
    description: '辱骂、骚扰或仇恨言论',
    icon: Icons.sentiment_dissatisfied_outlined,
  ),
  WanpanReportReason(
    value: 'unsafe',
    label: '危险攀爬行为',
    description: '可能误导他人的危险示范',
    icon: Icons.health_and_safety_outlined,
  ),
  WanpanReportReason(
    value: 'privacy',
    label: '侵犯隐私',
    description: '泄露个人信息或未经同意发布',
    icon: Icons.privacy_tip_outlined,
  ),
  WanpanReportReason(
    value: 'false_info',
    label: '虚假信息',
    description: '内容与事实不符或具有误导性',
    icon: Icons.fact_check_outlined,
  ),
  WanpanReportReason(
    value: 'other',
    label: '其他问题',
    description: '不属于以上类型的违规内容',
    icon: Icons.more_horiz_rounded,
  ),
];

Future<String?> showWanpanReportReasonSheet(
  BuildContext context, {
  required String subject,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .82,
    ),
    child: ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: wanpanReportReasons.length + 1,
      separatorBuilder: (_, index) =>
          index == 0 ? const SizedBox(height: 14) : const Divider(indent: 52),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('举报$subject', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '选择最符合的原因，我们会尽快核实处理。对方不会知道是你提交的。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          );
        }
        final reason = wanpanReportReasons[index - 1];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 10,
          leading: DecoratedBox(
            decoration: const BoxDecoration(
              color: WanpanColors.coralSoft,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                reason.icon,
                color: WanpanColors.coralStrong,
                size: 22,
              ),
            ),
          ),
          title: Text(
            reason.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            reason.description,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: WanpanColors.muted,
          ),
          onTap: () => Navigator.pop(context, reason.value),
        );
      },
    ),
  ),
);

Future<bool> showWanpanBlockConfirmation(
  BuildContext context, {
  required String nickname,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('拉黑$nickname？', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '拉黑后，你们将不再看到对方的动态和评论，对方也无法再与你互动。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            WanpanButton(
              label: '确认拉黑',
              style: WanpanButtonStyle.danger,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
            WanpanButton(
              label: '取消',
              style: WanpanButtonStyle.quiet,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ) ??
    false;
