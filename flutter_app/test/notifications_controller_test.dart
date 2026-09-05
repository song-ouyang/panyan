import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/notification_models.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/notifications/application/notifications_controller.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

JsonMap _notification(String id, {bool read = false}) => {
  'id': id,
  'type': 'friend_request',
  'title': '新的岩友申请',
  'content': '有人想添加你为岩友',
  'target_path': '/pages/friends/index',
  'read_at': read ? '2026-09-05T12:00:00Z' : null,
  'created_at': '2026-09-05T11:00:00Z',
};

JsonMap _request(String id) => {'id': id, 'nickname': '岩友 $id'};

class _NotificationsApi extends ApiClient {
  _NotificationsApi() : super(config: _config, accessTokenProvider: () => null);

  List<JsonMap> inbox = [_notification('notification-1')];
  List<JsonMap> friendRequests = [_request('friend-1')];
  final calls = <String>[];
  final inboxResponses = Queue<Future<JsonMap>>();
  final requestResponses = Queue<Future<JsonMap>>();
  Future<JsonMap> Function(String path)? onPost;

  int count(String method, String path) =>
      calls.where((call) => call == '$method $path').length;

  JsonMap get inboxSnapshot => {
    'items': [for (final item in inbox) Map<String, dynamic>.of(item)],
    'unread': inbox.where((item) => item['read_at'] == null).length,
  };

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('GET $path');
    if (path == '/notifications') {
      if (inboxResponses.isNotEmpty) return inboxResponses.removeFirst();
      return inboxSnapshot;
    }
    if (path == '/users/me/friend-requests') {
      if (requestResponses.isNotEmpty) return requestResponses.removeFirst();
      return {
        'items': [
          for (final user in friendRequests) Map<String, dynamic>.of(user),
        ],
      };
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('POST $path');
    final response = onPost == null ? null : await onPost!(path);
    if (path.endsWith('/friend-accept')) {
      final result = response ?? {'status': 'accepted'};
      if (result['status'] == 'accepted') {
        final userId = path.split('/')[2];
        friendRequests = friendRequests
            .where((user) => user['id'] != userId)
            .toList();
      }
      return result;
    }
    if (path.startsWith('/notifications/')) {
      final id = path.split('/')[2];
      inbox = [
        for (final item in inbox)
          if (id == 'read-all' || item['id'] == id)
            {...item, 'read_at': '2026-09-05T12:00:00Z'}
          else
            item,
      ];
      return response ?? {'read': true};
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<SessionController> _session({bool authenticated = true}) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  if (authenticated) await _signIn(session, 'account-a');
  return session;
}

Future<void> _signIn(SessionController session, String id) =>
    session.acceptSession(
      AuthSession(
        token: 'token-$id',
        user: UserSummary(id: id, nickname: id),
        needsProfile: false,
      ),
    );

NotificationsController _controller(
  _NotificationsApi api,
  SessionController session,
) {
  final controller = NotificationsController(api: api, session: session);
  _fixtureDisposers.add(() {
    controller.dispose();
    api.dispose();
    session.dispose();
  });
  return controller;
}

final _fixtureDisposers = <VoidCallback>[];

void _controllerTest(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    try {
      await body(tester);
    } finally {
      for (final dispose in _fixtureDisposers.reversed) {
        dispose();
      }
      _fixtureDisposers.clear();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _controllerTest('游客不读取或修改消息，登录后自动加载未读和收到的申请', (tester) async {
    final session = await _session(authenticated: false);
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();

    await controller.refresh();
    await controller.markAllRead();
    await controller.markRead(AppNotificationItem.fromJson(_notification('n')));
    await controller.acceptFriendRequest('friend-1');
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    api.socialActivity.recordChanged();
    await tester.pump();
    expect(api.calls, isEmpty);

    await _signIn(session, 'account-a');
    await tester.pump();
    expect(controller.items.single.id, 'notification-1');
    expect(controller.requests.single.id, 'friend-1');
    expect(controller.unreadCount, 1);
    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
    expect(api.count('GET', '/notifications'), 1);
    controller.start();
    await tester.pump();
    expect(api.count('GET', '/notifications'), 1);
  });

  _controllerTest('读取失败保留已有消息和申请，并提供可重试错误', (tester) async {
    final session = await _session();
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();
    await tester.pump();
    final response = Completer<JsonMap>();
    api.inboxResponses.add(response.future);
    final refresh = controller.refresh();
    response.completeError(StateError('offline'));
    await refresh;

    expect(controller.items.single.id, 'notification-1');
    expect(controller.requests.single.id, 'friend-1');
    expect(controller.unreadCount, 1);
    expect(controller.error, isNotNull);
    expect(controller.loading, isFalse);
    await controller.refresh();
    expect(controller.error, isNull);
  });

  for (final all in [false, true]) {
    _controllerTest('${all ? '全部' : '单条'}已读写入失败仍保留未读，重试成功后才更新', (tester) async {
      final session = await _session();
      final api = _NotificationsApi();
      final controller = _controller(api, session)..start();
      await tester.pump();
      final write = Completer<JsonMap>();
      api.onPost = (_) => write.future;
      final pending = all
          ? controller.markAllRead()
          : controller.markRead(controller.items.single);
      expect(controller.unreadCount, 1);
      expect(controller.items.single.isUnread, isTrue);
      final failed = expectLater(pending, throwsStateError);
      write.completeError(StateError('offline'));
      await failed;
      expect(controller.unreadCount, 1);
      expect(controller.items.single.isUnread, isTrue);

      api.onPost = null;
      if (all) {
        await controller.markAllRead();
      } else {
        await controller.markRead(controller.items.single);
      }
      expect(controller.unreadCount, 0);
      expect(controller.items.single.isUnread, isFalse);
    });
  }

  _controllerTest('成功标记已读后，迟到的旧读取不会恢复未读', (tester) async {
    final session = await _session();
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();
    await tester.pump();
    final oldInbox = api.inboxSnapshot;
    final response = Completer<JsonMap>();
    api.inboxResponses.add(response.future);
    final refresh = controller.refresh();
    await controller.markRead(controller.items.single);
    response.complete(oldInbox);
    await refresh;

    expect(controller.unreadCount, 0);
    expect(controller.items.single.isUnread, isFalse);
    expect(controller.loading, isFalse);
  });

  _controllerTest('全部已读写入期间新读取到的消息仍保留未读', (tester) async {
    final session = await _session();
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();
    await tester.pump();
    final write = Completer<JsonMap>();
    api.onPost = (_) => write.future;
    final pending = controller.markAllRead();
    api.inbox = [...api.inbox, _notification('notification-new')];
    await controller.refresh();
    expect(controller.unreadCount, 2);
    write.complete({'read': true});
    await pending;

    expect(controller.unreadCount, 1);
    expect(controller.items.first.isUnread, isFalse);
    expect(controller.items.last.id, 'notification-new');
    expect(controller.items.last.isUnread, isTrue);
  });

  _controllerTest('同意申请防止重复提交，失败可重试，成功移除并刷新列表', (tester) async {
    final session = await _session();
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();
    await tester.pump();
    final write = Completer<JsonMap>();
    api.onPost = (_) => write.future;
    final pending = controller.acceptFriendRequest('friend-1');
    await controller.acceptFriendRequest('friend-1');
    expect(controller.isAccepting('friend-1'), isTrue);
    expect(api.count('POST', '/users/friend-1/friend-accept'), 1);
    final failed = expectLater(pending, throwsStateError);
    write.completeError(StateError('offline'));
    await failed;

    expect(controller.isAccepting('friend-1'), isFalse);
    expect(controller.requests.single.id, 'friend-1');
    api.onPost = null;
    api.inbox = [_notification('acceptance-refresh')];
    await controller.acceptFriendRequest('friend-1');
    expect(controller.requests, isEmpty);
    expect(controller.isAccepting('friend-1'), isFalse);
    expect(controller.items.single.id, 'acceptance-refresh');
    expect(api.count('POST', '/users/friend-1/friend-accept'), 2);
  });

  _controllerTest('非 accepted 的回复不会把申请误判为通过', (tester) async {
    final session = await _session();
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();
    await tester.pump();
    api.onPost = (_) async => {'status': 'blocked'};

    await expectLater(
      controller.acceptFriendRequest('friend-1'),
      throwsStateError,
    );
    await tester.pump();
    expect(controller.requests.single.id, 'friend-1');
    expect(controller.isAccepting('friend-1'), isFalse);
  });

  _controllerTest('切换账号立即清空，旧账号迟到的消息与申请不能覆盖新账号', (tester) async {
    final session = await _session();
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();
    await tester.pump();
    final oldInbox = Completer<JsonMap>();
    final oldRequests = Completer<JsonMap>();
    api.inboxResponses.add(oldInbox.future);
    api.requestResponses.add(oldRequests.future);
    final oldRefresh = controller.refresh();
    final newInbox = Completer<JsonMap>();
    final newRequests = Completer<JsonMap>();
    api.inboxResponses.add(newInbox.future);
    api.requestResponses.add(newRequests.future);

    await _signIn(session, 'account-b');
    expect(controller.items, isEmpty);
    expect(controller.requests, isEmpty);
    expect(controller.unreadCount, 0);
    newInbox.complete({
      'items': [_notification('account-b-message')],
      'unread': 1,
    });
    newRequests.complete({
      'items': [_request('account-b-friend')],
    });
    await tester.pump();
    oldInbox.complete({
      'items': [_notification('account-a-private')],
      'unread': 99,
    });
    oldRequests.complete({
      'items': [_request('account-a-private-friend')],
    });
    await oldRefresh;

    expect(controller.items.single.id, 'account-b-message');
    expect(controller.requests.single.id, 'account-b-friend');
    expect(controller.unreadCount, 1);
    expect(controller.error, isNull);
  });

  _controllerTest('旧账号迟到的已读写入不能修改新账号的未读', (tester) async {
    final session = await _session();
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();
    await tester.pump();
    final write = Completer<JsonMap>();
    api.onPost = (_) => write.future;
    final pending = controller.markRead(controller.items.single);
    await _signIn(session, 'account-b');
    await tester.pump();
    write.complete({'read': true});
    await pending;

    expect(controller.unreadCount, 1);
    expect(controller.items.single.isUnread, isTrue);
  });

  _controllerTest('退出后清空所有消息，迟到的读取和批准都不能恢复旧数据', (tester) async {
    final session = await _session();
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();
    await tester.pump();
    final oldInbox = Completer<JsonMap>();
    api.inboxResponses.add(oldInbox.future);
    final refresh = controller.refresh();
    final write = Completer<JsonMap>();
    api.onPost = (_) => write.future;
    final accept = controller.acceptFriendRequest('friend-1');
    await session.signOut();
    expect(controller.items, isEmpty);
    expect(controller.requests, isEmpty);
    expect(controller.unreadCount, 0);
    expect(controller.isAccepting('friend-1'), isFalse);
    final callCount = api.calls.length;
    oldInbox.completeError(StateError('old request failed'));
    write.complete({'status': 'accepted'});
    await Future.wait([refresh, accept]);
    await tester.pump(const Duration(seconds: 31));

    expect(controller.items, isEmpty);
    expect(controller.requests, isEmpty);
    expect(controller.unreadCount, 0);
    expect(controller.error, isNull);
    expect(controller.loading, isFalse);
    expect(api.calls.length, callCount);
  });

  _controllerTest('仅前台定时轮询，恢复前台及好友变更会刷新', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final session = await _session();
    final api = _NotificationsApi();
    final controller = _controller(api, session)..start();
    await tester.pump();
    expect(api.count('GET', '/notifications'), 1);
    await tester.pump(const Duration(seconds: 30));
    expect(api.count('GET', '/notifications'), 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 60));
    expect(api.count('GET', '/notifications'), 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.count('GET', '/notifications'), 3);
    api.socialActivity.recordChanged();
    await tester.pump();
    expect(api.count('GET', '/notifications'), 4);
    expect(controller.error, isNull);
  });

  group('消息目标路径白名单', () {
    AppNotificationItem item(String? path, {String type = 'content_review'}) =>
        AppNotificationItem(id: 'n', type: type, title: '消息', targetPath: path);

    test('支持既有小程序目的地，并保持岩友消息固定进入岩友列表', () {
      expect(item('/pages/friends/index').route, '/friends');
      expect(item('/pages/my-submissions/index').route, '/route-submissions');
      expect(item('/submissions/mine').route, '/route-submissions');
      expect(item('/pages/my-posts/index').route, '/profile/calendar');
      const id = '00000000-0000-4000-8000-000000000001';
      expect(item('/pages/post/index?id=$id').route, '/posts/$id');
      expect(item(null, type: 'friend_request').route, '/friends');
      expect(
        item('https://example.com', type: 'friend_accepted').route,
        '/friends',
      );
    });

    test('外部 URL、未知目的地和无效线路参数都无法导航', () {
      for (final path in <String?>[
        null,
        '',
        'https://example.com/pages/friends/index',
        '//example.com/pages/friends/index',
        'javascript:alert(1)',
        '/settings',
        '/pages/post/index',
        '/pages/post/index?id=../../settings',
        '/pages/post/index?id=%2Fsettings',
        '/pages/post/index?id=%FF',
      ]) {
        expect(item(path).route, isNull, reason: 'Unsupported target: $path');
      }
    });
  });
}
