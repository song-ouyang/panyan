import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:wanpan_diary/shared/widgets/wanpan_lottie_stage.dart';

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
  testWidgets('热门线路入口会直接打开公开线路榜', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: RankingScreen(
          api: _EmptyRankingApi(),
          session: session,
          initialSegment: 1,
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

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: RankingScreen(api: _EmptyRankingApi(), session: session),
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
        home: RankingScreen(api: _EmptyRankingApi(), session: session),
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

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: RankingScreen(api: api, session: session),
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
}

WanpanLottieStage _lottieStage(WidgetTester tester) =>
    tester.widget<WanpanLottieStage>(find.byType(WanpanLottieStage));
