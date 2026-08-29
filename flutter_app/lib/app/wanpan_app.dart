import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/network/api_client.dart';
import '../features/auth/application/session_controller.dart';
import 'app_scope.dart';
import 'wanpan_theme.dart';

class WanpanApp extends StatelessWidget {
  const WanpanApp({
    required this.api,
    required this.session,
    required this.router,
    super.key,
  });

  final ApiClient api;
  final SessionController session;
  final GoRouter router;

  @override
  Widget build(BuildContext context) => AppScope(
    api: api,
    session: session,
    child: MaterialApp.router(
      title: '完攀日记',
      debugShowCheckedModeBanner: false,
      theme: WanpanTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(minScaleFactor: .9, maxScaleFactor: 1.35),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}
