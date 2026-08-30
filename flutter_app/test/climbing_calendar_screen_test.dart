import 'package:flutter/material.dart';
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
    expect(find.text('香蕉攀岩·南山店'), findsNWidgets(2));
    expect(find.text('8 月 12 日 · 完成 2 条'), findsOneWidget);
    expect(find.text('V3'), findsWidgets);

    await tester.tap(find.byKey(const Key('calendar-previous-month')));
    await tester.pumpAndSettle();

    expect(repository.requestedMonths, ['2026-08', '2026-07']);
    expect(find.text('2026 年 7 月'), findsOneWidget);
    expect(find.textContaining('这个月还没有记录'), findsOneWidget);
  });
}

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository(super.api);

  final requestedMonths = <String>[];

  @override
  Future<MonthDashboard> getMonthDashboard(String month) async {
    requestedMonths.add(month);
    if (month == '2026-08') {
      return MonthDashboard(
        month: month,
        days: [
          MonthlyDayStat(
            day: DateTime(2026, 8, 12),
            gymName: '香蕉攀岩·南山店',
            grade: 'V3',
            sends: 2,
          ),
        ],
        summary: const MonthlySummary(
          climbingDays: 1,
          sends: 2,
          gyms: 1,
          maxGrade: 3,
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
