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
import 'package:wanpan_diary/features/gyms/gym_screen.dart';
import 'package:wanpan_diary/features/gyms/gyms_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _ActivityApi extends ApiClient {
  _ActivityApi() : super(config: _config, accessTokenProvider: () => null);

  int sends = 0;
  int profileReads = 0;
  final routeQueries = <Map<String, dynamic>>[];
  final directoryCities = <String?>[];

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    switch (path) {
      case '/gyms/gym-1':
        return {
          'id': 'gym-1',
          'name': '测试岩馆',
          'city': '上海',
          'province': '上海市',
          'address': '攀岩路 1 号',
          'verified': true,
          'routeSets': [
            {
              'id': 'set-1',
              'gym_id': 'gym-1',
              'name': '九月新线',
              'starts_on': '2026-09-01',
              'active': true,
            },
          ],
        };
      case '/gyms/gym-1/routes':
        routeQueries.add({...?queryParameters});
        return {
          'items': [
            {
              'id': 'route-1',
              'gym_id': 'gym-1',
              'route_set_id': 'set-1',
              'name': '红色小屋檐',
              'grade': 'V2',
              'color': '红色',
              'send_count': sends,
            },
          ],
        };
      case '/users/me':
        profileReads += 1;
        return {
          'id': 'user-1',
          'nickname': '岩友',
          'stats': {
            'total_sends': sends,
            'monthly_sends': sends,
            'gym_count': sends == 0 ? 0 : 1,
            'max_grade': sends == 0 ? 0 : 2,
            'monthly_max_grade': sends == 0 ? 0 : 2,
          },
        };
      case '/gyms/directory':
        directoryCities.add(queryParameters?['city'] as String?);
        return {
          'items': [
            {
              'brand_id': 'brand-1',
              'brand_name': '测试岩馆',
              'city': '上海',
              'cities': ['上海'],
              'store_count': 1,
              'route_count': 1,
              'verified': true,
            },
          ],
        };
      case '/routes/weekly':
        return {'items': <Object>[]};
      default:
        throw StateError('Unexpected request: $path');
    }
  }
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(390, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'home_city_selection': '上海',
      'home_city_manual': true,
    });
  });

  testWidgets('mounted gym refreshes send count and keeps grade and cycle', (
    tester,
  ) async {
    final api = _ActivityApi();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });
    await _pumpScreen(tester, GymScreen(api: api, gymId: 'gym-1'));
    final mountedState = tester.state(find.byType(GymScreen));
    expect(find.text('0 人完攀'), findsOneWidget);

    await tester.tap(find.byTooltip('切换线路周期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('九月新线').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'V2'));
    await tester.pumpAndSettle();
    expect(api.routeQueries.last, {'grade': 'V2', 'setId': 'set-1'});
    final readsBefore = api.routeQueries.length;

    api.sends = 1;
    api.climbingActivity.recordChanged();
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(GymScreen)), same(mountedState));
    expect(api.routeQueries.length, readsBefore + 1);
    expect(api.routeQueries.last, {'grade': 'V2', 'setId': 'set-1'});
    expect(find.text('九月新线'), findsOneWidget);
    expect(find.text('0 人完攀'), findsNothing);
    expect(find.text('1 人完攀'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mounted home refreshes monthly progress after a check-in', (
    tester,
  ) async {
    final api = _ActivityApi();
    final preferences = await SharedPreferences.getInstance();
    final session = SessionController(
      preferences: preferences,
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    await session.acceptSession(
      const AuthSession(
        token: 'test-token',
        user: UserSummary(id: 'user-1', nickname: '岩友'),
        needsProfile: false,
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      api.dispose();
    });
    await _pumpScreen(tester, GymsScreen(api: api, session: session));
    final mountedState = tester.state(find.byType(GymsScreen));
    expect(find.text('0'), findsOneWidget);
    expect(find.text('V0'), findsOneWidget);
    final readsBefore = api.profileReads;
    api.directoryCities.clear();

    api.sends = 1;
    api.climbingActivity.recordChanged();
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(GymsScreen)), same(mountedState));
    expect(api.profileReads, readsBefore + 1);
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('V2'), findsOneWidget);
    expect(api.directoryCities, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
