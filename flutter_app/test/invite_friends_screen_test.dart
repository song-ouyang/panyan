import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_router.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/services/share_service.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';
import 'package:wanpan_diary/features/auth/data/native_auth_service.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/profile/invite_friends_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
  shareBaseUrl: 'https://invite.example.com',
);
final _inviteUrl = _config.inviteUrl;

class _Service extends ShareService {
  final shared = <({Uri url, String title, Rect origin})>[];
  final copied = <Uri>[];
  final opened = <Uri>[];
  ShareResultStatus result = ShareResultStatus.success;
  Completer<ShareResultStatus>? pendingShare;
  bool failShare = false;
  bool failCopy = false;
  bool failOpen = false;

  @override
  Future<ShareResultStatus> share({
    required Uri url,
    required String title,
    required Rect origin,
  }) async {
    shared.add((url: url, title: title, origin: origin));
    if (failShare) throw StateError('Native share failed');
    return pendingShare?.future ?? result;
  }

  @override
  Future<void> copy(Uri url) async {
    copied.add(url);
    if (failCopy) throw StateError('Clipboard failed');
  }

  @override
  Future<void> preview(Uri url) async {
    opened.add(url);
    if (failOpen) throw StateError('Browser unavailable');
  }
}

Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is WanpanButton && widget.label == label,
);

