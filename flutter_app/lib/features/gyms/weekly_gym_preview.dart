import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_states.dart';
import 'application/weekly_route_preview_data.dart';

class WeeklyGymPreviewCarousel extends StatelessWidget {
  const WeeklyGymPreviewCarousel({
    required this.gyms,
    required this.onOpen,
    super.key,
  });

  final List<WeeklyGymPreview> gyms;
  final ValueChanged<WeeklyGymPreview> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Leave a glimpse of the next card to make horizontal scrolling clear.
      final width = ((constraints.maxWidth - 30) / 2).clamp(150.0, 220.0);
      return SizedBox(
        height: 112 + MediaQuery.textScalerOf(context).scale(60),
        child: ListView.separated(
          key: const Key('weekly-gym-carousel'),
          scrollDirection: Axis.horizontal,
          itemCount: gyms.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, index) {
            final gym = gyms[index];
            return SizedBox(
              width: width,
              child: WanpanPressable(
                key: Key('weekly-gym-${gym.id}'),
                onTap: () => onOpen(gym),
                semanticLabel: '打开${gym.name}，${gym.city} ${gym.storeName}',
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: WanpanColors.surface,
                    border: Border.all(color: WanpanColors.border),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        gym.coverAsset,
                        height: 80,
                        fit: BoxFit.cover,
                        cacheWidth: 480,
                        excludeFromSemantics: true,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                gym.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                gym.storeName.isEmpty
                                    ? gym.city
                                    : '${gym.city} · ${gym.storeName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '查看岩馆',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(color: WanpanColors.coral),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: WanpanColors.coral,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

/// Local destination for a requested gym that has not joined the directory.
/// It deliberately has no fabricated server ID, address or publishing action.
class PendingGymInformationScreen extends StatelessWidget {
  const PendingGymInformationScreen({required this.gym, super.key});

  final WeeklyGymPreview gym;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(gym.name)),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(gym.city, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            const WanpanEmptyState(
              title: '岩馆资料待补充',
              description: '门店地址和线路信息将在补充后显示。',
            ),
          ],
        ),
      ),
    ),
  );
}
