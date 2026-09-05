import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_router.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';
import 'package:wanpan_diary/features/auth/data/native_auth_service.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/profile/my_activity_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_video_cover.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);
const _owner = UserSummary(id: 'owner', nickname: '本人');
const _other = UserSummary(id: 'other', nickname: '另一个账号');

Map<String, dynamic> _post(String id) => {
  'id': id,
  'user_id': 'author-$id',
  'nickname': '作者 $id',
  'caption': '父动态 $id',
  'attempts': 1,
  'image_urls': <String>[],
  'visibility': 'public',
  'moderation_status': 'approved',
  'liked': true,
  'favorited': true,
  'like_count': 3,
  'comment_count': 1,
  'comments': <Object>[],
  'sent_at': '2025-08-01T08:00:00Z',
  'activity_at': '2026-09-05T08:00:00Z',
};

Map<String, dynamic> _comment(String id) => {
  'id': id,
  'content': '我发出的评论 $id',
  'created_at': '2026-09-05T08:00:00Z',
  'moderation_status': 'approved',
  'post': _post('parent-$id'),
};

class _ActivityApi extends ApiClient {
  _ActivityApi(this.session)
    : super(config: _config, accessTokenProvider: () => session.token);
  final SessionController session;
  final pages = <String, Map<String, dynamic>>{};
  final reads = <({String? userId, String path, String? cursor, int? limit})>[];
  final deletes = <({String? userId, String path})>[];
  final readGates = <String, Completer<void>>{};
  final failedPages = <String>{};
  Completer<void>? deleteGate;
  bool failDelete = false;
  bool malformedDelete = false;

  String key(String kind, {String user = 'owner', String? cursor}) =>
      '$user/$kind/${cursor ?? ''}';

  void setPage(
    String kind,
    List<Map<String, dynamic>> items, {
    String user = 'owner',
    String? cursor,
    String? next,
  }) {
    pages[key(kind, user: user, cursor: cursor)] = {
      'items': items,
      'nextCursor': next,
    };
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final kind = path.split('/').last;
    if (!MyActivityKind.values.any((value) => value.name == kind)) {
      throw StateError('Unexpected GET $path');
    }
    final userId = session.user?.id;
    final cursor = queryParameters?['cursor'] as String?;
    reads.add((
      userId: userId,
      path: path,
      cursor: cursor,
      limit: queryParameters?['limit'] as int?,
    ));
    final pageKey = key(kind, user: userId ?? 'guest', cursor: cursor);
    final page = pages[pageKey] ?? {'items': <Object>[], 'nextCursor': null};
    final frozen = {...page, 'items': List<Object>.from(page['items'] as List)};
    final shouldFail = failedPages.contains(pageKey);
    await readGates.remove(pageKey)?.future;
    if (shouldFail) throw StateError('Page unavailable');
    return frozen;
  }

  @override
  Future<Map<String, dynamic>> deleteJson(String path, {Object? data}) async {
    final actor = session.user?.id;
    deletes.add((userId: actor, path: path));
    await deleteGate?.future;
    if (failDelete) throw StateError('Mutation unavailable');
    if (malformedDelete) return {};
    final segments = path.split('/');
    final kind = segments[3] == 'comments'
        ? 'comments'
        : segments[3] == 'favorite'
        ? 'favorites'
        : 'likes';
    final id = kind == 'comments' ? segments[4] : segments[2];
    for (final entry in pages.entries.where(
      (entry) => entry.key.startsWith('$actor/$kind/'),
    )) {
      entry.value['items'] = (entry.value['items'] as List)
          .where((row) => (row as Map)['id'] != id)
          .toList();
    }
    return switch (kind) {
      'comments' => {'deleted': true},
      'favorites' => {'favorited': false},
      _ => {'liked': false},
    };
  }
}

Future<void> _signIn(SessionController session, UserSummary user) =>
    session.acceptSession(
      AuthSession(token: 'token-${user.id}', user: user, needsProfile: false),
    );

Future<({SessionController session, _ActivityApi api})> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  final api = _ActivityApi(session);
  await session.initialize(AuthRepository(api));
  await _signIn(session, _owner);
  addTearDown(session.dispose);
  addTearDown(api.dispose);
  return (session: session, api: api);
}

