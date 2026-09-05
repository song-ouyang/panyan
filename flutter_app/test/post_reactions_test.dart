import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/feed_repository.dart';
import 'package:wanpan_diary/core/repositories/profile_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/feed/feed_screen.dart';
import 'package:wanpan_diary/features/feed/post_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);
AuthSession _account(String id) => AuthSession(
  token: 'token-$id',
  user: UserSummary(id: id, nickname: id, profileCompleted: true),
  needsProfile: false,
);

class _Api extends ApiClient {
  _Api() : super(config: _config, accessTokenProvider: () => 'test');
  String Function() viewer = () => 'me';
  final likes = <String>{}, favorites = <String>{};
  final writes = <String>[];
  Completer<void>? writeBarrier, readBarrier;
  bool fail = false, malformed = false;
  Map<String, dynamic>? query;
  Map<String, dynamic> get post => {
    'id': 'post-1',
    'user_id': 'author',
    'nickname': '橙线岩友',
    'caption': '周末的攀岩记录',
    'image_urls': <String>[],
    'visibility': 'public',
    'moderation_status': 'approved',
    'like_count': likes.length,
    'liked': likes.contains(viewer()),
    'favorited': favorites.contains(viewer()),
    'comment_count': 0,
    'comments': <Object>[],
    'sent_at': '2026-09-05T08:00:00Z',
    'activity_at': '2026-09-06T08:00:00Z',
  };
  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    query = queryParameters;
    final snapshot = post, barrier = readBarrier;
    readBarrier = null;
    await barrier?.future;
    if (path == '/sends/post-1') return snapshot;
    if (path == '/users/me/comments') {
      return {
        'items': [
          {
            'id': 'comment-1',
            'content': '下次一起爬',
            'created_at': '2026-09-06T09:00:00Z',
            'moderation_status': 'approved',
            'post': snapshot,
          },
        ],
        'nextCursor': 'comment-cursor',
      };
    }
    if ([
      '/sends/feed',
      '/users/me/likes',
      '/users/me/favorites',
    ].contains(path)) {
      return {
        'items': [snapshot],
        'nextCursor': 'cursor-2',
      };
    }
    throw StateError('Unexpected GET $path');
  }

  Future<Map<String, dynamic>> _write(String method, String path) async {
    writes.add('$method $path');
    final user = viewer();
    await writeBarrier?.future;
    if (fail) throw Exception('offline');
    if (malformed) return {};
    final value = method == 'POST';
    if (path.endsWith('/favorite')) {
      if (value) {
        favorites.add(user);
      } else {
        favorites.remove(user);
      }
      return {'favorited': value};
    }
    if (path.endsWith('/like')) {
      if (value) {
        likes.add(user);
      } else {
        likes.remove(user);
      }
      return {'liked': value};
    }
    return {'deleted': true};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) => _write('POST', path);
  @override
  Future<Map<String, dynamic>> deleteJson(String path, {Object? data}) =>
      _write('DELETE', path);
}

