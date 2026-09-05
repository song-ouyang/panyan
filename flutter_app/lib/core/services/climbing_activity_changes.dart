import 'package:flutter/foundation.dart';

/// Invalidates climbing summaries after a saved route or check-in changes.
/// Each API client owns its notifier, so separate app sessions do not share it.
class ClimbingActivityChanges extends ChangeNotifier {
  void recordChanged() => notifyListeners();
}
