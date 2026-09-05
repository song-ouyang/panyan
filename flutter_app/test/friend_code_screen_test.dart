import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/services/share_service.dart';
import 'package:wanpan_diary/features/profile/friend_code_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

const _user = UserSummary(
  id: 'fb7db6aa-6b30-4333-a9ca-4dbbe975aafe',
  nickname: '向上攀的岩友',
);
final _friendUrl = Uri.parse(
  'https://invite.example.com/?friend=${_user.id}#download',
);

class _Service extends ShareService {
  final copied = <Uri>[];
  bool failCopy = false;

  @override
  Future<void> copy(Uri url) async {
    copied.add(url);
    if (failCopy) throw StateError('Clipboard unavailable');
  }
}

Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is WanpanButton && widget.label == label,
);

Future<void> _pumpCode(
  WidgetTester tester, {
  UserSummary user = _user,
  _Service? service,
  Future<void> Function()? onScan,
  Size size = const Size(430, 932),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: FriendCodeScreen(
        user: user,
        friendUrl: _friendUrl,
        service: service ?? _Service(),
        onScan: onScan,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(_button(label));
  await tester.pumpAndSettle();
  await tester.tap(_button(label));
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
  testWidgets('好友码显示实际昵称并编码个人链接，解释 App 扫码和网页下载', (tester) async {
    final service = _Service();
    await _pumpCode(tester, service: service);

    expect(find.text(_user.nickname), findsOneWidget);
    expect(find.text('用完攀日记扫一扫，加我为岩友'), findsOneWidget);
    expect(find.text('确认后发送申请'), findsOneWidget);
    expect(find.text('还没有 App？用微信或相机扫码可前往官网下载'), findsOneWidget);
    expect(find.byKey(const Key('friend-avatar-fallback')), findsOneWidget);
    expect(_button('扫一扫添加岩友'), findsNothing);
    expect(service.copied, isEmpty);

    final qrFinder = find.byKey(const Key('friend-qr-code'));
    final qr = tester.widget<QrImageView>(qrFinder);
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: qrFinder, matching: find.byType(CustomPaint)),
    );
    final expected = QrPainter(
      data: _friendUrl.toString(),
      version: qr.version,
      errorCorrectionLevel: qr.errorCorrectionLevel,
      gapless: qr.gapless,
      eyeStyle: qr.eyeStyle,
      dataModuleStyle: qr.dataModuleStyle,
    );
    await tester.runAsync(() async {
      expect(
        await _qrPixels(paint.painter! as QrPainter),
        orderedEquals(await _qrPixels(expected)),
      );
    });
    expect(qr.padding, const EdgeInsets.all(32));
    expect(qr.backgroundColor, Colors.white);
    expect(qr.embeddedImage, isNull);
    await _tap(tester, '复制好友链接');
    expect(service.copied, [_friendUrl]);
    expect(find.text('好友链接已复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('使用实际头像，加载失败时回退为既有黑猫', (tester) async {
    const avatarUrl = 'https://avatars.example.com/actual-user.png';
    await _pumpCode(
      tester,
      user: const UserSummary(
        id: 'fb7db6aa-6b30-4333-a9ca-4dbbe975aafe',
        nickname: '实际昵称',
        avatarUrl: avatarUrl,
      ),
    );
    final avatar = tester.widget<Image>(
      find.byKey(const Key('friend-user-avatar')),
    );
    expect((avatar.image as NetworkImage).url, avatarUrl);
    expect(find.byKey(const Key('friend-avatar-fallback')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('复制失败可重试且成功后移除错误', (tester) async {
    final service = _Service()..failCopy = true;
    await _pumpCode(tester, service: service);
    await _tap(tester, '复制好友链接');
    expect(find.text('暂时没能复制链接，请重试'), findsOneWidget);
    service.failCopy = false;
    await _tap(tester, '复制好友链接');
    expect(service.copied, [_friendUrl, _friendUrl]);
    expect(find.text('好友链接已复制'), findsOneWidget);
    expect(find.text('暂时没能复制链接，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('扫码期间防止重复导航并在扫码返回后恢复操作', (tester) async {
    final pending = Completer<void>();
    var scans = 0;
    await _pumpCode(
      tester,
      onScan: () {
        scans++;
        return pending.future;
      },
    );
    final scan = _button('扫一扫添加岩友');
    await tester.ensureVisible(scan);
    await tester.pumpAndSettle();
    await tester.tap(scan);
    await tester.tap(scan);
    await tester.pump();
    expect(scans, 1);
    expect(tester.widget<WanpanButton>(scan).loading, isTrue);
    expect(tester.widget<WanpanButton>(scan).onPressed, isNull);
    expect(tester.widget<WanpanButton>(_button('复制好友链接')).onPressed, isNull);

    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<WanpanButton>(scan).loading, isFalse);
    expect(tester.widget<WanpanButton>(scan).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('扫码导航失败后可重试，离页后的错误不更新已销毁页面', (tester) async {
    var fail = true;
    final pending = Completer<void>();
    await _pumpCode(
      tester,
      onScan: () async {
        if (fail) throw StateError('Navigator unavailable');
        await pending.future;
      },
    );
    await _tap(tester, '扫一扫添加岩友');
    expect(find.text('暂时无法打开扫一扫，请重试'), findsOneWidget);

    fail = false;
    await tester.tap(_button('扫一扫添加岩友'));
    await tester.pump();
    expect(find.text('暂时无法打开扫一扫，请重试'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: Text('上一页')));
    pending.completeError(StateError('Late navigation failure'));
    await tester.pumpAndSettle();
    expect(find.text('上一页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 大字和长昵称下二维码完整且操作可滚动访问', (tester) async {
    final service = _Service();
    var scans = 0;
    await _pumpCode(
      tester,
      service: service,
      user: const UserSummary(
        id: 'fb7db6aa-6b30-4333-a9ca-4dbbe975aafe',
        nickname: '每个周末都想和朋友一起向上攀岩',
      ),
      onScan: () async => scans++,
      size: const Size(320, 568),
      textScale: 1.35,
    );
    final qr = find.byKey(const Key('friend-qr-code'));
    await tester.ensureVisible(qr);
    await tester.pumpAndSettle();
    expect(tester.getSize(qr).width, tester.getSize(qr).height);
    expect(tester.getRect(qr).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(qr).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);

    for (final label in ['扫一扫添加岩友', '复制好友链接']) {
      final action = _button(label);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      expect(tester.getRect(action).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(action).right, lessThanOrEqualTo(320));
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(scans, 1);
    expect(service.copied, [_friendUrl]);
  });
}
