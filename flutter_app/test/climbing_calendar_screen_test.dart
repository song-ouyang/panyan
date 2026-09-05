import 'dart:ui' as ui;

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
    final hero = find.byKey(const Key('calendar-month-hero'));
    expect(
      find.descendant(of: hero, matching: find.text('积分')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hero, matching: find.text('55')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hero, matching: find.text('视频记录')),
      findsNothing,
    );
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

  testWidgets('积分指标可读可点，窄屏大字下规则可滚动且关闭后保留月份与记录', (tester) async {
    final api = _api();
    final repository = _FakeProfileRepository(api);
    await _pumpCalendar(
      tester,
      api,
      repository,
      size: const Size(320, 568),
      textScale: 1.35,
    );
    final semantics = tester.ensureSemantics();
    await tester.pump();
    final points = find.byKey(const Key('calendar-points-rules'));
    await tester.ensureVisible(points);
    await tester.pumpAndSettle();
    expect(points.hitTestable(), findsOneWidget);
    expect(tester.getSize(points).shortestSide, greaterThanOrEqualTo(44));
    try {
      final pointsSemantics = find.bySemanticsLabel('积分55，查看积分规则');
      expect(pointsSemantics, findsOneWidget);
      expect(
        tester
            .getSemantics(pointsSemantics)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
    } finally {
      semantics.dispose();
    }

    await tester.tap(points);
    await tester.pumpAndSettle();
    expect(find.text('积分规则'), findsOneWidget);
    expect(find.text('+10 分'), findsOneWidget);
    expect(find.text('+V级 × 5 分'), findsOneWidget);
    expect(find.text('尝试 1 次即完成'), findsOneWidget);
    expect(find.text('+5 分'), findsOneWidget);
    expect(find.text('10 + 2 × 5 + 5 = 25 分'), findsOneWidget);
    expect(find.text('这里仅统计完攀积分，不含排行榜的点赞加分。'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final sheet = find.byKey(const Key('calendar-points-rules-sheet'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: sheet, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    final dismiss = find.byKey(const Key('calendar-points-rules-dismiss'));
    await tester.ensureVisible(dismiss);
    await tester.pumpAndSettle();
    expect(dismiss.hitTestable(), findsOneWidget);
    expect(tester.getSize(dismiss).shortestSide, greaterThanOrEqualTo(44));
    await tester.tap(dismiss);
    await tester.pumpAndSettle();

    expect(sheet, findsNothing);
    expect(repository.requestedMonths, ['2026-08']);
    expect(find.text('2026 年 8 月'), findsOneWidget);
    final dayDetails = find.text('8 月 12 日 · 完成 2 条');
    await tester.scrollUntilVisible(
      dayDetails,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(dayDetails, findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('calendar-share-month')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('每日数量按区间分色且 V0 到 V17 各有独立色条', (tester) async {
    final api = _api();
    const counts = [1, 2, 3, 4, 6, 7, 9, 10];
    final repository = _FakeProfileRepository(api)
      ..records = [
        for (var grade = 0; grade <= 17; grade++)
          _record(grade + 1, 'V$grade', counts[grade % counts.length]),
      ];
    await _pumpCalendar(tester, api, repository);

    expect({
      for (var day = 1; day <= 18; day++) _barColor(tester, 'grade', day),
    }, hasLength(18));
    expect({
      for (final day in [1, 2, 4, 6, 8]) _barColor(tester, 'count', day),
    }, hasLength(5));
    expect(_barColor(tester, 'count', 2), _barColor(tester, 'count', 3));
    expect(_barColor(tester, 'count', 4), _barColor(tester, 'count', 5));
    expect(_barColor(tester, 'count', 6), _barColor(tester, 'count', 7));
    for (var day = 1; day <= 18; day++) {
      for (final kind in ['count', 'grade']) {
        final contrast =
            (_barColor(tester, kind, day).computeLuminance() + .05) /
            (WanpanColors.ink.computeLuminance() + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
    }
    expect(
      find.byKey(const Key('calendar-day-count-bar-2026-08-19')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏和大字号下两条色条铺满日期格且文字不裁切', (tester) async {
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
    final countBar = find.byKey(const Key('calendar-day-count-bar-2026-08-12'));
    final gradeBar = find.byKey(const Key('calendar-day-grade-bar-2026-08-12'));
    final countParagraph = tester.renderObject<RenderParagraph>(count);
    final gradeParagraph = tester.renderObject<RenderParagraph>(grade);
    expect(countParagraph.didExceedMaxLines, isFalse);
    expect(gradeParagraph.didExceedMaxLines, isFalse);
    expect(tester.getSize(countBar).width, tester.getSize(day).width);
    expect(tester.getSize(gradeBar).width, tester.getSize(day).width);
    expect(
      tester.getRect(countBar).bottom,
      lessThan(tester.getRect(gradeBar).top),
    );
    expect(
      tester.getRect(count).center.dx,
      closeTo(tester.getRect(countBar).center.dx, .01),
    );
    expect(
      tester.getRect(grade).center.dx,
      closeTo(tester.getRect(gradeBar).center.dx, .01),
    );
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

Color _barColor(WidgetTester tester, String kind, int day) {
  final date = '2026-08-${day.toString().padLeft(2, '0')}';
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byKey(Key('calendar-day-$kind-bar-$date')),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
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
