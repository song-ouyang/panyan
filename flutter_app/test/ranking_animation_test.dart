import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/ranking/ranking_screen.dart';
import 'package:wanpan_diary/shared/app_assets.dart';
import 'package:wanpan_diary/shared/motion/wanpan_motion_sound.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_lottie_stage.dart';

import 'support/fake_motion_sound_player.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _EmptyRankingApi extends ApiClient {
  _EmptyRankingApi() : super(config: _config, accessTokenProvider: () => null);

  int rankingRequests = 0;

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/rankings/regions') return {'items': <Object>[]};
    if (path == '/rankings') {
      rankingRequests++;
      return {
        'items': <Object>[],
        'myRank': null,
        'scoring': {'completion': 10, 'gradeStep': 2, 'flash': 5, 'like': 1},
      };
    }
    if (path == '/rankings/routes') return {'items': <Object>[]};
    throw StateError('Unexpected ranking request: $path');
  }
}

void main() {
  setUp(() async {
    Lottie.cache.clear();
    await AssetLottie(AppAssets.rankingEncouragementAnimation).load();
  });

  testWidgets('热门线路入口会直接打开公开线路榜', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(session.dispose);
    final sounds = FakeMotionSoundPlayer();

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: RankingScreen(
          api: _EmptyRankingApi(),
          session: session,
          initialSegment: 1,
          motionSoundPlayer: sounds,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有热门线路'), findsOneWidget);
    expect(find.text('登录后加入全国榜'), findsNothing);
  });

  testWidgets('每种排行空状态在同一页面生命周期只播放一次', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(session.dispose);
    final sounds = FakeMotionSoundPlayer();

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: RankingScreen(
          api: _EmptyRankingApi(),
          session: session,
          motionSoundPlayer: sounds,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本月榜单刚刚开始'), findsOneWidget);
    expect(_lottieStage(tester).play, isTrue);

    await tester.tap(find.text('热门线路'));
    await tester.pumpAndSettle();
    expect(find.text('还没有热门线路'), findsOneWidget);
    expect(_lottieStage(tester).play, isTrue);

    await tester.tap(find.text('全国榜'));
    await tester.pumpAndSettle();
    expect(find.text('本月榜单刚刚开始'), findsOneWidget);
    expect(_lottieStage(tester).play, isFalse);
    expect(sounds.plays, hasLength(2));
    expect(
      sounds.plays.map((playback) => playback.cue),
      everyElement(WanpanMotionSoundCue.rankingEncouragement),
    );
    expect(
      sounds.plays.map((playback) => playback.animated),
      everyElement(isTrue),
    );

    await tester.tap(find.text('热门线路'));
    await tester.pumpAndSettle();
    expect(find.text('还没有热门线路'), findsOneWidget);
    expect(_lottieStage(tester).play, isFalse);
  });

  testWidgets('已登录全国榜空状态返回后停在终帧', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(session.dispose);
    final sounds = FakeMotionSoundPlayer();
    await session.acceptSession(
      const AuthSession(
        token: 'test-token',
        user: UserSummary(id: 'me', nickname: '小欧'),
        needsProfile: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: RankingScreen(
          api: _EmptyRankingApi(),
          session: session,
          motionSoundPlayer: sounds,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本月榜单刚刚开始'), findsOneWidget);
    expect(_lottieStage(tester).play, isTrue);

    await tester.tap(find.text('热门线路'));
    await tester.pumpAndSettle();
    expect(find.text('还没有热门线路'), findsOneWidget);
    expect(_lottieStage(tester).play, isTrue);

    await tester.tap(find.text('全国榜'));
    await tester.pumpAndSettle();
    expect(find.text('本月榜单刚刚开始'), findsOneWidget);
    expect(_lottieStage(tester).play, isFalse);
  });

  testWidgets('排行页停留期间登录或退出会立即重载公开榜', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(session.dispose);
    final api = _EmptyRankingApi();
    final sounds = FakeMotionSoundPlayer();

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: RankingScreen(
          api: api,
          session: session,
          motionSoundPlayer: sounds,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本月榜单刚刚开始'), findsOneWidget);
    expect(find.text('登录后加入'), findsOneWidget);
    expect(api.rankingRequests, 1);

    await session.acceptSession(
      const AuthSession(
        token: 'fresh-token',
        user: UserSummary(id: 'me', nickname: '小欧'),
        needsProfile: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(api.rankingRequests, 2);
    expect(find.text('本月榜单刚刚开始'), findsOneWidget);

    await session.signOut();
    await tester.pumpAndSettle();

    expect(find.text('本月榜单刚刚开始'), findsOneWidget);
    expect(find.text('登录后加入'), findsOneWidget);
    expect(api.rankingRequests, 3);
  });

  testWidgets('不可见的保活排行页不会发声，离开时会停止声音', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(session.dispose);
    final api = _EmptyRankingApi();
    final sounds = FakeMotionSoundPlayer();

    Widget host({required bool visible}) => MaterialApp(
      theme: WanpanTheme.light(),
      home: TickerMode(
        enabled: visible,
        child: RankingScreen(
          key: const ValueKey('kept-alive-ranking'),
          api: api,
          session: session,
          motionSoundPlayer: sounds,
        ),
      ),
    );

    await tester.pumpWidget(host(visible: false));
    await tester.pumpAndSettle();
    expect(find.text('本月榜单刚刚开始'), findsOneWidget);
    expect(sounds.plays, isEmpty);

    await tester.pumpWidget(host(visible: true));
    await tester.pumpAndSettle();
    expect(sounds.plays, hasLength(1));

    final stopsBeforeLeaving = sounds.stopCount;
    await tester.pumpWidget(host(visible: false));
    await tester.pump();
    expect(sounds.stopCount, greaterThan(stopsBeforeLeaving));
  });
}

WanpanLottieStage _lottieStage(WidgetTester tester) =>
    tester.widget<WanpanLottieStage>(find.byType(WanpanLottieStage));
