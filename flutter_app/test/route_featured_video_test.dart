import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/models/feed_models.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/features/gyms/route_screen.dart';

void main() {
  testWidgets('线路详情直接展示作者可见的首条完攀视频', (tester) async {
    var openedProfile = false;
    const post = FeedPost(
      id: 'send-1',
      user: UserSummary(id: 'user-1', nickname: '小欧'),
      attempts: 1,
      videoUrl: 'https://example.com/send.mp4',
      imageUrls: [],
      caption: '第一次完攀，最后一步终于稳住了！',
      visibility: 'private',
      moderationStatus: 'pending',
      likeCount: 3,
      commentCount: 1,
      liked: false,
      comments: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RouteFeaturedVideo(
              post: post,
              onOpenProfile: () => openedProfile = true,
              videoBuilder: (_, url) => SizedBox(
                key: const Key('inline-route-video'),
                height: 180,
                child: Text(url),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('inline-route-video')), findsOneWidget);
    expect(find.text('首条完攀 · 尝试 1 次 · 仅自己可见'), findsOneWidget);
    expect(find.text('内容处理中'), findsOneWidget);
    expect(find.text('第一次完攀，最后一步终于稳住了！'), findsOneWidget);

    await tester.tap(find.byType(CircleAvatar));
    await tester.pump();
    expect(openedProfile, isTrue);
  });
}
