import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wanpan_diary/core/services/share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  const service = ShareService();
  const origin = Rect.fromLTWH(20, 480, 280, 60);
  final url = Uri.parse('https://example.com/share/route/1');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
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
