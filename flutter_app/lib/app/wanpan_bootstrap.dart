import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/native_auth_service.dart';
import '../features/onboarding/application/onboarding_controller.dart';
import '../features/splash/splash_screen.dart';
import 'wanpan_app.dart';
import 'wanpan_router.dart';
import 'wanpan_theme.dart';

typedef WanpanPreferencesLoader = Future<SharedPreferences> Function();

/// Paints the branded startup surface before plugin-backed preferences finish
/// loading, then hands the same visual state to the real router.
class WanpanBootstrap extends StatefulWidget {
  const WanpanBootstrap({
    required this.config,
    super.key,
    this.preferencesLoader,
  });

  final AppConfig config;
  final WanpanPreferencesLoader? preferencesLoader;

  @override
  State<WanpanBootstrap> createState() => _WanpanBootstrapState();
}

class _WanpanBootstrapState extends State<WanpanBootstrap> {
  _WanpanDependencies? _dependencies;
  double _progress = .12;
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final attempt = ++_attempt;
    setState(() {
      _failed = false;
      _progress = .18;
    });

    try {
      final loadPreferences =
          widget.preferencesLoader ?? SharedPreferences.getInstance;
      final preferences = await loadPreferences();
      if (!mounted || attempt != _attempt) return;
      setState(() => _progress = .42);

      final session = SessionController(
        preferences: preferences,
        config: widget.config,
      );
      final onboarding = OnboardingController(preferences: preferences);
      final api = ApiClient(
        config: widget.config,
        accessTokenProvider: () => session.token,
      );
      api.onUnauthorized = session.handleUnauthorizedResponse;
      final authRepository = AuthRepository(api);
      final router = createWanpanRouter(
        api: api,
        session: session,
        authRepository: authRepository,
        nativeAuth: NativeAuthService(
          appleLoginEnabled: widget.config.enableAppleLogin,
        ),
        onboarding: onboarding,
      );
      final dependencies = _WanpanDependencies(
        api: api,
        session: session,
        onboarding: onboarding,
        authRepository: authRepository,
        router: router,
      );

      if (!mounted || attempt != _attempt) {
        dependencies.dispose();
        return;
      }
      setState(() {
        _progress = .58;
        _dependencies = dependencies;
      });
      unawaited(_initializeSession(dependencies));
    } catch (error, stackTrace) {
      debugPrint('App bootstrap failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && attempt == _attempt) {
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _initializeSession(_WanpanDependencies dependencies) async {
    try {
      await dependencies.session.initialize(dependencies.authRepository);
    } catch (error, stackTrace) {
      // Public browsing remains available when session restoration fails.
      debugPrint('Session initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _attempt++;
    _dependencies?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    if (dependencies != null) {
      return WanpanApp(
        api: dependencies.api,
        session: dependencies.session,
        router: dependencies.router,
      );
    }

    return MaterialApp(
      title: '完攀日记',
      debugShowCheckedModeBanner: false,
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(minScaleFactor: .9, maxScaleFactor: 1.35),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: StartupSplashScreen(
        progress: _progress,
        failed: _failed,
        onRetry: _failed ? _initialize : null,
      ),
    );
  }
}

class _WanpanDependencies {
  const _WanpanDependencies({
    required this.api,
    required this.session,
    required this.onboarding,
    required this.authRepository,
    required this.router,
  });

  final ApiClient api;
  final SessionController session;
  final OnboardingController onboarding;
  final AuthRepository authRepository;
  final GoRouter router;

  void dispose() {
    router.dispose();
    api.dispose();
    onboarding.dispose();
    session.dispose();
  }
}
