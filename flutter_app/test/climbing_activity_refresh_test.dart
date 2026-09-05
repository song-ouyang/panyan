import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/route_submission_models.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';
import 'package:wanpan_diary/core/repositories/checkin_repository.dart';
import 'package:wanpan_diary/core/repositories/route_submission_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/gyms/gym_screen.dart';
import 'package:wanpan_diary/features/profile/profile_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

const _user = UserSummary(
  id: 'profile-user',
  nickname: '攀爬小熊',
  profileCompleted: true,
);

const _draft = RouteSubmissionDraft(
  clientRequestId: 'new-route-request',
  gymId: 'gym-1',
  name: '红色线路',
  grade: 'V2',
  color: '红色',
  coverUrl: 'https://example.com/route.png',
  points: [],
  videoUrl: 'https://example.com/send.mp4',
);

JsonMap _profile({required int sends, required int grade}) => {
  ..._user.toJson(),
  'stats': {
    'total_sends': sends,
    'gym_count': sends == 0 ? 0 : 1,
    'max_grade': grade,
    'monthly_sends': sends,
    'monthly_max_grade': grade,
  },
};

class _ActivityApi extends ApiClient {
  _ActivityApi() : super(config: _config, accessTokenProvider: () => 'token');

  final profileResponses = Queue<Future<JsonMap>>();
  int profileRequests = 0;
  int gymRouteRequests = 0;
  int savedSends = 0;
  Object? createError;
  bool malformedCreateResponse = false;

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/gyms/gym-1') {
      return {
        'id': 'gym-1',
        'name': '测试岩馆',
        'city': '深圳',
        'address': '南山大道',
        'route_count': 1,
        'routeSets': [],
      };
    }
    if (path == '/gyms/gym-1/routes') {
      gymRouteRequests++;
      return {
        'items': [
          {
            'id': 'route-1',
            'gym_id': 'gym-1',
            'name': '红色线路',
            'grade': 'V2',
            'color': '红色',
            'send_count': savedSends,
          },
        ],
      };
    }
    if (path != '/users/me') {
      throw StateError('Unexpected request: $path');
    }
    profileRequests++;
    if (profileResponses.isNotEmpty) return profileResponses.removeFirst();
    return _profile(sends: savedSends, grade: savedSends == 0 ? 0 : 2);
  }

  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path != '/sends' && path != '/submissions') {
      throw StateError('Unexpected request: $path');
    }
    final error = createError;
    if (error != null) throw error;
    if (malformedCreateResponse) return {};
    savedSends++;
    if (path == '/submissions') {
      return {
        'id': 'submission-1',
        'submitter_id': _user.id,
        'gym_id': 'gym-1',
        'name': '红色线路',
        'grade': 'V2',
        'color': '红色',
        'cover_url': 'https://example.com/route.png',
        'points': [],
        'status': 'approved',
        'published_route_id': 'route-1',
        'send_id': 'send-1',
        'video_moderation_status': 'approved',
      };
    }
    return {
      'sendId': 'send-$savedSends',
      'moderationStatus': 'approved',
      'pointsEarned': 25,
      'pendingPoints': 0,
    };
  }
}

