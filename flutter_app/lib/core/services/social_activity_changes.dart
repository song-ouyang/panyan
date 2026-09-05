import 'package:flutter/foundation.dart';

/// Refreshes social state after a saved friendship or post change in this client.
class SocialActivityChanges extends ChangeNotifier {
  void recordChanged() => notifyListeners();
}
