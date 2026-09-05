import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wanpan_diary/core/services/share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const service = ShareService();
  const origin = Rect.fromLTWH(20, 480, 280, 60);
  final url = Uri.parse('https://example.com/share/route/1');
  final imageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aP9sAAAAASUVORK5CYII=',
  );
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('wanpan-share-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
          expect(call.method, 'getTemporaryDirectory');
          return temporaryDirectory.path;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'native share receives the URL, title and actual iPad anchor rectangle',
    () async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (value) async {
            call = value;
            return 'com.example.target';
          });
      expect(
        await service.share(url: url, title: '线路 | 完攀日记', origin: origin),
        ShareResultStatus.success,
      );
      expect(call!.method, 'share');
      expect(call!.arguments, {
        'uri': '$url',
        'title': '线路 | 完攀日记',
        'subject': '线路 | 完攀日记',
        'originX': 20.0,
        'originY': 480.0,
        'originWidth': 280.0,
        'originHeight': 60.0,
      });
    },
  );

  test(
    'cancelled and unavailable results stay distinct from success',
    () async {
      for (final entry in {
        '': ShareResultStatus.dismissed,
        'dev.fluttercommunity.plus/share/unavailable':
            ShareResultStatus.unavailable,
      }.entries) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => entry.key);
        expect(
          await service.share(url: url, title: '线路', origin: origin),
          entry.value,
        );
      }
    },
  );

  test(
    'native image share receives the PNG, readable filename and iPad anchor',
    () async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (value) async {
            call = value;
            return 'com.example.target';
          });

      expect(
        await service.shareImage(
          bytes: imageBytes,
          title: '2026 年 9 月攀岩记录',
          fileName: 'wanpan-2026-09.png',
          origin: origin,
        ),
        ShareResultStatus.success,
      );
      expect(call!.method, 'share');
      final arguments = Map<String, dynamic>.from(call!.arguments as Map);
      final imagePath = (arguments['paths'] as List).single as String;
      expect(imagePath, endsWith('/wanpan-2026-09.png'));
      expect(await File(imagePath).readAsBytes(), imageBytes);
      expect(arguments, {
        'title': '2026 年 9 月攀岩记录',
        'subject': '2026 年 9 月攀岩记录',
        'paths': [imagePath],
        'mimeTypes': ['image/png'],
        'originX': 20.0,
        'originY': 480.0,
        'originWidth': 280.0,
        'originHeight': 60.0,
      });
    },
  );

  test('image sharing preserves dismissal and unavailable results', () async {
    for (final entry in {
      '': ShareResultStatus.dismissed,
      'dev.fluttercommunity.plus/share/unavailable':
          ShareResultStatus.unavailable,
    }.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => entry.key);
      expect(
        await service.shareImage(
          bytes: imageBytes,
          title: '月度攀岩记录',
          fileName: 'wanpan-2026-09.png',
          origin: origin,
        ),
        entry.value,
      );
    }
  });

  test('image sharing reports a native failure to the caller', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'share_failed');
        });
    await expectLater(
      service.shareImage(
        bytes: imageBytes,
        title: '月度攀岩记录',
        fileName: 'wanpan-2026-09.png',
        origin: origin,
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'share_failed',
        ),
      ),
    );
  });

  test('copy places only the share link on the clipboard', () async {
    MethodCall? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          copied = call;
          return null;
        });
    await service.copy(url);
    expect(copied!.method, 'Clipboard.setData');
    expect(copied!.arguments, {'text': '$url'});
  });
}
