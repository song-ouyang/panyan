import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:wanpan_diary/features/gyms/checkin_screen.dart';
import 'package:wanpan_diary/shared/app_assets.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_lottie_stage.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_milestone_stage.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _CheckinApi extends ApiClient {
  _CheckinApi({
    this.milestoneGrade,
    this.monthDashboard,
    this.monthDashboardFuture,
  }) : super(config: _config, accessTokenProvider: () => 'secure-token');

  final String? milestoneGrade;
  final JsonMap? monthDashboard;
  final Future<JsonMap>? monthDashboardFuture;
  JsonMap? submittedData;
  bool monthDashboardRequested = false;

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path != '/users/me/month-dashboard') {
      throw StateError('Unexpected request: $path');
    }
    monthDashboardRequested = true;
    final pendingDashboard = monthDashboardFuture;
    if (pendingDashboard != null) return pendingDashboard;
    final dashboard = monthDashboard;
    if (dashboard == null) throw StateError('Month dashboard unavailable');
    return dashboard;
  }

  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path != '/sends') throw StateError('Unexpected request: $path');
    submittedData = jsonMap(data);
    return {
      'sendId': 'send-1',
      'moderationStatus': 'approved',
      'pointsEarned': 12,
      'pendingPoints': 0,
      if (milestoneGrade != null)
        'milestone': {'type': 'highest_grade', 'grade': milestoneGrade},
    };
  }
}

Future<SessionController> _signedInSession() async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  await session.acceptSession(
    const AuthSession(
      token: 'secure-token',
      user: UserSummary(id: 'me', nickname: '小欧', profileCompleted: true),
      needsProfile: false,
    ),
  );
  return session;
}

Widget _host({
  required ApiClient api,
  required SessionController session,
  required bool reduceMotion,
}) {
  return MaterialApp(
    theme: WanpanTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: CheckinScreen(
      api: api,
      session: session,
      routeId: 'route-1',
      routeName: '橙色月亮线',
      grade: 'V4',
    ),
  );
}

Future<void> _settleBackgroundLoad(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 180)),
  );
  await tester.pump();
  await tester.pumpAndSettle();
  await tester.pump();
}

void main() {
  testWidgets('ordinary check-in shows stable success and medium feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final session = await _signedInSession();
    addTearDown(session.dispose);
    final dashboardRequest = Completer<JsonMap>();
    final api = _CheckinApi(monthDashboardFuture: dashboardRequest.future);

    await tester.pumpWidget(
      _host(api: api, session: session, reduceMotion: false),
    );
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is WanpanButton && widget.label == '保存完攀',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('完攀记录已保存！'), findsOneWidget);
    expect(api.monthDashboardRequested, isTrue);
    expect(dashboardRequest.isCompleted, isFalse);
    expect(find.text('返回线路'), findsOneWidget);
    expect(
      tester.widget<WanpanLottieStage>(find.byType(WanpanLottieStage)).asset,
      AppAssets.sendSuccessAnimation,
    );

    await _settleBackgroundLoad(tester);

    expect(api.submittedData?['routeId'], 'route-1');
    expect(
      haptics.where((value) => value == 'HapticFeedbackType.mediumImpact'),
      hasLength(1),
    );
    expect(find.text('完攀记录已保存！'), findsOneWidget);
    dashboardRequest.completeError(StateError('offline'));
    await tester.pump();
  });

  testWidgets('reduced-motion milestone keeps final state and heavy feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final session = await _signedInSession();
    addTearDown(session.dispose);
    final api = _CheckinApi(milestoneGrade: 'V5');

    await tester.pumpWidget(
      _host(api: api, session: session, reduceMotion: true),
    );
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is WanpanButton && widget.label == '保存完攀',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('新的最高难度 V5！'), findsOneWidget);
    expect(
      tester.widget<WanpanLottieStage>(find.byType(WanpanLottieStage)).asset,
      AppAssets.gradeMilestoneAnimation,
    );
    expect(
      tester
          .widget<WanpanMilestoneStage>(find.byType(WanpanMilestoneStage))
          .grades,
      ['V1', 'V2', 'V3'],
    );

    await _settleBackgroundLoad(tester);

    expect(find.text('V5'), findsOneWidget);
    expect(
      haptics.where((value) => value == 'HapticFeedbackType.heavyImpact'),
      hasLength(1),
    );
    expect(find.text('返回线路'), findsOneWidget);
  });

  testWidgets('milestone uses recent grades from the prefetched current month', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final session = await _signedInSession();
    addTearDown(session.dispose);
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    String day(int value) => '$month-${value.toString().padLeft(2, '0')}';
    final api = _CheckinApi(
      milestoneGrade: 'V6',
      monthDashboard: {
        'month': month,
        'days': [
          {'day': day(1), 'gym_name': '岩馆', 'grade': 'V1', 'sends': 1},
          {'day': day(2), 'gym_name': '岩馆', 'grade': 'V2', 'sends': 1},
          {'day': day(3), 'gym_name': '岩馆', 'grade': 'V4', 'sends': 1},
          {'day': day(4), 'gym_name': '岩馆', 'grade': 'V5', 'sends': 1},
        ],
        'summary': {
          'climbing_days': 4,
          'sends': 4,
          'gyms': 1,
          'max_grade': 5,
          'flashes': 0,
          'videos': 0,
        },
        'byGrade': <Object?>[],
        'byGym': <Object?>[],
      },
    );

    await tester.pumpWidget(
      _host(api: api, session: session, reduceMotion: true),
    );
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is WanpanButton && widget.label == '保存完攀',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(api.monthDashboardRequested, isTrue);
    expect(find.text('新的最高难度 V6！'), findsOneWidget);
    expect(
      tester
          .widget<WanpanMilestoneStage>(find.byType(WanpanMilestoneStage))
          .grades,
      ['V4', 'V5', 'V6'],
    );
    expect(find.text('V4'), findsOneWidget);
    expect(find.text('V5'), findsOneWidget);
    expect(find.text('V6'), findsNWidgets(2));
  });
}
