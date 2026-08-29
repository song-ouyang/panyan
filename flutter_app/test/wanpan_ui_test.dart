import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/splash/splash_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

void main() {
  testWidgets('primary button exposes its label and handles a tap', (
    tester,
  ) async {
    var pressed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: Scaffold(
          body: WanpanButton(label: '进入完攀日记', onPressed: () => pressed = true),
        ),
      ),
    );

    expect(find.text('进入完攀日记'), findsOneWidget);
    await tester.tap(find.text('进入完攀日记'));
    await tester.pump();
    expect(pressed, isTrue);
  });

  testWidgets('disabled button does not trigger its action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: const Scaffold(
          body: WanpanButton(label: '正在上传', onPressed: null),
        ),
      ),
    );

    await tester.tap(find.text('正在上传'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final device in const [
    (size: Size(320, 568), padding: EdgeInsets.only(top: 20)),
    (size: Size(390, 844), padding: EdgeInsets.only(top: 47, bottom: 34)),
    (size: Size(430, 932), padding: EdgeInsets.only(top: 59, bottom: 34)),
  ]) {
    testWidgets('splash content stays on-screen at '
        '${device.size.width}x${device.size.height}', (tester) async {
      final size = device.size;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final session = SessionController(
        preferences: preferences,
        config: const AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: 'http://127.0.0.1:3000/api',
          enableDevelopmentLogin: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WanpanTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: device.padding,
              viewPadding: device.padding,
              textScaler: const TextScaler.linear(1.35),
            ),
            child: child!,
          ),
          home: SplashScreen(session: session, onContinue: () {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final hero = tester.getRect(find.byKey(const Key('splash-hero')));
      final actions = tester.getRect(find.byKey(const Key('splash-actions')));
      final button = tester.getRect(find.byType(WanpanButton));
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('splash-hero')),
          matching: find.byType(Image),
        ),
      );

      expect(hero.left, greaterThanOrEqualTo(0));
      expect(hero.right, lessThanOrEqualTo(size.width));
      expect(hero.top, greaterThanOrEqualTo(device.padding.top));
      expect(actions.left, greaterThanOrEqualTo(0));
      expect(actions.right, lessThanOrEqualTo(size.width));
      expect(
        actions.bottom,
        lessThanOrEqualTo(size.height - device.padding.bottom),
      );
      expect(button.height, greaterThanOrEqualTo(52));
      expect(image.fit, BoxFit.contain);
      expect(tester.takeException(), isNull);
    });
  }
}
