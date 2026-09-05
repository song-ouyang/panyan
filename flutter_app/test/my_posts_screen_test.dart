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
import 'package:wanpan_diary/features/profile/my_posts_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_video_cover.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);
const _owner = UserSummary(id: 'owner', nickname: '我的账号', role: 'user');
const _other = UserSummary(id: 'other', nickname: '另一个账号', role: 'user');

Map<String, dynamic> _post(
  String id, {
  String? caption,
  bool checkin = false,
  String visibility = 'public',
  String status = 'approved',
  bool media = false,
}) => {
  'id': id,
  'caption': caption ?? '我的动态 $id',
  'attempts': 3,
  'visibility': visibility,
  'moderation_status': status,
  'image_urls': media ? ['https://example.com/photo.jpg'] : <String>[],
  'video_url': media ? 'https://example.com/climb.mp4' : null,
  'sent_at': '2026-09-05T08:30:00Z',
  if (checkin) ...{
    'route_id': 'route-$id',
    'route_name': '很喜欢的一条线路',
    'grade': 'V3',
    'gym_name': '测试岩馆',
  },
};

class _MyPostsApi extends ApiClient {
  _MyPostsApi(this.session)
    : super(config: _config, accessTokenProvider: () => session.token);

  final SessionController session;
  final postsByUser = <String, List<Map<String, dynamic>>>{};
  final reads = <String?>[];
  final deletes = <({String? userId, String path})>[];
  final readBarriers = <Completer<void>>[];
  Completer<void>? deleteBarrier;
  bool failReads = false;
  bool failDelete = false;
  bool keepStaleRows = false;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/users/me') {
      return {...session.user!.toJson(), 'stats': <String, int>{}};
    }
    if (path != '/users/me/sends') throw StateError('Unexpected GET $path');
    final userId = session.user?.id;
    reads.add(userId);
    final response = (postsByUser[userId] ?? [])
        .map(Map<String, dynamic>.from)
        .toList();
    final shouldFail = failReads;
    if (readBarriers.isNotEmpty) await readBarriers.removeAt(0).future;
    if (shouldFail) throw StateError('List request failed');
    return {'items': response};
  }

  @override
  Future<Map<String, dynamic>> deleteJson(String path, {Object? data}) async {
    final userId = session.user?.id;
    deletes.add((userId: userId, path: path));
    await deleteBarrier?.future;
    if (failDelete) throw StateError('Deletion failed');
    if (!keepStaleRows) {
      postsByUser[userId]?.removeWhere(
        (post) => path == '/sends/${post['id']}',
      );
    }
    return {'deleted': true};
  }
}

Future<({SessionController session, _MyPostsApi api})> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  final api = _MyPostsApi(session);
  await session.initialize(AuthRepository(api));
  await _signIn(session, _owner);
  addTearDown(session.dispose);
  addTearDown(api.dispose);
  return (session: session, api: api);
}

Future<void> _signIn(SessionController session, UserSummary user) =>
    session.acceptSession(
      AuthSession(token: 'token-${user.id}', user: user, needsProfile: false),
    );

