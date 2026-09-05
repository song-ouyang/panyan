import 'package:flutter/material.dart';
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

    for (final label in const ['岩馆', '广场', '排行', '我的']) {
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
    for (var index = 0; index < 4; index++) {
      final tab = tester.getRect(
        find.byKey(ValueKey('wanpan-bottom-tab-$index')),
      );
      expect(tab.width, greaterThanOrEqualTo(44));
      expect(tab.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
  });
}
