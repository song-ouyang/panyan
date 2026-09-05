import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/models/route_submission_models.dart';

void main() {
  test('no-photo drafts omit cover URLs and default to no marker points', () {
    for (final cover in <String?>[null, '', '  ']) {
      final draft = RouteSubmissionDraft(
        clientRequestId: 'no-photo-request',
        gymId: 'gym-1',
        grade: 'V2',
        color: '橙',
        coverUrl: cover,
      );

      final json = draft.toJson();
      expect(json.containsKey('coverUrl'), isFalse);
      expect(json['points'], isEmpty);
      expect(json.containsKey('videoUrl'), isFalse);
      expect(json.containsKey('caption'), isFalse);
      expect(json.containsKey('visibility'), isFalse);
      expect(json['name'], 'V2 橙线');
    }
  });

  test('video-only drafts keep video metadata without inventing a cover', () {
    const draft = RouteSubmissionDraft(
      clientRequestId: 'video-only-request',
      gymId: 'gym-1',
      grade: 'V2',
      color: '橙',
      videoUrl: ' https://example.com/climb.mp4 ',
      caption: ' 首次完攀 ',
      visibility: 'friends',
    );

    final json = draft.toJson();
    expect(json.containsKey('coverUrl'), isFalse);
    expect(json['points'], isEmpty);
    expect(json['videoUrl'], 'https://example.com/climb.mp4');
    expect(json['caption'], '首次完攀');
    expect(json['visibility'], 'friends');
  });

  test('published submissions accept null or omitted cover URLs', () {
    for (final includeNullCover in [true, false]) {
      final submission = RouteSubmission.fromJson({
        'id': 'submission-no-photo',
        'submitter_id': 'me',
        'gym_id': 'gym-1',
        'name': 'V2 橙线',
        'grade': 'V2',
        'color': '橙',
        if (includeNullCover) 'cover_url': null,
        'points': [],
        'status': 'approved',
        'published_route_id': 'route-no-photo',
      });

      expect(submission.coverUrl, isNull);
      expect(submission.points, isEmpty);
      expect(submission.status, 'approved');
      expect(submission.publishedRouteId, 'route-no-photo');
    }
  });

  test('an omitted route name submits a grade and color name', () {
    const draft = RouteSubmissionDraft(
      clientRequestId: 'request-1',
      gymId: 'gym-1',
      grade: 'V2',
      color: ' 橙 ',
      coverUrl: 'https://example.com/route.jpg',
      points: [],
    );

    final json = draft.toJson();

    expect(json['name'], 'V2 橙线');
    expect(json['color'], '橙');
    expect(json.containsKey('wallZone'), isFalse);
  });

  test('whitespace names submit the same default as empty names', () {
    for (final name in ['', ' \t\n ']) {
      final json = _draft(name: name).toJson();

      expect(json['name'], 'V10 蓝线');
      expect(json['color'], '蓝');
    }
  });

  test('a custom route name is preserved with outer whitespace removed', () {
    final json = _draft(name: '  蓝色 小宇宙  ').toJson();

    expect(json['name'], '蓝色 小宇宙');
  });

  test('existing route metadata and optional wall zones remain compatible', () {
    final json = _draft(name: '转角线', wallZone: '  左侧岩壁  ').toJson();

    expect(json, {
      'clientRequestId': 'request-1',
      'gymId': 'gym-1',
      'routeSetId': 'set-1',
      'name': '转角线',
      'grade': 'V10',
      'color': '蓝',
      'wallZone': '左侧岩壁',
      'coverUrl': 'https://example.com/route.jpg',
      'points': [
        {'x': .2, 'y': .8, 'type': 'start'},
        {'x': .7, 'y': .1, 'type': 'finish'},
      ],
      'videoUrl': 'https://example.com/climb.mp4',
      'caption': '试试这条线',
      'visibility': 'friends',
    });
    expect(_draft(wallZone: '  ').toJson().containsKey('wallZone'), isFalse);
  });
}

RouteSubmissionDraft _draft({String name = '', String? wallZone}) =>
    RouteSubmissionDraft(
      clientRequestId: 'request-1',
      gymId: 'gym-1',
      routeSetId: 'set-1',
      name: name,
      grade: 'V10',
      color: ' 蓝 ',
      wallZone: wallZone,
      coverUrl: 'https://example.com/route.jpg',
      points: const [
        RoutePoint(x: .2, y: .8, type: RoutePointType.start),
        RoutePoint(x: .7, y: .1, type: RoutePointType.finish),
      ],
      videoUrl: ' https://example.com/climb.mp4 ',
      caption: ' 试试这条线 ',
      visibility: 'friends',
    );
