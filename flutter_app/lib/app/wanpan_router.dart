import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/network/api_client.dart';
import '../core/services/friend_code.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/native_auth_service.dart';
import '../features/auth/domain/auth_return_path.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/profile_setup_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/feed/post_screen.dart';
import '../features/gyms/brand_screen.dart';
import '../features/gyms/application/home_city_controller.dart';
import '../features/gyms/checkin_screen.dart';
import '../features/gyms/gym_screen.dart';
import '../features/gyms/gyms_screen.dart';
import '../features/gyms/route_picker_screen.dart';
import '../features/gyms/route_screen.dart';
import '../features/gyms/route_submission_screen.dart';
import '../features/onboarding/application/onboarding_controller.dart';
import '../features/notifications/application/notifications_controller.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/profile/climbing_calendar_screen.dart';
import '../features/profile/account_privacy_screen.dart';
import '../features/profile/friends_screen.dart';
import '../features/profile/friend_code_screen.dart';
import '../features/profile/friend_scanner_screen.dart';
import '../features/profile/invite_friends_screen.dart';
import '../features/profile/my_posts_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/public_profile_screen.dart';
import '../features/profile/route_submissions_screen.dart';
import '../features/profile/settings_screen.dart';
import '../features/ranking/ranking_screen.dart';
import '../features/shell/wanpan_shell.dart';
import '../features/splash/splash_screen.dart';

