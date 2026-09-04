import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OnboardingGoal { findGyms, checkInRoute, browseFeed, viewRanking }

class OnboardingController extends ChangeNotifier {
  OnboardingController({required SharedPreferences preferences})
    : _preferences = preferences,
      _completedVersion = preferences.getInt(_completedVersionKey) ?? 0,
      _savedGoal = _readGoal(preferences.getString(_goalKey));

  OnboardingController.ephemeral({bool completed = true})
    : _preferences = null,
      _completedVersion = completed ? currentVersion : 0,
      _savedGoal = null;

  static const currentVersion = 1;
  static const _completedVersionKey = 'onboarding.completed_version';
  static const _goalKey = 'onboarding.goal';

  final SharedPreferences? _preferences;
  int _completedVersion;
  OnboardingGoal? _savedGoal;

  bool get hasCompleted => _completedVersion >= currentVersion;
  OnboardingGoal? get savedGoal => _savedGoal;

  Future<void> complete({required OnboardingGoal? landingGoal}) async {
    final preferences = _preferences;
    if (preferences != null) {
      if (landingGoal == null) {
        await _writeOrThrow(preferences.remove(_goalKey));
      } else {
        await _writeOrThrow(preferences.setString(_goalKey, landingGoal.name));
      }
      // Write the version last so a partially written choice never marks the
      // whole onboarding flow as complete.
      await _writeOrThrow(
        preferences.setInt(_completedVersionKey, currentVersion),
      );
    }

    _savedGoal = landingGoal;
    _completedVersion = currentVersion;
    notifyListeners();
  }

  Future<void> skip() async {
    final preferences = _preferences;
    if (preferences != null) {
      await _writeOrThrow(preferences.remove(_goalKey));
      await _writeOrThrow(
        preferences.setInt(_completedVersionKey, currentVersion),
      );
    }
    _savedGoal = null;
    _completedVersion = currentVersion;
    notifyListeners();
  }

  static OnboardingGoal? _readGoal(String? stored) {
    if (stored == null) return null;
    for (final value in OnboardingGoal.values) {
      if (value.name == stored) return value;
    }
    return null;
  }

  static Future<void> _writeOrThrow(Future<bool> write) async {
    if (!await write) {
      throw StateError('无法保存首次使用设置');
    }
  }
}
