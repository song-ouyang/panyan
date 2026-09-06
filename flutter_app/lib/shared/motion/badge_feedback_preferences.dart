import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Badge sound is opt-in. This preference is shared by automatic celebration
/// and manual replay; changing it notifies an active player immediately.
class BadgeFeedbackPreferences extends ChangeNotifier {
  BadgeFeedbackPreferences._();
  static final instance = BadgeFeedbackPreferences._();
  static const storageKey = 'feedback.badgeSoundEnabled';
  bool _enabled = false;
  Future<void>? _loading;
  bool get enabled => _enabled;
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      _enabled =
          (await SharedPreferences.getInstance()).getBool(storageKey) ?? false;
      notifyListeners();
    } catch (_) {
      // Missing preference storage keeps optional audio muted.
    }
  }

  Future<void> setEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool(storageKey, value)) {
      throw StateError('音效设置未保存');
    }
    _enabled = value;
    notifyListeners();
  }
}