Future<({SessionController session, GoRouter router})> _open(
  WidgetTester tester,
  _Api api, {
  bool detail = false,
  bool guest = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  if (!guest) await session.acceptSession(_account('me'));
  api.viewer = () => session.user?.id ?? 'guest';
  final router = GoRouter(
    initialLocation: detail ? '/posts/post-1' : '/feed',
    routes: [
      GoRoute(
        path: '/feed',
        builder: (_, _) => FeedScreen(api: api, session: session),
      ),
      GoRoute(
        path: '/posts/:id',
        builder: (_, state) => PostScreen(
          api: api,
          session: session,
          postId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text('登录页')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    session.dispose();
    api.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return (session: session, router: router);
}

void main() {
  test('personal activity models preserve parent post/date and repositories send bounded pagination', () async {
    final api = _Api();
    addTearDown(api.dispose);
    final repo = ProfileRepository(api);
    final saved = await repo.getMyFavorites(cursor: 'opaque', limit: 100);
    expect(api.query, {'cursor': 'opaque', 'limit': 50});
    expect(saved.nextCursor, 'cursor-2');
    expect(saved.items.single.activityAt, DateTime.utc(2026, 9, 6, 8));
    await repo.getMyLikes(limit: 0);
    expect(api.query, {'limit': 1});
    final comments = await repo.getMyComments(cursor: 'before');
    expect(comments.items.single.post.id, 'post-1');
    expect(comments.items.single.content, '下次一起爬');
    expect(comments.nextCursor, 'comment-cursor');
  });
  test(
    'only confirmed reaction/comment writes broadcast successful changes',
    () async {
      final api = _Api();
      addTearDown(api.dispose);
      final repo = FeedRepository(api);
      var changes = 0;
      api.socialActivity.addListener(() => changes++);
      for (final malformed in [true, false]) {
        api.malformed = malformed;
        api.fail = !malformed;
        await expectLater(
          repo.setLiked('post-1', liked: true),
          throwsException,
        );
        await expectLater(
          repo.setFavorited('post-1', favorited: false),
          throwsException,
        );
        await expectLater(
          repo.deleteComment('post-1', 'comment-1'),
          throwsException,
        );
      }
      expect(changes, 0);
      api.fail = false;
      await repo.setFavorited('post-1', favorited: true);
      await repo.setLiked('post-1', liked: true);
      await repo.deleteComment('post-1', 'comment-1');
      expect(changes, 3);
      expect(api.socialActivity.changedPostId, 'post-1');
      expect(api.socialActivity.postDeleted, false);
    },
  );
  testWidgets('favorite and like state follows square, friends and detail', (
    tester,
  ) async {
    final api = _Api();
    await _open(tester, api);
    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消收藏'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    await tester.tap(find.text('朋友圈'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消收藏'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    await tester.tap(find.text('周末的攀岩记录'));
    await tester.pumpAndSettle();
    expect(find.text('已收藏'), findsOneWidget);
    await tester.tap(find.text('已收藏'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(api.favorites, isEmpty);
    expect(api.likes, {'me'});
    expect(tester.takeException(), isNull);
  });
  for (final detail in [false, true]) {
    testWidgets(
      '${detail ? 'detail' : 'feed'} serializes taps and rolls back rejected save',
      (tester) async {
        final barrier = Completer<void>();
        final api = _Api()
          ..writeBarrier = barrier
          ..malformed = true;
        await _open(tester, api, detail: detail);
        await tester.tap(find.byIcon(Icons.star_border_rounded));
        await tester.pump();
        expect(find.byIcon(Icons.star_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.star_rounded));
        await tester.pump();
        expect(api.writes.length, 1);
        barrier.complete();
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
        expect(api.favorites, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${detail ? 'detail' : 'feed'} pending save cannot mark next account saved',
      (tester) async {
        final barrier = Completer<void>();
        final api = _Api()..writeBarrier = barrier;
        final state = await _open(tester, api, detail: detail);
        await tester.tap(find.byIcon(Icons.star_border_rounded));
        await tester.pump();
        await state.session.acceptSession(_account('second'));
        await tester.pumpAndSettle();
        barrier.complete();
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
        expect(api.favorites, {'me'});
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('${detail ? 'detail' : 'feed'} guest save requires login', (
      tester,
    ) async {
      final api = _Api();
      await _open(tester, api, detail: detail, guest: true);
      await tester.tap(find.byIcon(Icons.star_border_rounded));
      await tester.pumpAndSettle();
      expect(find.text('登录页'), findsOneWidget);
      expect(api.writes, isEmpty);
    });
  }
  testWidgets('late detail refresh cannot restore favorite after unsaving', (
    tester,
  ) async {
    final api = _Api()..favorites.add('me');
    await _open(tester, api, detail: true);
    final barrier = Completer<void>();
    api.readBarrier = barrier;
    api.socialActivity.recordChanged(postId: 'post-1');
    await tester.pump();
    await tester.tap(find.text('已收藏'));
    await tester.pumpAndSettle();
    barrier.complete();
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsOneWidget);
    expect(api.favorites, isEmpty);
  });
  testWidgets(
    'relationship refresh during save cannot strand detail on loading',
    (tester) async {
      final write = Completer<void>();
      final read = Completer<void>();
      final api = _Api()..writeBarrier = write;
      await _open(tester, api, detail: true);
      await tester.tap(find.text('收藏'));
      await tester.pump();
      api.readBarrier = read;
      api.socialActivity.recordChanged();
      await tester.pump();
      write.complete();
      await tester.pumpAndSettle();
      read.complete();
      await tester.pumpAndSettle();
      expect(find.text('周末的攀岩记录'), findsOneWidget);
      expect(find.text('已收藏'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
