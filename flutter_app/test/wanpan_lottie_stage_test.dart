import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:wanpan_diary/shared/app_assets.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_lottie_stage.dart';

class _ControlledAssetBundle extends CachingAssetBundle {
  final Completer<ByteData> _asset = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) => _asset.future;

  void complete(ByteData data) => _asset.complete(data);
}

Widget _stageHost({
  required Widget child,
  bool reduceMotion = false,
  AssetBundle? bundle,
}) {
  return MaterialApp(
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: DefaultAssetBundle(bundle: bundle ?? rootBundle, child: appChild!),
    ),
    home: Scaffold(body: child),
  );
}

Future<void> _settleBackgroundLoad(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
  await tester.pumpAndSettle();
  await tester.pump();
}

void main() {
  setUp(Lottie.cache.clear);

  testWidgets('cold load keeps a static fallback until animation is ready', (
    tester,
  ) async {
    final bundle = _ControlledAssetBundle();
    final source = await rootBundle.load(AppAssets.sendSuccessAnimation);
    final presentations = <bool>[];
    final completions = <bool>[];

    await tester.pumpWidget(
      _stageHost(
        bundle: bundle,
        child: WanpanLottieStage(
          asset: AppAssets.sendSuccessAnimation,
          semanticLabel: '完攀成功',
          onPresented: presentations.add,
          onCompleted: completions.add,
          fallback: const SizedBox(key: Key('cold-load-fallback')),
        ),
      ),
    );

    expect(find.byKey(const Key('cold-load-fallback')), findsOneWidget);
    expect(presentations, isEmpty);
    expect(completions, isEmpty);

    bundle.complete(source);
    await _settleBackgroundLoad(tester);

    expect(find.byKey(const Key('cold-load-fallback')), findsNothing);
    expect(presentations, <bool>[true]);
    expect(completions, <bool>[true]);
    expect(tester.widget<Lottie>(find.byType(Lottie)).controller?.value, 1);
  });

  testWidgets('reduced motion presents the final frame and reports static', (
    tester,
  ) async {
    final presentations = <bool>[];
    final completions = <bool>[];

    await tester.pumpWidget(
      _stageHost(
        reduceMotion: true,
        child: WanpanLottieStage(
          asset: AppAssets.gradeMilestoneAnimation,
          semanticLabel: '新最高难度',
          onPresented: presentations.add,
          onCompleted: completions.add,
        ),
      ),
    );
    await _settleBackgroundLoad(tester);

    expect(presentations, <bool>[false]);
    expect(completions, <bool>[false]);
    expect(tester.widget<Lottie>(find.byType(Lottie)).controller?.value, 1);
  });

  testWidgets('a skipped replay presents the final frame without animation', (
    tester,
  ) async {
    final presentations = <bool>[];
    final completions = <bool>[];

    await tester.pumpWidget(
      _stageHost(
        child: WanpanLottieStage(
          asset: AppAssets.rankingEncouragementAnimation,
          semanticLabel: '排行榜鼓励',
          play: false,
          onPresented: presentations.add,
          onCompleted: completions.add,
        ),
      ),
    );
    await _settleBackgroundLoad(tester);

    expect(presentations, <bool>[false]);
    expect(completions, <bool>[false]);
    expect(tester.widget<Lottie>(find.byType(Lottie)).controller?.value, 1);
  });

  testWidgets('load failure presents the fallback exactly once', (
    tester,
  ) async {
    final presentations = <bool>[];
    final completions = <bool>[];

    await tester.pumpWidget(
      _stageHost(
        child: WanpanLottieStage(
          asset: 'assets/lottie/missing-feedback.json',
          semanticLabel: '静态成功反馈',
          onPresented: presentations.add,
          onCompleted: completions.add,
          fallback: const SizedBox(key: Key('error-fallback')),
        ),
      ),
    );
    await _settleBackgroundLoad(tester);

    expect(find.byKey(const Key('error-fallback')), findsOneWidget);
    expect(presentations, <bool>[false]);
    expect(completions, <bool>[false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching assets reports one presentation for each asset', (
    tester,
  ) async {
    var asset = AppAssets.sendSuccessAnimation;
    late StateSetter rebuild;
    final presentations = <String>[];
    final completions = <String>[];

    await tester.pumpWidget(
      _stageHost(
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return WanpanLottieStage(
              asset: asset,
              semanticLabel: '状态反馈',
              onPresented: (animated) {
                presentations.add('$asset:$animated');
              },
              onCompleted: (animated) {
                completions.add('$asset:$animated');
              },
            );
          },
        ),
      ),
    );
    await _settleBackgroundLoad(tester);

    final stageContext = tester.element(find.byType(WanpanLottieStage));
    await tester.runAsync(
      () =>
          preloadWanpanLottie(stageContext, AppAssets.routePublishedAnimation),
    );
    rebuild(() => asset = AppAssets.routePublishedAnimation);
    await tester.pumpAndSettle();
    await tester.pump();

    expect(presentations, <String>[
      '${AppAssets.sendSuccessAnimation}:true',
      '${AppAssets.routePublishedAnimation}:true',
    ]);
    expect(completions, <String>[
      '${AppAssets.sendSuccessAnimation}:true',
      '${AppAssets.routePublishedAnimation}:true',
    ]);
  });

  testWidgets('preload failures stay best-effort', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    await expectLater(
      preloadWanpanLottie(context, 'assets/lottie/missing-preload.json'),
      completes,
    );
  });
}
