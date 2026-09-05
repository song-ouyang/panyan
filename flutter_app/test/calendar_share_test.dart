import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/services/share_service.dart';
import 'package:wanpan_diary/features/profile/climbing_calendar_screen.dart';
import 'package:wanpan_diary/features/sharing/monthly_share_preview.dart';

void main() {
  Future<void> pumpCalendar(
    WidgetTester tester,
    _Api api,
    _ShareService service, {
    DateTime? initialMonth,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: ClimbingCalendarScreen(
          api: api,
          initialMonth: initialMonth,
          shareService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'top-right share previews and sends the selected month as an image',
    (tester) async {
      final api = _Api();
      final service = _ShareService();
      await pumpCalendar(tester, api, service, initialMonth: DateTime(2026, 8));
      expect(find.text('分享这个月的记录'), findsNothing);
      expect(find.byTooltip('分享这个月'), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar-previous-month')));
      await tester.pumpAndSettle();
      expect(find.text('2026 年 7 月'), findsOneWidget);
      await tester.tap(find.byTooltip('分享这个月'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('2026 年 7 月攀岩记录'), findsOneWidget);
      final poster = tester.widget<MonthlySharePoster>(
        find.byKey(const Key('monthly-share-poster')),
      );
      expect(poster.month, '2026-07');
      expect(poster.dashboard!.month, '2026-07');
      expect(
        find.descendant(
          of: find.byKey(const Key('monthly-share-poster')),
          matching: find.text('积分'),
        ),
        findsOneWidget,
      );
      expect(find.text('点数'), findsNothing);
      expect(find.text('分享给朋友'), findsOneWidget);
      expect(find.text('停止分享'), findsNothing);
      expect(find.text('复制链接'), findsNothing);
      expect(find.text('预览分享页'), findsNothing);
      expect(api.lookedUp, isEmpty);
      expect(api.published, isEmpty);
      expect(service.images, isEmpty);
      await tester.runAsync(() async {
        await tester.tap(find.text('分享给朋友'));
        for (var frame = 0; frame < 120 && service.images.isEmpty; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      });
      await tester.pumpAndSettle();
      expect(service.images, hasLength(1));
      expect(service.title, '2026 年 7 月攀岩记录 | 完攀日记');
      expect(service.fileName, 'wanpan-month-2026-07.png');
      expect(service.images.single.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(service.origin!.width, greaterThanOrEqualTo(44));
      expect(service.origin!.height, greaterThanOrEqualTo(44));
      expect(api.lookedUp, isEmpty);
      expect(api.published, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a loading month cannot accidentally share the previous dashboard',
    (tester) async {
      final api = _Api();
      await pumpCalendar(
        tester,
        api,
        _ShareService(),
        initialMonth: DateTime(2026, 8),
      );
      api.pending = Completer<JsonMap>();
      await tester.tap(find.byKey(const Key('calendar-previous-month')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('calendar-share-month')))
            .onPressed,
        isNull,
      );
      expect(api.lookedUp, isEmpty);
      api.pending!.complete(_dashboard('2026-07'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('分享这个月'));
      await tester.pumpAndSettle();
      expect(find.text('2026 年 7 月攀岩记录'), findsOneWidget);
      expect(api.lookedUp, isEmpty);
      expect(api.published, isEmpty);
    },
  );

  testWidgets(
    'dashboard error blocks sharing and retry restores selected month',
    (tester) async {
      final api = _Api()..failDashboard = true;
      await pumpCalendar(
        tester,
        api,
        _ShareService(),
        initialMonth: DateTime(2026, 8),
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('calendar-share-month')))
            .onPressed,
        isNull,
      );
      expect(find.text('重新加载'), findsOneWidget);
      api.failDashboard = false;
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('分享这个月'));
      await tester.pumpAndSettle();
      expect(find.text('2026 年 8 月攀岩记录'), findsOneWidget);
      expect(api.lookedUp, isEmpty);
      expect(api.published, isEmpty);
    },
  );

  testWidgets('mismatched dashboard response cannot expose a different month', (
    tester,
  ) async {
    final api = _Api()..wrongMonth = true;
    await pumpCalendar(
      tester,
      api,
      _ShareService(),
      initialMonth: DateTime(2026, 8),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('calendar-share-month')))
          .onPressed,
      isNull,
    );
    expect(find.text('重新加载'), findsOneWidget);
    expect(api.published, isEmpty);
  });

  testWidgets('closing the local preview does not publish or send anything', (
    tester,
  ) async {
    final api = _Api();
    final service = _ShareService();
    await pumpCalendar(tester, api, service, initialMonth: DateTime(2026, 8));
    await tester.tap(find.byTooltip('分享这个月'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭分享'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('monthly-share-poster')), findsNothing);
    expect(find.text('2026 年 8 月'), findsOneWidget);
    expect(api.lookedUp, isEmpty);
    expect(api.published, isEmpty);
    expect(service.images, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an older dashboard response cannot replace a newer refresh', (
    tester,
  ) async {
    final api = _Api();
    await pumpCalendar(
      tester,
      api,
      _ShareService(),
      initialMonth: DateTime(2026, 8),
    );
    final older = Completer<JsonMap>();
    api.pending = older;
    api.climbingActivity.recordChanged();
    await tester.pump();
    final newer = Completer<JsonMap>();
    api.pending = newer;
    api.climbingActivity.recordChanged();
    await tester.pump();
    newer.complete(_dashboard('2026-08'));
    await tester.pumpAndSettle();
    older.complete(_dashboard('2026-01'));
    await tester.pumpAndSettle();
    expect(find.text('重新加载'), findsNothing);
    await tester.tap(find.byTooltip('分享这个月'));
    await tester.pumpAndSettle();
    expect(find.text('2026 年 8 月攀岩记录'), findsOneWidget);
    expect(find.text('2026 年 1 月攀岩记录'), findsNothing);
    expect(api.lookedUp, isEmpty);
    expect(api.published, isEmpty);
  });

  testWidgets(
    'initial month and future navigation follow the Shanghai calendar',
    (tester) async {
      final api = _Api();
      await pumpCalendar(tester, api, _ShareService());
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      expect(api.dashboardMonths, [month]);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('calendar-next-month')))
            .onPressed,
        isNull,
      );
    },
  );
}

JsonMap _dashboard(String month) => {
  'month': month,
  'summary': {
    'climbing_days': 0,
    'sends': 0,
    'gyms': 0,
    'max_grade': 0,
    'flashes': 0,
    'videos': 0,
  },
  'days': [],
  'byGrade': [],
  'byGym': [],
};

class _Api extends ApiClient {
  _Api()
    : super(
        config: const AppConfig(
          environment: AppEnvironment.production,
          apiBaseUrl: 'https://example.com/api',
          enableDevelopmentLogin: false,
        ),
        accessTokenProvider: () => 'token',
      );
  final dashboardMonths = <String>[];
  final lookedUp = <String>[];
  final published = <String>[];
  Completer<JsonMap>? pending;
  bool failDashboard = false;
  bool wrongMonth = false;

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final month = queryParameters!['month'] as String;
    if (path == '/users/me/month-dashboard') {
      dashboardMonths.add(month);
      if (failDashboard) throw StateError('offline');
      if (pending != null) return pending!.future;
      return _dashboard(wrongMonth ? '2026-01' : month);
    }
    expect(path, '/shares/monthly');
    lookedUp.add(month);
    return {'token': null, 'month': month};
  }

  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    expect(path, '/shares/monthly');
    final month = (data as Map<String, dynamic>)['month'] as String;
    published.add(month);
    return {
      'token': 'abcdefghijklmnopqrstuvwxyz0123456789_-ABCDE',
      'month': month,
    };
  }
}

class _ShareService extends ShareService {
  final images = <Uint8List>[];
  String? title;
  String? fileName;
  Rect? origin;

  @override
  Future<ShareResultStatus> shareImage({
    required Uint8List bytes,
    required String title,
    required String fileName,
    required Rect origin,
  }) async {
    images.add(bytes);
    this.title = title;
    this.fileName = fileName;
    this.origin = origin;
    return ShareResultStatus.success;
  }
}
