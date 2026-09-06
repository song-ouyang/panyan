import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/growth_models.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/growth_repository.dart';
import 'package:wanpan_diary/core/services/publication_request_draft.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';

const config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);
const user = UserSummary(
  id: 'growth-owner',
  nickname: '岩友',
  role: 'user',
  profileCompleted: true,
);
JsonMap snapshot({
  int revision = 1,
  int level = 1,
  int days = 1,
  int routes = 1,
}) => {
  'rulesVersion': 'wanpan-growth-v1',
  'revision': revision,
  'currentLevel': level,
  'levelName': '初次上墙',
  'climbingDays': days,
  'uniqueRoutes': routes,
  'nextLevel': level == 10
      ? null
      : {
          'level': 2,
          'name': '渐入佳境',
          'days': 3,
          'routes': 8,
          'badgeKey': 'account-level-02',
        },
  'remainingDays': (3 - days).clamp(0, 3),
  'remainingRoutes': (8 - routes).clamp(0, 8),
  'backfillStatus': 'complete',
};

class GrowthApi extends ApiClient {
  GrowthApi() : super(config: config, accessTokenProvider: () => 'token');
  final reads = <Completer<JsonMap>>[];
  final consumes = <Completer<JsonMap>>[];
  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    final result = Completer<JsonMap>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) {
    final result = Completer<JsonMap>();
    consumes.add(result);
    return result.future;
  }
}

Future<SessionController> createSession() async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: config,
    tokenStore: MemorySessionTokenStore(),
  );
  await session.acceptSession(
    const AuthSession(token: 'token', user: user, needsProfile: false),
  );
  return session;
}

JsonMap presentationResponse({int revision = 1, int level = 1}) => {
  'growth': snapshot(revision: revision, level: level),
  'shouldPresent': true,
  'presentation': {
    'id': 'presentation-1',
    'fromLevel': 0,
    'toLevel': level,
    'badgeKeys': ['account-level-01'],
    'newBadgeCount': 1,
    'levelName': '初次上墙',
    'growthRevision': revision,
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('definite validation rejection unlocks editable payload without changing request ID', () async {
    SharedPreferences.setMockInitialValues({});
    final draft = await PublicationRequestDraft.load(
      ownerId: 'owner',
      kind: 'submission',
      target: 'new',
    );
    await draft.freeze({
      'points': List.filled(81, {'x': 0, 'y': 0, 'type': 'hold'}),
    });
    await draft.unlockAfterRejection();
    final restored = await PublicationRequestDraft.load(
      ownerId: 'owner',
      kind: 'submission',
      target: 'new',
    );
    expect(restored.id, draft.id);
    expect(restored.payload, isNull);
    await restored.freeze({'points': []});
    expect(restored.payload!['points'], isEmpty);
  });
  test('overlapping reads preserve the newest server revision', () async {
    final session = await createSession();
    final api = GrowthApi();
    final repository = GrowthRepository(api: api, session: session);
    addTearDown(repository.dispose);
    addTearDown(session.dispose);
    addTearDown(api.dispose);
    final old = repository.refresh();
    final current = repository.refresh();
    api.reads[1].complete(snapshot(revision: 8, days: 3, routes: 8));
    await current;
    api.reads[0].complete(snapshot(revision: 7));
    await old;
    expect(repository.snapshot!.revision, 8);
    expect(repository.snapshot!.uniqueRoutes, 8);
  });
  test(
    'account switch discards late snapshots and consumed celebration',
    () async {
      final session = await createSession();
      final api = GrowthApi();
      final repository = GrowthRepository(api: api, session: session);
      addTearDown(repository.dispose);
      addTearDown(session.dispose);
      addTearDown(api.dispose);
      final read = repository.refresh();
      final consume = repository.consumePresentation();
      await session.acceptSession(
        const AuthSession(
          token: 'other-token',
          user: UserSummary(
            id: 'other-owner',
            nickname: '另一位',
            role: 'user',
            profileCompleted: true,
          ),
          needsProfile: false,
        ),
      );
      api.reads.single.complete(snapshot());
      api.consumes.single.complete(presentationResponse());
      expect(await read, isNull);
      expect(await consume, isNull);
      expect(repository.snapshot, isNull);
    },
  );
  test('single in-flight consume and stale presentation cannot play', () async {
    final session = await createSession();
    final api = GrowthApi();
    final repository = GrowthRepository(api: api, session: session);
    addTearDown(repository.dispose);
    addTearDown(session.dispose);
    addTearDown(api.dispose);
    final consume = repository.consumePresentation();
    expect(await repository.consumePresentation(), isNull);
    repository.acceptSnapshot(
      GrowthSnapshot.fromJson(snapshot(revision: 5, level: 2)),
      generation: repository.sessionGeneration,
    );
    api.consumes.single.complete(presentationResponse(revision: 4));
    expect(await consume, isNull);
    expect(api.consumes.length, 1);
    expect(repository.snapshot!.revision, 5);
  });
  test(
    'each gate displays its own progress and highest level has no target',
    () {
      final value = GrowthSnapshot.fromJson(snapshot(days: 3, routes: 4));
      expect(value.daysProgress, 1);
      expect(value.routesProgress, .5);
      expect(value.remainingDays, 0);
      expect(value.remainingRoutes, 4);
      expect(GrowthSnapshot.fromJson(snapshot(level: 10)).nextLevel, isNull);
    },
  );
  test('frozen UUID and exact uploaded payload survive restart and clear only after success', () async {
    SharedPreferences.setMockInitialValues({});
    final draft = await PublicationRequestDraft.load(
      ownerId: 'owner',
      kind: 'checkin',
      target: 'route',
    );
    await draft.freeze({
      'routeId': 'route',
      'videoUrl': 'https://example.com/first.mp4',
      'caption': '第一次内容',
    });
    final restored = await PublicationRequestDraft.load(
      ownerId: 'owner',
      kind: 'checkin',
      target: 'route',
    );
    expect(restored.id, draft.id);
    await restored.freeze({
      'videoUrl': 'https://example.com/other.mp4',
      'caption': '不应覆盖',
    });
    expect(restored.payload!['videoUrl'], 'https://example.com/first.mp4');
    expect(restored.payload!['caption'], '第一次内容');
    final other = await PublicationRequestDraft.load(
      ownerId: 'other',
      kind: 'checkin',
      target: 'route',
    );
    expect(other.id, isNot(draft.id));
    await restored.clear();
    final next = await PublicationRequestDraft.load(
      ownerId: 'owner',
      kind: 'checkin',
      target: 'route',
    );
    expect(next.id, isNot(draft.id));
  });
}
