import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/models/route_submission_models.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/gym_repository.dart';
import 'package:wanpan_diary/core/repositories/checkin_repository.dart';
import 'package:wanpan_diary/core/repositories/route_submission_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/gyms/route_submission_screen.dart';
import 'package:wanpan_diary/shared/app_assets.dart';
import 'package:wanpan_diary/shared/motion/wanpan_motion_sound.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_lottie_stage.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_notice.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

import 'support/fake_motion_sound_player.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

const _gym = Gym(
  id: 'gym-1',
  name: '香蕉攀岩·南山店',
  city: '深圳',
  province: '广东省',
  district: '南山区',
  address: '科技园',
  verified: true,
);

final _activeSet = RouteSet(
  id: 'set-1',
  gymId: _gym.id,
  name: '本轮线路',
  startsOn: DateTime(2026, 8, 1),
  active: true,
);

const _existingRoute = ClimbingRoute(
  id: 'route-1',
  gymId: 'gym-1',
  routeSetId: 'set-1',
  routeSetName: '本轮线路',
  name: '橙色月亮线',
  grade: 'V3',
  color: '橙',
  wallZone: 'A区',
  published: true,
);

class _RouteApiClient extends ApiClient {
  _RouteApiClient()
    : super(config: _config, accessTokenProvider: () => 'secure-token');
}

class _RouteGymRepository extends GymRepository {
  _RouteGymRepository(super.api);

  int getRoutesCallCount = 0;

  @override
  Future<List<Gym>> getGyms({String? city, String? query}) async => [_gym];

  @override
  Future<GymDetail> getGym(String gymId) async =>
      GymDetail(gym: _gym, routeSets: [_activeSet]);

  @override
  Future<List<ClimbingRoute>> getRoutes(
    String gymId, {
    String? grade,
    String? routeSetId,
  }) async {
    getRoutesCallCount++;
    return [_existingRoute];
  }
}

class _RouteSubmissionRepository extends RouteSubmissionRepository {
  _RouteSubmissionRepository(super.api);

  RouteSubmissionDraft? submittedDraft;
  final coverUploads = <String>[];
  final videoUploads = <String>[];
  Completer<String>? videoUploadGate;

  @override
  Future<String> uploadCover(
    String filePath, {
    RouteCoverUploadProgress? onProgress,
  }) async {
    coverUploads.add(filePath);
    onProgress?.call(1);
    return 'https://example.com/route.png';
  }

  @override
  Future<String> uploadVideo(
    String filePath, {
    String? filename,
    String? mimeType,
    RouteCoverUploadProgress? onProgress,
    VideoUploadPhaseChanged? onPhaseChanged,
  }) async {
    videoUploads.add(filePath);
    onProgress?.call(1);
    return await videoUploadGate?.future ??
        'https://example.com/first-send.mp4';
  }

  @override
  Future<RouteSubmission> create(RouteSubmissionDraft draft) async {
    submittedDraft = draft;
    return RouteSubmission(
      id: 'submission-1',
      submitterId: 'me',
      gymId: draft.gymId,
      routeSetId: draft.routeSetId,
      name: draft.name.trim(),
      grade: draft.grade,
      color: draft.color.trim(),
      wallZone: draft.wallZone,
      coverUrl: draft.coverUrl,
      points: draft.points,
      status: 'approved',
      publishedRouteId: 'published-route-1',
      sendId: draft.videoUrl == null ? null : 'send-1',
      videoModerationStatus: draft.videoUrl == null ? null : 'approved',
    );
  }
}

class _RouteImagePicker extends ImagePicker {
  _RouteImagePicker({required this.imagePath, required this.videoPath});

  final String imagePath;
  final String videoPath;
  int videoPickCount = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => XFile(imagePath, name: 'route.png');

  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    videoPickCount++;
    return XFile(videoPath, name: 'first-send.mp4');
  }
}

Finder _fieldWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<
  ({
    SessionController session,
    _RouteSubmissionRepository submissions,
    _RouteImagePicker picker,
  })
