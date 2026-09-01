import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/network/api_client.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/native_auth_service.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/profile_setup_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/feed/post_screen.dart';
import '../features/gyms/brand_screen.dart';
import '../features/gyms/checkin_screen.dart';
import '../features/gyms/gym_screen.dart';
import '../features/gyms/gyms_screen.dart';
import '../features/gyms/route_picker_screen.dart';
import '../features/gyms/route_screen.dart';
import '../features/gyms/route_submission_screen.dart';
import '../features/profile/climbing_calendar_screen.dart';
import '../features/profile/account_privacy_screen.dart';
import '../features/profile/friends_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/public_profile_screen.dart';
import '../features/profile/route_submissions_screen.dart';
import '../features/ranking/ranking_screen.dart';
import '../features/shell/wanpan_shell.dart';
import '../features/splash/splash_screen.dart';

GoRouter createWanpanRouter({
  required ApiClient api,
  required SessionController session,
  required AuthRepository authRepository,
  required NativeAuthService nativeAuth,
}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: session,
    redirect: (context, state) {
      if (session.isInitializing) return null;
      final path = state.uri.path;
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
        final from = _safeReturnTo(state.uri.queryParameters['from']);
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
          onContinue: () => context.go('/gyms'),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/login',
        builder: (context, state) => LoginScreen(
          session: session,
          repository: authRepository,
          nativeAuth: nativeAuth,
          returnTo: _safeReturnTo(state.uri.queryParameters['from']),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/setup',
        builder: (context, state) => ProfileSetupScreen(
          api: api,
          session: session,
          repository: authRepository,
          returnTo: _safeReturnTo(state.uri.queryParameters['from']),
          editing: state.uri.queryParameters['editing'] == 'true',
        ),
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            WanpanShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/gyms',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: GymsScreen(api: api, session: session),
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
                  child: RankingScreen(api: api, session: session),
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
        builder: (context, state) =>
            BrandScreen(api: api, brandId: state.pathParameters['brandId']!),
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
  if (path == '/feed' || path == '/ranking' || path == '/profile') return true;
  if (path == '/profile/setup' || path.startsWith('/profile/')) return true;
  if (path == '/friends' || path.startsWith('/users/')) return true;
  if (path.startsWith('/posts/')) return true;
  if (path == '/route-submissions' || path.startsWith('/route-submissions/')) {
    return true;
  }
  return path.startsWith('/routes/') && path.endsWith('/checkin');
}

String _safeReturnTo(String? value) {
  if (value == null || !value.startsWith('/') || value.startsWith('/login')) {
    return '/gyms';
  }
  return value;
}
