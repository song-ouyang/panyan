import 'package:flutter/foundation.dart';

/// Announces saved changes; consumers reload using the current account.
class SocialActivityChanges extends ChangeNotifier {
  String? changedPostId;
  bool postDeleted = false;

  void recordChanged({String? postId, bool deleted = false}) {
    changedPostId = postId;
    postDeleted = deleted;
    notifyListeners();
  }
}
