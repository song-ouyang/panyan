import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/models/notification_models.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/features/notifications/application/notifications_controller.dart';
import 'package:wanpan_diary/features/notifications/notifications_screen.dart';

const _request = UserSummary(id: 'climber-1', nickname: '一起上墙的小岩友');
final _unread = AppNotificationItem(
  id: 'request-message',
  type: 'friend_request',
  title: '收到新的岩友申请',
  content: '一起上墙的小岩友想和你成为岩友。',
  createdAt: DateTime(2026, 9, 5, 12, 30),
);
final _history = AppNotificationItem(
  id: 'history-message',
  type: 'system',
  title: '你的线路已发布',
  content: '这条线路已经可以打卡啦。',
  createdAt: DateTime(2026, 9, 4, 9, 10),
  readAt: DateTime(2026, 9, 4, 10),
);

class _NotificationsController extends ChangeNotifier
    implements NotificationsController {
  _NotificationsController({this.items = const [], this.requests = const []});

  @override
  List<AppNotificationItem> items;
  @override
  List<UserSummary> requests;
  @override
  bool loading = false;
  @override
  String? error;
  @override
  int get unreadCount => items.where((item) => item.isUnread).length;

  final readCalls = <String>[];
  final acceptCalls = <String>[];
  final _accepting = <String>{};
  int allReadCalls = 0;
  int refreshCalls = 0;
  bool disposed = false;
  bool failRead = false;
  bool failAllRead = false;
  bool failAccept = false;
  String? refreshError;
  Completer<void>? refreshGate;
  Completer<void>? readGate;
  Completer<void>? acceptGate;

  @override
  bool isAccepting(String userId) => _accepting.contains(userId);

  @override
  Future<void> refresh() async {
    refreshCalls += 1;
    loading = refreshGate != null;
    error = null;
    notifyListeners();
    await refreshGate?.future;
    error = refreshError;
    loading = false;
    notifyListeners();
  }

  @override
  Future<void> markRead(AppNotificationItem item) async {
    readCalls.add(item.id);
    await readGate?.future;
    if (failRead) throw StateError('offline');
    items = [
      for (final current in items)
        current.id == item.id ? current.asRead(DateTime(2026)) : current,
    ];
    notifyListeners();
  }

  @override
  Future<void> markAllRead() async {
    allReadCalls += 1;
    if (failAllRead) throw StateError('offline');
    items = [for (final item in items) item.asRead(DateTime(2026))];
    notifyListeners();
  }

  @override
  Future<void> acceptFriendRequest(String userId) async {
    acceptCalls.add(userId);
    _accepting.add(userId);
    notifyListeners();
    try {
      await acceptGate?.future;
      if (failAccept) throw StateError('offline');
      requests = requests.where((user) => user.id != userId).toList();
    } finally {
      _accepting.remove(userId);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GoRouter> _pump(
  WidgetTester tester,
  _NotificationsController controller, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, _) => NotificationsScreen(controller: controller),
      ),
      GoRoute(
        path: '/friends',
        builder: (_, _) => Scaffold(
          appBar: AppBar(title: const Text('我的岩友')),
          body: const Text('岩友列表'),
        ),
      ),
      GoRoute(
        path: '/users/:userId',
        builder: (_, state) => Scaffold(
          appBar: AppBar(title: const Text('岩友主页')),
          body: Text('主页：${state.pathParameters['userId']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: WanpanTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    160,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('notifications-list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows requests and history without marking messages on entry', (
    tester,
  ) async {
    final controller = _NotificationsController(
      items: [_unread, _history],
      requests: [_request],
    );
    await _pump(tester, controller);

    expect(controller.refreshCalls, 1);
    expect(controller.readCalls, isEmpty);
    expect(controller.allReadCalls, 0);
    expect(find.text('岩友申请'), findsOneWidget);
    expect(find.text(_request.nickname), findsOneWidget);
    expect(find.text('消息记录'), findsOneWidget);
    expect(find.text(_unread.content!), findsOneWidget);
    expect(find.text('2026/09/05 12:30'), findsOneWidget);
    expect(
      find.byKey(const Key('notification-unread-request-message')),
      findsOneWidget,
    );
    await _show(tester, find.byKey(const Key('notification-history-message')));
    expect(find.text(_history.title), findsOneWidget);
    expect(
      find.byKey(const Key('notification-unread-history-message')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.disposed, isFalse);
  });

  testWidgets('accepts a request once and keeps the notification history', (
    tester,
  ) async {
    final completion = Completer<void>();
    final controller = _NotificationsController(
      items: [_unread, _history],
      requests: [_request],
    )..acceptGate = completion;
    await _pump(tester, controller);

    final accept = find.byKey(const Key('notification-accept-climber-1'));
    await tester.tap(accept);
    await tester.pump();
    await tester.tap(accept);
    await tester.pump();
    expect(controller.acceptCalls, ['climber-1']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completion.complete();
    await tester.pumpAndSettle();
    expect(controller.requests, isEmpty);
    expect(find.text('已经成为岩友啦'), findsOneWidget);
    expect(find.text('岩友申请'), findsNothing);
    expect(find.text(_unread.title), findsOneWidget);
    expect(find.text(_history.title), findsOneWidget);
    expect(controller.readCalls, isEmpty);
  });

  testWidgets('opens the applicant profile and refreshes on return', (
    tester,
  ) async {
    final controller = _NotificationsController(requests: [_request]);
    final router = await _pump(tester, controller);

    await tester.tap(find.byKey(const Key('notification-profile-climber-1')));
    await tester.pumpAndSettle();
    expect(find.text('主页：climber-1'), findsOneWidget);
    expect(controller.readCalls, isEmpty);
    router.pop();
    await tester.pumpAndSettle();
    expect(controller.refreshCalls, 2);
  });

  testWidgets('marks only the tapped record before opening its destination', (
    tester,
  ) async {
    final completion = Completer<void>();
    final other = AppNotificationItem(
      id: 'other-message',
      type: 'system',
      title: '另一条未读消息',
    );
    final controller = _NotificationsController(items: [_unread, other])
      ..readGate = completion;
    final router = await _pump(tester, controller);

    final record = find.byKey(const Key('notification-request-message'));
    await tester.tap(record);
    await tester.pump();
    await tester.tap(record);
    await tester.pump();
    expect(controller.readCalls, ['request-message']);
    expect(find.text('岩友列表'), findsNothing);
    expect(controller.unreadCount, 2);

    completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('岩友列表'), findsOneWidget);
    expect(controller.unreadCount, 1);
    router.pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('notification-unread-request-message')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('notification-unread-other-message')),
      findsOneWidget,
    );
    expect(find.text(_unread.title), findsOneWidget);
  });

  testWidgets('unsupported target stays in the inbox after marking read', (
    tester,
  ) async {
    final item = AppNotificationItem(
      id: 'unsupported',
      type: 'system',
      title: '消息正文可在这里查看',
      targetPath: 'https://untrusted.example/not-an-app-destination',
    );
    final controller = _NotificationsController(items: [item]);
    await _pump(tester, controller);

    await tester.tap(find.byKey(const Key('notification-unsupported')));
    await tester.pumpAndSettle();
    expect(controller.readCalls, ['unsupported']);
    expect(controller.unreadCount, 0);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text(item.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marks all read only on demand and preserves read history', (
    tester,
  ) async {
    final controller = _NotificationsController(items: [_unread, _history]);
    await _pump(tester, controller);
    expect(controller.allReadCalls, 0);

    await tester.tap(find.byKey(const Key('notifications-mark-all-read')));
    await tester.pumpAndSettle();
    expect(controller.allReadCalls, 1);
    expect(controller.unreadCount, 0);
    expect(find.text(_unread.title), findsOneWidget);
    expect(find.text(_history.title), findsOneWidget);
    expect(find.byKey(const Key('notifications-mark-all-read')), findsNothing);
    expect(find.text('全部消息已读'), findsOneWidget);
  });

  testWidgets('failed writes keep unread records and allow request retry', (
    tester,
  ) async {
    final controller =
        _NotificationsController(items: [_unread], requests: [_request])
          ..failAccept = true
          ..failRead = true;
    await _pump(tester, controller);

    await tester.tap(find.byKey(const Key('notification-accept-climber-1')));
    await tester.pumpAndSettle();
    expect(find.text('通过申请失败，请稍后重试'), findsOneWidget);
    expect(controller.requests, [_request]);
    expect(controller.isAccepting('climber-1'), isFalse);
    await tester.tap(find.byKey(const Key('notification-request-message')));
    await tester.pumpAndSettle();
    expect(find.text('消息暂时没有打开，请稍后重试'), findsOneWidget);
    expect(controller.unreadCount, 1);
    expect(find.text('岩友列表'), findsNothing);

    controller.failAccept = false;
    await tester.tap(find.byKey(const Key('notification-accept-climber-1')));
    await tester.pumpAndSettle();
    expect(controller.requests, isEmpty);
    expect(find.text('已经成为岩友啦'), findsOneWidget);
  });

  testWidgets('shows an empty inbox and supports pull to refresh', (
    tester,
  ) async {
    final controller = _NotificationsController();
    await _pump(tester, controller);

    expect(find.byKey(const Key('notifications-empty')), findsOneWidget);
    expect(find.text('还没有消息'), findsOneWidget);
    expect(find.text('消息记录'), findsNothing);
    expect(find.byKey(const Key('notifications-mark-all-read')), findsNothing);
    await tester.drag(
      find.byKey(const Key('notifications-list')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(controller.refreshCalls, 2);
  });

  testWidgets('refresh failure retains history and can be retried', (
    tester,
  ) async {
    final controller = _NotificationsController(items: [_history])
      ..refreshError = '消息暂时没有加载出来，请重试';
    await _pump(tester, controller);

    expect(find.byKey(const Key('notifications-error')), findsOneWidget);
    expect(find.text(_history.title), findsOneWidget);
    expect(find.byKey(const Key('notifications-empty')), findsNothing);
    controller.refreshError = null;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(controller.refreshCalls, 2);
    expect(find.byKey(const Key('notifications-error')), findsNothing);
    expect(find.text(_history.title), findsOneWidget);
  });

  testWidgets('an initial failure shows retry instead of an empty inbox', (
    tester,
  ) async {
    final controller = _NotificationsController()
      ..refreshError = '消息暂时没有加载出来，请重试';
    await _pump(tester, controller);

    expect(find.byKey(const Key('notifications-error')), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.byKey(const Key('notifications-empty')), findsNothing);
  });

  testWidgets('initial loading shows skeletons until the inbox arrives', (
    tester,
  ) async {
    final completion = Completer<void>();
    final controller = _NotificationsController()..refreshGate = completion;
    await _pump(tester, controller);

    expect(find.bySemanticsLabel('正在加载消息'), findsOneWidget);
    expect(find.byKey(const Key('notifications-empty')), findsNothing);
    controller.items = [_history];
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('正在加载消息'), findsNothing);
    expect(find.text(_history.title), findsOneWidget);
  });

  testWidgets('remains usable at 320px with accessibility size text', (
    tester,
  ) async {
    final controller = _NotificationsController(
      items: [_unread, _history],
      requests: [
        const UserSummary(id: 'climber-1', nickname: '喜欢攀岩和分享每一次进步的超长昵称岩友'),
      ],
    );
    await _pump(tester, controller, size: const Size(320, 568), textScale: 3.2);

    expect(find.byTooltip('全部已读').hitTestable(), findsOneWidget);
    final profile = find.byKey(const Key('notification-profile-climber-1'));
    await _show(tester, profile);
    expect(profile.hitTestable(), findsOneWidget);
    expect(tester.getSize(profile).height, greaterThanOrEqualTo(44));
    final accept = find.byKey(const Key('notification-accept-climber-1'));
    await _show(tester, accept);
    expect(accept.hitTestable(), findsOneWidget);
    expect(tester.getRect(accept).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);

    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(controller.acceptCalls, ['climber-1']);
    await _show(tester, find.byKey(const Key('notification-history-message')));
    expect(find.text(_history.content!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
