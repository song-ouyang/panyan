import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/services/friend_code.dart';
import 'package:wanpan_diary/features/profile/friend_scanner_screen.dart';

const _selfId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _friendId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
final _codec = FriendCode(shareBaseUrl: 'https://wanpan.example.com');

BarcodeCapture _capture(String rawValue) => BarcodeCapture(
  barcodes: [Barcode(rawValue: rawValue, format: BarcodeFormat.qrCode)],
);

class _ScannerPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture>.broadcast();
  final calls = <String>[];
  final options = <StartOptions>[];
  MobileScannerErrorCode? startError;
  Completer<void>? pendingStart;
  BarcodeCapture? imageCapture;
  Object? imageError;
  Completer<BarcodeCapture?>? pendingImage;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream<TorchState>.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream<double>.empty();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    calls.add('start');
    options.add(startOptions);
    await pendingStart?.future;
    if (startError case final error?) {
      throw MobileScannerException(errorCode: error);
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Widget buildCameraView() =>
      const ColoredBox(key: Key('native-camera-preview'), color: Colors.grey);

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');

  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const [],
  }) async {
    calls.add('analyze:$path');
    expect(formats, [BarcodeFormat.qrCode]);
    if (imageError case final error?) throw error;
    return pendingImage == null ? imageCapture : pendingImage!.future;
  }
}