Future<GoRouter> _mount(
  WidgetTester tester,
  ({SessionController session, _MyPostsApi api}) harness, {
  double textScale = 1,
}) async {
  final router = GoRouter(
    initialLocation: '/profile/posts',
    routes: [
      GoRoute(
        path: '/profile/posts',
        builder: (_, _) =>
            MyPostsScreen(api: harness.api, session: harness.session),
      ),
      GoRoute(
        path: '/posts/:id',
        builder: (_, state) => Scaffold(
          appBar: AppBar(title: const Text('动态详情')),
          body: Text('查看 ${state.pathParameters['id']}'),
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

Future<void> _openDelete(WidgetTester tester, String id) async {
  await tester.ensureVisible(find.byKey(Key('delete-my-post-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('delete-my-post-$id')));
  await tester.pumpAndSettle();
  expect(find.text('删除这条动态？'), findsOneWidget);
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.text('确认删除'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('显示自己的私密与未公开内容、线路成绩及真实媒体，点击可进入详情', (tester) async {
    const videoChannel = MethodChannel('plugins.justsoft.xyz/video_thumbnail');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      videoChannel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        videoChannel,
        null,
      ),
    );
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [
      _post(
        'private',
        visibility: 'private',
        status: 'rejected',
        checkin: true,
        media: true,
      ),
    ];
    final router = await _mount(tester, harness);
    await tester.pumpAndSettle();
    expect(find.text('我的动态'), findsOneWidget);
    expect(find.text('仅自己'), findsOneWidget);
    expect(find.text('未公开'), findsOneWidget);
    expect(find.text('尝试 3 次'), findsOneWidget);
    expect(find.text('V3 · 很喜欢的一条线路'), findsOneWidget);
    expect(find.text('测试岩馆'), findsOneWidget);
    expect(
      tester.widget<WanpanVideoCover>(find.byType(WanpanVideoCover)).url,
      'https://example.com/climb.mp4',
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is ResizeImage,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('我的动态 private'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/posts/private');
    expect(find.text('查看 private'), findsOneWidget);
  });

  testWidgets('取消删除不发请求，打卡删除确认说明日历成绩变化与线路保留', (tester) async {
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [_post('checkin', checkin: true)];
    await _mount(tester, harness);
    await tester.pumpAndSettle();
    await _openDelete(tester, 'checkin');
    expect(find.textContaining('线路仍会保留'), findsOneWidget);
    expect(find.textContaining('攀岩日历和成绩统计'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(harness.api.deletes, isEmpty);
    expect(find.text('我的动态 checkin'), findsOneWidget);
  });

  testWidgets('删除失败仍保留内容且不发送刷新通知', (tester) async {
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [_post('failed')];
    harness.api.failDelete = true;
    var refreshes = 0;
    harness.api.climbingActivity.addListener(() => refreshes++);
    await _mount(tester, harness);
    await tester.pumpAndSettle();
    await _openDelete(tester, 'failed');
    await _confirmDelete(tester);
    await tester.pumpAndSettle();
    expect(find.text('我的动态 failed'), findsOneWidget);
    expect(find.text('删除失败，请稍后重试'), findsOneWidget);
    expect(find.text('动态已删除'), findsNothing);
    expect(refreshes, 0);
  });

  testWidgets('服务端确认删除前不隐藏内容，成功后不会被旧列表恢复且只通知一次', (tester) async {
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [_post('deleted'), _post('keep')];
    harness.api.keepStaleRows = true;
    harness.api.deleteBarrier = Completer<void>();
    var refreshes = 0;
    harness.api.climbingActivity.addListener(() => refreshes++);
    await _mount(tester, harness);
    await tester.pumpAndSettle();
    await _openDelete(tester, 'deleted');
    await _confirmDelete(tester);
    expect(find.text('我的动态 deleted'), findsOneWidget);
    expect(harness.api.deletes, [(userId: 'owner', path: '/sends/deleted')]);
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('open-my-post-deleted')))
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('delete-my-post-keep')))
          .onPressed,
      isNull,
    );
    harness.api.deleteBarrier!.complete();
    await tester.pumpAndSettle();
    expect(find.text('我的动态 deleted'), findsNothing);
    expect(find.text('我的动态 keep'), findsOneWidget);
    expect(find.text('动态已删除'), findsOneWidget);
    expect(refreshes, 1);
    harness.api.climbingActivity.recordChanged();
    await tester.pumpAndSettle();
    expect(find.text('我的动态 deleted'), findsNothing);
  });

  testWidgets('删除成功后的刷新失败不误报删除失败', (tester) async {
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [_post('deleted'), _post('keep')];
    await _mount(tester, harness);
    await tester.pumpAndSettle();
    await _openDelete(tester, 'deleted');
    harness.api.failReads = true;
    await _confirmDelete(tester);
    await tester.pumpAndSettle();
    expect(find.text('我的动态 deleted'), findsNothing);
    expect(find.text('我的动态 keep'), findsOneWidget);
    expect(find.text('动态已删除'), findsOneWidget);
    expect(find.text('删除失败，请稍后重试'), findsNothing);
    expect(find.text('刷新失败，仍保留已有动态'), findsOneWidget);
  });

  testWidgets('账号切换立即清空私密内容，旧请求不能覆盖新账号的列表', (tester) async {
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [
      _post('private', visibility: 'private'),
    ];
    harness.api.postsByUser['other'] = [_post('other')];
    await _mount(tester, harness);
    await tester.pumpAndSettle();
    final oldRead = Completer<void>();
    harness.api.readBarriers.add(oldRead);
    harness.api.climbingActivity.recordChanged();
    await tester.pump();
    final newRead = Completer<void>();
    harness.api.readBarriers.add(newRead);
    await _signIn(harness.session, _other);
    await tester.pump();
    expect(find.text('我的动态 private'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    newRead.complete();
    await tester.pumpAndSettle();
    expect(find.text('我的动态 other'), findsOneWidget);
    oldRead.complete();
    await tester.pumpAndSettle();
    expect(find.text('我的动态 private'), findsNothing);
    expect(find.text('我的动态 other'), findsOneWidget);
  });

  testWidgets('退出登录后立即移除本人内容且迟到的响应不能重新显示', (tester) async {
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [
      _post('private', visibility: 'private'),
    ];
    await _mount(tester, harness);
    await tester.pumpAndSettle();
    final oldRead = Completer<void>();
    harness.api.readBarriers.add(oldRead);
    harness.api.climbingActivity.recordChanged();
    await tester.pump();
    await harness.session.signOut();
    await tester.pump();
    expect(find.text('我的动态 private'), findsNothing);
    expect(find.text('登录后查看自己的动态'), findsOneWidget);
    oldRead.complete();
    await tester.pumpAndSettle();
    expect(find.text('我的动态 private'), findsNothing);
    expect(harness.api.reads.where((id) => id == null), isEmpty);
  });

  testWidgets('确认框打开期间切换账号不会用新账号执行旧删除', (tester) async {
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [_post('old')];
    harness.api.postsByUser['other'] = [_post('new')];
    await _mount(tester, harness);
    await tester.pumpAndSettle();
    await _openDelete(tester, 'old');
    await _signIn(harness.session, _other);
    await tester.pump();
    await _confirmDelete(tester);
    await tester.pumpAndSettle();
    expect(harness.api.deletes, isEmpty);
    expect(find.text('我的动态 old'), findsNothing);
    expect(find.text('我的动态 new'), findsOneWidget);
  });

  testWidgets('旧账号的删除结果不会清除新账号内容或显示成功提示', (tester) async {
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [_post('old')];
    harness.api.postsByUser['other'] = [_post('new')];
    harness.api.deleteBarrier = Completer<void>();
    await _mount(tester, harness);
    await tester.pumpAndSettle();
    await _openDelete(tester, 'old');
    await _confirmDelete(tester);
    await _signIn(harness.session, _other);
    await tester.pumpAndSettle();
    harness.api.deleteBarrier!.complete();
    await tester.pumpAndSettle();
    expect(find.text('我的动态 new'), findsOneWidget);
    expect(find.text('我的动态 old'), findsNothing);
    expect(find.text('动态已删除'), findsNothing);
  });

  testWidgets('初次加载失败可重试，空列表收到通知后显示新发布内容', (tester) async {
    final harness = await _setup();
    harness.api.failReads = true;
    await _mount(tester, harness);
    await tester.pumpAndSettle();
    expect(find.text('动态暂时没有加载出来'), findsOneWidget);
    harness.api.failReads = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('还没有发布动态'), findsOneWidget);
    harness.api.postsByUser['owner'] = [_post('fresh')];
    harness.api.climbingActivity.recordChanged();
    await tester.pumpAndSettle();
    expect(find.text('我的动态 fresh'), findsOneWidget);
    expect(find.text('还没有发布动态'), findsNothing);
  });

  testWidgets('320px大字号长内容仍可查看和删除且无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = await _setup();
    harness.api.postsByUser['owner'] = [
      _post(
        'long',
        checkin: true,
        caption: '和岩友一起认真攀爬非常非常喜欢的线路，记录这次的每一点进步。' * 5,
      ),
    ];
    await _mount(tester, harness, textScale: 1.35);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final button = find.byKey(const Key('delete-my-post-long'));
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(44));
    await _openDelete(tester, 'long');
    expect(find.text('确认删除').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实路由保护我的动态并在登录后返回管理页', (tester) async {
    final harness = await _setup();
    await harness.session.signOut();
    final router = createWanpanRouter(
      api: harness.api,
      session: harness.session,
      authRepository: AuthRepository(harness.api),
      nativeAuth: NativeAuthService(),
    );
    addTearDown(router.dispose);
    router.go('/profile/posts');
    await tester.pumpWidget(
      MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/login');
    expect(router.state.uri.queryParameters['from'], '/profile/posts');
    expect(harness.api.reads, isEmpty);
    await _signIn(harness.session, _owner);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/profile/posts');
    expect(find.byType(MyPostsScreen), findsOneWidget);
    expect(find.text('还没有发布动态'), findsOneWidget);
  });
}
