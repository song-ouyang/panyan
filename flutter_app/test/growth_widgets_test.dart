import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/growth_models.dart';
import 'package:wanpan_diary/features/growth/badge_celebration.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/growth_repository.dart';
import 'package:wanpan_diary/features/growth/growth_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_account_badge.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_badge_stage.dart';
import 'package:wanpan_diary/shared/motion/badge_feedback_preferences.dart';
import 'package:wanpan_diary/shared/motion/wanpan_motion_sound.dart';

import 'support/fake_motion_sound_player.dart';
import 'growth_repository_test.dart' as fixture;

class _Api extends ApiClient {
  _Api() : super(config: fixture.config, accessTokenProvider: () => 'token');
  int consumeCount = 0;
  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => {
    'growth': fixture.snapshot(),
    'badges': [
      {
        'badgeKey': 'account-level-01',
        'level': 1,
        'name': '初次上墙',
        'days': 1,
        'routes': 1,
        'status': 'earned',
        'earnedAt': '2026-09-01T00:00:00Z',
      },
      {
        'badgeKey': 'account-level-02',
        'level': 2,
        'name': '渐入佳境',
        'days': 3,
        'routes': 8,
        'status': 'locked',
        'earnedAt': null,
      },
      {
        'badgeKey': 'account-level-03',
        'level': 3,
        'name': '岩馆常客',
        'days': 7,
        'routes': 25,
        'status': 'revoked',
        'earnedAt': '2026-08-01T00:00:00Z',
      },
    ],
  };
  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    consumeCount++;
    return {
      'shouldPresent': false,
      'growth': fixture.snapshot(),
      'presentation': null,
    };
  }
}

void main() {
  testWidgets(
    'compact collection shows earned locked revoked badges and both gates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = await fixture.createSession();
      final api = _Api();
      addTearDown(() {
        GrowthRepository.disposeFor(api);
        session.dispose();
        api.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: WanpanTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.35),
              disableAnimations: true,
            ),
            child: GrowthScreen(api: api, session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('累计攀爬日'), findsOneWidget);
      expect(find.text('不同完攀线路'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('记录已撤销'), 180);
      expect(find.text('待解锁'), findsOneWidget);
      expect(find.text('已获得'), findsOneWidget);
      expect(find.text('记录已撤销'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('manual replay never consumes or awards and uses same badge', (
    tester,
  ) async {
    final session = await fixture.createSession();
    final api = _Api();
    addTearDown(() {
      GrowthRepository.disposeFor(api);
      session.dispose();
      api.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: GrowthScreen(api: api, session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lv.1 初次上墙'), 160);
    await tester.ensureVisible(find.text('Lv.1 初次上墙'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lv.1 初次上墙'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重播获得动效'));
    await tester.pumpAndSettle();
    expect(
      api.consumeCount,
      1,
      reason: 'Opening details consumes once; replay does not consume again',
    );
    expect(find.byType(WanpanBadgeStage), findsOneWidget);
    expect(
      tester.widget<WanpanBadgeStage>(find.byType(WanpanBadgeStage)).level,
      1,
    );
    await session.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(WanpanBadgeStage), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'downgrade closes earned detail and blocks stale replay immediately',
    (tester) async {
      final session = await fixture.createSession();
      final api = _Api();
      final repository = GrowthRepository.forSession(api, session);
      addTearDown(() {
        GrowthRepository.disposeFor(api);
        session.dispose();
        api.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: WanpanTheme.light(),
          home: GrowthScreen(api: api, session: session),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lv.1 初次上墙'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lv.1 初次上墙'));
      await tester.pumpAndSettle();
      expect(find.text('重播获得动效'), findsOneWidget);
      repository.acceptSnapshot(
        GrowthSnapshot.fromJson(
          fixture.snapshot(revision: 2, level: 0, days: 0, routes: 0),
        ),
        generation: repository.sessionGeneration,
      );
      await tester.pumpAndSettle();
      expect(find.text('重播获得动效'), findsNothing);
      expect(repository.badges, isEmpty);
      final context = tester.element(find.byType(GrowthScreen));
      await showBadgeCelebration(
        context,
        repository: repository,
        presentation: GrowthPresentation.fromJson(
          fixture.presentationResponse()['presentation'] as JsonMap,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WanpanBadgeStage), findsNothing);
      expect(
        api.consumeCount,
        1,
        reason: 'Opening details consumes once; replay does not consume again',
      );
    },
  );
  testWidgets(
    'badge sound uses selected C and turning preference off stops playback',
    (tester) async {
      final session = await fixture.createSession();
      addTearDown(session.dispose);
      final preferences = BadgeFeedbackPreferences.instance;
      await preferences.setEnabled(true);
      final sound = FakeMotionSoundPlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: WanpanBadgeStage(level: 5, soundPlayer: sound),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WanpanAccountBadge), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(sound.plays.single.cue, WanpanMotionSoundCue.badgeEarned);
      expect(sound.plays.single.animated, false);
      expect(WanpanMotionSoundCue.badgeEarned.volume, .41085);
      final before = sound.stopCount;
      await preferences.setEnabled(false);
      await tester.pump();
      expect(sound.stopCount, greaterThan(before));
      expect(tester.takeException(), isNull);
    },
  );
}