Future<void> _pumpInvite(
  WidgetTester tester,
  _Service service, {
  Size size = const Size(430, 932),
  double textScale = 1,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: navigatorKey == null
          ? InviteFriendsScreen(inviteUrl: _inviteUrl, service: service)
          : const Scaffold(body: Text('上一页')),
    ),
  );
  if (navigatorKey != null) {
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) =>
              InviteFriendsScreen(inviteUrl: _inviteUrl, service: service),
        ),
      ),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<Uint8List> _qrPixels(QrPainter painter) async {
  final picture = painter.toPicture(256);
  final image = picture.toImageSync(256, 256);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  testWidgets('二维码、复制、系统分享和官网预览都使用同一个下载链接', (tester) async {
    final service = _Service();
    await _pumpInvite(tester, service);

    expect(find.text('邀请好友'), findsOneWidget);
    final qrFinder = find.byKey(const Key('invite-qr-code'));
    final qr = tester.widget<QrImageView>(qrFinder);
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: qrFinder, matching: find.byType(CustomPaint)),
    );
    final expectedPainter = QrPainter(
      data: _inviteUrl.toString(),
      version: qr.version,
      errorCorrectionLevel: qr.errorCorrectionLevel,
      gapless: qr.gapless,
      eyeStyle: qr.eyeStyle,
      dataModuleStyle: qr.dataModuleStyle,
    );
    // qr_flutter keeps its source data private; compare the rendered modules.
    await tester.runAsync(() async {
      expect(
        await _qrPixels(paint.painter! as QrPainter),
        orderedEquals(await _qrPixels(expectedPainter)),
      );
    });
    expect(qr.backgroundColor, Colors.white);
    expect(qr.embeddedImage, isNull);
    expect(service.shared, isEmpty);
    expect(service.copied, isEmpty);

    await _tap(tester, '复制链接');
    expect(service.copied, [_inviteUrl]);
    expect(find.text('链接已复制，发给朋友一起攀岩吧'), findsOneWidget);

    await _tap(tester, '分享链接');
    expect(service.shared.single.url, _inviteUrl);
    expect(service.shared.single.title, contains('完攀日记'));
    expect(find.text('已交给所选应用分享'), findsOneWidget);

    await _tap(tester, '打开官网');
    expect(service.opened, [_inviteUrl]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统分享等待布局后使用真实按钮范围并阻止重复操作', (tester) async {
    final service = _Service()..pendingShare = Completer<ShareResultStatus>();
    await _pumpInvite(tester, service);
    final share = _button('分享链接');
    await tester.ensureVisible(share);
    await tester.pumpAndSettle();

    await tester.tap(share);
    await tester.tap(share);
    expect(service.shared, isEmpty, reason: '布局完成前不能打开原生分享');
    await tester.pump();

    expect(service.shared, hasLength(1));
    final origin = service.shared.single.origin;
    expect(origin, tester.getRect(share));
    expect(origin.width, greaterThan(44));
    expect(origin.height, greaterThanOrEqualTo(44));
    expect(origin.left, greaterThanOrEqualTo(0));
    expect(origin.right, lessThanOrEqualTo(430));
    expect(tester.widget<WanpanButton>(share).onPressed, isNull);
    expect(tester.widget<WanpanButton>(_button('复制链接')).onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '打开官网'))
          .onPressed,
      isNull,
    );
    await tester.tap(share);
    await tester.pump();
    expect(service.shared, hasLength(1));

    service.pendingShare!.complete(ShareResultStatus.success);
    await tester.pumpAndSettle();
    expect(tester.widget<WanpanButton>(share).onPressed, isNotNull);
    expect(find.text('已交给所选应用分享'), findsOneWidget);
  });

  for (final scenario in [
    (ShareResultStatus.dismissed, '已取消分享，可以随时再试'),
    (ShareResultStatus.unavailable, '可以复制链接后发送给朋友'),
  ]) {
    testWidgets('${scenario.$1.name} 分享后可重试并继续复制', (tester) async {
      final service = _Service()..result = scenario.$1;
      await _pumpInvite(tester, service);
      await _tap(tester, '分享链接');
      expect(find.text(scenario.$2), findsOneWidget);
      expect(tester.widget<WanpanButton>(_button('分享链接')).loading, isFalse);

      service.result = ShareResultStatus.success;
      await _tap(tester, '分享链接');
      expect(service.shared, hasLength(2));
      expect(find.text('已交给所选应用分享'), findsOneWidget);
      expect(find.text(scenario.$2), findsNothing);
      await _tap(tester, '复制链接');
      expect(service.copied, [_inviteUrl]);
    });
  }

  testWidgets('分享失败展示可恢复反馈，重试成功后移除错误', (tester) async {
    final service = _Service()..failShare = true;
    await _pumpInvite(tester, service);
    await _tap(tester, '分享链接');
    expect(find.text('分享暂时不可用，请重试或复制链接'), findsOneWidget);
    expect(tester.widget<WanpanButton>(_button('分享链接')).loading, isFalse);

    service.failShare = false;
    await _tap(tester, '分享链接');
    expect(service.shared, hasLength(2));
    expect(find.text('已交给所选应用分享'), findsOneWidget);
    expect(find.text('分享暂时不可用，请重试或复制链接'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('复制和打开官网失败后仍可重试', (tester) async {
    final service = _Service()
      ..failCopy = true
      ..failOpen = true;
    await _pumpInvite(tester, service);
    await _tap(tester, '复制链接');
    expect(find.text('暂时没能复制链接，请重试'), findsOneWidget);
    service.failCopy = false;
    await _tap(tester, '复制链接');
    expect(service.copied, [_inviteUrl, _inviteUrl]);
    expect(find.text('链接已复制，发给朋友一起攀岩吧'), findsOneWidget);

    await _tap(tester, '打开官网');
    expect(find.text('暂时无法打开官网，可以复制链接后在浏览器打开'), findsOneWidget);
    service.failOpen = false;
    await _tap(tester, '打开官网');
    expect(service.opened, [_inviteUrl, _inviteUrl]);
    expect(find.text('暂时无法打开官网，可以复制链接后在浏览器打开'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击分享后立即返回，在退场期间仍不打开原生面板', (tester) async {
    final service = _Service();
    final navigator = GlobalKey<NavigatorState>();
    await _pumpInvite(tester, service, navigatorKey: navigator);
    await tester.ensureVisible(_button('分享链接'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(
      tester.element(find.byType(InviteFriendsScreen)),
    )!;

    await tester.tap(_button('分享链接'));
    navigator.currentState!.pop();
    expect(route.isCurrent, isFalse);
    expect(find.byType(InviteFriendsScreen), findsOneWidget);
    await tester.pump();
    expect(service.shared, isEmpty);
    await tester.pumpAndSettle();
    expect(find.text('上一页'), findsOneWidget);
    expect(service.shared, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('离页后异步分享返回不更新已销毁页面', (tester) async {
    final service = _Service()..pendingShare = Completer<ShareResultStatus>();
    final navigator = GlobalKey<NavigatorState>();
    await _pumpInvite(tester, service, navigatorKey: navigator);
    await tester.ensureVisible(_button('分享链接'));
    await tester.pumpAndSettle();
    await tester.tap(_button('分享链接'));
    await tester.pump();
    expect(service.shared, hasLength(1));

    navigator.currentState!.pop();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    service.pendingShare!.completeError(StateError('Late native failure'));
    await tester.pumpAndSettle();
    expect(find.text('上一页'), findsOneWidget);
    expect(find.text('分享暂时不可用，请重试或复制链接'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 大字模式下二维码和所有操作可滚动访问且无溢出', (tester) async {
    final service = _Service();
    await _pumpInvite(
      tester,
      service,
      size: const Size(320, 568),
      textScale: 1.35,
    );
    final qr = find.byKey(const Key('invite-qr-code'));
    await tester.ensureVisible(qr);
    await tester.pumpAndSettle();
    expect(tester.getSize(qr).width, tester.getSize(qr).height);
    expect(tester.getRect(qr).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(qr).right, lessThanOrEqualTo(320));

    for (final label in ['分享链接', '复制链接', '打开官网']) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      final action = label == '打开官网'
          ? find.widgetWithText(TextButton, label)
          : _button(label);
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      expect(tester.getRect(action).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(action).right, lessThanOrEqualTo(320));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(service.shared.single.url, _inviteUrl);
    expect(service.copied, [_inviteUrl]);
    expect(service.opened, [_inviteUrl]);
  });

  testWidgets('真实路由保留邀请目标，游客登录后回到配置的官网邀请页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    final api = ApiClient(
      config: _config,
      accessTokenProvider: () => session.token,
    );
    final auth = AuthRepository(api);
    await session.initialize(auth);
    final router = createWanpanRouter(
      api: api,
      session: session,
      authRepository: auth,
      nativeAuth: NativeAuthService(),
    );
    addTearDown(session.dispose);
    addTearDown(router.dispose);
    router.go('/profile/invite');
    await tester.pumpWidget(
      MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/login');
    expect(router.state.uri.queryParameters['from'], '/profile/invite');
    expect(find.byType(InviteFriendsScreen), findsNothing);

    await session.acceptSession(
      const AuthSession(
        token: 'invite-test-token',
        user: UserSummary(
          id: 'invite-user',
          nickname: '岩友',
          role: 'user',
          profileCompleted: true,
        ),
        needsProfile: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/profile/invite');
    expect(
      tester
          .widget<InviteFriendsScreen>(find.byType(InviteFriendsScreen))
          .inviteUrl,
      Uri.parse('https://invite.example.com/#download'),
    );
    expect(find.byKey(const Key('invite-qr-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
