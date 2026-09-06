import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/growth_models.dart';
import '../../core/repositories/growth_repository.dart';
import '../../shared/motion/wanpan_motion_sound.dart';
import '../../shared/widgets/wanpan_badge_stage.dart';
import '../../shared/widgets/wanpan_pressable.dart';

Future<void> showBadgeCelebration(
  BuildContext context, {
  required GrowthRepository repository,
  required GrowthPresentation presentation,
}) {
  if (!repository.session.isAuthenticated ||
      (repository.snapshot?.currentLevel ?? 0) < presentation.toLevel ||
      presentation.toLevel < 1) {
    return Future<void>.value();
  }
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _SessionBadgeDialog(repository: repository, presentation: presentation),
  );
}

class _SessionBadgeDialog extends StatefulWidget {
  const _SessionBadgeDialog({
    required this.repository,
    required this.presentation,
  });
  final GrowthRepository repository;
  final GrowthPresentation presentation;
  @override
  State<_SessionBadgeDialog> createState() => _SessionBadgeDialogState();
}

class _SessionBadgeDialogState extends State<_SessionBadgeDialog> {
  late final _generation = widget.repository.sessionGeneration;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_validate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _validate());
  }

  void _validate() {
    if (_closing || !mounted) return;
    final snapshot = widget.repository.snapshot;
    if (!widget.repository.isCurrentSession(_generation) ||
        (snapshot != null &&
            snapshot.currentLevel < widget.presentation.toLevel)) {
      _closing = true;
      Navigator.of(context).removeRoute(ModalRoute.of(context)!);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_validate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: WanpanColors.surface,
    insetPadding: const EdgeInsets.all(20),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '关闭庆祝',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            BadgeCelebrationContent(presentation: widget.presentation),
            const SizedBox(height: 20),
            WanpanButton(
              label: '收下徽章',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    ),
  );
}

class BadgeCelebrationContent extends StatelessWidget {
  const BadgeCelebrationContent({
    required this.presentation,
    this.soundPlayer,
    super.key,
  });
  final GrowthPresentation presentation;
  final WanpanMotionSoundPlayer? soundPlayer;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      WanpanBadgeStage(level: presentation.toLevel, soundPlayer: soundPlayer),
      Text(
        'Lv.${presentation.toLevel} · ${presentation.levelName}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: WanpanColors.coralStrong,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        presentation.newBadgeCount > 1
            ? '这次点亮了 ${presentation.newBadgeCount} 枚徽章'
            : '每一次上墙，都在积累热爱',
        textAlign: TextAlign.center,
      ),
    ],
  );
}
