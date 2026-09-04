import 'package:flutter/foundation.dart';

import '../../core/models/profile_models.dart';

enum MilestoneGradeSequenceSource { configured, currentMonth, fallback }

@immutable
class MilestoneGradeSequence {
  const MilestoneGradeSequence._({required this.grades, required this.source});

  final List<String> grades;
  final MilestoneGradeSequenceSource source;

  String get displayLabel => grades.join(' → ');
}

/// Resolves the three V grades shown by the milestone animation.
///
/// Precedence is deliberately explicit: a preview/operator override wins,
/// then the latest distinct grade entries in the supplied current-month
/// dashboard (with [latestGrade] appended as the newest completed result),
/// and finally the stable V1 → V2 → V3 demo sequence. Sparse real history is
/// left-padded by repeating its earliest value so it never invents a reversal.
abstract final class MilestoneGradeSequenceResolver {
  static const fallbackGrades = <String>['V1', 'V2', 'V3'];

  static MilestoneGradeSequence resolve({
    String? configured,
    MonthDashboard? currentMonth,
    String? latestGrade,
    DateTime? now,
  }) {
    final configuredGrades = parseConfigured(configured);
    if (configuredGrades.length == 3) {
      return MilestoneGradeSequence._(
        grades: configuredGrades,
        source: MilestoneGradeSequenceSource.configured,
      );
    }

    final recentGrades = _recentCurrentMonthGrades(
      currentMonth,
      now ?? DateTime.now(),
      latestGrade: latestGrade,
    );
    if (recentGrades.isNotEmpty) {
      return MilestoneGradeSequence._(
        grades: recentGrades,
        source: MilestoneGradeSequenceSource.currentMonth,
      );
    }

    return const MilestoneGradeSequence._(
      grades: fallbackGrades,
      source: MilestoneGradeSequenceSource.fallback,
    );
  }

  /// Parses `V2,V3,V4`, `v2 → v3 → v4`, and similar preview input.
  ///
  /// Exactly three distinct product grades (V0–V17) are required. Invalid,
  /// duplicate, shorter, or longer input returns an empty list so callers can
  /// fall through to current-month data or the stable demo default.
  static List<String> parseConfigured(String? value) {
    if (value == null || value.trim().isEmpty) return const [];

    final tokens = value
        .split(RegExp(r'[\s,，、>→/|_-]+'))
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
    if (tokens.length != 3) return const [];

    final result = <String>[];
    final seen = <String>{};
    for (final token in tokens) {
      final grade = _normalizeGrade(token);
      if (grade == null || !seen.add(grade)) return const [];
      result.add(grade);
    }
    return List.unmodifiable(result);
  }

  static List<String> _recentCurrentMonthGrades(
    MonthDashboard? dashboard,
    DateTime now, {
    String? latestGrade,
  }) {
    if (dashboard == null || dashboard.month != _monthKey(now)) {
      return const [];
    }

    final entries = <_DatedGrade>[];
    for (var index = 0; index < dashboard.days.length; index += 1) {
      final day = dashboard.days[index];
      final grade = _normalizeGrade(day.grade);
      if (day.day == null || grade == null) continue;
      entries.add(_DatedGrade(day: day.day!, grade: grade, index: index));
    }
    entries.sort((a, b) {
      final dateOrder = a.day.compareTo(b.day);
      return dateOrder == 0 ? a.index.compareTo(b.index) : dateOrder;
    });
    if (entries.isEmpty) return const [];

    final latestFirst = <String>[];
    final seen = <String>{};
    final normalizedLatestGrade = latestGrade == null
        ? null
        : _normalizeGrade(latestGrade);
    if (normalizedLatestGrade != null) {
      seen.add(normalizedLatestGrade);
      latestFirst.add(normalizedLatestGrade);
    }
    for (final entry in entries.reversed) {
      if (!seen.add(entry.grade)) continue;
      latestFirst.add(entry.grade);
      if (latestFirst.length == 3) break;
    }
    final recent = latestFirst.reversed.toList(growable: false);
    if (recent.isEmpty || recent.length == 3) {
      return List.unmodifiable(recent);
    }

    return List.unmodifiable([
      ...List.filled(3 - recent.length, recent.first),
      ...recent,
    ]);
  }

  static String? _normalizeGrade(String value) {
    final match = RegExp(
      r'^V\s*(\d{1,2})$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;
    final number = int.parse(match.group(1)!);
    if (number < 0 || number > 17) return null;
    return 'V$number';
  }

  static String _monthKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}';
}

class _DatedGrade {
  const _DatedGrade({
    required this.day,
    required this.grade,
    required this.index,
  });

  final DateTime day;
  final String grade;
  final int index;
}