Future<ValueNotifier<int>> _showCachedProfile(
  WidgetTester tester,
  _ActivityApi api,
) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  addTearDown(session.dispose);
  await session.acceptSession(
    const AuthSession(token: 'token', user: _user, needsProfile: false),
  );
  final selectedTab = ValueNotifier(0);
  addTearDown(selectedTab.dispose);
  final profileScreen = ProfileScreen(api: api, session: session);
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: ValueListenableBuilder<int>(
        valueListenable: selectedTab,
        builder: (context, index, _) => IndexedStack(
          index: index,
          children: [
            profileScreen,
            const Scaffold(body: Center(child: Text('完攀操作页面'))),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return selectedTab;
}

Finder _growthText(String text) => find.descendant(
  of: find.byKey(const Key('profile-growth-card')),
  matching: find.text(text),
);

void main() {
  testWidgets(
    'cached profile refreshes monthly and lifetime stats after a send',
    (tester) async {
      final api = _ActivityApi();
      final selectedTab = await _showCachedProfile(tester, api);
      final originalState = tester.state(find.byType(ProfileScreen));
      expect(_growthText('0'), findsOneWidget);
      expect(_growthText('V0'), findsOneWidget);
      expect(api.profileRequests, 1);
      await tester.tap(find.byKey(const Key('profile-growth-period-lifetime')));
      await tester.pumpAndSettle();
      expect(_growthText('0'), findsNWidgets(2));

      selectedTab.value = 1;
      await tester.pumpAndSettle();
      final result = await CheckinRepository(api).createCheckin(
        routeId: 'route-1',
        videoUrl: 'https://example.com/send.mp4',
      );
      expect(result.moderationStatus, 'approved');
      await tester.pumpAndSettle();
      selectedTab.value = 0;
      await tester.pumpAndSettle();

      expect(tester.state(find.byType(ProfileScreen)), same(originalState));
      expect(api.profileRequests, 2);
      expect(_growthText('1'), findsNWidgets(2));
      expect(
        _growthText('去过岩馆'),
        findsOneWidget,
        reason: 'Refreshing must keep the selected growth period',
      );

      await tester.tap(find.byKey(const Key('profile-growth-period-month')));
      await tester.pumpAndSettle();
      expect(_growthText('1'), findsOneWidget);
      expect(_growthText('V2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('profile-growth-period-lifetime')));
      await tester.pumpAndSettle();
      expect(_growthText('1'), findsNWidgets(2));
      expect(_growthText('V2'), findsOneWidget);
      expect(_growthText('去过岩馆'), findsOneWidget);
      expect(
        api.profileRequests,
        2,
        reason: 'Changing periods uses refreshed stats',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed or malformed sends do not invalidate the mounted profile',
    (tester) async {
      final api = _ActivityApi();
      await _showCachedProfile(tester, api);
      var notifications = 0;
      api.climbingActivity.addListener(() => notifications++);
      final repository = CheckinRepository(api);

      api.createError = const ApiException(
        code: 'FORBIDDEN',
        message: '无法保存这次完攀',
        statusCode: 403,
      );
      await expectLater(
        repository.createCheckin(routeId: 'route-1'),
        throwsA(isA<ApiException>()),
      );
      api.createError = null;
      api.malformedCreateResponse = true;
      await expectLater(
        repository.createCheckin(routeId: 'route-1'),
        throwsA(isA<FormatException>()),
      );
      await tester.pumpAndSettle();

      expect(notifications, 0);
      expect(api.profileRequests, 1);
      expect(_growthText('0'), findsOneWidget);
      expect(_growthText('V0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final staleRequestFails in [false, true]) {
    testWidgets(
      'latest profile refresh wins over a stale ${staleRequestFails ? 'error' : 'response'}',
      (tester) async {
        final api = _ActivityApi();
        await _showCachedProfile(tester, api);
        final olderRequest = Completer<JsonMap>();
        final newerRequest = Completer<JsonMap>();
        api.profileResponses.addAll([olderRequest.future, newerRequest.future]);

        api.climbingActivity.recordChanged();
        await tester.pump();
        api.climbingActivity.recordChanged();
        await tester.pump();
        expect(api.profileRequests, 3);

        newerRequest.complete(_profile(sends: 2, grade: 4));
        await tester.pumpAndSettle();
        expect(_growthText('2'), findsOneWidget);
        expect(_growthText('V4'), findsOneWidget);

        if (staleRequestFails) {
          olderRequest.completeError(StateError('Old request failed'));
        } else {
          olderRequest.complete(_profile(sends: 1, grade: 2));
        }
        await tester.pumpAndSettle();
        expect(_growthText('2'), findsOneWidget);
        expect(_growthText('V4'), findsOneWidget);
        expect(_growthText('V2'), findsNothing);
        expect(find.text('成长记录暂时没有加载出来'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'activity from another API client does not refresh this profile',
    (tester) async {
      final api = _ActivityApi();
      final unrelatedApi = _ActivityApi();
      await _showCachedProfile(tester, api);

      await CheckinRepository(unrelatedApi).createCheckin(routeId: 'route-1');
      await tester.pumpAndSettle();
      expect(api.profileRequests, 1);
      expect(_growthText('0'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      api.climbingActivity.recordChanged();
      await tester.pump();
      expect(api.profileRequests, 1, reason: 'Disposed screens stop listening');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mounted gym routes refresh their send counts after a check-in', (
    tester,
  ) async {
    final api = _ActivityApi();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: GymScreen(api: api, gymId: 'gym-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.gymRouteRequests, 1);
    expect(find.text('0 人完攀'), findsOneWidget);

    await CheckinRepository(api).createCheckin(routeId: 'route-1');
    await tester.pumpAndSettle();
    expect(api.gymRouteRequests, 2);
    expect(find.text('1 人完攀'), findsOneWidget);
    expect(find.text('0 人完攀'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'route publication notifies only after a valid successful response',
    () async {
      final api = _ActivityApi();
      final repository = RouteSubmissionRepository(api);
      var notifications = 0;
      api.climbingActivity.addListener(() => notifications++);

      api.createError = const ApiException(
        code: 'FORBIDDEN',
        message: '无法发布这条线路',
        statusCode: 403,
      );
      await expectLater(
        repository.create(_draft),
        throwsA(isA<ApiException>()),
      );
      api.createError = null;
      api.malformedCreateResponse = true;
      await expectLater(
        repository.create(_draft),
        throwsA(isA<FormatException>()),
      );
      expect(notifications, 0);

      api.malformedCreateResponse = false;
      final result = await repository.create(_draft);
      expect(result.publishedRouteId, 'route-1');
      expect(result.sendId, 'send-1');
      expect(notifications, 1);
    },
  );
}