GoRouter createWanpanRouter({
  required ApiClient api,
  required SessionController session,
  required AuthRepository authRepository,
  required NativeAuthService nativeAuth,
  OnboardingController? onboarding,
  HomeCityController? cityController,
  NotificationsController? notificationsController,
}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final friendCode = FriendCode(shareBaseUrl: api.config.shareBaseUrl);
  final onboardingState =
      onboarding ?? OnboardingController.ephemeral(completed: true);
  final onboardingEnabled = onboarding != null;

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: session,
    redirect: (context, state) {
      final path = state.uri.path;
      if (path == '/onboarding' && onboardingState.hasCompleted) {
        return '/gyms';
      }
      if (session.isInitializing) return null;
      final protected = _isProtectedPath(path);
      if (!session.isAuthenticated && protected) {
        return Uri(
          path: '/login',
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      if (session.isAuthenticated &&
          session.profileNeedsCompletion &&
          protected &&
          path != '/profile/setup') {
        return Uri(
          path: '/profile/setup',
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      if (session.isAuthenticated && path == '/login') {
        final from = safeAuthReturnTo(state.uri.queryParameters['from']);
        return session.profileNeedsCompletion
            ? Uri(
                path: '/profile/setup',
                queryParameters: {'from': from},
              ).toString()
            : from;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => SplashScreen(
          session: session,
          onContinue: () => context.go(
            onboardingEnabled && !onboardingState.hasCompleted
                ? '/onboarding'
                : '/gyms',
          ),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/onboarding',
        builder: (context, state) => OnboardingScreen(
          controller: onboardingState,
          onExit: () => context.go('/splash'),
          onSkipped: () => context.go('/gyms'),
          onFinished: context.go,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/login',
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: LoginScreen(
            session: session,
            repository: authRepository,
            nativeAuth: nativeAuth,
            returnTo: safeAuthReturnTo(state.uri.queryParameters['from']),
          ),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/setup',
        builder: (context, state) => ProfileSetupScreen(
          api: api,
          session: session,
          repository: authRepository,
          returnTo: safeAuthReturnTo(state.uri.queryParameters['from']),
          editing: state.uri.queryParameters['editing'] == 'true',
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/invite',
        builder: (context, state) => InviteFriendsScreen(
          inviteUrl: api.config.inviteUrl,
          onShowFriendCode: () => context.push('/friends/code'),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/posts',
        builder: (context, state) => MyPostsScreen(api: api, session: session),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/calendar',
        builder: (context, state) => ClimbingCalendarScreen(api: api),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/privacy',
        builder: (context, state) =>
            AccountPrivacyScreen(api: api, session: session),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings',
        builder: (context, state) => SettingsScreen(session: session),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            WanpanShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/gyms',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: GymsScreen(
                    api: api,
                    session: session,
                    cityController: cityController,
                    notificationsController: notificationsController,
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/feed',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: FeedScreen(api: api, session: session),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ranking',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: RankingScreen(
                    api: api,
                    session: session,
                    cityController: cityController,
                    initialSegment: state.uri.queryParameters['tab'] == 'routes'
                        ? 1
                        : 0,
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: ProfileScreen(api: api, session: session),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/brands/:brandId',
        builder: (context, state) => BrandScreen(
          api: api,
          brandId: state.pathParameters['brandId']!,
          city: state.uri.queryParameters['city'],
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/gyms/:gymId',
        builder: (context, state) =>
            GymScreen(api: api, gymId: state.pathParameters['gymId']!),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/posts/:postId',
        builder: (context, state) => PostScreen(
          api: api,
          session: session,
          postId: state.pathParameters['postId']!,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/route-submissions/new',
        builder: (context, state) => RouteSubmissionScreen(
          api: api,
          session: session,
          initialGymId: state.uri.queryParameters['gymId'],
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/route-submissions',
        builder: (context, state) => RouteSubmissionsScreen(api: api),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/friends',
        builder: (context, state) => FriendsScreen(
          api: api,
          onOpenProfile: (userId) => context.push('/users/$userId'),
          onScan: () => context.push<String>('/friends/scan'),
          onShowFriendCode: () => context.push<Object?>('/friends/code'),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/friends/code',
        builder: (context, state) {
          final user = session.user;
          if (user == null) return const _WaitingForSession();
          return FriendCodeScreen(
            user: user,
            friendUrl: friendCode.encode(user.id),
            onScan: () async {
              final userId = await context.push<String>('/friends/scan');
              if (userId != null && context.mounted) {
                await context.push<void>('/users/$userId');
              }
            },
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/friends/scan',
        builder: (context, state) {
          final user = session.user;
          if (user == null) return const _WaitingForSession();
          return FriendScannerScreen(
            codec: friendCode,
            currentUserId: user.id,
            onScanned: (userId) {
              // Login restoration may open the scanner as the first page.
              if (context.canPop()) {
                context.pop(userId);
              } else {
                context.go('/users/$userId');
              }
            },
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/notifications',
        builder: (context, state) => _NotificationsRoute(
          api: api,
          session: session,
          controller: notificationsController,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/users/:userId',
        builder: (context, state) => PublicProfileScreen(
          api: api,
          userId: state.pathParameters['userId']!,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/routes/pick',
        builder: (context, state) => RoutePickerScreen(
          api: api,
          session: session,
          initialGymId: state.uri.queryParameters['gymId'],
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/routes/:routeId',
        builder: (context, state) => RouteScreen(
          api: api,
          session: session,
          routeId: state.pathParameters['routeId']!,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/routes/:routeId/checkin',
        builder: (context, state) {
          final extra = state.extra is Map<String, String>
              ? state.extra! as Map<String, String>
              : null;
          return CheckinScreen(
            api: api,
            session: session,
            routeId: state.pathParameters['routeId']!,
            grade: extra?['grade'],
            routeName: extra?['name'],
          );
        },
      ),
    ],
  );
}

bool _isProtectedPath(String path) {
  if (path == '/notifications') return true;
  if (path == '/settings') return true;
  if (path == '/profile') return true;
  if (path == '/profile/setup' || path.startsWith('/profile/')) return true;
  if (path == '/friends' ||
      path.startsWith('/friends/') ||
      path.startsWith('/users/')) {
    return true;
  }
  if (path == '/route-submissions' || path.startsWith('/route-submissions/')) {
    return true;
  }
  return path.startsWith('/routes/') && path.endsWith('/checkin');
}

class _WaitingForSession extends StatelessWidget {
  const _WaitingForSession();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(strokeWidth: 3)),
  );
}

class _NotificationsRoute extends StatefulWidget {
  const _NotificationsRoute({
    required this.api,
    required this.session,
    this.controller,
  });

  final ApiClient api;
  final SessionController session;
  final NotificationsController? controller;

  @override
  State<_NotificationsRoute> createState() => _NotificationsRouteState();
}

class _NotificationsRouteState extends State<_NotificationsRoute> {
  late final NotificationsController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        NotificationsController(api: widget.api, session: widget.session);
    if (widget.controller == null) _controller.start();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationsScreen(controller: _controller);
}
