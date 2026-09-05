import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/checkin_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/gyms/checkin_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

import 'support/fake_motion_sound_player.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

const _approvedSend = {
  'sendId': 'send-1',
  'moderationStatus': 'approved',
  'pointsEarned': 25,
  'pendingPoints': 0,
};

class _UploadRequest {
  _UploadRequest(this.path, this.onProgress);

  final String path;
  final ProgressCallback? onProgress;
  final completed = Completer<String>();
}

class _CheckinUploadApi extends ApiClient {
  _CheckinUploadApi()
    : super(config: _config, accessTokenProvider: () => 'secure-token');

  Completer<void>? preparationGate;
  final uploads = <_UploadRequest>[];
  final sends = <JsonMap>[];
  final published = Completer<JsonMap>();
  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path != '/users/me/month-dashboard') {
      throw StateError('Unexpected request: $path');
    }
    throw StateError('Optional month dashboard unavailable');
  }

  @override
  Future<String> uploadFile(
    String filePath, {
    String fieldName = 'file',
    String? filename,
    ProgressCallback? onSendProgress,
  }) {
    final request = _UploadRequest(filePath, onSendProgress);
    uploads.add(request);
    return request.completed.future;
  }

  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) {
    if (path != '/sends') throw StateError('Unexpected request: $path');
    sends.add(jsonMap(data));
    return published.future;
  }
}

class _CheckinUploadRepository extends CheckinRepository {
  _CheckinUploadRepository(this.api) : super(api);
  final _CheckinUploadApi api;

  @override
  Future<String> uploadVideo(
    String filePath, {
    UploadProgress? onProgress,
    VideoUploadPhaseChanged? onPhaseChanged,
  }) async {
    onPhaseChanged?.call(VideoUploadPhase.preparing);
    onProgress?.call(.25);
    await api.preparationGate?.future;
    onPhaseChanged?.call(VideoUploadPhase.uploading);
    onProgress?.call(0);
    return api.uploadFile(
      filePath,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );
  }
}

Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is WanpanButton && widget.label == label,
);

