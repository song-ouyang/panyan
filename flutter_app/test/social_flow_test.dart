import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
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
            caption: friends ? '朋友圈动态' : '广场动态',
            visibility: friends ? 'friends' : 'public',
          ),
        ],
      };
    }
    if (path == '/sends/post-1') return _post(id: 'post-1', caption: '详情动态');
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
    if (path == '/sends/post-1/like') return {'liked': true};
    if (path == '/sends/post-1/comments') {
      return {
        'id': 'comment-1',
        'content': (data as Map<String, dynamic>)['content'],
      };
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