Future<({GlobalKey<NavigatorState> navigator, List<String?> results})> _open(
  WidgetTester tester, {
  Future<XFile?> Function()? pickImage,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final navigator = GlobalKey<NavigatorState>();
  final results = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: const Scaffold(body: Text('好友列表')),
    ),
  );
  unawaited(
    navigator.currentState!
        .push<String>(
          MaterialPageRoute(
            builder: (_) => FriendScannerScreen(
              codec: _codec,
              currentUserId: _selfId.toUpperCase(),
              pickImage: pickImage,
            ),
          ),
        )
        .then(results.add),
  );
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
  return (navigator: navigator, results: results);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ScannerPlatform platform;
  late MobileScannerPlatform previousPlatform;

  setUp(() {
    MobileScannerController.resetPlatformSessionOwner();
    previousPlatform = MobileScannerPlatform.instance;
    platform = _ScannerPlatform();
    MobileScannerPlatform.instance = platform;
  });

  tearDown(() async {
    await platform.captures.close();
    MobileScannerController.resetPlatformSessionOwner();
    MobileScannerPlatform.instance = previousPlatform;
  });

  testWidgets('invalid and own QR codes keep scanning; valid ID returns once', (
    tester,
  ) async {
    final route = await _open(tester);
    expect(platform.options.single.formats, [BarcodeFormat.qrCode]);
    expect(platform.options.single.cameraDirection, CameraFacing.back);

    platform.captures.add(_capture('https://untrusted.example/$_friendId'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到完攀好友二维码，请重新对准或换张图片'), findsOneWidget);
    expect(route.results, isEmpty);

    platform.captures.add(_capture(_codec.encode(_selfId).toString()));
    await tester.pumpAndSettle();
    expect(find.text('这是你自己的好友二维码，试试扫描朋友的吧'), findsOneWidget);
    expect(route.results, isEmpty);

    final capture = _capture(_codec.encode(_friendId).toString());
    platform.captures.add(capture);
    platform.captures.add(capture);
    await tester.pumpAndSettle();
    expect(route.results, [_friendId]);
    expect(find.text('好友列表'), findsOneWidget);
    expect(platform.calls.where((call) => call == 'stop'), hasLength(1));
    expect(platform.calls.last, 'dispose');
  });

  testWidgets('permission denial explains recovery and retry starts camera', (
    tester,
  ) async {
    platform.startError = MobileScannerErrorCode.permissionDenied;
    await _open(tester);
    expect(find.text('需要相机权限'), findsOneWidget);
    expect(find.text('从相册选择二维码'), findsOneWidget);

    platform.startError = null;
    await tester.tap(find.text('重试相机'));
    await tester.pumpAndSettle();
    expect(find.text('需要相机权限'), findsNothing);
    expect(find.byKey(const Key('native-camera-preview')), findsOneWidget);
    expect(platform.calls.where((call) => call == 'start'), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('scanner as the only route delivers callback once without pop', (
    tester,
  ) async {
    final results = <String>[];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: WanpanTheme.light(),
        home: FriendScannerScreen(
          codec: _codec,
          currentUserId: _selfId,
          onScanned: results.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(navigator.currentState!.canPop(), isFalse);

    final capture = _capture(_codec.encode(_friendId).toString());
    platform.captures.add(capture);
    platform.captures.add(capture);
    await tester.pumpAndSettle();

    expect(results, [_friendId]);
    expect(find.byType(FriendScannerScreen), findsOneWidget);
    expect(platform.calls, ['start', 'stop']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('no camera still allows album recognition without overflow', (
    tester,
  ) async {
    platform.startError = MobileScannerErrorCode.unsupported;
    platform.imageCapture = _capture(_codec.encode(_friendId).toString());
    final route = await _open(
      tester,
      size: const Size(320, 568),
      textScale: 1.3,
      pickImage: () async => XFile('/tmp/friend.png'),
    );
    expect(find.text('当前设备没有可用相机'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('从相册选择二维码'));
    await tester.tap(find.text('从相册选择二维码'));
    await tester.pumpAndSettle();
    expect(route.results, [_friendId]);
    expect(platform.calls, contains('analyze:/tmp/friend.png'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('background pauses scanning and resume starts it once', (
    tester,
  ) async {
    final route = await _open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    platform.captures.add(_capture(_codec.encode(_friendId).toString()));
    await tester.pumpAndSettle();
    expect(route.results, isEmpty);
    expect(platform.calls, ['start', 'stop']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.calls, ['start', 'stop', 'start']);
    platform.captures.add(_capture(_codec.encode(_friendId).toString()));
    await tester.pumpAndSettle();
    expect(route.results, [_friendId]);
  });

  testWidgets(
    'leaving while native start is pending cleans up its late result',
    (tester) async {
      platform.pendingStart = Completer<void>();
      final route = await _open(tester, settle: false);
      await tester.pump();
      expect(platform.calls, ['start']);

      route.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      platform.pendingStart!.complete();
      await tester.pumpAndSettle();
      platform.captures.add(_capture(_codec.encode(_friendId).toString()));
      await tester.pumpAndSettle();
      expect(route.results, [null]);
      expect(platform.calls, ['start', 'stop', 'dispose']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permission lifecycle changes do not overlap native start calls',
    (tester) async {
      platform.pendingStart = Completer<void>();
      await _open(tester, settle: false);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.calls, ['start']);
      platform.pendingStart!.complete();
      await tester.pumpAndSettle();
      expect(platform.calls, ['start']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('album cancellation resumes camera and ignores stale captures', (
    tester,
  ) async {
    final image = Completer<XFile?>();
    final route = await _open(tester, pickImage: () => image.future);
    await tester.tap(find.text('从相册选择二维码'));
    await tester.pump();
    expect(platform.calls, ['start', 'stop']);
    platform.captures.add(_capture(_codec.encode(_friendId).toString()));
    await tester.pump();
    expect(route.results, isEmpty);
    image.complete(null);
    await tester.pumpAndSettle();
    expect(platform.calls, ['start', 'stop', 'start']);
    expect(route.results, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('failed album recognition can be retried', (tester) async {
    platform.imageError = StateError('Native image decode failed');
    final route = await _open(
      tester,
      pickImage: () async => XFile('/tmp/friend.png'),
    );
    await tester.tap(find.text('从相册选择二维码'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法识别这张图片，请重试或使用相机扫码'), findsOneWidget);
    expect(platform.calls, [
      'start',
      'stop',
      'analyze:/tmp/friend.png',
      'start',
    ]);

    platform.imageError = null;
    platform.imageCapture = _capture(_codec.encode(_friendId).toString());
    await tester.tap(find.text('从相册选择二维码'));
    await tester.pumpAndSettle();
    expect(route.results, [_friendId]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('album result arriving after back cannot pop another route', (
    tester,
  ) async {
    platform.pendingImage = Completer<BarcodeCapture?>();
    final route = await _open(
      tester,
      pickImage: () async => XFile('/tmp/friend.png'),
    );
    await tester.tap(find.text('从相册选择二维码'));
    await tester.pump();
    expect(platform.calls, contains('analyze:/tmp/friend.png'));

    route.navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    platform.pendingImage!.complete(
      _capture(_codec.encode(_friendId).toString()),
    );
    await tester.pumpAndSettle();
    expect(route.results, [null]);
    expect(find.text('好友列表'), findsOneWidget);
    expect(platform.calls.where((call) => call == 'start'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
