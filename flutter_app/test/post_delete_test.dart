import 'dart:async';

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
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);
const _caption = '这条动态由我管理';

AuthSession _account(String id) => AuthSession(
  token: 'token-$id',
  user: UserSummary(id: id, nickname: '岩友$id', profileCompleted: true),
  needsProfile: false,
);

class _DeleteApi extends ApiClient {
  _DeleteApi()
    : super(config: _config, accessTokenProvider: () => 'test-token');

  String authorId = 'me';
  bool deleted = false;
  bool failDelete = false;
  Map<String, dynamic> deleteResponse = {'deleted': true};
  Completer<void>? deleteBarrier;
  Completer<void>? nextFeedBarrier;
  final deleteCalls = <String>[];
  int feedReads = 0;

  Map<String, dynamic> get post => {
    'id': 'post-1',
    'user_id': authorId,
    'nickname': '岩友$authorId',
    'caption': _caption,
    'image_urls': <String>[],
    'visibility': 'public',
    'moderation_status': 'approved',
    'sent_at': '2026-09-05T08:00:00.000Z',
    'like_count': 0,
    'comment_count': 0,
    'comments': <Object>[],
  };

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/sends/feed') {
      feedReads++;
      // Keep a real snapshot: a delayed response still contains the post that
      // existed when this read started, even if a later DELETE succeeds first.
      final response = <String, dynamic>{
        'items': [if (!deleted) post],
      };
      final barrier = nextFeedBarrier;
      nextFeedBarrier = null;
      await barrier?.future;
      return response;
    }
    if (path == '/sends/post-1') return post;
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Map<String, dynamic>> deleteJson(String path, {Object? data}) async {
    deleteCalls.add(path);
    await deleteBarrier?.future;
    if (failDelete) throw StateError('DELETE failed');
    if (deleteResponse['deleted'] == true) deleted = true;
    return deleteResponse;
  }
}

enum _View { feed, detail, directDetail }

class _Harness {
  _Harness(this.api, this.session, this.router) {
    api.climbingActivity.addListener(() => climbingEvents++);
    api.socialActivity.addListener(() => socialEvents++);
  }

  final _DeleteApi api;
  final SessionController session;
  final GoRouter router;
  int climbingEvents = 0;
  int socialEvents = 0;
  bool? popResult;
}

