import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_bootstrap.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/splash/splash_screen.dart';
import 'package:wanpan_diary/shared/app_assets.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_lottie_stage.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_reward_burst.dart';

void main() {
  testWidgets('primary button exposes its label and handles a tap', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var pressed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: Scaffold(
          body: WanpanButton(label: '进入完攀日记', onPressed: () => pressed = true),
        ),
      ),
    );

    expect(find.text('进入完攀日记'), findsOneWidget);
    final semanticButton = find.bySemanticsLabel('进入完攀日记');
    expect(semanticButton, findsOneWidget);
    expect(
      tester
          .getSemantics(semanticButton)
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(find.text('进入完攀日记'));
    await tester.pump();
    expect(pressed, isTrue);
    semantics.dispose();
  });

  testWidgets('disabled button does not trigger its action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: const Scaffold(
          body: WanpanButton(label: '正在上传', onPressed: null),
        ),
      ),
    );

    await tester.tap(find.text('正在上传'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reward burst respects reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: WanpanRewardBurst(child: Text('完攀成功'))),
      ),
    );

    await tester.pump();
    expect(find.text('完攀成功'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lottie stage loads and settles under reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(
          body: WanpanLottieStage(
            asset: AppAssets.sendSuccessAnimation,
            semanticLabel: '完攀成功动画',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(WanpanLottieStage), findsOneWidget);
    expect(find.bySemanticsLabel('完攀成功动画'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bootstrap paints the launch artwork before preferences load', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preferences = Completer<SharedPreferences>();

    await tester.pumpWidget(
      WanpanBootstrap(
        config: const AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: 'http://127.0.0.1:3000/api',
          enableDevelopmentLogin: false,
        ),
        preferencesLoader: () => preferences.future,
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      tester.getRect(find.byKey(const Key('splash-background'))),
      const Offset(0, 0) & const Size(390, 844),
    );
    expect(find.byKey(const Key('splash-progress')), findsOneWidget);
    expect(find.text('记录每一次上墙，看见每一步成长'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final device in const [
    (size: Size(320, 568), padding: EdgeInsets.only(top: 20)),
    (size: Size(390, 844), padding: EdgeInsets.only(top: 47, bottom: 34)),
    (size: Size(430, 932), padding: EdgeInsets.only(top: 59, bottom: 34)),
  ]) {
    testWidgets('splash content stays on-screen at '
        '${device.size.width}x${device.size.height}', (tester) async {
      final size = device.size;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      const config = AppConfig(
        environment: AppEnvironment.development,
        apiBaseUrl: 'http://127.0.0.1:3000/api',
        enableDevelopmentLogin: false,
      );
      final session = SessionController(
        preferences: preferences,
        config: config,
        tokenStore: MemorySessionTokenStore(),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: WanpanTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: device.padding,
              viewPadding: device.padding,
              textScaler: const TextScaler.linear(1.35),
            ),
            child: child!,
          ),
          home: SplashScreen(session: session, onContinue: () {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final background = tester.getRect(
        find.byKey(const Key('splash-background')),
      );
      final actions = tester.getRect(find.byKey(const Key('splash-actions')));
      final progress = tester.getRect(find.byKey(const Key('splash-progress')));
      final image = tester.widget<Image>(
        find.byKey(const Key('splash-background')),
      );

      expect(background, Offset.zero & size);
      expect(image.fit, BoxFit.cover);
      expect((image.image as AssetImage).assetName, AppAssets.launchBackground);
      expect(actions.left, greaterThanOrEqualTo(0));
      expect(actions.right, lessThanOrEqualTo(size.width));
      expect(
        actions.bottom,
        lessThanOrEqualTo(size.height - device.padding.bottom),
      );
      expect(progress.left, greaterThanOrEqualTo(0));
      expect(progress.right, lessThanOrEqualTo(size.width));
      expect(progress.top, greaterThan(size.height * .75));
      expect(progress.height, 10);
      expect(find.bySemanticsLabel('启动进度'), findsOneWidget);
      expect(find.text('记录每一次上墙，看见每一步成长'), findsNothing);
      expect(find.byType(WanpanButton), findsNothing);
      expect(tester.takeException(), isNull);

      final api = ApiClient(
        config: config,
        accessTokenProvider: () => session.token,
      );
      await session.initialize(AuthRepository(api));
      await tester.pump();
      await tester.pumpAndSettle();

      final button = tester.getRect(find.byType(WanpanButton));
      expect(find.text('进入完攀日记'), findsOneWidget);
      expect(find.byKey(const Key('splash-progress')), findsNothing);
      expect(button.height, greaterThanOrEqualTo(52));
      expect(button.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }
}
