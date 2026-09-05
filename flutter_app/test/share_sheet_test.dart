import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/models/profile_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/share_repository.dart';
import 'package:wanpan_diary/core/services/share_service.dart';
import 'package:wanpan_diary/features/sharing/share_sheet.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

const monthPreview = SharePreview(
  title: '2026 年 8 月攀岩记录',
  summary: '3 天攀岩 · 完攀 8 条 · 最高 V4',
  month: '2026-08',
);

final populatedMonth = MonthDashboard(
  month: '2026-08',
  days: [
    MonthlyDayStat(
      day: DateTime(2026, 8, 4),
      gymName: '岩馆甲',
      grade: 'V1',
      sends: 1,
    ),
    MonthlyDayStat(
      day: DateTime(2026, 8, 4),
      gymName: '岩馆乙',
      grade: 'V2',
      sends: 2,
    ),
    MonthlyDayStat(
      day: DateTime(2026, 8, 7),
      gymName: '岩馆甲',
      grade: 'V4',
      sends: 1,
    ),
    MonthlyDayStat(
      day: DateTime(2026, 8, 13),
      gymName: '岩馆甲',
      grade: 'V3',
      sends: 4,
    ),
    MonthlyDayStat(
      day: DateTime(2026, 8, 14),
      gymName: '岩馆甲',
      grade: 'V3',
      sends: 0,
    ),
    MonthlyDayStat(
      day: DateTime(2026, 7, 4),
      gymName: '岩馆甲',
      grade: 'V1',
      sends: 20,
    ),
    MonthlyDayStat(
      day: DateTime(2025, 8, 4),
      gymName: '岩馆甲',
      grade: 'V1',
      sends: 30,
    ),
    const MonthlyDayStat(day: null, gymName: '岩馆甲', grade: 'V1', sends: 40),
  ],
  byGrade: const [
    GradeSummary(grade: 'V1', sends: 1),
    GradeSummary(grade: 'V2', sends: 2),
    GradeSummary(grade: 'V3', sends: 4),
    GradeSummary(grade: 'V4', sends: 1),
  ],
  byGym: const [],
  summary: const MonthlySummary(
    climbingDays: 3,
    sends: 8,
    gyms: 2,
    maxGrade: 4,
    flashes: 1,
    videos: 2,
  ),
);

const emptyMonth = MonthDashboard(
  month: '2026-08',
  days: [],
  byGrade: [],
  byGym: [],
  summary: MonthlySummary(
    climbingDays: 0,
    sends: 0,
    gyms: 0,
    maxGrade: 0,
    flashes: 0,
    videos: 0,
  ),
);