Future<_Harness> _open(
  WidgetTester tester, {
  _View view = _View.feed,
  _DeleteApi? api,
  bool guest = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  if (!guest) await session.acceptSession(_account('me'));
  final client = api ?? _DeleteApi();
  final router = GoRouter(
    initialLocation: view == _View.directDetail ? '/posts/post-1' : '/feed',
    routes: [
      GoRoute(
        path: '/feed',
        builder: (_, _) => FeedScreen(api: client, session: session),
      ),
      GoRoute(
        path: '/posts/:id',
        builder: (_, state) => PostScreen(
          api: client,
          session: session,
          postId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
  final harness = _Harness(client, session, router);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    session.dispose();
    client.dispose();
  });
  await tester.pumpWidget(
    MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  if (view == _View.detail) {
    unawaited(
      router.push<bool>('/posts/post-1').then((result) {
        harness.popResult = result;
      }),
    );
    await tester.pumpAndSettle();
  }
  return harness;
}

Future<void> _openDeleteConfirmation(WidgetTester tester) async {
  await tester.tap(find.byTooltip('动态操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('删除动态'));
  await tester.pumpAndSettle();
  expect(find.text('删除这条动态？'), findsOneWidget);
}

Future<void> _tapConfirmation(WidgetTester tester, String label) async {
  final button = find.byWidgetPredicate(
    (widget) => widget is WanpanButton && widget.label == label,
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final view in [_View.feed, _View.detail]) {
    testWidgets('${view.name}本人取消删除不发请求、不刷新、不离开', (tester) async {
      final state = await _open(tester, view: view);
      final readsBefore = state.api.feedReads;
      await _openDeleteConfirmation(tester);
      await _tapConfirmation(tester, '取消');
      expect(state.api.deleteCalls, isEmpty);
      expect(state.api.feedReads, readsBefore);
      expect(state.climbingEvents, 0);
      expect(state.socialEvents, 0);
      expect(find.text(_caption), findsOneWidget);
      expect(state.popResult, isNull);
    });
  }

  testWidgets('广场等服务器确认后才移除动态、刷新并分别通知一次', (tester) async {
    final barrier = Completer<void>();
    final state = await _open(
      tester,
      api: _DeleteApi()..deleteBarrier = barrier,
    );
    final readsBefore = state.api.feedReads;
    await _openDeleteConfirmation(tester);
    await _tapConfirmation(tester, '确认删除');
    expect(state.api.deleteCalls, ['/sends/post-1']);
    expect(find.text(_caption), findsOneWidget);
    expect(state.api.feedReads, readsBefore);
    expect(state.climbingEvents, 0);
    expect(state.socialEvents, 0);

    await tester.tap(find.text(_caption));
    await tester.pump();
    expect(find.byType(PostScreen), findsNothing);
    expect(state.router.canPop(), isFalse);

    barrier.complete();
    await tester.pumpAndSettle();
    expect(find.text(_caption), findsNothing);
    expect(find.text('动态已删除'), findsOneWidget);
    expect(state.api.feedReads, greaterThan(readsBefore));
    expect(state.climbingEvents, 1);
    expect(state.socialEvents, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情确认删除成功后返回true，之前不离开，底层广场同步刷新', (tester) async {
    final barrier = Completer<void>();
    final state = await _open(
      tester,
      view: _View.detail,
      api: _DeleteApi()..deleteBarrier = barrier,
    );
    final readsBefore = state.api.feedReads;
    await _openDeleteConfirmation(tester);
    await _tapConfirmation(tester, '确认删除');
    expect(find.byType(PostScreen), findsOneWidget);
    expect(state.popResult, isNull);
    expect(state.api.feedReads, readsBefore);
    expect(state.climbingEvents, 0);
    expect(state.socialEvents, 0);

    barrier.complete();
    await tester.pumpAndSettle();
    expect(state.popResult, isTrue);
    expect(find.byType(PostScreen), findsNothing);
    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.text(_caption), findsNothing);
    expect(state.api.deleteCalls, ['/sends/post-1']);
    expect(state.api.feedReads, greaterThan(readsBefore));
    expect(state.climbingEvents, 1);
    expect(state.socialEvents, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('直达详情无父页面时删除成功跳回广场，导航不空栈', (tester) async {
    final state = await _open(tester, view: _View.directDetail);
    expect(state.router.canPop(), isFalse);
    await _openDeleteConfirmation(tester);
    await _tapConfirmation(tester, '确认删除');
    expect(find.byType(PostScreen), findsNothing);
    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.text(_caption), findsNothing);
    expect(state.climbingEvents, 1);
    expect(state.socialEvents, 1);
    expect(tester.takeException(), isNull);
  });

  for (final view in [_View.feed, _View.detail]) {
    for (final response in ['error', 'missing', 'false', 'string']) {
      testWidgets('${view.name}删除$response结果保留动态，不刷新、不广播、不假成功', (tester) async {
        final api = _DeleteApi()
          ..failDelete = response == 'error'
          ..deleteResponse = switch (response) {
            'false' => {'deleted': false},
            'string' => {'deleted': 'true'},
            _ => {},
          };
        final state = await _open(tester, view: view, api: api);
        final readsBefore = state.api.feedReads;
        await _openDeleteConfirmation(tester);
        await _tapConfirmation(tester, '确认删除');
        expect(api.deleteCalls, ['/sends/post-1']);
        expect(find.text(_caption), findsOneWidget);
        expect(find.text('删除失败，动态仍保留，请稍后重试'), findsOneWidget);
        expect(find.text('动态已删除'), findsNothing);
        expect(state.popResult, isNull);
        expect(api.feedReads, readsBefore);
        expect(state.climbingEvents, 0);
        expect(state.socialEvents, 0);
        await _openDeleteConfirmation(tester);
        await _tapConfirmation(tester, '取消');
        expect(api.deleteCalls, hasLength(1));
      });
    }
  }

  for (final view in [_View.feed, _View.detail]) {
    for (final guest in [false, true]) {
      testWidgets('${view.name}${guest ? '游客' : '其他作者'}不提供删除入口', (
        tester,
      ) async {
        final state = await _open(
          tester,
          view: view,
          guest: guest,
          api: _DeleteApi()..authorId = 'other',
        );
        expect(find.text(_caption), findsOneWidget);
        expect(find.byTooltip('动态操作'), findsNothing);
        expect(find.text('删除动态'), findsNothing);
        if (!guest && view == _View.detail) {
          await tester.tap(find.byTooltip('动态安全操作'));
          await tester.pumpAndSettle();
          expect(find.text('举报动态'), findsOneWidget);
          expect(find.text('拉黑该用户'), findsOneWidget);
          expect(find.text('删除动态'), findsNothing);
        }
        expect(state.api.deleteCalls, isEmpty);
      });
    }

    testWidgets('${view.name}确认弹窗期间切换账号，确认后不发送DELETE', (tester) async {
      final state = await _open(tester, view: view);
      await _openDeleteConfirmation(tester);
      await state.session.acceptSession(_account('other'));
      await tester.pumpAndSettle();
      await _tapConfirmation(tester, '确认删除');
      expect(state.api.deleteCalls, isEmpty);
      expect(state.climbingEvents, 0);
      expect(state.socialEvents, 0);
      expect(state.popResult, isNull);
      expect(find.text(_caption), findsOneWidget);
      expect(find.byTooltip('动态操作'), findsNothing);
    });
  }

  testWidgets('广场删除后晚回的旧GET不能把动态重新放回列表', (tester) async {
    final state = await _open(tester);
    final oldRead = Completer<void>();
    state.api.nextFeedBarrier = oldRead;
    final refreshing = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    expect(state.api.feedReads, 2);
    await _openDeleteConfirmation(tester);
    await _tapConfirmation(tester, '确认删除');
    expect(state.api.deleted, isTrue);
    expect(find.text(_caption), findsNothing);
    expect(state.api.feedReads, 3);

    oldRead.complete();
    await refreshing;
    await tester.pumpAndSettle();
    expect(find.text(_caption), findsNothing);
    expect(find.text('这里还很安静'), findsOneWidget);
    expect(state.climbingEvents, 1);
    expect(state.socialEvents, 1);
  });
}
