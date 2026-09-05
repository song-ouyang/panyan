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
          body: WanpanButton(label: '立即开爬', onPressed: () => pressed = true),
        ),
      ),
    );

    expect(find.text('立即开爬'), findsOneWidget);
    final semanticButton = find.bySemanticsLabel('立即开爬');
    expect(semanticButton, findsOneWidget);
    expect(
      tester
          .getSemantics(semanticButton)
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(find.text('立即开爬'));
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
    expect(find.text('今天也去\n上墙吧！'), findsOneWidget);
    expect(find.byKey(const Key('splash-hero')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('立即开爬'), findsNothing);
    expect(find.text('记录每一次上墙，看见每一步成长'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bootstrap failure keeps welcome artwork and retries loading', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final retryPreferences = Completer<SharedPreferences>();
    var attempts = 0;

    await tester.pumpWidget(
      WanpanBootstrap(
        config: const AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: 'http://127.0.0.1:3000/api',
          enableDevelopmentLogin: false,
        ),
        preferencesLoader: () {
          attempts++;
          if (attempts == 1) {
            return Future<SharedPreferences>.error(
              StateError('Preferences unavailable'),
            );
          }
          return retryPreferences.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天也去\n上墙吧！'), findsOneWidget);
    expect(find.byKey(const Key('splash-hero')), findsOneWidget);
    expect(find.text('启动没有完成，请再试一次'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('立即开爬'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('重新加载'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(attempts, 2);
    expect(find.text('今天也去\n上墙吧！'), findsOneWidget);
    expect(find.byKey(const Key('splash-hero')), findsOneWidget);
    expect(find.text('启动没有完成，请再试一次'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(WanpanButton), findsNothing);
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
      final hero = tester.getRect(find.byKey(const Key('splash-hero')));
      final image = tester.widget<Image>(find.byKey(const Key('splash-hero')));

      expect(background, Offset.zero & size);
      expect(image.fit, BoxFit.contain);
      expect((image.image as AssetImage).assetName, AppAssets.homeHeroCat);
      expect(hero.width, greaterThan(0));
      expect(hero.height, greaterThan(0));
      expect(hero.left, greaterThanOrEqualTo(0));
      expect(hero.right, lessThanOrEqualTo(size.width));
      expect(hero.top, greaterThanOrEqualTo(0));
      expect(hero.bottom, lessThanOrEqualTo(actions.top));
      expect(actions.left, greaterThanOrEqualTo(0));
      expect(actions.right, lessThanOrEqualTo(size.width));
      expect(
        actions.bottom,
        lessThanOrEqualTo(size.height - device.padding.bottom),
      );
      expect(find.text('今天也去\n上墙吧！'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('记录每一次上墙，看见每一步成长'), findsNothing);
      expect(find.byType(WanpanButton), findsNothing);
      expect(tester.takeException(), isNull);

      final api = ApiClient(
        config: config,
        accessTokenProvider: () => session.token,
      );
      await session.initialize(AuthRepository(api));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      final button = tester.getRect(find.byType(WanpanButton));
      final readyHero = tester.getRect(find.byKey(const Key('splash-hero')));
      expect(find.text('立即开爬'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(readyHero.width, greaterThan(0));
      expect(readyHero.height, greaterThan(0));
      expect(readyHero.left, greaterThanOrEqualTo(0));
      expect(readyHero.right, lessThanOrEqualTo(size.width));
      expect(readyHero.top, greaterThanOrEqualTo(0));
      expect(readyHero.bottom, lessThanOrEqualTo(button.top));
      expect(button.height, greaterThanOrEqualTo(52));
      expect(
        button.bottom,
        lessThanOrEqualTo(size.height - device.padding.bottom),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
