import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/features/shell/wanpan_shell.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_bottom_navigation.dart';

void main() {
  testWidgets('scrolling clears the floating tabs and preserves branch state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('increment-0')));
    await tester.pump();
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('list-0')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final lastRow = tester.getRect(find.byKey(const ValueKey('last-row-0')));
    final surface = tester.getRect(
      find.byKey(const ValueKey('wanpan-bottom-navigation-surface')),
    );
    expect(lastRow.bottom, lessThan(surface.top));
    final offset = position.pixels;

    await tester.tap(find.byKey(const ValueKey('wanpan-bottom-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('Branch 1 · 0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wanpan-bottom-tab-0')));
    await tester.pumpAndSettle();
    expect(find.text('Branch 0 · 1'), findsOneWidget);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard hides navigation and resizes nested content once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _router();
    addTearDown(router.dispose);
    final keyboard = ValueNotifier<double>(0);
    addTearDown(keyboard.dispose);
    await tester.pumpWidget(_app(router, keyboard: keyboard));
    await tester.pumpAndSettle();
    expect(find.byType(WanpanBottomNavigation), findsOneWidget);

    keyboard.value = 300;
    await tester.pumpAndSettle();
    expect(find.byType(WanpanBottomNavigation), findsNothing);
    expect(
      tester.getRect(find.byKey(const ValueKey('list-0'))).bottom,
      844 - 300,
    );
    final contentContext = tester.element(find.byKey(const ValueKey('list-0')));
    expect(MediaQuery.viewInsetsOf(contentContext).bottom, 0);
    expect(MediaQuery.paddingOf(contentContext).bottom, 0);

    keyboard.value = 0;
    await tester.pumpAndSettle();
    expect(find.byType(WanpanBottomNavigation), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('list-0'))).bottom, 844);
    expect(tester.takeException(), isNull);
  });
}

GoRouter _router() => GoRouter(
  initialLocation: '/branch/0',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => WanpanShell(navigationShell: shell),
      branches: [
        for (var index = 0; index < 4; index++)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/branch/$index',
                builder: (context, state) => _BranchPage(index: index),
              ),
            ],
          ),
      ],
    ),
  ],
);

Widget _app(GoRouter router, {ValueNotifier<double>? keyboard}) =>
    MaterialApp.router(
      theme: WanpanTheme.light(),
      routerConfig: router,
      builder: (context, child) {
        Widget withInsets(double inset) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(bottom: inset > 0 ? 0 : 34),
            viewPadding: const EdgeInsets.only(bottom: 34),
            viewInsets: EdgeInsets.only(bottom: inset),
          ),
          child: child!,
        );
        return keyboard == null
            ? withInsets(0)
            : ValueListenableBuilder<double>(
                valueListenable: keyboard,
                builder: (context, inset, _) => withInsets(inset),
              );
      },
    );

class _BranchPage extends StatefulWidget {
  const _BranchPage({required this.index});

  final int index;

  @override
  State<_BranchPage> createState() => _BranchPageState();
}

class _BranchPageState extends State<_BranchPage> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Branch ${widget.index} · $_count'),
      actions: [
        IconButton(
          key: ValueKey('increment-${widget.index}'),
          onPressed: () => setState(() => _count++),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: ListView(
      key: ValueKey('list-${widget.index}'),
      padding: EdgeInsets.only(
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        for (var row = 0; row < 24; row++)
          SizedBox(
            key: row == 23 ? ValueKey('last-row-${widget.index}') : null,
            height: 64,
            child: Text('Row $row'),
          ),
      ],
    ),
  );
}
