import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/services/video_cover_cache.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_video_cover.dart';

final _image = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aP9sAAAAASUVORK5CYII=',
);

Widget _app(
  VideoCoverCache cache, {
  String url = 'https://example.com/a.mp4',
}) => MaterialApp(
  theme: WanpanTheme.light(),
  home: Scaffold(
    body: WanpanVideoCover(url: url, cache: cache),
  ),
);

void main() {
  testWidgets('视频封面从加载状态变为真实图片，并保留播放提示', (tester) async {
    final pending = Completer<Uint8List?>();
    await tester.pumpWidget(
      _app(VideoCoverCache(loader: (_) => pending.future)),
    );
    expect(find.text('封面加载中…'), findsOneWidget);

    pending.complete(_image);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-cover-image')), findsOneWidget);
    expect(find.text('封面加载中…'), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('提帧失败时保留可点击的视频入口', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            onTap: () => opened = true,
            child: WanpanVideoCover(
              url: 'https://example.com/unavailable.mp4',
              cache: VideoCoverCache(loader: (_) => Future.error(Exception())),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('点击查看完攀视频'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('视频切换后不显示上一条迟到的封面', (tester) async {
    final first = Completer<Uint8List?>();
    final second = Completer<Uint8List?>();
    final cache = VideoCoverCache(
      loader: (url) => url.endsWith('a.mp4') ? first.future : second.future,
    );
    await tester.pumpWidget(_app(cache));
    await tester.pumpWidget(_app(cache, url: 'https://example.com/b.mp4'));
    first.complete(_image);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-cover-image')), findsNothing);
    expect(find.text('封面加载中…'), findsOneWidget);

    second.complete(_image);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-cover-image')), findsOneWidget);
  });

  testWidgets('封面超时后仍可打开视频，组件销毁后不会更新页面', (tester) async {
    final pending = Completer<Uint8List?>();
    await tester.pumpWidget(
      _app(VideoCoverCache(loader: (_) => pending.future)),
    );
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(find.text('点击查看完攀视频'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete(_image);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
