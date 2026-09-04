import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_app.dart';
import 'package:wanpan_diary/app/wanpan_router.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';
import 'package:wanpan_diary/features/auth/data/native_auth_service.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/onboarding/application/onboarding_controller.dart';
import 'package:wanpan_diary/features/onboarding/presentation/onboarding_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

Future<SharedPreferences> _preferences([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  required OnboardingController controller,
  required ValueChanged<String> onFinished,
  VoidCallback? onSkipped,
  VoidCallback? onExit,
  bool compact = false,
}) async {
  if (compact) {
    await tester.binding.setSurfaceSize(const Size(320, 568));
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            padding: compact
                ? const EdgeInsets.only(top: 20, bottom: 24)
                : null,
            viewPadding: compact
                ? const EdgeInsets.only(top: 20, bottom: 24)
                : null,
            textScaler: compact
                ? const TextScaler.linear(1.35)
                : mediaQuery.textScaler,
            disableAnimations: compact,
          ),
          child: child!,
        );
      },
      home: OnboardingScreen(
        controller: controller,
        onFinished: onFinished,
        onSkipped: onSkipped ?? () => onFinished('/gyms'),
        onExit: onExit ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectSegmentedProgress(WidgetTester tester, int filledCount) {
  Rect? previousRect;
  for (var index = 0; index < 3; index++) {
    final segment = find.byKey(Key('onboarding-progress-segment-$index'));
    expect(segment, findsOneWidget);

    final rect = tester.getRect(segment);
    if (previousRect != null) {
      expect(rect.left, greaterThan(previousRect.right));
      expect(rect.width, closeTo(previousRect.width, .01));
    }
    previousRect = rect;

    final widget = tester.widget<AnimatedContainer>(segment);
    final decoration = widget.decoration! as BoxDecoration;
    expect(
      decoration.color,
      index < filledCount
          ? WanpanColors.coralStrong
          : WanpanColors.surfaceMuted,
    );
  }
}

Future<void> _reachGoalStep(WidgetTester tester) async {
  for (var step = 0; step < 2; step++) {
    await tester.tap(find.byKey(const Key('onboarding-continue')));
    await tester.pumpAndSettle();
  }
}

void main() {
  test(
    'completion and selected goal persist across controller instances',
    () async {
      final preferences = await _preferences();
      final first = OnboardingController(preferences: preferences);
      addTearDown(first.dispose);

      expect(first.hasCompleted, isFalse);
      expect(first.savedGoal, isNull);

      await first.complete(landingGoal: OnboardingGoal.browseFeed);

      final restored = OnboardingController(preferences: preferences);
      addTearDown(restored.dispose);
      expect(restored.hasCompleted, isTrue);
      expect(restored.savedGoal, OnboardingGoal.browseFeed);
      expect(
        preferences.getInt('onboarding.completed_version'),
        OnboardingController.currentVersion,
      );
    },
  );

  test('skipping a newer guide clears a stale saved goal', () async {
    final preferences = await _preferences({
      'onboarding.goal': OnboardingGoal.browseFeed.name,
    });
    final controller = OnboardingController(preferences: preferences);
    addTearDown(controller.dispose);

    expect(controller.savedGoal, OnboardingGoal.browseFeed);
    await controller.skip();

    expect(controller.hasCompleted, isTrue);
    expect(controller.savedGoal, isNull);
    expect(preferences.containsKey('onboarding.goal'), isFalse);
  });

  test(
    'completion without a single landing goal clears a stale goal',
    () async {
      final preferences = await _preferences({
        'onboarding.goal': OnboardingGoal.browseFeed.name,
      });
      final controller = OnboardingController(preferences: preferences);
      addTearDown(controller.dispose);

      await controller.complete(landingGoal: null);

      expect(controller.hasCompleted, isTrue);
      expect(controller.savedGoal, isNull);
      expect(preferences.containsKey('onboarding.goal'), isFalse);
    },
  );

  testWidgets('three steps finish at the selected goal destination', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = OnboardingController(preferences: await _preferences());
    addTearDown(controller.dispose);
    String? destination;

    await _pumpOnboarding(
      tester,
      controller: controller,
      onFinished: (value) => destination = value,
    );

    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('先找到今天想爬的线'), findsOneWidget);
    _expectSegmentedProgress(tester, 1);
    final firstProgress = tester.getSemantics(
      find.byKey(const Key('onboarding-progress')),
    );
    expect(firstProgress.label, '引导进度');
    expect(firstProgress.value, '第 1 步，共 3 步');

    await tester.tap(find.byKey(const Key('onboarding-continue')));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('把每一次上墙都记下来'), findsOneWidget);
    _expectSegmentedProgress(tester, 2);
    expect(find.text('你可以'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    final feature = find.bySemanticsLabel('功能说明：记录完攀与尝试次数');
    expect(feature, findsOneWidget);
    expect(
      tester
          .getSemantics(feature)
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );

    await tester.tap(find.byKey(const Key('onboarding-continue')));
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('你想先从哪里开始？'), findsOneWidget);
    _expectSegmentedProgress(tester, 3);
    expect(find.text('至少选择一项'), findsOneWidget);
    final disabledFinish = tester
        .getSemantics(find.byKey(const Key('onboarding-finish')))
        .getSemanticsData();
    expect(disabledFinish.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(disabledFinish.hasAction(ui.SemanticsAction.tap), isFalse);
    final feedGoal = find.bySemanticsLabel('逛逛广场，看看岩友最近都在爬什么');
    expect(feedGoal, findsOneWidget);
    final unselectedFeed = tester.getSemantics(feedGoal).getSemanticsData();
    expect(unselectedFeed.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(unselectedFeed.flagsCollection.isChecked, ui.CheckedState.isFalse);
    expect(unselectedFeed.flagsCollection.isInMutuallyExclusiveGroup, isFalse);

    await tester.tap(find.byKey(const Key('onboarding-finish')));
    await tester.pump();
    expect(destination, isNull);
    expect(controller.hasCompleted, isFalse);

    await tester.tap(find.byKey(const Key('onboarding-goal-browseFeed')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding-finish')));
    await tester.pumpAndSettle();

    expect(destination, '/feed');
    expect(controller.hasCompleted, isTrue);
    expect(controller.savedGoal, OnboardingGoal.browseFeed);
    semantics.dispose();
  });

  testWidgets(
    'multiple goals toggle independently and finish on the home tab',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final preferences = await _preferences();
      final controller = OnboardingController(preferences: preferences);
      addTearDown(controller.dispose);
      String? destination;

      await _pumpOnboarding(
        tester,
        controller: controller,
        onFinished: (value) => destination = value,
      );
      await _reachGoalStep(tester);

      final feedGoal = find.byKey(const Key('onboarding-goal-browseFeed'));
      final rankingGoal = find.byKey(const Key('onboarding-goal-viewRanking'));

      await tester.tap(feedGoal);
      await tester.pumpAndSettle();
      expect(find.text('去逛广场'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('逛逛广场，看看岩友最近都在爬什么'))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        ui.CheckedState.isTrue,
      );

      await tester.tap(feedGoal);
      await tester.pumpAndSettle();
      expect(find.text('至少选择一项'), findsOneWidget);

      await tester.tap(feedGoal);
      await tester.pumpAndSettle();
      expect(find.text('去逛广场'), findsOneWidget);

      await tester.scrollUntilVisible(
        rankingGoal,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(rankingGoal);
      await tester.pumpAndSettle();
      expect(find.text('进入主页'), findsOneWidget);

      await tester.tap(rankingGoal);
      await tester.pumpAndSettle();
      expect(find.text('去逛广场'), findsOneWidget);

      await tester.tap(rankingGoal);
      await tester.pumpAndSettle();
      expect(find.text('进入主页'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('看看热门线路，看看近期完攀和点赞多的线路'))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        ui.CheckedState.isTrue,
      );

      await tester.tap(find.byKey(const Key('onboarding-finish')));
      await tester.pumpAndSettle();

      expect(destination, '/gyms');
      expect(controller.hasCompleted, isTrue);
      expect(controller.savedGoal, isNull);
      expect(preferences.containsKey('onboarding.goal'), isFalse);
      semantics.dispose();
    },
  );

  for (final testCase in const [
    (
      name: 'nearby gyms',
      goal: OnboardingGoal.findGyms,
      key: 'findGyms',
      destination: '/gyms',
      buttonLabel: '去找岩馆',
    ),
    (
      name: 'route check-in',
      goal: OnboardingGoal.checkInRoute,
      key: 'checkInRoute',
      destination: '/routes/pick',
      buttonLabel: '去找线路',
    ),
    (
      name: 'public feed',
      goal: OnboardingGoal.browseFeed,
      key: 'browseFeed',
      destination: '/feed',
      buttonLabel: '去逛广场',
    ),
    (
      name: 'popular routes',
      goal: OnboardingGoal.viewRanking,
      key: 'viewRanking',
      destination: '/ranking?tab=routes',
      buttonLabel: '去看热门线路',
    ),
  ]) {
    testWidgets('single ${testCase.name} goal opens its matching page', (
      tester,
    ) async {
      final controller = OnboardingController(
        preferences: await _preferences(),
      );
      addTearDown(controller.dispose);
      String? destination;

      await _pumpOnboarding(
        tester,
        controller: controller,
        onFinished: (value) => destination = value,
      );
      await _reachGoalStep(tester);

      final goal = find.byKey(Key('onboarding-goal-${testCase.key}'));
      await tester.scrollUntilVisible(
        goal,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(goal.hitTestable(), findsOneWidget);
      await tester.tap(goal);
      await tester.pumpAndSettle();
      expect(find.text(testCase.buttonLabel), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding-finish')));
      await tester.pumpAndSettle();

      expect(destination, testCase.destination);
      expect(controller.savedGoal, testCase.goal);
    });
  }

  testWidgets('skip completes onboarding and opens the public gyms tab', (
    tester,
  ) async {
    final controller = OnboardingController(preferences: await _preferences());
    addTearDown(controller.dispose);
    String? destination;

    await _pumpOnboarding(
      tester,
      controller: controller,
      onFinished: (value) => destination = value,
    );

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(destination, '/gyms');
    expect(controller.hasCompleted, isTrue);
    expect(controller.savedGoal, isNull);
  });

  testWidgets(
    'compact layout keeps its action visible and reaches the last choice',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = OnboardingController(
        preferences: await _preferences(),
      );
      addTearDown(controller.dispose);

      await _pumpOnboarding(
        tester,
        controller: controller,
        onFinished: (_) {},
        compact: true,
      );

      for (var step = 0; step < 3; step++) {
        final actionKey = Key(
          step == 2 ? 'onboarding-finish' : 'onboarding-continue',
        );
        final action = find.byKey(actionKey);
        expect(action, findsOneWidget);
        expect(action.hitTestable(), findsOneWidget);
        final actionRect = tester.getRect(action);
        expect(actionRect.left, greaterThanOrEqualTo(0));
        expect(actionRect.right, lessThanOrEqualTo(320));
        expect(actionRect.bottom, lessThanOrEqualTo(568));
        expect(tester.takeException(), isNull);

        if (step < 2) {
          await tester.tap(action);
          await tester.pumpAndSettle();
        }
      }

      final lastGoal = find.byKey(const Key('onboarding-goal-viewRanking'));
      await tester.scrollUntilVisible(
        lastGoal,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(lastGoal.hitTestable(), findsOneWidget);
      await tester.tap(lastGoal);
      await tester.pumpAndSettle();
      expect(find.text('去看热门线路'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fresh preferences route from splash into onboarding', (
    tester,
  ) async {
    final preferences = await _preferences();
    final session = SessionController(
      preferences: preferences,
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(session.dispose);
    final onboarding = OnboardingController(preferences: preferences);
    addTearDown(onboarding.dispose);
    final api = ApiClient(
      config: _config,
      accessTokenProvider: () => session.token,
    );
    final repository = AuthRepository(api);
    await session.initialize(repository);
    final router = createWanpanRouter(
      api: api,
      session: session,
      authRepository: repository,
      nativeAuth: NativeAuthService(),
      onboarding: onboarding,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      WanpanApp(api: api, session: session, router: router),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/splash');
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('splash-actions')),
        matching: find.text('进入完攀日记'),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/onboarding');
    expect(find.byKey(const Key('onboarding-screen')), findsOneWidget);
  });

  testWidgets('completed onboarding continues from splash to the gyms tab', (
    tester,
  ) async {
    final preferences = await _preferences({
      'onboarding.completed_version': OnboardingController.currentVersion,
    });
    final session = SessionController(
      preferences: preferences,
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(session.dispose);
    final onboarding = OnboardingController(preferences: preferences);
    addTearDown(onboarding.dispose);
    final api = ApiClient(
      config: _config,
      accessTokenProvider: () => session.token,
    );
    final router = createWanpanRouter(
      api: api,
      session: session,
      authRepository: AuthRepository(api),
      nativeAuth: NativeAuthService(),
      onboarding: onboarding,
    );
    addTearDown(router.dispose);

    await session.initialize(AuthRepository(api));
    await tester.pumpWidget(
      WanpanApp(api: api, session: session, router: router),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/splash');
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('splash-actions')),
        matching: find.text('进入完攀日记'),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/gyms');
    expect(find.byKey(const Key('onboarding-screen')), findsNothing);
  });
}
