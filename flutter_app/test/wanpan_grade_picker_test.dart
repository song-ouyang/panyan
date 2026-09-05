import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_grade_picker.dart';

Future<void> _pumpPicker(
  WidgetTester tester, {
  String initialValue = 'V2',
  ValueChanged<String>? onChanged,
  bool disabled = false,
  MediaQueryData? mediaQuery,
}) async {
  var value = initialValue;
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: mediaQuery == null
          ? null
          : (context, child) => MediaQuery(data: mediaQuery, child: child!),
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: WanpanGradePicker(
                value: value,
                onChanged: disabled
                    ? null
                    : (grade) {
                        setState(() => value = grade);
                        onChanged?.call(grade);
                      },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byType(WanpanGradePicker));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'initial sheet offers V0 through V10 and keeps higher grades hidden',
    (tester) async {
      await _pumpPicker(tester);
      await _openPicker(tester);

      expect(find.text('选择难度'), findsOneWidget);
      for (var index = 0; index <= 10; index++) {
        expect(find.byKey(Key('wanpan-grade-V$index')), findsOneWidget);
        final size = tester.getSize(find.byKey(Key('wanpan-grade-V$index')));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(find.text('更多'), findsOneWidget);
      for (var index = 11; index <= 17; index++) {
        expect(find.text('V$index'), findsNothing);
      }
    },
  );

  testWidgets(
    'more reveals V17, selection closes and reopening shows current grade',
    (tester) async {
      String? selected;
      await _pumpPicker(tester, onChanged: (grade) => selected = grade);
      await _openPicker(tester);
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      final highest = find.byKey(const Key('wanpan-grade-V17'));
      await tester.ensureVisible(highest);
      await tester.tap(highest);
      await tester.pumpAndSettle();

      expect(selected, 'V17');
      expect(find.text('选择难度'), findsNothing);
      expect(find.text('V17'), findsOneWidget);

      await _openPicker(tester);
      expect(find.text('更多'), findsNothing);
      expect(highest.hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('wanpan-grade-V3')));
      await tester.pumpAndSettle();
      expect(selected, 'V3');
      await _openPicker(tester);
      expect(find.text('更多'), findsOneWidget);
      expect(highest, findsNothing);
    },
  );

  testWidgets('dismissing preserves the current grade', (tester) async {
    var changed = false;
    await _pumpPicker(tester, onChanged: (_) => changed = true);
    await _openPicker(tester);
    await tester.tap(find.byTooltip('关闭难度选择'));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    expect(find.text('V2'), findsOneWidget);
    expect(find.text('选择难度'), findsNothing);
  });

  testWidgets('disabled picker does not open', (tester) async {
    await _pumpPicker(tester, disabled: true);
    await tester.tap(find.byType(WanpanGradePicker));
    await tester.pumpAndSettle();
    expect(find.text('选择难度'), findsNothing);
    expect(find.text('V2'), findsOneWidget);
  });

  testWidgets(
    'compact screen with keyboard and large text can select advanced grades',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? selected;
      await _pumpPicker(
        tester,
        initialValue: 'V17',
        onChanged: (grade) => selected = grade,
        mediaQuery: const MediaQueryData(
          size: Size(320, 568),
          padding: EdgeInsets.only(top: 20, bottom: 24),
          viewInsets: EdgeInsets.only(bottom: 180),
          textScaler: TextScaler.linear(1.8),
          disableAnimations: true,
        ),
      );
      await _openPicker(tester);
      expect(tester.takeException(), isNull);
      final highest = find.byKey(const Key('wanpan-grade-V17'));
      expect(highest.hitTestable(), findsOneWidget);
      await tester.tap(highest);
      await tester.pumpAndSettle();
      expect(selected, 'V17');
      expect(find.text('选择难度'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
