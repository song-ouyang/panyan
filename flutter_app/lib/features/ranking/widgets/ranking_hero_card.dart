import 'package:flutter/material.dart';

import '../../../app/wanpan_theme.dart';
import '../../../core/models/ranking_models.dart';
import '../../../shared/app_assets.dart';
import '../../../shared/widgets/wanpan_cat_mark.dart';

/// Real ranking data over a text-free illustration. Large text gets its own
/// full-width area so the cat can never cover a name, rank, or point total.
class RankingHeroCard extends StatelessWidget {
  const RankingHeroCard({
    required this.myRank,
    required this.regionLabel,
    required this.isAuthenticated,
    super.key,
  });

  final RankingEntry? myRank;
  final String regionLabel;
  final bool isAuthenticated;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final stacked =
          width < 310 ||
          textScale > 1.3 ||
          regionLabel.length > 6 ||
          (myRank?.points.toString().length ?? 0) > 6;
      final stats = _HeroStats(
        myRank: myRank,
        regionLabel: regionLabel,
        isAuthenticated: isAuthenticated,
        titleSize: stacked ? 21 : (width * .057).clamp(18, 23),
        rankSize: stacked ? 62 : (width * .19).clamp(48, 74),
        pointsSize: stacked ? 44 : (width * .13).clamp(38, 50),
      );
      return Container(
        key: const Key('ranking-my-summary'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4DF),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFEFCFA7), width: 1.4),
        ),
        child: stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: stats,
                  ),
                  _HeroScene(rank: myRank?.rank),
                ],
              )
            : AspectRatio(
                aspectRatio: 1.15,
                child: Stack(
                  children: [
                    Positioned.fill(child: _HeroScene(rank: myRank?.rank)),
                    Positioned(
                      left: width * .055,
                      top: width / 1.15 * .1,
                      width: width * .415,
                      child: stats,
                    ),
                  ],
                ),
              ),
      );
    },
  );
}

class _HeroStats extends StatelessWidget {
  const _HeroStats({
    required this.myRank,
    required this.regionLabel,
    required this.isAuthenticated,
    required this.titleSize,
    required this.rankSize,
    required this.pointsSize,
  });

  final RankingEntry? myRank;
  final String regionLabel;
  final bool isAuthenticated;
  final double titleSize;
  final double rankSize;
  final double pointsSize;

  @override
  Widget build(BuildContext context) {
    final me = myRank;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          me == null
              ? isAuthenticated
                    ? '完成线路，加入$regionLabel榜'
                    : '登录后加入$regionLabel榜'
              : '我的$regionLabel排名',
          key: const Key('ranking-hero-title'),
          style: TextStyle(
            color: WanpanColors.ink,
            fontSize: titleSize,
            height: 1.25,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (me != null) ...[
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '#${me.rank}',
              key: const Key('ranking-hero-rank'),
              style: TextStyle(
                color: WanpanColors.coral,
                fontSize: rankSize,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              height: 2,
              width: double.infinity,
              child: CustomPaint(painter: _DashedDividerPainter()),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${me.points}',
                    key: const Key('ranking-hero-points'),
                    style: TextStyle(
                      color: WanpanColors.coral,
                      fontSize: pointsSize,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '积分',
                style: TextStyle(
                  color: WanpanColors.ink,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HeroScene extends StatelessWidget {
  const _HeroScene({required this.rank});

  final int? rank;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AspectRatio(
      aspectRatio: 1.15,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                AppAssets.rankingHeroScene,
                fit: BoxFit.fill,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: WanpanColors.goldSoft,
                  child: Align(
                    alignment: const Alignment(.7, .3),
                    child: WanpanCatMark(size: width * .43),
                  ),
                ),
              ),
              if (rank != null)
                Positioned(
                  left: width * .627 - width * .055,
                  top: height * .205 - height * .053,
                  width: width * .11,
                  height: height * .106,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$rank',
                        key: const Key('ranking-hero-trophy-rank'),
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: const Color(0xFFAE6700),
                          fontSize: width * .069,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _DashedDividerPainter extends CustomPainter {
  const _DashedDividerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEBC9A4)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (var x = 1.0; x < size.width; x += 12) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 6).clamp(0, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedDividerPainter oldDelegate) => false;
}
