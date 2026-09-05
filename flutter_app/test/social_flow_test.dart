import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/profile_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/feed/feed_screen.dart';
import 'package:wanpan_diary/features/feed/post_screen.dart';
import 'package:wanpan_diary/features/profile/friends_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

const _currentUser = UserSummary(
  id: 'me',
  nickname: '小欧',
  role: 'user',
  profileCompleted: true,
);

Map<String, dynamic> _post({
  required String id,
  required String caption,
  String visibility = 'public',
}) => {
  'id': id,
  'user_id': 'author-1',
  'nickname': '橙线岩友',
  'attempts': 1,
  'image_urls': <String>[],
  'caption': caption,
  'visibility': visibility,
  'moderation_status': 'approved',
  'like_count': 2,
  'comment_count': 0,
  'liked': false,
  'comments': <Object>[],
  'sent_at': '2026-08-30T08:00:00.000Z',
};

class _SocialApiClient extends ApiClient {
  _SocialApiClient()
    : super(config: _config, accessTokenProvider: () => 'secure-token');

  final List<String> calls = [];
  bool friendAccepted = false;
  bool liked = false;
  final List<Map<String, dynamic>> comments = [];
  String commentModerationStatus = 'approved';
  bool failComment = false;
  bool failDetailRefresh = false;
  bool omitCommentAuthorInPost = false;
  Completer<void>? detailRefreshBarrier;
  String? Function()? viewerIdProvider;
  int detailReads = 0;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('GET $path ${queryParameters ?? const {}}');
    if (path == '/sends/feed') {
      final friends = queryParameters?['scope'] == 'friends';
      return {
        'items': [
          _post(
            id: friends ? 'friends-post' : 'square-post',
            caption: friends
                ? friendAccepted
                      ? '新岩友的朋友圈动态'
                      : '朋友圈动态'
                : '广场动态',
            visibility: friends ? 'friends' : 'public',
          ),
        ],
      };
    }
    if (path == '/sends/post-1') {
      detailReads++;
      final viewerId = viewerIdProvider == null
          ? _currentUser.id
          : viewerIdProvider!();
      // Freeze this request's response before a delay: an old read must not
      // acquire a comment posted later just because the network was slow.
      final response = <String, dynamic>{
        ..._post(id: 'post-1', caption: '详情动态'),
        'liked': liked,
        'like_count': liked ? 3 : 2,
        'comment_count': comments
            .where((comment) => comment['moderation_status'] == 'approved')
            .length,
        'comments': comments
            .where(
              (comment) =>
                  comment['moderation_status'] == 'approved' ||
                  (comment['moderation_status'] == 'pending' &&
                      comment['user_id'] == viewerId),
            )
            .map(Map<String, dynamic>.from)
            .toList(),
      };
      if (detailReads > 1) {
        await detailRefreshBarrier?.future;
        if (failDetailRefresh) throw StateError('Detail refresh unavailable');
      }
      return response;
    }
    if (path == '/users/me/friends') {
      return {
        'items': friendAccepted
            ? [
                {
                  'id': 'incoming',
                  'nickname': '待接受岩友',
                  'friendship': 'accepted',
                },
              ]
            : <Object>[],
      };
    }
    if (path == '/users/me/friend-requests') {
      return {
        'items': friendAccepted
            ? <Object>[]
            : [
                {
                  'id': 'incoming',
                  'nickname': '待接受岩友',
                  'created_at': '2026-08-30T08:00:00.000Z',
                  'friendship': 'received',
                },
              ],
      };
    }
    if (path == '/users/search') {
      return {
        'items': [
          {
            'id': 'search-user',
            'nickname': '新岩友',
            'bio': '喜欢橙色动态线',
            'friendship': 'none',
          },
        ],
      };
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('POST $path ${data ?? const {}}');
    if (path == '/users/incoming/friend-accept') {
      friendAccepted = true;
      return {'status': 'accepted'};
    }
    if (path == '/users/search-user/friend-request') {
      return {'status': 'pending'};
    }
    if (path == '/sends/post-1/like') {
      liked = true;
      return {'liked': true};
    }
    if (path == '/sends/post-1/comments') {
      if (failComment) throw StateError('Comment was not saved');
      final comment = <String, dynamic>{
        'id': 'comment-${comments.length + 1}',
        'content': (data as Map<String, dynamic>)['content'],
        'user_id': _currentUser.id,
        'nickname': _currentUser.nickname,
        'avatar_url': _currentUser.avatarUrl,
        'created_at': '2026-09-05T08:00:00.000Z',
        'moderation_status': commentModerationStatus,
      };
      comments.add(comment);
      return {...comment}..removeWhere(
        (key, _) =>
            omitCommentAuthorInPost &&
            (key == 'nickname' || key == 'avatar_url'),
      );
    }
    if (path == '/reports') return {'reported': true};
    throw StateError('Unexpected POST $path');
  }
}