void main() {
  late _Repository repository;
  late _Service service;

  setUp(() {
    repository = _Repository();
    service = _Service();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    SharePreview preview = monthPreview,
    Size size = const Size(430, 932),
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWanpanShareSheet(
                context: context,
                preview: preview,
                repository: repository,
                service: service,
              ),
              child: const Text('打开分享'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开分享'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  // RepaintBoundary rasterization runs outside the widget test's fake clock.
  // Pump frames and permit real raster work until the native bridge is reached.
  Future<void> waitForImageShare(WidgetTester tester, int expectedCalls) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (service.images.length >= expectedCalls) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(service.images, hasLength(expectedCalls));
  }

  Future<void> shareImage(WidgetTester tester, {int expectedCalls = 1}) async {
    await tester.tap(find.text('分享给朋友'));
    await waitForImageShare(tester, expectedCalls);
    await tester.pumpAndSettle();
  }

  void expectNoMonthlyPublication() {
    expect(repository.lookups, isEmpty);
    expect(repository.creates, isEmpty);
    expect(repository.revoked, isEmpty);
    expect(service.shared, isEmpty);
    expect(service.copied, isEmpty);
    expect(service.previewed, isEmpty);
  }

  void expectStat(String label, String value) {
    final stat = find
        .ancestor(of: find.text(label), matching: find.byType(Column))
        .first;
    expect(
      find.descendant(of: stat, matching: find.text(value)),
      findsOneWidget,
    );
  }

  testWidgets('opening a month shows a local poster with one share action', (
    tester,
  ) async {
    await pumpSheet(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('分享预览'), findsOneWidget);
    expect(find.byKey(const Key('monthly-share-poster')), findsOneWidget);
    expect(find.text(monthPreview.title), findsOneWidget);
    expect(find.text(monthPreview.summary), findsOneWidget);
    expect(find.byTooltip('关闭分享'), findsOneWidget);
    expect(find.text('分享给朋友'), findsOneWidget);
    for (final oldAction in ['停止分享', '复制链接', '预览分享页']) {
      expect(find.text(oldAction), findsNothing);
    }
    expect(find.textContaining('昵称、头像'), findsNothing);
    expect(find.textContaining('分享已开启'), findsNothing);
    expect(find.textContaining('朋友无需登录'), findsNothing);
    expect(service.images, isEmpty);
    expectNoMonthlyPublication();
  });

  testWidgets(
    'poster contains selected month statistics and aggregates dates',
    (tester) async {
      await pumpSheet(tester, preview: SharePreview.monthly(populatedMonth));
      expectStat('攀爬天数', '3');
      expectStat('完成线路', '8');
      expectStat('最高难度', 'V4');
      // 1×15 + 2×20 + 4×25 + 1×30, plus 5 for one flash.
      expectStat('积分', '190');
      expect(find.text('视频记录'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '4 日，完攀 3 条',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '7 日，完攀 1 条',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '13 日，完攀 4 条',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == '14 日',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              RegExp(r'完攀 (20|30|40|53) 条')
                  .hasMatch(widget.properties.label ?? ''),
        ),
        findsNothing,
      );
      expect(find.textContaining('岩馆甲'), findsNothing);
      expect(find.textContaining('岩馆乙'), findsNothing);
      expectNoMonthlyPublication();
    },
  );

  testWidgets(
    'sharing exports the actual poster PNG with a valid native anchor',
    (tester) async {
      await pumpSheet(tester, preview: SharePreview.monthly(populatedMonth));
      await shareImage(tester);
      final image = service.images.single;
      expect(image.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final header = ByteData.sublistView(image.bytes);
      expect(header.getUint32(16), 1080);
      expect(header.getUint32(20), 1680);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(image.bytes);
        try {
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 1080);
          expect(frame.image.height, 1680);
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      });
      expect(image.fileName, 'wanpan-month-2026-08.png');
      expect(image.title, '2026 年 8 月攀岩记录 | 完攀日记');
      expect(image.origin.width, greaterThan(44));
      expect(image.origin.height, greaterThanOrEqualTo(44));
      expect(image.origin.left, greaterThanOrEqualTo(0));
      expect(image.origin.right, lessThanOrEqualTo(430));
      expect(image.origin.top, greaterThanOrEqualTo(0));
      expect(image.origin.bottom, lessThanOrEqualTo(932));
      expect(find.text('已取消发送，可以随时再次分享'), findsOneWidget);
      expect(find.byKey(const Key('monthly-share-poster')), findsOneWidget);
      expectNoMonthlyPublication();
    },
  );

  testWidgets(
    'success reports native handoff and the poster remains available',
    (tester) async {
      service.result = ShareResultStatus.success;
      await pumpSheet(tester);
      await shareImage(tester);
      expect(find.text('已交给所选应用分享'), findsOneWidget);
      expect(find.byKey(const Key('monthly-share-poster')), findsOneWidget);
      expectNoMonthlyPublication();
    },
  );

  testWidgets('native unavailable and failure allow another image share', (
    tester,
  ) async {
    service.result = ShareResultStatus.unavailable;
    await pumpSheet(tester);
    await shareImage(tester);
    expect(find.text('暂时无法打开分享，请重试'), findsOneWidget);
    service.failShare = true;
    await shareImage(tester, expectedCalls: 2);
    expect(find.text('暂时没能分享，请重试'), findsOneWidget);
    expect(find.text('已交给所选应用分享'), findsNothing);
    service.failShare = false;
    service.result = ShareResultStatus.success;
    await shareImage(tester, expectedCalls: 3);
    expect(find.text('已交给所选应用分享'), findsOneWidget);
    expect(find.text('暂时没能分享，请重试'), findsNothing);
    expectNoMonthlyPublication();
  });

  testWidgets(
    'pending native share prevents duplicate requests and late updates',
    (tester) async {
      service.pendingShare = Completer<ShareResultStatus>();
      await pumpSheet(tester);
      await tester.tap(find.text('分享给朋友'));
      await waitForImageShare(tester, 1);
      expect(
        tester.widget<WanpanButton>(find.byType(WanpanButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('分享给朋友'));
      await tester.pump();
      expect(service.images, hasLength(1));
      await tester.tap(find.byTooltip('关闭分享'));
      await tester.pumpAndSettle();
      service.pendingShare!.complete(ShareResultStatus.success);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('已交给所选应用分享'), findsNothing);
      expect(service.images, hasLength(1));
      expectNoMonthlyPublication();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing before the next frame prevents a late native image share',
    (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text('分享给朋友'));
      // Closing starts the dialog's exit transition; rendering may finish while
      // the dialog is still mounted, before that transition disposes it.
      await tester.tap(find.byTooltip('关闭分享'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(service.images, isEmpty);
      expectNoMonthlyPublication();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty month fits compact large text without inventing V0', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      preview: SharePreview.monthly(emptyMonth),
      size: const Size(320, 568),
      scale: 1.3,
    );
    expect(find.textContaining('这个月还没有完攀记录'), findsOneWidget);
    expectStat('攀爬天数', '0');
    expectStat('完成线路', '0');
    expectStat('最高难度', '--');
    expectStat('积分', '0');
    expect(find.textContaining('V0'), findsNothing);
    expect(tester.takeException(), isNull);
    await shareImage(tester);
    expect(service.images.single.origin.bottom, lessThanOrEqualTo(568));
    expect(service.images.single.origin.right, lessThanOrEqualTo(320));
    expect(find.text('已取消发送，可以随时再次分享'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectNoMonthlyPublication();
  });

  testWidgets(
    'route still supports native URL sharing, copy, and web preview',
    (tester) async {
      await pumpSheet(
        tester,
        preview: SharePreview.route(
          const ClimbingRoute(
            id: 'route-1',
            gymId: 'gym-1',
            name: '一条名字很长但值得试试的抱石线路',
            grade: 'V4',
            color: '黄色',
            published: true,
            gymName: '这是一个名字很长的攀岩馆',
          ),
        ),
        size: const Size(320, 568),
        scale: 1.3,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tap(tester, '分享给朋友');
      await tap(tester, '复制链接');
      await tap(tester, '预览分享页');
      expect(service.shared.single.path, '/share/route/route-1');
      expect(service.copied.single, service.shared.single);
      expect(service.previewed.single, service.shared.single);
      expect(service.origin!.width, greaterThan(44));
      expect(service.origin!.height, greaterThanOrEqualTo(44));
      expect(repository.lookups, isEmpty);
      expect(repository.creates, isEmpty);
      expect(repository.revoked, isEmpty);
      expect(service.images, isEmpty);
      expect(find.text('停止分享'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Repository extends ShareRepository {
  _Repository()
    : super(
        ApiClient(
          config: const AppConfig(
            environment: AppEnvironment.production,
            apiBaseUrl: 'https://example.com/api',
            enableDevelopmentLogin: false,
          ),
          accessTokenProvider: () => 'token',
        ),
      );
  final lookups = <String>[];
  final creates = <String>[];
  final revoked = <String>[];

  @override
  Future<String?> getMonthlyToken(String month) async {
    lookups.add(month);
    return null;
  }

  @override
  Future<String> createMonthlyShare(String month) async {
    creates.add(month);
    return 'unexpected-publication';
  }

  @override
  Future<void> revokeMonthlyShare(String token) async => revoked.add(token);
}

class _ImageShare {
  const _ImageShare({
    required this.bytes,
    required this.title,
    required this.fileName,
    required this.origin,
  });
  final Uint8List bytes;
  final String title;
  final String fileName;
  final Rect origin;
}

class _Service extends ShareService {
  final shared = <Uri>[];
  final copied = <Uri>[];
  final previewed = <Uri>[];
  final images = <_ImageShare>[];
  Rect? origin;
  bool failShare = false;
  ShareResultStatus result = ShareResultStatus.dismissed;
  Completer<ShareResultStatus>? pendingShare;

  @override
  Future<ShareResultStatus> shareImage({
    required Uint8List bytes,
    required String title,
    required String fileName,
    required Rect origin,
  }) async {
    images.add(
      _ImageShare(
        bytes: bytes,
        title: title,
        fileName: fileName,
        origin: origin,
      ),
    );
    if (failShare) throw StateError('native share unavailable');
    if (pendingShare != null) return pendingShare!.future;
    return result;
  }

  @override
  Future<ShareResultStatus> share({
    required Uri url,
    required String title,
    required Rect origin,
  }) async {
    if (failShare) throw StateError('native share unavailable');
    shared.add(url);
    this.origin = origin;
    return result;
  }

  @override
  Future<void> copy(Uri url) async => copied.add(url);
  @override
  Future<void> preview(Uri url) async => previewed.add(url);
}
