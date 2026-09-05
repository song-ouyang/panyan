import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/features/profile/invite_friends_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

void main() {
  testWidgets('邀请页顶部可打开个人好友码，同时保留邀请下载二维码和分享功能', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: InviteFriendsScreen(
          inviteUrl: Uri.parse('https://invite.example.com/#download'),
          onShowFriendCode: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byTooltip('我的好友二维码');
    expect(entry.hitTestable(), findsOneWidget);
    expect(tester.getSize(entry).shortestSide, greaterThanOrEqualTo(44));
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byKey(const Key('invite-qr-code')), findsOneWidget);
    for (final label in ['分享链接', '复制链接']) {
      expect(
        find.byWidgetPredicate(
          (widget) => widget is WanpanButton && widget.label == label,
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
