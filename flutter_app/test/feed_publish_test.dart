import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/feed_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/feed/feed_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _FeedApi extends ApiClient {
  _FeedApi() : super(config: _config, accessTokenProvider: () => 'test-token');

  String? status = 'approved';
  bool camelCaseStatus = false;
  Completer<void>? saveBarrier;
  Map<String, dynamic>? saved;
  final scopes = <String>[];

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    expect(path, '/sends/feed');
    final scope = queryParameters?['scope'] as String;
    scopes.add(scope);
    final post = saved;
    final matchesScope =
        post != null && (scope == 'friends' || post['visibility'] == 'public');
    return {
      'items': [if (status == 'approved' && matchesScope) post],
    };
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    expect(path, '/sends/moments');
    await saveBarrier?.future;
    final body = data as Map<String, dynamic>;
    saved = {
      'id': 'new-moment',
      'user_id': 'me',
      'nickname': '小欧',
      'caption': body['caption'],
      'image_urls': body['imageUrls'],
      'visibility': body['visibility'],
      if (status != null)
        camelCaseStatus ? 'moderationStatus' : 'moderation_status': status,
      'sent_at': '2026-09-06T08:00:00.000Z',
    };
    return saved!;
  }
}

Future<void> _openComposer(WidgetTester tester, _FeedApi api) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  await session.acceptSession(
    const AuthSession(
      token: 'test-token',
      user: UserSummary(id: 'me', nickname: '小欧', profileCompleted: true),
      needsProfile: false,
    ),
  );
  addTearDown(session.dispose);
  addTearDown(api.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      home: FeedScreen(api: api, session: session),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('发布动态'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '今天又有新的进步');
  await tester.pump();
}

Future<void> _publish(WidgetTester tester) async {
  final button = find.byWidgetPredicate(
    (widget) => widget is WanpanButton && widget.label == '发布动态',
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  testWidgets('文字动态发布直接显示成功并刷新出新动态', (tester) async {
    final api = _FeedApi()..saveBarrier = Completer<void>();
    await _openComposer(tester, api);
    expect(find.text('发布后所有人都可在广场看到'), findsOneWidget);
    expect(find.textContaining('审核'), findsNothing);
    await _publish(tester);
    expect(find.text('正在发布…'), findsOneWidget);
    expect(find.textContaining('审核'), findsNothing);

    api.saveBarrier!.complete();
    await tester.pumpAndSettle();
    expect(find.text('动态已发布'), findsOneWidget);
    expect(find.text('今天又有新的进步'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(api.scopes.length, greaterThanOrEqualTo(2));
    expect(api.scopes, everyElement('square'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('仅岩友动态发布后切换朋友圈并兼容camelCase状态', (tester) async {
    final api = _FeedApi()..camelCaseStatus = true;
    await _openComposer(tester, api);
    final friendsChoice = find.ancestor(
      of: find.text('仅岩友'),
      matching: find.byType(ChoiceChip),
    );
    await tester.ensureVisible(friendsChoice);
    await tester.tap(friendsChoice);
    await tester.pump();
    expect(find.text('发布后仅你和已添加的岩友可见'), findsOneWidget);
    await _publish(tester);
    await tester.pumpAndSettle();
    expect(api.saved!['visibility'], 'friends');
    expect(api.scopes.last, 'friends');
    expect(find.text('动态已发布'), findsOneWidget);
    expect(find.text('今天又有新的进步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in <({String? status, String message})>[
    (status: 'pending', message: '动态已提交，审核后可见'),
    (status: 'rejected', message: '动态未通过，请调整内容后重新发布'),
    (status: null, message: '动态已提交，刷新后查看'),
  ]) {
    testWidgets('兼容${scenario.status}响应，不误报或展示为已发布', (tester) async {
      final api = _FeedApi()..status = scenario.status;
      await _openComposer(tester, api);
      await _publish(tester);
      await tester.pumpAndSettle();
      expect(find.text(scenario.message), findsOneWidget);
      expect(find.text('动态已发布'), findsNothing);
      expect(find.text('今天又有新的进步'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('图片动态保留上传图片URL和服务端发布状态', () async {
    final api = _FeedApi();
    addTearDown(api.dispose);
    final post = await FeedRepository(api).publishMoment(
      imageUrls: ['https://cdn.example.com/climbing.jpg'],
      visibility: 'public',
    );
    expect(post.imageUrls, ['https://cdn.example.com/climbing.jpg']);
    expect(post.moderationStatus, 'approved');
    expect(post.caption, '');
  });
}