>
_pumpOptionalPhotoForm(WidgetTester tester) async {
  // Finish parsing before fake time starts driving the form's background preload.
  await tester.runAsync(() async {
    await AssetLottie(AppAssets.routePublishedAnimation).load();
  });
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  await session.acceptSession(
    const AuthSession(
      token: 'secure-token',
      user: UserSummary(id: 'me', nickname: '小欧', profileCompleted: true),
      needsProfile: false,
    ),
  );
  final api = _RouteApiClient();
  final submissions = _RouteSubmissionRepository(api);
  final fixturePath = File('assets/logo.png').absolute.path;
  final picker = _RouteImagePicker(
    imagePath: fixturePath,
    videoPath: fixturePath,
  );
  final sounds = FakeMotionSoundPlayer();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await sounds.dispose();
    session.dispose();
    api.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: RouteSubmissionScreen(
        api: api,
        session: session,
        initialGymId: _gym.id,
        gymRepository: _RouteGymRepository(api),
        submissionRepository: submissions,
        imagePicker: picker,
        localVideoPreviewBuilder: (_) =>
            const SizedBox(height: 100, child: Text('测试完攀视频预览')),
        imageSizeReader: (_) async => const Size(1254, 1254),
        motionSoundPlayer: sounds,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(_fieldWithLabel('线路颜色'), '橙');
  return (session: session, submissions: submissions, picker: picker);
}

Future<void> _chooseCover(WidgetTester tester) async {
  await tester.tap(find.text('拍摄或选择线路照片'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('从相册选择'));
  await tester.pumpAndSettle();
}

Future<void> _chooseVideo(WidgetTester tester) async {
  final addVideo = find.text('添加完攀视频');
  await tester.ensureVisible(addVideo);
  await tester.tap(addVideo);
  await tester.pumpAndSettle();
  await tester.tap(find.text('从相册选择视频'));
  await tester.pumpAndSettle();
}

Future<void> _publishForm(WidgetTester tester, {bool settle = true}) async {
  final publish = find.byWidgetPredicate(
    (widget) => widget is WanpanButton && widget.label == '发布新线路',
  );
  await tester.ensureVisible(publish);
  await tester.tap(publish);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('无照片和视频也可发布，隐藏标点操作并跳过全部上传', (tester) async {
    final form = await _pumpOptionalPhotoForm(tester);

    expect(find.text('拍照并标记线路点（选填）'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '起点'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '终点'), findsNothing);
    expect(find.text('撤销上一步'), findsNothing);
    expect(find.text('清空标点'), findsNothing);
    await _publishForm(tester);

    final draft = form.submissions.submittedDraft;
    expect(draft, isNotNull);
    expect(draft!.coverUrl, isNull);
    expect(draft.points, isEmpty);
    expect(draft.videoUrl, isNull);
    expect(draft.toJson(), containsPair('name', 'V2 橙线'));
    expect(draft.toJson().containsKey('coverUrl'), isFalse);
    expect(draft.toJson().containsKey('videoUrl'), isFalse);
    expect(form.submissions.coverUploads, isEmpty);
    expect(form.submissions.videoUploads, isEmpty);
    expect(find.byType(WanpanLottieStage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('仅选择完攀视频时只上传视频并保留配文和可见范围', (tester) async {
    final form = await _pumpOptionalPhotoForm(tester);
    await _chooseVideo(tester);
    await tester.enterText(_fieldWithLabel('视频配文（选填）'), '没有线路照片也能分享完攀');
    await tester.tap(find.text('仅岩友'));
    await _publishForm(tester);

    final draft = form.submissions.submittedDraft;
    expect(draft, isNotNull);
    expect(draft!.coverUrl, isNull);
    expect(draft.points, isEmpty);
    expect(draft.videoUrl, 'https://example.com/first-send.mp4');
    expect(draft.caption, '没有线路照片也能分享完攀');
    expect(draft.visibility, 'friends');
    expect(draft.toJson().containsKey('coverUrl'), isFalse);
    expect(form.picker.videoPickCount, 1);
    expect(form.submissions.coverUploads, isEmpty);
    expect(form.submissions.videoUploads, [form.picker.videoPath]);
    expect(find.byType(WanpanLottieStage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('线路照片可以不添加标点直接发布', (tester) async {
    final form = await _pumpOptionalPhotoForm(tester);
    await _chooseCover(tester);
    expect(find.widgetWithText(ChoiceChip, '起点'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '终点'), findsOneWidget);
    await _publishForm(tester);

    final draft = form.submissions.submittedDraft;
    expect(draft, isNotNull);
    expect(draft!.coverUrl, 'https://example.com/route.png');
    expect(draft.points, isEmpty);
    expect(form.submissions.coverUploads, [form.picker.imagePath]);
    expect(form.submissions.videoUploads, isEmpty);
    expect(find.byType(WanpanLottieStage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('部分标点仍需起终点，移除照片清空标点后可跳过照片发布', (tester) async {
    final form = await _pumpOptionalPhotoForm(tester);
    await _chooseCover(tester);
    tester
        .widget<GestureDetector>(
          find
              .ancestor(
                of: find.text('点击添加起点'),
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTapDown!(TapDownDetails(localPosition: const Offset(110, 110)));
    await tester.pump();
    await _publishForm(tester);
    expect(find.text('请补充终点，或清空标点后直接发布'), findsOneWidget);
    expect(form.submissions.submittedDraft, isNull);
    expect(form.submissions.coverUploads, isEmpty);

    final remove = find.text('移除照片');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('拍摄或选择线路照片'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '起点'), findsNothing);
    expect(find.text('清空标点'), findsNothing);
    await _publishForm(tester);

    final draft = form.submissions.submittedDraft;
    expect(draft, isNotNull);
    expect(draft!.coverUrl, isNull);
    expect(draft.points, isEmpty);
    expect(form.submissions.coverUploads, isEmpty);
    expect(form.submissions.videoUploads, isEmpty);
    expect(find.byType(WanpanLottieStage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('仅视频上传期间切换账号不会把线路发布到新账号', (tester) async {
    final form = await _pumpOptionalPhotoForm(tester);
    await _chooseVideo(tester);
    final uploading = Completer<String>();
    form.submissions.videoUploadGate = uploading;
    await _publishForm(tester, settle: false);
    expect(form.submissions.coverUploads, isEmpty);
    expect(form.submissions.videoUploads, hasLength(1));
    expect(form.submissions.submittedDraft, isNull);

    await form.session.acceptSession(
      const AuthSession(
        token: 'another-token',
        user: UserSummary(
          id: 'another-user',
          nickname: '另一个岩友',
          profileCompleted: true,
        ),
        needsProfile: false,
      ),
    );
    uploading.complete('https://example.com/first-send.mp4');
    await tester.pumpAndSettle();

    expect(form.submissions.submittedDraft, isNull);
    expect(find.text('登录账号已切换，请重新提交'), findsOneWidget);
    expect(find.byType(WanpanLottieStage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('馆内投稿可完成图片标点、视频配文并同步朋友圈', (tester) async {
    tester.view.physicalSize = const Size(430, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final fixturePath = File('assets/logo.png').absolute.path;
    await tester.runAsync(() async {
      Lottie.cache.clear();
      await AssetLottie(AppAssets.routePublishedAnimation).load();
    });
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    await session.acceptSession(
      const AuthSession(
        token: 'secure-token',
        user: UserSummary(id: 'me', nickname: '小欧', profileCompleted: true),
        needsProfile: false,
      ),
    );
    final api = _RouteApiClient();
    final gymRepository = _RouteGymRepository(api);
    final submissionRepository = _RouteSubmissionRepository(api);
    final imagePicker = _RouteImagePicker(
      imagePath: fixturePath,
      videoPath: fixturePath,
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    final sounds = FakeMotionSoundPlayer();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: WanpanTheme.light(),
        home: const Scaffold(body: Center(child: Text('线路列表'))),
      ),
    );
    final routeResult = navigatorKey.currentState!.push<bool>(
      MaterialPageRoute(
        builder: (_) => RouteSubmissionScreen(
          api: api,
          session: session,
          initialGymId: _gym.id,
          gymRepository: gymRepository,
          submissionRepository: submissionRepository,
          imagePicker: imagePicker,
          localVideoPreviewBuilder: (_) => const SizedBox(
            height: 120,
            child: Center(child: Text('视频已选择，可点击画面预览')),
          ),
          imageSizeReader: (_) async => const Size(1254, 1254),
          motionSoundPlayer: sounds,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_gym.name), findsWidgets);
    expect(gymRepository.getRoutesCallCount, 0);
    expect(find.text(_existingRoute.name), findsNothing);
    expect(find.text('把新线路留给更多岩友'), findsNothing);
    expect(find.text('线路墙 / 周期'), findsNothing);
    expect(find.text('先找馆内已有线路'), findsNothing);
    expect(
      tester.getTopLeft(_fieldWithLabel('线路名称（选填）')).dy,
      lessThan(tester.getTopLeft(find.text('拍摄或选择线路照片').first).dy),
    );

    await tester.tap(find.text('拍摄或选择线路照片'));
    await tester.pumpAndSettle();
    tester
        .widget<ListTile>(
          find.ancestor(
            of: find.text('从相册选择'),
            matching: find.byType(ListTile),
          ),
        )
        .onTap!();
    await tester.pumpAndSettle();
    tester
        .widget<GestureDetector>(
          find
              .ancestor(
                of: find.text('点击添加起点'),
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTapDown!(TapDownDetails(localPosition: const Offset(110, 110)));
    await tester.pump();
    tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '终点'))
        .onSelected!(true);
    await tester.pump();
    tester
        .widget<GestureDetector>(
          find
              .ancestor(
                of: find.text('点击添加终点'),
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTapDown!(TapDownDetails(localPosition: const Offset(220, 220)));
    await tester.pump();

    tester
        .widget<WanpanPressable>(
          find
              .ancestor(
                of: find.text('添加完攀视频'),
                matching: find.byType(WanpanPressable),
              )
              .first,
        )
        .onTap!();
    await tester.pumpAndSettle();
    tester
        .widget<ListTile>(
          find.ancestor(
            of: find.text('从相册选择视频'),
            matching: find.byType(ListTile),
          ),
        )
        .onTap!();
    await tester.pumpAndSettle();

    expect(imagePicker.videoPickCount, 1);
    await tester.scrollUntilVisible(
      find.text('首条完攀（选填）'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('视频已选择，可点击画面预览'), findsOneWidget);
    expect(find.text('同步广场'), findsOneWidget);
    expect(find.text('仅岩友'), findsOneWidget);
    expect(find.text('仅自己'), findsOneWidget);

    await tester.enterText(_fieldWithLabel('视频配文（选填）'), '第一次完攀');
    await tester.tap(find.text('仅岩友'));
    await tester.pump();

    await tester.enterText(_fieldWithLabel('线路名称（选填）'), '测试橙线');
    await tester.enterText(_fieldWithLabel('线路颜色'), '橙');
    WanpanNotice.show(
      tester.element(find.byType(RouteSubmissionScreen)),
      '旧错误提示',
    );
    await tester.pump();
    expect(find.text('旧错误提示'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is WanpanButton && widget.label == '发布新线路',
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump();
    }

    expect(find.byType(WanpanLottieStage), findsOneWidget);
    expect(find.text('旧错误提示'), findsNothing);
    expect(find.text('新线路发布成功！'), findsNothing);
    expect(find.text('测试橙线'), findsNothing);
    expect(find.text('线路和首条完攀已发布'), findsNothing);
    expect(find.text('完成并返回'), findsNothing);
    tester.view.physicalSize = const Size(430, 932);
    await tester.pump();
    final successStage = tester.widget<WanpanLottieStage>(
      find.byType(WanpanLottieStage),
    );
    expect(successStage.width, 430);
    expect(successStage.height, 932);
    expect(
      tester.getSize(find.byType(WanpanLottieStage)),
      const Size(430, 932),
    );
    expect(
      tester
          .widget<Transform>(
            find.byKey(const ValueKey('route-published-stage-scale')),
          )
          .transform
          .storage[0],
      closeTo(1.35, .001),
    );
    await tester.pump(const Duration(milliseconds: 1));
    haptics.clear();

    await tester.pump(const Duration(milliseconds: 615));
    expect(
      haptics.where((value) => value == 'HapticFeedbackType.mediumImpact'),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      haptics.where((value) => value == 'HapticFeedbackType.mediumImpact'),
      hasLength(1),
    );
    expect(find.text('完成并返回'), findsNothing);
    await tester.pump(const Duration(milliseconds: 383));
    expect(find.text('完成并返回'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('完成并返回'), findsOneWidget);
    expect(sounds.plays, hasLength(1));
    expect(sounds.plays.single.cue, WanpanMotionSoundCue.routePublished);
    expect(sounds.plays.single.animated, isTrue);
    await tester.pumpAndSettle();

    final draft = submissionRepository.submittedDraft;
    expect(draft, isNotNull);
    expect(draft!.gymId, _gym.id);
    expect(draft.routeSetId, _activeSet.id);
    expect(draft.name.trim(), '测试橙线');
    expect(draft.points.map((point) => point.type), [
      RoutePointType.start,
      RoutePointType.finish,
    ]);
    expect(draft.videoUrl, 'https://example.com/first-send.mp4');
    expect(draft.caption, '第一次完攀');
    expect(draft.visibility, 'friends');

    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(WanpanLottieStage), findsOneWidget);
    expect(find.text('完成并返回'), findsOneWidget);
    expect(find.text('线路列表'), findsNothing);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is WanpanButton && widget.label == '完成并返回',
      ),
    );
    await tester.pumpAndSettle();
    expect(await routeResult, isTrue);
    expect(find.text('线路列表'), findsOneWidget);
  });
}
