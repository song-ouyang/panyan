import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_notice.dart';

Future<BuildContext> _open(
  WidgetTester tester, {
  bool reducedMotion = false,
  double textScale = 1,
  VoidCallback? onTap,
}) async {
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 640),
          viewPadding: const EdgeInsets.only(top: 44),
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          pageContext = context;
          return Scaffold(
            body: Center(
              child: TextButton(onPressed: onTap, child: const Text('页面操作')),
            ),
          );
        },
      ),
    ),
  );
  return pageContext;
}

final _notice = find.byKey(const Key('wanpan-top-notice'));
void main() {
  testWidgets(
    'green notice slides down below safe area and automatically disappears',
    (tester) async {
      final context = await _open(tester);
      WanpanNotice.show(context, '动态已删除');
      await tester.pump();
      final start = tester.getTopLeft(_notice).dy;
      await tester.pump(const Duration(milliseconds: 300));
      final finish = tester.getTopLeft(_notice).dy;
      expect(start, lessThan(finish));
      expect(finish, 56);
      expect(tester.widget<Material>(_notice).color, WanpanColors.mintSoft);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
    },
  );

  testWidgets('new notice replaces old notice and owns its own timeout', (
    tester,
  ) async {
    final context = await _open(tester);
    WanpanNotice.show(context, '第一条');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    WanpanNotice.show(context, '第二条');
    await tester.pumpAndSettle();
    expect(find.text('第一条'), findsNothing);
    expect(_notice, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('第二条'), findsOneWidget);
    WanpanNotice.dismiss(context);
    await tester.pump();
    expect(_notice, findsNothing);
  });

  testWidgets(
    'notice permits interaction with page and can be closed manually',
    (tester) async {
      var taps = 0;
      final context = await _open(tester, onTap: () => taps++);
      WanpanNotice.show(context, '操作已保存');
      await tester.pumpAndSettle();
      await tester.tap(find.text('页面操作'));
      expect(taps, 1);
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
    },
  );

  testWidgets(
    'replacement while exiting and app disposal cancel all timers safely',
    (tester) async {
      final context = await _open(tester);
      WanpanNotice.show(context, '旧提示');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pump(const Duration(milliseconds: 50));
      WanpanNotice.show(context, '新提示');
      await tester.pumpAndSettle();
      expect(find.text('新提示'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      WanpanNotice.show(context, '已卸载页面');
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'root overlay keeps successful feedback visible when source route pops',
    (tester) async {
      final context = await _open(tester);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Builder(
            builder: (inner) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    WanpanNotice.show(inner, '动态已删除');
                    Navigator.of(inner).pop();
                  },
                  child: const Text('完成并返回'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成并返回'));
      await tester.pumpAndSettle();
      expect(find.text('页面操作'), findsOneWidget);
      expect(find.text('动态已删除'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('320px large text wraps and close target stays accessible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final context = await _open(tester, textScale: 1.8);
    WanpanNotice.show(
      context,
      List.filled(20, '网络暂时不可用，动态仍然保留，请稍后重新尝试。').join(),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(_notice);
    expect(bounds.left, 20);
    expect(bounds.right, 300);
    expect(bounds.bottom, lessThan(640));
    final close = tester.getSize(find.byType(IconButton));
    expect(close.width, greaterThanOrEqualTo(44));
    expect(close.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'reduced motion removes vertical travel and message is a live region',
    (tester) async {
      final context = await _open(tester, reducedMotion: true);
      WanpanNotice.show(context, '动态已删除');
      await tester.pump();
      expect(tester.getTopLeft(_notice).dy, 56);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_notice).dy, 56);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