Future<SessionController> _showCheckin(
  WidgetTester tester,
  _CheckinUploadApi api,
) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  addTearDown(session.dispose);
  await session.acceptSession(
    const AuthSession(
      token: 'secure-token',
      user: UserSummary(id: 'me', nickname: '小欧', profileCompleted: true),
      needsProfile: false,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: CheckinScreen(
        api: api,
        repository: _CheckinUploadRepository(api),
        session: session,
        routeId: 'route-1',
        routeName: '红色线路',
        grade: 'V2',
        motionSoundPlayer: FakeMotionSoundPlayer(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<String> _selectVideo(WidgetTester tester) async {
  final directory = Directory.systemTemp.createTempSync('wanpan-checkin-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final video = File('${directory.path}/send.mp4')..writeAsBytesSync([0, 1, 2]);
  const pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    pickerChannel,
    (call) async {
      expect(call.method, 'pickVideo');
      expect(call.arguments['maxDuration'], 300);
      return video.path;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pickerChannel,
      null,
    ),
  );
  await tester.tap(find.text('选择或拍摄视频'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('从相册选择视频'));
  await tester.pumpAndSettle();
  expect(find.text('send.mp4'), findsOneWidget);
  return video.path;
}

Future<_UploadRequest> _startUpload(
  WidgetTester tester,
  _CheckinUploadApi api,
) async {
  final previousUploadCount = api.uploads.length;
  final submit = _button('上传并打卡');
  await tester.scrollUntilVisible(
    submit,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  // The screen checks the real file length before calling the upload API.
  await tester.tap(submit);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  expect(api.uploads, hasLength(previousUploadCount + 1));
  return api.uploads.last;
}

void _expectNoReview(WidgetTester tester) {
  expect(find.textContaining('审核'), findsNothing);
  expect(find.textContaining('待结算'), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'video shows upload progress then publishes after both requests',
    (tester) async {
      final api = _CheckinUploadApi();
      await _showCheckin(tester, api);
      final videoPath = await _selectVideo(tester);
      final upload = await _startUpload(tester, api);

      expect(upload.path, videoPath);
      expect(api.sends, isEmpty);
      expect(find.text('视频上传中…'), findsOneWidget);
      expect(find.text('完攀记录已保存！'), findsNothing);
      expect(find.text('视频已发布'), findsNothing);
      _expectNoReview(tester);

      upload.onProgress!(2, 5);
      await tester.pump();
      await tester.ensureVisible(find.byType(LinearProgressIndicator));
      await tester.pump();
      expect(find.text('40%').hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .4,
      );
      expect(api.sends, isEmpty);
      expect(tester.widget<WanpanButton>(_button('上传中…')).loading, isTrue);

      upload.completed.complete('https://example.com/send.mp4');
      await tester.pump();
      await tester.pump();

      expect(api.sends, hasLength(1));
      expect(api.sends.single['videoUrl'], 'https://example.com/send.mp4');
      expect(api.sends.single['routeId'], 'route-1');
      expect(find.text('视频已上传，正在发布…'), findsOneWidget);
      expect(find.text('完攀记录已保存！'), findsNothing);
      expect(find.text('视频已发布'), findsNothing);
      expect(tester.widget<WanpanButton>(_button('正在保存…')).loading, isTrue);
      _expectNoReview(tester);

      api.published.complete(_approvedSend);
      await tester.pumpAndSettle();

      expect(find.text('完攀记录已保存！'), findsOneWidget);
      expect(find.text('视频已上传，可在线路中查看。'), findsOneWidget);
      expect(find.text('视频已发布'), findsOneWidget);
      expect(find.text('+25 积分'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.ensureVisible(find.text('返回线路'));
      await tester.pumpAndSettle();
      expect(find.text('返回线路').hitTestable(), findsOneWidget);
      _expectNoReview(tester);
    },
  );

  testWidgets(
    'failed video upload keeps the form and can retry without a send',
    (tester) async {
      final api = _CheckinUploadApi();
      await _showCheckin(tester, api);
      await _selectVideo(tester);
      final upload = await _startUpload(tester, api);

      upload.completed.completeError(StateError('上传连接中断'));
      await tester.pumpAndSettle();

      expect(api.sends, isEmpty);
      expect(find.textContaining('上传连接中断'), findsOneWidget);
      expect(find.text('完攀记录已保存！'), findsNothing);
      expect(find.text('视频已发布'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.widget<WanpanButton>(_button('上传并打卡')).loading, isFalse);
      _expectNoReview(tester);

      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pumpAndSettle();
      final retry = await _startUpload(tester, api);
      expect(api.uploads, hasLength(2));
      expect(retry.path, upload.path);
      expect(api.sends, isEmpty);
      expect(find.text('视频上传中…'), findsOneWidget);

      retry.completed.complete('https://example.com/retry.mp4');
      await tester.pump();
      api.published.complete(_approvedSend);
      await tester.pumpAndSettle();

      expect(api.sends, hasLength(1));
      expect(api.sends.single['videoUrl'], 'https://example.com/retry.mp4');
      expect(find.text('视频已发布'), findsOneWidget);
      _expectNoReview(tester);
    },
  );

  testWidgets('compression is shown before upload and publishing waits', (
    tester,
  ) async {
    final api = _CheckinUploadApi()..preparationGate = Completer<void>();
    await _showCheckin(tester, api);
    await _selectVideo(tester);
    await tester.scrollUntilVisible(
      _button('上传并打卡'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(_button('上传并打卡'));
    await tester.pump();
    expect(find.text('正在压缩视频…'), findsOneWidget);
    expect(_button('压缩中…'), findsOneWidget);
    expect(api.uploads, isEmpty);
    expect(api.sends, isEmpty);
    api.preparationGate!.complete();
    await tester.pump();
    expect(api.uploads, hasLength(1));
    api.uploads.single.completed.complete('https://example.com/compressed.mp4');
    await tester.pump();
    api.published.complete(_approvedSend);
    await tester.pumpAndSettle();
    expect(api.sends.single['videoUrl'], 'https://example.com/compressed.mp4');
  });

  testWidgets(
    'switching account while uploading cannot publish to the new account',
    (tester) async {
      final api = _CheckinUploadApi();
      final session = await _showCheckin(tester, api);
      await _selectVideo(tester);
      final upload = await _startUpload(tester, api);
      await session.acceptSession(
        const AuthSession(
          token: 'another-token',
          user: UserSummary(
            id: 'another-user',
            nickname: '另一位岩友',
            profileCompleted: true,
          ),
          needsProfile: false,
        ),
      );
      upload.completed.complete('https://example.com/previous-owner.mp4');
      await tester.pumpAndSettle();
      expect(api.sends, isEmpty);
      expect(find.textContaining('登录账号已切换'), findsOneWidget);
    },
  );

  testWidgets('disposing the form while uploading does not publish afterward', (
    tester,
  ) async {
    final api = _CheckinUploadApi();
    await _showCheckin(tester, api);
    await _selectVideo(tester);
    final upload = await _startUpload(tester, api);
    await tester.pumpWidget(const SizedBox());
    upload.completed.complete('https://example.com/video.mp4');
    await tester.pumpAndSettle();
    expect(api.sends, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving without a video retains the ordinary success copy', (
    tester,
  ) async {
    final api = _CheckinUploadApi();
    await _showCheckin(tester, api);
    await tester.scrollUntilVisible(
      _button('保存完攀'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(_button('保存完攀'));
    await tester.pump();

    expect(api.uploads, isEmpty);
    expect(api.sends, hasLength(1));
    expect(api.sends.single['videoUrl'], isNull);
    expect(find.text('完攀记录已保存！'), findsNothing);

    api.published.complete(_approvedSend);
    await tester.pumpAndSettle();

    expect(find.text('完攀记录已保存！'), findsOneWidget);
    expect(find.text('完攀记录已保存'), findsOneWidget);
    expect(find.text('这次上墙，已经好好记下来了。'), findsOneWidget);
    expect(find.text('视频已发布'), findsNothing);
    _expectNoReview(tester);
  });
}
