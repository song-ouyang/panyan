import 'package:flutter/widgets.dart';

import '../core/network/api_client.dart';
import '../features/auth/application/session_controller.dart';

class AppScope extends InheritedNotifier<SessionController> {
  const AppScope({
    required this.api,
    required this.session,
    required super.child,
    super.key,
  }) : super(notifier: session);

  final ApiClient api;
  final SessionController session;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this context.');
    return scope!;
  }

  static AppScope read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    assert(element != null, 'AppScope is missing above this context.');
    return element!.widget as AppScope;
  }
}
