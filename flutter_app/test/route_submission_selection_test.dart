import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/models/route_submission_models.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/preferences/gym_selection_store.dart';
import 'package:wanpan_diary/core/repositories/gym_repository.dart';
import 'package:wanpan_diary/core/repositories/route_submission_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/gyms/route_submission_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_grade_picker.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_gym_picker.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

import 'support/fake_motion_sound_player.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

const _firstGym = Gym(
  id: 'gym-nanshan',
  name: '香蕉攀岩·南山店',
  city: '深圳',
  province: '广东省',
  district: '南山区',
  address: '科技园',
  verified: true,
);

const _secondGym = Gym(
  id: 'gym-baoan',
  name: '香蕉攀岩·宝安店',
  city: '深圳',
  province: '广东省',
  district: '宝安区',
  address: '创业路',
  verified: true,
);

GymDetail _detail(Gym gym) => GymDetail(
  gym: gym,
  routeSets: [
    RouteSet(
      id: 'set-${gym.id}',
      gymId: gym.id,
      name: '${gym.name}本轮线路',
      startsOn: DateTime(2026, 8, 1),
      active: true,
    ),
  ],
);

class _SelectionGymRepository extends GymRepository {
  _SelectionGymRepository(super.api);

  List<Gym> gyms = [_firstGym, _secondGym];
  Object? directoryError;
  Completer<List<Gym>>? delayedDirectory;
  final delayedDetails = <String, Completer<GymDetail>>{};
  final requestedGymIds = <String>[];

  @override
  Future<List<Gym>> getGyms({String? city, String? query}) async {
    if (directoryError case final error?) throw error;
    return delayedDirectory?.future ?? gyms;
  }

  @override
  Future<GymDetail> getGym(String gymId) async {
    requestedGymIds.add(gymId);
    return delayedDetails[gymId]?.future ??
        _detail([_firstGym, _secondGym].singleWhere((gym) => gym.id == gymId));
  }
}

class _SubmissionRepository extends RouteSubmissionRepository {
  _SubmissionRepository(super.api);

  RouteSubmissionDraft? submittedDraft;

  @override
  Future<String> uploadCover(
    String filePath, {
    RouteCoverUploadProgress? onProgress,
  }) async => 'https://example.com/route.png';

  @override
  Future<RouteSubmission> create(RouteSubmissionDraft draft) async {
    submittedDraft = draft;
    return RouteSubmission(
      id: 'submission-1',
      submitterId: 'me',
      gymId: draft.gymId,
      routeSetId: draft.routeSetId,
      name: draft.name,
      grade: draft.grade,
      color: draft.color,
      coverUrl: draft.coverUrl,
      points: draft.points,
      status: 'approved',
    );
  }
}

class _ImagePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => XFile(File('assets/logo.png').absolute.path);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _switchGym(WidgetTester tester, Gym gym) async {
  await tester.tap(find.byKey(const Key('route-submission-gym')));
  await tester.pumpAndSettle();
  final store = find.descendant(
    of: find.byType(WanpanGymPickerSheet),
    matching: find.text(gym.name),
  );
  await tester.ensureVisible(store);
  await tester.tap(store);
  await tester.pumpAndSettle();
}

