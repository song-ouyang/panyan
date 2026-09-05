import 'package:flutter/foundation.dart';

/// Refreshes social state after a successful friendship change in this client.
class SocialActivityChanges extends ChangeNotifier {
  void recordChanged() => notifyListeners();
}
