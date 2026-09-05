import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/gyms/route_picker_screen.dart';
import 'package:wanpan_diary/features/gyms/route_screen.dart';
import 'package:wanpan_diary/features/profile/route_submissions_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _RouteApi extends ApiClient {
  _RouteApi(this.coverUrl)
    : super(config: _config, accessTokenProvider: () => 'token');

  final String? coverUrl;

  JsonMap get route => {
    'id': 'route-1',
    'gym_id': 'gym-1',
    'name': '橙色平衡线',
    'grade': 'V3',
    'color': '橙色',
    'wall_zone': 'A区',
    'gym_name': '测试岩馆',
    'cover_url': coverUrl,
    'points': <Object>[],
    'published': true,
  };

  JsonMap get gym => {
    'id': 'gym-1',
    'name': '测试岩馆',
    'city': '成都',
    'address': '岩馆地址',
    'verified': true,
    'routeSets': <Object>[],
  };

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => switch (path) {
    '/submissions/mine' => {
      'items': [
        {
          ...route,
          'id': 'submission-1',
          'submitter_id': 'user-1',
          'status': 'approved',
          'published_route_id': 'route-1',
          'created_at': '2026-09-05T08:00:00Z',
        },
      ],
    },
    '/routes/route-1' => route,
    '/routes/route-1/leaderboard' => {
      'items': <Object>[],
      'completionCount': 0,
    },
    '/gyms' => {
      'items': [gym],
    },
    '/gyms/gym-1' => gym,
    '/gyms/gym-1/routes' => {
      'items': [route],
    },
    _ => throw StateError('Unexpected GET $path'),
  };
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required String? coverUrl,
  required String initialLocation,
}) async {
  SharedPreferences.setMockInitialValues({});
  final api = _RouteApi(coverUrl);
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  await session.acceptSession(
    const AuthSession(
      token: 'token',
      user: UserSummary(id: 'user-1', nickname: '岩友'),
      needsProfile: false,
    ),
  );
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/history',
        builder: (_, _) => RouteSubmissionsScreen(api: api),
      ),
      GoRoute(
        path: '/picker',
        builder: (_, _) => RoutePickerScreen(
          api: api,
          session: session,
          initialGymId: 'gym-1',
        ),
      ),
      GoRoute(
        path: '/routes/:routeId',
        builder: (_, state) => RouteScreen(
          api: api,
          session: session,
          routeId: state.pathParameters['routeId']!,
        ),
      ),
      GoRoute(
        path: '/routes/:routeId/checkin',
        builder: (_, _) => const Scaffold(body: Text('打卡页面')),
      ),
    ],
  );
  addTearDown(api.dispose);
  addTearDown(session.dispose);
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(const Size(320, 568));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp.router(
      theme: WanpanTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

bool _isNetworkImage(ImageProvider image) =>
    image is NetworkImage ||
    (image is ResizeImage && _isNetworkImage(image.imageProvider));

Finder get _networkImages => find.byWidgetPredicate(
  (widget) => widget is Image && _isNetworkImage(widget.image),
);

void main() {
  for (final (label, coverUrl) in <(String, String?)>[
    ('null', null),
    ('empty', ''),
    ('blank', '   '),
  ]) {
    testWidgets('$label封面记录可打开详情并打卡，不占用空照片区域', (tester) async {
      final router = await _pump(
        tester,
        coverUrl: coverUrl,
        initialLocation: '/history',
      );

      expect(find.text('橙色平衡线'), findsOneWidget);
      expect(find.text('V3'), findsOneWidget);
      expect(find.text('发布记录暂时没有加载出来'), findsNothing);
      expect(_networkImages, findsNothing);
      await tester.tap(find.text('橙色平衡线'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/routes/route-1');
      expect(find.text('橙色平衡线'), findsNWidgets(2));
      expect(find.text('V3'), findsOneWidget);
      expect(find.text('测试岩馆 · A区'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == 'route-route-1',
        ),
        findsNothing,
      );
      expect(_networkImages, findsNothing);
      expect(find.text('我完攀了').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('我完攀了'));
      await tester.pumpAndSettle();
      expect(find.text('打卡页面'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$label封面线路可从选择列表直接打卡，不请求空图片地址', (tester) async {
      await _pump(tester, coverUrl: coverUrl, initialLocation: '/picker');

      expect(find.text('橙色平衡线'), findsOneWidget);
      expect(_networkImages, findsNothing);
      await tester.tap(find.text('橙色平衡线'));
      await tester.pumpAndSettle();
      expect(find.text('打卡页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('带封面的线路保留详情图片', (tester) async {
    await _pump(
      tester,
      coverUrl: 'https://example.com/route.jpg',
      initialLocation: '/routes/route-1',
    );

    expect(_networkImages, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == 'route-route-1',
      ),
      findsOneWidget,
    );
    expect(find.text('我完攀了').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