Future<void> _publish(WidgetTester tester, {String name = '换馆后的新线路'}) async {
  await tester.enterText(_field('线路名称（选填）'), name);
  await tester.enterText(_field('线路颜色'), '橙');
  await tester.tap(find.text('拍摄或选择线路照片'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('从相册选择'));
  await tester.pumpAndSettle();
  void addPoint(String hint, Offset point) {
    tester
        .widget<GestureDetector>(
          find
              .ancestor(
                of: find.text(hint),
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTapDown!(TapDownDetails(localPosition: point));
  }

  addPoint('点击添加起点', const Offset(100, 100));
  await tester.pump();
  tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '终点')).onSelected!(
    true,
  );
  await tester.pump();
  addPoint('点击添加终点', const Offset(200, 200));
  await tester.pump();
  final publish = find.byWidgetPredicate(
    (widget) => widget is WanpanButton && widget.label == '发布新线路',
  );
  await tester.ensureVisible(publish);
  await tester.tap(publish);
  for (var index = 0; index < 4; index++) {
    await tester.pump();
  }
}

void main() {
  late SharedPreferences preferences;
  late GymSelectionStore selectionStore;
  late SessionController session;
  late ApiClient api;
  late _SelectionGymRepository gymRepository;
  late _SubmissionRepository submissionRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    selectionStore = GymSelectionStore(preferences: preferences);
    session = SessionController(
      preferences: preferences,
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
    api = ApiClient(config: _config, accessTokenProvider: () => 'test-token');
    gymRepository = _SelectionGymRepository(api);
    submissionRepository = _SubmissionRepository(api);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    String? initialGymId,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: RouteSubmissionScreen(
          key: UniqueKey(),
          api: api,
          session: session,
          initialGymId: initialGymId,
          selectionStore: GymSelectionStore(preferences: preferences),
          gymRepository: gymRepository,
          submissionRepository: submissionRepository,
          imagePicker: _ImagePicker(),
          imageSizeReader: (_) async => const Size(1254, 1254),
          motionSoundPlayer: FakeMotionSoundPlayer(),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('岩馆位于表单最上方，未选择时不默认第一家门店', (tester) async {
    useTallScreen(tester);
    await pumpScreen(tester);

    final selector = find.byKey(const Key('route-submission-gym'));
    expect(
      find.descendant(of: selector, matching: find.text('选择岩馆')),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(selector).dy,
      lessThan(tester.getTopLeft(find.text('线路信息')).dy),
    );
    expect(gymRepository.requestedGymIds, isEmpty);
    expect(selectionStore.gymId, isNull);
  });

  testWidgets('重新创建页面和存储实例仍恢复最近一次选择', (tester) async {
    useTallScreen(tester);
    await selectionStore.rememberGym(_firstGym);
    await pumpScreen(tester);
    expect(find.text(_firstGym.name), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester);

    expect(find.text(_firstGym.name), findsOneWidget);
    expect(gymRepository.requestedGymIds, [_firstGym.id, _firstGym.id]);
  });

  testWidgets('名称位于颜色下方且留空可以发布，不再显示或提交墙面区域', (tester) async {
    useTallScreen(tester);
    await pumpScreen(tester, initialGymId: _firstGym.id);

    expect(
      tester.getTopLeft(_field('线路名称（选填）')).dy,
      greaterThan(tester.getBottomLeft(_field('线路颜色')).dy),
    );
    expect(find.text('墙面区域（选填）'), findsNothing);
    await tester.tap(find.byType(WanpanGradePicker));
    await tester.pumpAndSettle();
    expect(find.text('V17'), findsNothing);
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('V17'));
    await tester.pumpAndSettle();
    await _publish(tester, name: '   ');

    final draft = submissionRepository.submittedDraft;
    expect(draft, isNotNull);
    expect(draft!.grade, 'V17');
    expect(draft.toJson()['name'], 'V17 橙线');
    expect(draft.toJson().containsKey('wallZone'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('明确岩馆入口优先于记忆，目录加载失败仍可读取该馆详情', (tester) async {
    useTallScreen(tester);
    await selectionStore.rememberGym(_firstGym);
    gymRepository.directoryError = const SocketException('offline');
    await pumpScreen(tester, initialGymId: _secondGym.id);

    expect(find.text(_secondGym.name), findsOneWidget);
    expect(find.text(_firstGym.name), findsNothing);
    expect(gymRepository.requestedGymIds, [_secondGym.id]);
    expect(selectionStore.gymId, _secondGym.id);
  });

  testWidgets('手动切换后再次进入保留该馆，发布线路使用该馆换线周期', (tester) async {
    useTallScreen(tester);
    await selectionStore.rememberGym(_firstGym);
    await pumpScreen(tester);
    await _switchGym(tester, _secondGym);
    expect(find.text(_secondGym.name), findsOneWidget);
    expect(selectionStore.gymId, _secondGym.id);

    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester);
    expect(find.text(_secondGym.name), findsOneWidget);
    await _publish(tester);

    expect(submissionRepository.submittedDraft, isNotNull);
    expect(submissionRepository.submittedDraft!.gymId, _secondGym.id);
    expect(
      submissionRepository.submittedDraft!.routeSetId,
      'set-${_secondGym.id}',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('记忆门店已不在目录时保持未选择，不擅自切换其他馆', (tester) async {
    useTallScreen(tester);
    await selectionStore.rememberGym(_firstGym);
    gymRepository.gyms = [_secondGym];
    await pumpScreen(tester);

    expect(find.text('选择岩馆'), findsOneWidget);
    expect(find.text(_secondGym.name), findsNothing);
    expect(gymRepository.requestedGymIds, isEmpty);
    expect(selectionStore.gymId, isNull);
  });

  testWidgets('目录临时失败保留记忆，重进恢复同一家岩馆', (tester) async {
    useTallScreen(tester);
    await selectionStore.rememberGym(_firstGym);
    gymRepository.directoryError = const SocketException('offline');
    await pumpScreen(tester);
    expect(selectionStore.gymId, _firstGym.id);
    expect(gymRepository.requestedGymIds, isEmpty);

    gymRepository.directoryError = null;
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester);
    expect(find.text(_firstGym.name), findsOneWidget);
  });

  testWidgets('恢复中的旧门店详情晚到不会覆盖手动切换及其换线周期', (tester) async {
    useTallScreen(tester);
    await selectionStore.rememberGym(_firstGym);
    final delayed = Completer<GymDetail>();
    gymRepository.delayedDetails[_firstGym.id] = delayed;
    await pumpScreen(tester, settle: false);
    expect(gymRepository.requestedGymIds, [_firstGym.id]);

    // Open the picker while the old detail request still drives a spinner.
    await tester.tap(find.byKey(const Key('route-submission-gym')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(
      find.descendant(
        of: find.byType(WanpanGymPickerSheet),
        matching: find.text(_secondGym.name),
      ),
    );
    await tester.pumpAndSettle();
    delayed.complete(_detail(_firstGym));
    await tester.pumpAndSettle();

    expect(find.text(_secondGym.name), findsOneWidget);
    expect(find.text(_firstGym.name), findsNothing);
    expect(selectionStore.gymId, _secondGym.id);
    await _publish(tester);
    expect(submissionRepository.submittedDraft!.gymId, _secondGym.id);
    expect(
      submissionRepository.submittedDraft!.routeSetId,
      'set-${_secondGym.id}',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('晚到的目录不会用旧记忆替换明确入口', (tester) async {
    useTallScreen(tester);
    await selectionStore.rememberGym(_firstGym);
    final directory = Completer<List<Gym>>();
    gymRepository.delayedDirectory = directory;
    await pumpScreen(tester, initialGymId: _secondGym.id, settle: false);
    expect(find.text(_secondGym.name), findsOneWidget);

    directory.complete([_firstGym, _secondGym]);
    await tester.pumpAndSettle();
    expect(find.text(_secondGym.name), findsOneWidget);
    expect(gymRepository.requestedGymIds, [_secondGym.id]);
    expect(selectionStore.gymId, _secondGym.id);
  });
}