Future<GoRouter> _mount(
  WidgetTester tester,
  ({SessionController session, _ActivityApi api}) h,
  MyActivityKind kind, {
  double textScale = 1,
}) async {
  final router = GoRouter(
    initialLocation: '/activity',
    routes: [
      GoRoute(
        path: '/activity',
        builder: (_, _) =>
            MyActivityScreen(api: h.api, session: h.session, kind: kind),
      ),
      GoRoute(
        path: '/posts/:id',
        builder: (_, state) => Scaffold(
          appBar: AppBar(title: const Text('动态详情')),
          body: Text('详情 ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: WanpanTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await tester.pump();
  return router;
}

Future<void> _remove(
  WidgetTester tester,
  String id, {
  bool comment = false,
}) async {
  final button = find.byKey(Key('activity-remove-$id'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  if (comment) {
    await tester.pumpAndSettle();
    expect(find.text('删除这条评论？'), findsOneWidget);
    await tester.tap(find.text('确认删除'));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _more(WidgetTester tester) async {
  final more = find.byKey(const Key('activity-load-more'));
  await tester.ensureVisible(more);
  await tester.pumpAndSettle();
  await tester.tap(more);
  await tester.pump();
}

void main() {
  testWidgets('我的评论呈现发出的文字与父动态，点击进入对应动态', (tester) async {
    final h = await _setup();
    h.api.setPage('comments', [_comment('c')]);
    final router = await _mount(tester, h, MyActivityKind.comments);
    await tester.pumpAndSettle();
    expect(find.text('我的评论'), findsOneWidget);
    expect(find.text('我发出的评论 c'), findsOneWidget);
    expect(find.text('作者 parent-c 的动态'), findsOneWidget);
    expect(find.text('父动态 parent-c'), findsOneWidget);
    expect(h.api.reads.single, (
      userId: 'owner',
      path: '/users/me/comments',
      cursor: null,
      limit: 20,
    ));
    await tester.tap(find.text('我发出的评论 c'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/posts/parent-c');
  });

  for (final kind in [MyActivityKind.favorites, MyActivityKind.likes]) {
    testWidgets('${kind.name}展示真实作者和互动日期并可取消', (tester) async {
      final h = await _setup();
      h.api.setPage(kind.name, [_post('p')]);
      var notifications = 0;
      h.api.socialActivity.addListener(() => notifications++);
      await _mount(tester, h, kind);
      await tester.pumpAndSettle();
      expect(
        find.text(kind == MyActivityKind.favorites ? '我的收藏' : '我的点赞'),
        findsOneWidget,
      );
      expect(find.text('作者 p'), findsOneWidget);
      expect(find.text('2026.09.05'), findsOneWidget);
      expect(find.text('2025.08.01'), findsNothing);
      await _remove(tester, 'p');
      await tester.pumpAndSettle();
      expect(
        h.api.deletes.single.path,
        '/sends/p/${kind == MyActivityKind.favorites ? 'favorite' : 'like'}',
      );
      expect(find.text('父动态 p'), findsNothing);
      expect(notifications, 1, reason: '页面不能重复广播仓库已广播的变更');
      expect(h.api.reads.length, 2);
    });
  }

  testWidgets('复用真实视频封面组件显示收藏内容', (tester) async {
    const channel = MethodChannel('plugins.justsoft.xyz/video_thumbnail');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final h = await _setup();
    h.api.setPage('favorites', [
      {..._post('video'), 'video_url': 'https://example.com/activity.mp4'},
    ]);
    await _mount(tester, h, MyActivityKind.favorites);
    await tester.pumpAndSettle();
    expect(
      tester.widget<WanpanVideoCover>(find.byType(WanpanVideoCover)).url,
      'https://example.com/activity.mp4',
    );
  });

  testWidgets('删除自己的评论需要确认，取消不请求且成功后才移除', (tester) async {
    final h = await _setup();
    h.api.setPage('comments', [_comment('c')]);
    await _mount(tester, h, MyActivityKind.comments);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activity-remove-c')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(h.api.deletes, isEmpty);
    h.api.deleteGate = Completer<void>();
    await _remove(tester, 'c', comment: true);
    expect(find.text('我发出的评论 c'), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(const Key('activity-open-c'))).onTap,
      isNull,
    );
    h.api.deleteGate!.complete();
    await tester.pumpAndSettle();
    expect(h.api.deletes.single.path, '/sends/parent-c/comments/c');
    expect(find.text('我发出的评论 c'), findsNothing);
    expect(find.text('评论已删除'), findsOneWidget);
  });

  for (final kind in MyActivityKind.values) {
    for (final malformed in [false, true]) {
      testWidgets('${kind.name}${malformed ? '未确认成功' : '请求失败'}保留原记录', (
        tester,
      ) async {
        final h = await _setup();
        h.api.setPage(kind.name, [
          kind == MyActivityKind.comments ? _comment('item') : _post('item'),
        ]);
        h.api.failDelete = !malformed;
        h.api.malformedDelete = malformed;
        var notifications = 0;
        h.api.socialActivity.addListener(() => notifications++);
        await _mount(tester, h, kind);
        await tester.pumpAndSettle();
        await _remove(tester, 'item', comment: kind == MyActivityKind.comments);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('activity-open-item')), findsOneWidget);
        expect(find.textContaining('失败，请稍后重试'), findsOneWidget);
        expect(notifications, 0);
      });
    }
  }

  testWidgets('按游标加载更多，失败保留已有记录，重试不重复展示重叠项', (tester) async {
    final h = await _setup();
    h.api.setPage('likes', [_post('first')], next: 'next-page');
    h.api.setPage('likes', [
      _post('first'),
      _post('second'),
    ], cursor: 'next-page');
    h.api.failedPages.add(h.api.key('likes', cursor: 'next-page'));
    await _mount(tester, h, MyActivityKind.likes);
    await tester.pumpAndSettle();
    await _more(tester);
    await tester.pumpAndSettle();
    expect(find.text('父动态 first'), findsOneWidget);
    expect(find.text('后面的记录暂时没有加载出来'), findsOneWidget);
    h.api.failedPages.clear();
    await _more(tester);
    await tester.pumpAndSettle();
    expect(find.text('父动态 first'), findsOneWidget);
    expect(find.text('父动态 second'), findsOneWidget);
    expect(h.api.reads.last.cursor, 'next-page');
    expect(h.api.reads.last.limit, 20);
    expect(find.byKey(const Key('activity-load-more')), findsNothing);
  });

  testWidgets('刷新后迟到的下一页不能混入新列表', (tester) async {
    final h = await _setup();
    h.api.setPage('favorites', [_post('old')], next: 'old-page');
    h.api.setPage('favorites', [_post('old-more')], cursor: 'old-page');
    final gate = Completer<void>();
    h.api.readGates[h.api.key('favorites', cursor: 'old-page')] = gate;
    await _mount(tester, h, MyActivityKind.favorites);
    await tester.pumpAndSettle();
    await _more(tester);
    h.api.setPage('favorites', [_post('fresh')]);
    h.api.socialActivity.recordChanged(postId: 'fresh');
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('父动态 fresh'), findsOneWidget);
    expect(find.text('父动态 old-more'), findsNothing);
  });

  testWidgets('迟到刷新不能恢复已取消收藏，但以后重新收藏会正常出现', (tester) async {
    final h = await _setup();
    h.api.setPage('favorites', [_post('remove'), _post('keep')]);
    await _mount(tester, h, MyActivityKind.favorites);
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    h.api.readGates[h.api.key('favorites')] = gate;
    h.api.socialActivity.recordChanged(postId: 'remove');
    await tester.pump();
    await _remove(tester, 'remove');
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('父动态 remove'), findsNothing);
    expect(find.text('父动态 keep'), findsOneWidget);
    h.api.setPage('favorites', [_post('remove'), _post('keep')]);
    h.api.socialActivity.recordChanged(postId: 'remove');
    await tester.pumpAndSettle();
    expect(find.text('父动态 remove'), findsOneWidget);
  });

  testWidgets('取消成功后的刷新失败不误报操作失败', (tester) async {
    final h = await _setup();
    h.api.setPage('likes', [_post('remove'), _post('keep')]);
    await _mount(tester, h, MyActivityKind.likes);
    await tester.pumpAndSettle();
    h.api.failedPages.add(h.api.key('likes'));
    await _remove(tester, 'remove');
    await tester.pumpAndSettle();
    expect(find.text('父动态 remove'), findsNothing);
    expect(find.text('父动态 keep'), findsOneWidget);
    expect(find.text('已取消点赞'), findsOneWidget);
    expect(find.text('取消点赞失败，请稍后重试'), findsNothing);
    expect(find.text('刷新失败，仍保留已有记录'), findsOneWidget);
  });

  testWidgets('切换账号立即清空记录，旧请求不覆盖新账号', (tester) async {
    final h = await _setup();
    h.api.setPage('comments', [_comment('old')]);
    h.api.setPage('comments', [_comment('new')], user: 'other');
    await _mount(tester, h, MyActivityKind.comments);
    await tester.pumpAndSettle();
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    h.api.readGates[h.api.key('comments')] = oldGate;
    h.api.readGates[h.api.key('comments', user: 'other')] = newGate;
    h.api.socialActivity.recordChanged(postId: 'parent-old');
    await tester.pump();
    await _signIn(h.session, _other);
    await tester.pump();
    expect(find.text('我发出的评论 old'), findsNothing);
    newGate.complete();
    await tester.pumpAndSettle();
    oldGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('我发出的评论 new'), findsOneWidget);
    expect(find.text('我发出的评论 old'), findsNothing);
  });

  testWidgets('确认删除评论时退出登录不会发出旧账号删除请求', (tester) async {
    final h = await _setup();
    h.api.setPage('comments', [_comment('c')]);
    await _mount(tester, h, MyActivityKind.comments);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activity-remove-c')));
    await tester.pumpAndSettle();
    await h.session.signOut();
    await tester.pump();
    expect(find.text('我发出的评论 c'), findsNothing);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(h.api.deletes, isEmpty);
    expect(find.text('登录后查看我的评论'), findsOneWidget);
  });

  testWidgets('切换账号后旧取消请求成功不影响新账号内容', (tester) async {
    final h = await _setup();
    h.api.setPage('likes', [_post('old')]);
    h.api.setPage('likes', [_post('new')], user: 'other');
    h.api.deleteGate = Completer<void>();
    await _mount(tester, h, MyActivityKind.likes);
    await tester.pumpAndSettle();
    await _remove(tester, 'old');
    await _signIn(h.session, _other);
    await tester.pumpAndSettle();
    h.api.deleteGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('父动态 new'), findsOneWidget);
    expect(find.text('父动态 old'), findsNothing);
    expect(find.text('已取消点赞'), findsNothing);
  });

  testWidgets('初次加载失败可重试，空列表收到更新后展示记录', (tester) async {
    final h = await _setup();
    h.api.failedPages.add(h.api.key('favorites'));
    await _mount(tester, h, MyActivityKind.favorites);
    await tester.pumpAndSettle();
    expect(find.text('记录暂时没有加载出来'), findsOneWidget);
    h.api.failedPages.clear();
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('还没有收藏动态'), findsOneWidget);
    h.api.setPage('favorites', [_post('new')]);
    h.api.socialActivity.recordChanged(postId: 'new');
    await tester.pumpAndSettle();
    expect(find.text('父动态 new'), findsOneWidget);
  });

  testWidgets('岩友或拉黑关系变化立即移除缓存，刷新失败也不展示旧内容', (tester) async {
    final h = await _setup();
    h.api.setPage('comments', [_comment('private')], next: 'older-comments');
    await _mount(tester, h, MyActivityKind.comments);
    await tester.pumpAndSettle();
    h.api.failedPages.add(h.api.key('comments'));
    h.api.socialActivity.recordChanged();
    await tester.pump();
    expect(find.text('我发出的评论 private'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('父动态 parent-private'), findsNothing);
    expect(find.byKey(const Key('activity-load-more')), findsNothing);
    expect(find.text('记录暂时没有加载出来'), findsOneWidget);
  });

  testWidgets('父动态被删除时立即移除关联评论，即使刷新失败也不恢复', (tester) async {
    final h = await _setup();
    h.api.setPage('comments', [_comment('gone'), _comment('keep')]);
    await _mount(tester, h, MyActivityKind.comments);
    await tester.pumpAndSettle();
    h.api.failedPages.add(h.api.key('comments'));
    h.api.socialActivity.recordChanged(postId: 'parent-gone', deleted: true);
    await tester.pumpAndSettle();
    expect(find.text('我发出的评论 gone'), findsNothing);
    expect(find.text('我发出的评论 keep'), findsOneWidget);
    expect(find.text('刷新失败，仍保留已有记录'), findsOneWidget);
  });

  testWidgets('320px大字号评论与父动态长文本不会挤出操作按钮', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final h = await _setup();
    h.api.setPage('comments', [
      {
        ..._comment('long'),
        'content': '和岩友认真讨论每一次完攀的动作。' * 10,
        'post': {..._post('long-parent'), 'nickname': '每个周末都在认真攀爬的岩友小熊'},
      },
    ]);
    await _mount(tester, h, MyActivityKind.comments, textScale: 1.35);
    await tester.pumpAndSettle();
    final action = find.byKey(const Key('activity-remove-long'));
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getSize(action).shortestSide, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('确认删除').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final kind in MyActivityKind.values) {
    testWidgets('真实${kind.name}路由先登录再返回正确互动列表', (tester) async {
      final h = await _setup();
      await h.session.signOut();
      final router = createWanpanRouter(
        api: h.api,
        session: h.session,
        authRepository: AuthRepository(h.api),
        nativeAuth: NativeAuthService(),
      );
      addTearDown(router.dispose);
      router.go('/profile/${kind.name}');
      await tester.pumpWidget(
        MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/login');
      expect(router.state.uri.queryParameters['from'], '/profile/${kind.name}');
      expect(h.api.reads, isEmpty);
      await _signIn(h.session, _owner);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/profile/${kind.name}');
      expect(
        tester.widget<MyActivityScreen>(find.byType(MyActivityScreen)).kind,
        kind,
      );
      expect(h.api.reads.single.path, '/users/me/${kind.name}');
    });
  }
}
