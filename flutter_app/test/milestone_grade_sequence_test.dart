import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/models/profile_models.dart';
import 'package:wanpan_diary/shared/motion/milestone_grade_sequence.dart';

const _emptySummary = MonthlySummary(
  climbingDays: 0,
  sends: 0,
  gyms: 0,
  maxGrade: 0,
  flashes: 0,
  videos: 0,
);

MonthDashboard _dashboard({
  required String month,
  required List<MonthlyDayStat> days,
}) => MonthDashboard(
  month: month,
  days: days,
  summary: _emptySummary,
  byGrade: const [],
  byGym: const [],
);

MonthlyDayStat _day(String date, String grade) => MonthlyDayStat(
  day: DateTime.parse(date),
  gymName: '测试岩馆',
  grade: grade,
  sends: 1,
);

void main() {
  group('MilestoneGradeSequenceResolver', () {
    test('uses normalized configured grades before current-month data', () {
      final result = MilestoneGradeSequenceResolver.resolve(
        configured: 'v2 → V4, V6',
        currentMonth: _dashboard(
          month: '2026-09',
          days: [_day('2026-09-01', 'V1')],
        ),
        now: DateTime(2026, 9, 4),
      );

      expect(result.grades, ['V2', 'V4', 'V6']);
      expect(result.source, MilestoneGradeSequenceSource.configured);
    });

    test('uses the latest three distinct current-month entries', () {
      final result = MilestoneGradeSequenceResolver.resolve(
        currentMonth: _dashboard(
          month: '2026-09',
          days: [
            _day('2026-09-01', 'V1'),
            _day('2026-09-02', 'V3'),
            _day('2026-09-03', 'V2'),
            _day('2026-09-04', 'V3'),
            _day('2026-09-04', 'V5'),
          ],
        ),
        now: DateTime(2026, 9, 4),
      );

      expect(result.grades, ['V2', 'V3', 'V5']);
      expect(result.source, MilestoneGradeSequenceSource.currentMonth);
    });

    test(
      'repeats the earliest real value for a sparse current-month sequence',
      () {
        final result = MilestoneGradeSequenceResolver.resolve(
          currentMonth: _dashboard(
            month: '2026-09',
            days: [_day('2026-09-03', 'V7'), _day('2026-09-04', 'V7')],
          ),
          now: DateTime(2026, 9, 4),
        );

        expect(result.grades, ['V7', 'V7', 'V7']);
        expect(result.source, MilestoneGradeSequenceSource.currentMonth);
      },
    );

    test('appends the just-completed grade as the newest milestone', () {
      final result = MilestoneGradeSequenceResolver.resolve(
        currentMonth: _dashboard(
          month: '2026-09',
          days: [
            _day('2026-09-01', 'V2'),
            _day('2026-09-02', 'V4'),
            _day('2026-09-03', 'V5'),
          ],
        ),
        latestGrade: 'V6',
        now: DateTime(2026, 9, 4),
      );

      expect(result.grades, ['V4', 'V5', 'V6']);
      expect(result.source, MilestoneGradeSequenceSource.currentMonth);
    });

    test(
      'ignores a configured sequence that does not contain three grades',
      () {
        final result = MilestoneGradeSequenceResolver.resolve(
          configured: 'V8,V9',
          currentMonth: _dashboard(
            month: '2026-09',
            days: [_day('2026-09-04', 'V5')],
          ),
          now: DateTime(2026, 9, 4),
        );

        expect(result.grades, ['V5', 'V5', 'V5']);
        expect(result.source, MilestoneGradeSequenceSource.currentMonth);
      },
    );

    test('falls back when current-month data is absent, empty, or stale', () {
      final absent = MilestoneGradeSequenceResolver.resolve(
        now: DateTime(2026, 9, 4),
      );
      final empty = MilestoneGradeSequenceResolver.resolve(
        currentMonth: _dashboard(month: '2026-09', days: const []),
        now: DateTime(2026, 9, 4),
      );
      final stale = MilestoneGradeSequenceResolver.resolve(
        currentMonth: _dashboard(
          month: '2026-08',
          days: [_day('2026-08-31', 'V8')],
        ),
        now: DateTime(2026, 9, 4),
      );

      for (final result in [absent, empty, stale]) {
        expect(result.grades, ['V1', 'V2', 'V3']);
        expect(result.source, MilestoneGradeSequenceSource.fallback);
      }
    });
  });
}
