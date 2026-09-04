import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_milestone_stage.dart';

import '../tool/motion_preview_main.dart';

void main() {
  testWidgets('lab exposes four scenes and can reconfigure milestone grades', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MotionPreviewApp(configuredMilestoneGrades: 'V2,V4,V7'),
    );

    expect(find.text('完攀'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('里程碑'), findsOneWidget);
    expect(find.text('榜单'), findsOneWidget);

    await tester.tap(find.text('里程碑'));
    await tester.pumpAndSettle();

    expect(find.byType(WanpanMilestoneStage), findsOneWidget);
    expect(
      tester
          .widget<WanpanMilestoneStage>(find.byType(WanpanMilestoneStage))
          .grades,
      ['V2', 'V4', 'V7'],
    );
    expect(find.text('V2 → V4 → V7'), findsOneWidget);

    await tester.tap(find.byKey(const Key('milestone-grade-config-button')));
    await tester.pumpAndSettle();
    expect(find.text('配置里程碑等级'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('milestone-grade-config-field')),
      'V3, V5, V6',
    );
    await tester.tap(find.text('应用并重播'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<WanpanMilestoneStage>(find.byType(WanpanMilestoneStage))
          .grades,
      ['V3', 'V5', 'V6'],
    );
    expect(find.text('V3 → V5 → V6'), findsOneWidget);
  });

  testWidgets('lab grade editor rejects unsupported values', (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MotionPreviewApp());
    await tester.tap(find.text('里程碑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('milestone-grade-config-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('milestone-grade-config-field')),
      'V2, V18, V4',
    );
    await tester.tap(find.text('应用并重播'));
    await tester.pump();

    expect(find.text('仅支持 V0–V17，且不要重复'), findsOneWidget);
  });
}
