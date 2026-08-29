import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/models/feed_models.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/models/route_submission_models.dart';

void main() {
  test('parses a gym directory item returned by PostgreSQL', () {
    final item = GymDirectoryItem.fromJson({
      'city': '成都',
      'brand_id': 'brand-1',
      'brand_name': '香蕉攀岩',
      'store_count': '3',
      'route_count': '48',
      'verified': true,
    });

    expect(item.brandName, '香蕉攀岩');
    expect(item.storeCount, 3);
    expect(item.routeCount, 48);
    expect(item.verified, isTrue);
  });

  test('parses a route leaderboard with completion count', () {
    final board = RouteLeaderboard.fromJson({
      'completionCount': 1,
      'items': [
        {
          'rank': 1,
          'id': 'send-1',
          'user_id': 'user-1',
          'nickname': '岩友小欧',
          'attempts': 2,
          'image_urls': <String>[],
          'like_count': 12,
          'comment_count': 1,
          'liked': true,
          'comments': <Object>[],
        },
      ],
    });

    expect(board.completionCount, 1);
    expect(board.items.single.rank, 1);
    expect(board.items.single.post.user?.nickname, '岩友小欧');
    expect(board.items.single.post.likeCount, 12);
  });

  test('parses a visible featured video embedded in route detail', () {
    final route = ClimbingRoute.fromJson({
      'id': 'route-1',
      'gym_id': 'gym-1',
      'name': '橙色动态线',
      'grade': 'V3',
      'color': '橙',
      'published': true,
      'featuredSend': {
        'id': 'send-1',
        'user_id': 'user-1',
        'nickname': '小欧',
        'attempts': 1,
        'video_url': 'https://example.com/send.mp4',
        'image_urls': <String>[],
        'caption': '第一次完攀',
        'visibility': 'private',
        'moderation_status': 'pending',
        'like_count': 0,
        'comment_count': 0,
        'liked': false,
        'comments': <Object>[],
      },
    });

    expect(route.featuredSend?.videoUrl, 'https://example.com/send.mp4');
    expect(route.featuredSend?.visibility, 'private');
    expect(route.featuredSend?.moderationStatus, 'pending');
    expect(route.featuredSend?.user?.nickname, '小欧');
  });

  test('serializes a route submission with normalized points', () {
    const draft = RouteSubmissionDraft(
      clientRequestId: '11111111-2222-4333-8444-555555555555',
      gymId: 'gym-1',
      name: '  珊瑚橙线  ',
      grade: 'V3',
      color: '  橙  ',
      coverUrl: 'https://example.com/route.jpg',
      wallZone: '  ',
      videoUrl: '  https://example.com/send.mov  ',
      caption: '  第一次完攀  ',
      visibility: 'friends',
      points: [
        RoutePoint(x: .18, y: .82, type: RoutePointType.start),
        RoutePoint(x: .72, y: .12, type: RoutePointType.finish),
      ],
    );

    final json = draft.toJson();
    expect(json['clientRequestId'], '11111111-2222-4333-8444-555555555555');
    expect(json['name'], '珊瑚橙线');
    expect(json['color'], '橙');
    expect(json.containsKey('wallZone'), isFalse);
    expect(json['routeSetId'], isNull);
    expect(json['videoUrl'], 'https://example.com/send.mov');
    expect(json['caption'], '第一次完攀');
    expect(json['visibility'], 'friends');
    expect(json['points'], [
      {'x': .18, 'y': .82, 'type': 'start'},
      {'x': .72, 'y': .12, 'type': 'finish'},
    ]);
  });

  test('parses feed visibility for square and friends views', () {
    final post = FeedPost.fromJson({
      'id': 'send-friends',
      'attempts': 1,
      'image_urls': <String>[],
      'visibility': 'friends',
      'like_count': 0,
      'comment_count': 0,
      'liked': false,
      'comments': <Object>[],
    });

    expect(post.visibility, 'friends');
    expect(post.isMoment, isTrue);
  });

  test('parses a published route submission destination', () {
    final submission = RouteSubmission.fromJson({
      'id': 'submission-1',
      'submitter_id': 'user-1',
      'gym_id': 'gym-1',
      'name': '转角橙线',
      'grade': 'V4',
      'color': '橙色',
      'cover_url': 'https://example.com/route.jpg',
      'points': <Object>[],
      'status': 'approved',
      'published_route_id': 'route-1',
      'send_id': 'send-1',
      'send_moderation_status': 'approved',
      'send': {'moderation_status': 'pending'},
    });

    expect(submission.isApproved, isTrue);
    expect(submission.publishedRouteId, 'route-1');
    expect(submission.sendId, 'send-1');
    expect(submission.videoModerationStatus, 'approved');
  });
}