Future<SessionController> _signedInSession() async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  await session.acceptSession(
    const AuthSession(
      token: 'secure-token',
      user: _currentUser,
      needsProfile: false,
    ),
  );
  return session;
}

Future<SessionController> _guestSession() async {
  SharedPreferences.setMockInitialValues({});
  return SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
}

Future<void> _pumpPost(
  WidgetTester tester,
  _SocialApiClient api,
  SessionController session,
) async {
  api.viewerIdProvider = () =>
      session.isAuthenticated ? session.user?.id : null;
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(api.dispose);
  addTearDown(session.dispose);
  addTearDown(() {
    final barrier = api.detailRefreshBarrier;
    if (barrier != null && !barrier.isCompleted) barrier.complete();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      home: PostScreen(api: api, session: session, postId: 'post-1'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitComment(WidgetTester tester, String content) async {
  await tester.enterText(find.byType(TextField), content);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  // The POST can complete while the follow-up GET is still pending.
  await tester.pump();
}

Future<void> _refreshPost(WidgetTester tester) async {
  await tester
      .widget<RefreshIndicator>(find.byType(RefreshIndicator))
      .onRefresh();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('游客可以浏览广场公开动态', (tester) async {
    final api = _SocialApiClient();
    final session = await _guestSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: FeedScreen(api: api, session: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('广场动态'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(
      api.calls.any(
        (call) => call.contains('GET /sends/feed') && call.contains('square'),
      ),
      isTrue,
    );
  });

  testWidgets('广场和朋友圈切换使用各自数据源', (tester) async {
    final api = _SocialApiClient();
    final session = await _signedInSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: FeedScreen(api: api, session: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('广场动态'), findsOneWidget);
    await tester.tap(find.text('朋友圈'));
    await tester.pumpAndSettle();

    expect(find.text('朋友圈动态'), findsOneWidget);
    expect(
      api.calls.any(
        (call) => call.contains('GET /sends/feed') && call.contains('friends'),
      ),
      isTrue,
    );
  });

  testWidgets('在其他页面接受岩友申请后，保留的朋友圈页面自动刷新', (tester) async {
    final api = _SocialApiClient();
    final session = await _signedInSession();
    final feedVisible = ValueNotifier(true);
    addTearDown(api.dispose);
    addTearDown(session.dispose);
    addTearDown(feedVisible.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: ValueListenableBuilder<bool>(
          valueListenable: feedVisible,
          child: FeedScreen(api: api, session: session),
          builder: (_, visible, child) => TickerMode(
            enabled: visible,
            child: Offstage(offstage: !visible, child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('朋友圈'));
    await tester.pumpAndSettle();
    expect(find.text('朋友圈动态'), findsOneWidget);
    final retainedFeed = tester.state(find.byType(FeedScreen));
    final friendsRequestsBefore = api.calls
        .where(
          (call) =>
              call.startsWith('GET /sends/feed') && call.contains('friends'),
        )
        .length;

    // StatefulShell keeps a previous tab mounted while another tab is visible.
    feedVisible.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(FeedScreen), findsNothing);
    await ProfileRepository(api).acceptFriendRequest('incoming');
    await tester.pumpAndSettle();
    expect(
      api.calls
          .where(
            (call) =>
                call.startsWith('GET /sends/feed') && call.contains('friends'),
          )
          .length,
      friendsRequestsBefore + 1,
    );

    feedVisible.value = true;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(FeedScreen)), same(retainedFeed));
    expect(find.text('新岩友的朋友圈动态'), findsOneWidget);
    expect(find.text('朋友圈动态'), findsNothing);
    expect(find.text('广场动态'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('动态详情可以点赞并提交评论', (tester) async {
    final api = _SocialApiClient();
    final session = await _signedInSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: PostScreen(api: api, session: session, postId: 'post-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    expect(api.calls, contains('POST /sends/post-1/like {}'));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField), '一起去刷这条线');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(
      api.calls.any(
        (call) =>
            call.contains('POST /sends/post-1/comments') &&
            call.contains('一起去刷这条线'),
      ),
      isTrue,
    );
    expect(find.text('评论已提交'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('一起去刷这条线'), findsOneWidget);
    expect(find.text(_currentUser.nickname), findsOneWidget);
    expect(find.textContaining('审核中'), findsNothing);
    expect(find.text('还没有评论，来聊聊这条线路吧。'), findsNothing);

    await _refreshPost(tester);
    expect(find.text('一起去刷这条线'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('待审核评论提交后立即显示，刷新和重开页面后仍只显示一条', (tester) async {
    final barrier = Completer<void>();
    final api = _SocialApiClient()
      ..commentModerationStatus = 'pending'
      ..detailRefreshBarrier = barrier;
    final session = await _signedInSession();
    await _pumpPost(tester, api, session);
    const content = '这条线的脚点选择很有意思';

    await _submitComment(tester, content);

    expect(api.comments, hasLength(1));
    expect(api.detailReads, greaterThan(1));
    expect(barrier.isCompleted, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text(content), findsOneWidget);
    expect(find.text(_currentUser.nickname), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);
    expect(find.text('评论已提交，审核后其他岩友可见'), findsOneWidget);
    expect(find.text('评论失败，请稍后重试'), findsNothing);

    barrier.complete();
    await tester.pumpAndSettle();
    expect(find.text(content), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);
    final reads = api.detailReads;
    await _refreshPost(tester);
    expect(api.detailReads, reads + 1);
    expect(find.text(content), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);

    // Recreate the screen so visibility cannot depend only on a local insertion.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: PostScreen(api: api, session: session, postId: 'post-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(content), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);
    expect(
      api.calls.where((call) => call.startsWith('POST /sends/post-1/comments')),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('退出账号后立即移除本人待审核评论，游客重载只显示公开评论', (tester) async {
    final api = _SocialApiClient()..commentModerationStatus = 'pending';
    api.comments.add({
      'id': 'public-comment',
      'content': '大家都能看到的已审核评论',
      'user_id': 'another-climber',
      'nickname': '另一位岩友',
      'created_at': '2026-09-05T07:00:00.000Z',
      'moderation_status': 'approved',
    });
    final session = await _signedInSession();
    await _pumpPost(tester, api, session);
    const pendingContent = '这是我尚未审核的评论';
    await _submitComment(tester, pendingContent);
    await tester.pumpAndSettle();
    expect(find.text(pendingContent), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);

    final guestResponse = Completer<void>();
    api.detailRefreshBarrier = guestResponse;
    final reads = api.detailReads;
    await session.signOut();
    await tester.pump();

    expect(session.isAuthenticated, isFalse);
    expect(api.detailReads, reads + 1);
    expect(guestResponse.isCompleted, isFalse);
    // Do not wait for the guest response or an exit animation to hide data
    // which belongs only to the previous authenticated viewer.
    expect(find.text(pendingContent), findsNothing);
    expect(find.textContaining('审核中'), findsNothing);

    guestResponse.complete();
    await tester.pumpAndSettle();
    expect(find.text('大家都能看到的已审核评论'), findsOneWidget);
    expect(find.text(pendingContent), findsNothing);
    expect(find.textContaining('审核中'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('评论提交前发起的慢详情响应不能覆盖已成功显示的新评论', (tester) async {
    final api = _SocialApiClient()..commentModerationStatus = 'pending';
    final session = await _signedInSession();
    await _pumpPost(tester, api, session);
    final staleResponse = Completer<void>();
    addTearDown(() {
      if (!staleResponse.isCompleted) staleResponse.complete();
    });
    api.detailRefreshBarrier = staleResponse;
    final oldRefresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    expect(api.detailReads, 2);
    expect(api.comments, isEmpty);

    api.detailRefreshBarrier = null;
    const content = '在旧请求之后成功保存的新评论';
    await _submitComment(tester, content);
    await tester.pumpAndSettle();
    expect(api.detailReads, 3);
    expect(find.text(content), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);

    staleResponse.complete();
    await oldRefresh;
    await tester.pumpAndSettle();
    expect(find.text(content), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);
    expect(find.text('还没有评论，来聊聊这条线路吧。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('评论已保存但详情刷新失败时保留评论，不误报提交失败', (tester) async {
    final api = _SocialApiClient()
      ..commentModerationStatus = 'pending'
      ..failDetailRefresh = true;
    final session = await _signedInSession();
    await _pumpPost(tester, api, session);
    const content = '下次一起试试这条线';

    await _submitComment(tester, content);
    await tester.pumpAndSettle();

    expect(api.detailReads, greaterThan(1));
    expect(api.comments, hasLength(1));
    expect(find.text('详情动态'), findsOneWidget);
    expect(find.text(content), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('评论已提交，暂时无法刷新动态'), findsOneWidget);
    expect(find.text('评论失败，请稍后重试'), findsNothing);
    expect(find.text('这条动态暂时无法打开'), findsNothing);

    api.failDetailRefresh = false;
    await _refreshPost(tester);
    expect(find.text(content), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);
    expect(
      api.calls.where((call) => call.startsWith('POST /sends/post-1/comments')),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('兼容旧评论回包缺昵称时使用当前作者资料并立即展示', (tester) async {
    final barrier = Completer<void>();
    final api = _SocialApiClient()
      ..commentModerationStatus = 'pending'
      ..omitCommentAuthorInPost = true
      ..detailRefreshBarrier = barrier;
    final session = await _signedInSession();
    await _pumpPost(tester, api, session);
    const content = '这个动作很漂亮';

    await _submitComment(tester, content);
    expect(barrier.isCompleted, isFalse);
    expect(find.text(content), findsOneWidget);
    expect(find.text(_currentUser.nickname), findsOneWidget);
    expect(find.textContaining('审核中'), findsOneWidget);
    expect(find.text('评论失败，请稍后重试'), findsNothing);

    barrier.complete();
    await tester.pumpAndSettle();
    expect(find.text(content), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('评论提交真正失败时保留输入，不把未保存内容加进评论列表', (tester) async {
    final api = _SocialApiClient()..failComment = true;
    final session = await _signedInSession();
    await _pumpPost(tester, api, session);
    const content = '网络恢复后再提交这条评论';

    await _submitComment(tester, content);
    await tester.pumpAndSettle();
    expect(api.comments, isEmpty);
    expect(api.detailReads, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      content,
    );
    expect(find.text('评论失败，请稍后重试'), findsOneWidget);
    expect(find.text('还没有评论，来聊聊这条线路吧。'), findsOneWidget);
    expect(find.textContaining('审核中'), findsNothing);

    api.failComment = false;
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(api.comments, hasLength(1));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text(content), findsOneWidget);
    expect(find.text('评论已提交'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('游客在动态点赞或评论会跳转登录并保留返回地址', (tester) async {
    final api = _SocialApiClient();
    final session = await _guestSession();
    addTearDown(session.dispose);
    Uri? shownLoginUri;
    final router = GoRouter(
      initialLocation: '/posts/post-1',
      routes: [
        GoRoute(
          path: '/posts/:postId',
          builder: (context, state) => PostScreen(
            api: api,
            session: session,
            postId: state.pathParameters['postId']!,
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) {
            shownLoginUri = state.uri;
            return const Scaffold(body: Text('登录页'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();

    expect(find.text('登录页'), findsOneWidget);
    expect(shownLoginUri?.path, '/login');
    expect(shownLoginUri?.queryParameters['from'], '/posts/post-1');
    expect(api.calls.where((call) => call.contains('/like')), isEmpty);

    router.go('/posts/post-1');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '登录后再聊');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(find.text('登录页'), findsOneWidget);
    expect(shownLoginUri?.path, '/login');
    expect(shownLoginUri?.queryParameters['from'], '/posts/post-1');
    expect(api.calls.where((call) => call.contains('/comments')), isEmpty);
  });

  testWidgets('动态详情可见地提供举报入口并提交原因', (tester) async {
    final api = _SocialApiClient();
    final session = await _signedInSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: PostScreen(api: api, session: session, postId: 'post-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('动态安全操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('举报动态'));
    await tester.pumpAndSettle();
    expect(find.text('选择最符合的原因，我们会尽快核实处理。对方不会知道是你提交的。'), findsOneWidget);

    await tester.tap(find.text('垃圾广告'));
    await tester.pumpAndSettle();

    expect(
      api.calls.any(
        (call) =>
            call.contains('POST /reports') &&
            call.contains('targetType: send') &&
            call.contains('reason: spam'),
      ),
      isTrue,
    );
    expect(find.text('举报已提交，我们会尽快处理'), findsOneWidget);
  });

  testWidgets('岩友申请可接受，也可搜索并发送新申请', (tester) async {
    final api = _SocialApiClient();

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: FriendsScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('待接受岩友'), findsOneWidget);
    await tester.tap(find.text('接受'));
    await tester.pumpAndSettle();
    expect(api.friendAccepted, isTrue);
    expect(find.text('已经成为岩友啦'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '新岩友');
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pumpAndSettle();
    expect(find.text('新岩友'), findsNWidgets(2));

    await tester.tap(find.text('加岩友'));
    await tester.pumpAndSettle();
    expect(
      api.calls.any(
        (call) => call.startsWith('POST /users/search-user/friend-request'),
      ),
      isTrue,
    );
    expect(find.text('待确认'), findsOneWidget);
  });
}
