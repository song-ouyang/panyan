import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_bottom_navigation.dart';

void main() {
  testWidgets('renders four friendly tabs and reports selection', (
    tester,
  ) async {
    var selected = 2;

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: WanpanBottomNavigation(
              currentIndex: selected,
              onSelected: (index) => setState(() => selected = index),
            ),
          ),
        ),
      ),
    );

    const labels = ['岩馆', '广场', '排行', '我的'];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(WanpanTabIcon), findsNWidgets(4));

    final rankingSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey('wanpan-bottom-tab-2')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(rankingSemantics.properties.selected, isTrue);

    await tester.tap(find.text('广场'));
    await tester.pumpAndSettle();
    expect(selected, 1);

    final feedSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey('wanpan-bottom-tab-1')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(feedSemantics.properties.selected, isTrue);
    expect(rankingSemantics.properties.onTap, isNotNull);
    rankingSemantics.properties.onTap!();
    await tester.pumpAndSettle();
    expect(selected, 2);
    for (var index = 0; index < labels.length; index++) {
      await tester.tap(find.text(labels[index]));
      await tester.pumpAndSettle();
      expect(selected, index);
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(ValueKey('wanpan-bottom-tab-$index')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.label, labels[index]);
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.selected, isTrue);
      expect(semantics.properties.onTap, isNotNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the tab bar inside compact iPhone safe areas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(bottom: 20),
            viewPadding: const EdgeInsets.only(bottom: 20),
            textScaler: const TextScaler.linear(2.5),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: WanpanBottomNavigation(
            currentIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    final navigation = tester.getRect(find.byType(WanpanBottomNavigation));
    expect(navigation.left, 0);
    expect(navigation.right, 320);
    expect(navigation.bottom, 568);
    expect(navigation.height, greaterThanOrEqualTo(92));
    final surface = tester.getRect(
      find.byKey(const ValueKey('wanpan-bottom-navigation-surface')),
    );
    expect(surface.left, 18);
    expect(surface.right, 302);
    expect(surface.bottom, 548);
    for (var index = 0; index < 4; index++) {
      final tabFinder = find.byKey(ValueKey('wanpan-bottom-tab-$index'));
      final tab = tester.getRect(tabFinder);
      expect(tab.width, greaterThanOrEqualTo(44));
      expect(tab.height, greaterThanOrEqualTo(44));
      final textFinder = find.descendant(
        of: tabFinder,
        matching: find.byType(Text),
      );
      final paragraph = tester.renderObject<RenderParagraph>(textFinder);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width),
      );
      final textRect = tester.getRect(textFinder);
      expect(textRect.top, greaterThanOrEqualTo(tab.top));
      expect(textRect.bottom, lessThanOrEqualTo(tab.bottom));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('respects side safe areas and floats above a flat bottom edge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(left: 44, right: 34),
            viewPadding: const EdgeInsets.only(left: 44, right: 34),
          ),
          child: child!,
        ),
        home: Scaffold(
          bottomNavigationBar: WanpanBottomNavigation(
            currentIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    final surface = tester.getRect(
      find.byKey(const ValueKey('wanpan-bottom-navigation-surface')),
    );
    expect(surface.left, 44);
    expect(surface.right, 666);
    expect(surface.bottom, 308);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid switching stays responsive with reduced motion', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: WanpanBottomNavigation(
              currentIndex: selected,
              onSelected: (index) => setState(() => selected = index),
            ),
          ),
        ),
      ),
    );
    for (final index in [1, 3, 0, 2, 1]) {
      await tester.tap(find.byKey(ValueKey('wanpan-bottom-tab-$index')));
      await tester.pump(const Duration(milliseconds: 16));
      expect(selected, index);
    }
    await tester.pumpAndSettle();
    final selectedTab = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey('wanpan-bottom-tab-1')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(selectedTab.properties.selected, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab animation does not repaint the unchanged page beneath it', (
    tester,
  ) async {
    var selected = 0;
    var pagePaints = 0;
    final page = CustomPaint(
      painter: _PagePaintCounter(() => pagePaints++),
      child: const SizedBox.expand(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            extendBody: true,
            body: page,
            bottomNavigationBar: WanpanBottomNavigation(
              currentIndex: selected,
              onSelected: (index) => setState(() => selected = index),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pagePaints, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('wanpan-bottom-tab-3')));
    await tester.pump();
    expect(selected, 3);
    final paintsAfterSelection = pagePaints;
    for (var frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pagePaints, paintsAfterSelection);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid reversal stays continuous and lands on the tab in LTR and RTL',
    (tester) async {
      for (final direction in TextDirection.values) {
        var selected = 0;
        final selections = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(direction),
            theme: WanpanTheme.light(),
            builder: (context, child) =>
                Directionality(textDirection: direction, child: child!),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                bottomNavigationBar: WanpanBottomNavigation(
                  currentIndex: selected,
                  onSelected: (index) {
                    selections.add(index);
                    setState(() => selected = index);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final indicator = find.byKey(
          const ValueKey('wanpan-bottom-navigation-selection'),
        );
        Rect tabRect(int index) =>
            tester.getRect(find.byKey(ValueKey('wanpan-bottom-tab-$index')));
        expect(tester.getRect(indicator).center.dx, tabRect(0).center.dx);

        for (final index in [3, 0, 2, 1]) {
          final beforeTap = tester.getRect(indicator);
          await tester.tap(find.byKey(ValueKey('wanpan-bottom-tab-$index')));
          expect(selected, index);
          await tester.pump();
          expect(
            tester.getRect(indicator).center.dx,
            closeTo(beforeTap.center.dx, .01),
            reason: 'A redirected animation must continue from its visible position.',
          );
          await tester.pump(const Duration(milliseconds: 32));
          final position = tester.getRect(indicator).center.dx;
          final target = tabRect(index).center.dx;
          expect(
            (target - position).abs(),
            lessThan((target - beforeTap.center.dx).abs()),
            reason: 'The indicator should immediately move toward the selected tab.',
          );
        }
        await tester.pumpAndSettle();
        expect(selections, [3, 0, 2, 1]);
        expect(
          tester.getRect(indicator).center.dx,
          closeTo(tabRect(1).center.dx, .01),
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

class _PagePaintCounter extends CustomPainter {
  const _PagePaintCounter(this.onPaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PagePaintCounter oldDelegate) => false;
}
