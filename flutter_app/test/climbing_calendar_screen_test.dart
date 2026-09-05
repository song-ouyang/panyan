import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/profile_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/profile_repository.dart';
import 'package:wanpan_diary/features/profile/climbing_calendar_screen.dart';

void main() {
  testWidgets('日历展示记录、日详情并可切换到空月份', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const config = AppConfig(
      environment: AppEnvironment.development,
      apiBaseUrl: 'http://127.0.0.1:3000/api',
      enableDevelopmentLogin: false,
    );
    final api = ApiClient(config: config, accessTokenProvider: () => 'token');
    final repository = _FakeProfileRepository(api);

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: ClimbingCalendarScreen(
          api: api,
          repository: repository,
          initialMonth: DateTime(2026, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedMonths, ['2026-08']);
    expect(find.text('2026 年 8 月'), findsOneWidget);
    expect(find.text('香蕉攀岩·南山店'), findsWidgets);
    expect(find.text('8 月 12 日 · 完成 2 条'), findsOneWidget);
    expect(find.text('V3'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('calendar-day-count-2026-08-12')))
          .data,
      '2条',
    );
    expect(find.text('最高难度 V3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calendar-previous-month')));
    await tester.pumpAndSettle();

    expect(repository.requestedMonths, ['2026-08', '2026-07']);
    expect(find.text('2026 年 7 月'), findsOneWidget);
    expect(find.textContaining('这个月还没有记录'), findsOneWidget);
  });

  testWidgets('每天合计所有岩馆的完攀数并按数值展示最高难度', (tester) async {
    final api = _api();
    final repository = _FakeProfileRepository(api)
      ..records = [
        _record(12, 'V2', 2),
        _record(12, 'V9', 1),
        _record(12, 'V10', 1, gymName: '另一家岩馆'),
        _record(10, 'V17', 1),
        _record(13, 'V17', 0),
      ];
    await _pumpCalendar(tester, api, repository);

    expect(
      tester
          .widget<Text>(find.byKey(const Key('calendar-day-count-2026-08-12')))
          .data,
      '4条',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('calendar-day-grade-2026-08-12')))
          .data,
      'V10',
    );
    expect(find.text('8 月 12 日 · 完成 4 条'), findsOneWidget);
    expect(find.text('最高难度 V10'), findsOneWidget);
    expect(find.bySemanticsLabel('8月12日，完成4条线路，最高V10'), findsOneWidget);
    expect(
      find.byKey(const Key('calendar-day-count-2026-08-13')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('calendar-day-2026-08-13')));
    await tester.pumpAndSettle();
    expect(find.textContaining('这一天还没有记录'), findsOneWidget);
    expect(find.textContaining('这个月还没有记录'), findsNothing);
  });

  testWidgets('窄屏和大字号下日期下方的数量和最高难度不裁切', (tester) async {
    final api = _api();
    final repository = _FakeProfileRepository(api)
      ..records = [_record(12, 'V10', 12)];
    await _pumpCalendar(
      tester,
      api,
      repository,
      size: const Size(320, 568),
      textScale: 1.35,
    );
    final day = find.byKey(const Key('calendar-day-2026-08-12'));
    await tester.ensureVisible(day);
    await tester.pumpAndSettle();

    final count = find.byKey(const Key('calendar-day-count-2026-08-12'));
    final grade = find.byKey(const Key('calendar-day-grade-2026-08-12'));
    final countParagraph = tester.renderObject<RenderParagraph>(count);
    final gradeParagraph = tester.renderObject<RenderParagraph>(grade);
    expect(countParagraph.didExceedMaxLines, isFalse);
    expect(gradeParagraph.didExceedMaxLines, isFalse);
    expect(
      tester.getRect(count).bottom,
      lessThan(tester.getRect(grade).bottom),
    );
    expect(
      tester.getRect(grade).bottom,
      lessThanOrEqualTo(tester.getRect(day).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('完攀变更立即刷新当前月份并保留选中的日期', (tester) async {
    final api = _api();
    final repository = _FakeProfileRepository(api)
      ..records = [_record(10, 'V2', 1), _record(12, 'V3', 2)];
    await _pumpCalendar(tester, api, repository);
    await tester.tap(find.byKey(const Key('calendar-day-2026-08-10')));
    await tester.pumpAndSettle();
    expect(find.text('8 月 10 日 · 完成 1 条'), findsOneWidget);

    repository.records = [
      _record(10, 'V2', 1),
      _record(10, 'V4', 1),
      _record(12, 'V3', 2),
    ];
    api.climbingActivity.recordChanged();
    await tester.pumpAndSettle();

    expect(repository.requestedMonths, ['2026-08', '2026-08']);
    expect(find.text('8 月 10 日 · 完成 2 条'), findsOneWidget);
    expect(find.text('最高难度 V4'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('calendar-day-grade-2026-08-10')))
          .data,
      'V4',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    api.climbingActivity.recordChanged();
    await tester.pump();
    expect(repository.requestedMonths, ['2026-08', '2026-08']);
    expect(tester.takeException(), isNull);
  });
}

ApiClient _api() => ApiClient(
  config: const AppConfig(
    environment: AppEnvironment.development,
    apiBaseUrl: 'http://127.0.0.1:3000/api',
    enableDevelopmentLogin: false,
  ),
  accessTokenProvider: () => 'token',
);

Future<void> _pumpCalendar(
  WidgetTester tester,
  ApiClient api,
  ProfileRepository repository, {
  Size size = const Size(430, 932),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ClimbingCalendarScreen(
        api: api,
        repository: repository,
        initialMonth: DateTime(2026, 8),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MonthlyDayStat _record(
  int day,
  String grade,
  int sends, {
  String gymName = '香蕉攀岩·南山店',
}) => MonthlyDayStat(
  day: DateTime(2026, 8, day),
  gymName: gymName,
  grade: grade,
  sends: sends,
);

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository(super.api);

  final requestedMonths = <String>[];
  List<MonthlyDayStat> records = [_record(12, 'V3', 2)];

  @override
  Future<MonthDashboard> getMonthDashboard(String month) async {
    requestedMonths.add(month);
    if (month == '2026-08') {
      return MonthDashboard(
        month: month,
        days: records,
        summary: MonthlySummary(
          climbingDays: records.map((record) => record.day).toSet().length,
          sends: records.fold(0, (sum, record) => sum + record.sends),
          gyms: records.map((record) => record.gymName).toSet().length,
          maxGrade: records.fold(0, (max, record) {
            final grade = int.parse(record.grade.substring(1));
            return grade > max ? grade : max;
          }),
          flashes: 1,
          videos: 1,
        ),
        byGrade: const [GradeSummary(grade: 'V3', sends: 2)],
        byGym: const [
          GymSummary(
            gymId: 'gym-1',
            gymName: '香蕉攀岩·南山店',
            sends: 2,
            maxGrade: 3,
          ),
        ],
      );
    }
    return MonthDashboard(
      month: month,
      days: const [],
      summary: const MonthlySummary(
        climbingDays: 0,
        sends: 0,
        gyms: 0,
        maxGrade: 0,
        flashes: 0,
        videos: 0,
      ),
      byGrade: const [],
      byGym: const [],
    );
  }
}
