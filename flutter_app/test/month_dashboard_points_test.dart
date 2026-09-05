import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/models/profile_models.dart';

void main() {
  test('monthly points include V0, multi-digit grades and flash bonuses', () {
    final dashboard = MonthDashboard.fromJson({
      'month': '2026-08',
      'summary': {
        'climbing_days': 3,
        'sends': 5,
        'gyms': 2,
        'max_grade': 17,
        'flashes': 2,
        'videos': 4,
      },
      'days': [],
      'byGrade': [
        {'grade': 'V0', 'sends': '1'},
        {'grade': 'V2', 'sends': '2'},
        {'grade': 'V10', 'sends': '1'},
        {'grade': 'V17', 'sends': '1'},
      ],
      'byGym': [],
    });

    // 10 + 40 + 60 + 95 for the routes, plus two 5-point flash bonuses.
    expect(dashboard.completionPoints, 215);
    expect(dashboard.summary.videos, 4);
  });

  test('a month without completions has zero points', () {
    final dashboard = MonthDashboard.fromJson({
      'month': '2026-07',
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
    });

    expect(dashboard.completionPoints, 0);
  });
}
