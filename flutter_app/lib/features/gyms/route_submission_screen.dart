import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/models/route_submission_models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/preferences/gym_selection_store.dart';
import '../../core/services/video_preparation_service.dart';
import '../../core/repositories/gym_repository.dart';
import '../../core/repositories/checkin_repository.dart';
import '../../core/repositories/route_submission_repository.dart';
import '../auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/motion/wanpan_motion_sound.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_notice.dart';
import '../../shared/widgets/wanpan_grade_picker.dart';
import '../../shared/widgets/wanpan_gym_picker.dart';
import '../../shared/widgets/wanpan_lottie_stage.dart';
import '../../shared/widgets/wanpan_mascot.dart';
import '../../shared/widgets/wanpan_pressable.dart';

typedef LocalRouteVideoPreviewBuilder = Widget Function(File file);
typedef RouteImageSizeReader = Future<Size> Function(String path);

class RouteSubmissionScreen extends StatefulWidget {
  const RouteSubmissionScreen({
    required this.api,
    required this.session,
    super.key,
    this.initialGymId,
    this.gymRepository,
    this.submissionRepository,
    this.imagePicker,
    this.localVideoPreviewBuilder,
    this.imageSizeReader,
    this.motionSoundPlayer,
    this.selectionStore,
  });

  final ApiClient api;
  final SessionController session;
  final String? initialGymId;
  final GymRepository? gymRepository;
  final RouteSubmissionRepository? submissionRepository;
  final ImagePicker? imagePicker;
  final LocalRouteVideoPreviewBuilder? localVideoPreviewBuilder;
  final RouteImageSizeReader? imageSizeReader;
  final WanpanMotionSoundPlayer? motionSoundPlayer;
  final GymSelectionStore? selectionStore;

  @override
  State<RouteSubmissionScreen> createState() => _RouteSubmissionScreenState();
}

class _RouteSubmissionScreenState extends State<RouteSubmissionScreen> {
  static const _suggestedColors = <String>[
    '红',
    '橙',
    '黄',
    '绿',
    '蓝',
    '紫',
    '黑',
    '白',
  ];

  late final GymRepository _gymRepository;
  late final RouteSubmissionRepository _submissionRepository;
  late final ImagePicker _picker;
  late final String _clientRequestId;
  final _nameController = TextEditingController();
  final _colorController = TextEditingController();
  final _captionController = TextEditingController();

  List<Gym> _gyms = const [];
  GymDetail? _gymDetail;
  String? _gymId;
  String? _routeSetId;
  String _grade = 'V2';
  bool _loadingGyms = true;
  bool _loadingGymDetail = false;
  Object? _gymLoadError;
  Object? _gymDetailError;
  int _gymSelectionRevision = 0;
  int _gymListRequestId = 0;
  int _gymDetailRequestId = 0;

  XFile? _cover;
  Size? _coverSize;
  List<RoutePoint> _points = const [];
  RoutePointType _pointType = RoutePointType.start;
  XFile? _video;
  String _visibility = 'public';

  bool _submitting = false;
  double _progress = 0;
  String _stage = '';
  bool _published = false;
  bool _successHapticPlayed = false;
  bool _motionPreloadStarted = false;
  Timer? _successHapticTimer;
  late final WanpanMotionSoundPlayer _motionSoundPlayer;
  late final bool _ownsMotionSoundPlayer;

  @override
  void initState() {
    super.initState();
    _gymRepository = widget.gymRepository ?? GymRepository(widget.api);
    _submissionRepository =
        widget.submissionRepository ?? RouteSubmissionRepository(widget.api);
    _picker = widget.imagePicker ?? ImagePicker();
    _ownsMotionSoundPlayer = widget.motionSoundPlayer == null;
    _motionSoundPlayer =
        widget.motionSoundPlayer ?? WanpanAssetMotionSoundPlayer();
    _clientRequestId = _newUuidV4();
    final initialGymId = widget.initialGymId?.trim();
    if (initialGymId != null && initialGymId.isNotEmpty) {
      _gymId = initialGymId;
      _loadGymDetail(initialGymId, rememberSelection: true);
    }
    _loadGyms();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionPreloadStarted) return;
    _motionPreloadStarted = true;
    unawaited(preloadWanpanLottie(context, AppAssets.routePublishedAnimation));
    unawaited(
      _motionSoundPlayer.preload(const [WanpanMotionSoundCue.routePublished]),
    );
  }

  @override
  void dispose() {
    _successHapticTimer?.cancel();
    _nameController.dispose();
    _colorController.dispose();
    _captionController.dispose();
    if (_ownsMotionSoundPlayer) {
      unawaited(_motionSoundPlayer.dispose());
    } else {
      unawaited(_motionSoundPlayer.stop());
    }
    super.dispose();
  }

  Future<void> _loadGyms() async {
    final requestId = ++_gymListRequestId;
    if (mounted) {
      setState(() {
        _loadingGyms = true;
        _gymLoadError = null;
      });
    }
    try {
      final gyms = await _gymRepository.getGyms();
      if (!mounted || requestId != _gymListRequestId) return;
      setState(() => _gyms = gyms);
      await _restoreGymSelection(gyms, requestId);
    } catch (error) {
      if (mounted && requestId == _gymListRequestId) {
        setState(() => _gymLoadError = error);
      }
    } finally {
      if (mounted && requestId == _gymListRequestId) {
        setState(() => _loadingGyms = false);
      }
    }
  }

  Future<GymSelectionStore> _getSelectionStore() async =>
      widget.selectionStore ?? await GymSelectionStore.load();

  Future<void> _restoreGymSelection(List<Gym> gyms, int requestId) async {
    if (_gymId != null) return;
    final revision = _gymSelectionRevision;
    try {
      final store = await _getSelectionStore();
      if (!mounted ||
          requestId != _gymListRequestId ||
          revision != _gymSelectionRevision ||
          _gymId != null) {
        return;
      }
      final rememberedId = store.gymId;
      if (rememberedId == null) return;
      if (!gyms.any((gym) => gym.id == rememberedId)) {
        await store.clearGym();
        return;
      }
      setState(() {
        _gymId = rememberedId;
        _gymSelectionRevision++;
      });
      unawaited(_loadGymDetail(rememberedId));
    } catch (_) {
      debugPrint('Could not restore the selected gym.');
    }
  }

  Future<void> _rememberGymSelection(Gym gym, int revision) async {
    try {
      final store = await _getSelectionStore();
      if (!mounted || revision != _gymSelectionRevision || _gymId != gym.id) {
        return;
      }
      await store.rememberGym(gym);
    } catch (_) {
      debugPrint('Could not save the selected gym.');
    }
  }

  Future<void> _loadGymDetail(
    String gymId, {
    bool rememberSelection = false,
  }) async {
    final requestId = ++_gymDetailRequestId;
    final revision = _gymSelectionRevision;
    setState(() {
      _loadingGymDetail = true;
      _gymDetailError = null;
    });
    try {
      final detail = await _gymRepository.getGym(gymId);
      if (!mounted || _gymId != gymId || requestId != _gymDetailRequestId) {
        return;
      }
      final activeSet = detail.routeSets.where((set) => set.active).firstOrNull;
      setState(() {
        _gymDetail = detail;
        _routeSetId = activeSet?.id;
      });
      if (rememberSelection) {
        await _rememberGymSelection(detail.gym, revision);
      }
    } catch (error) {
      if (mounted && _gymId == gymId && requestId == _gymDetailRequestId) {
        setState(() => _gymDetailError = error);
      }
    } finally {
      if (mounted && _gymId == gymId && requestId == _gymDetailRequestId) {
        setState(() => _loadingGymDetail = false);
      }
    }
  }

  Future<void> _selectGym(String gymId) async {
    if (gymId == _gymId && _gymDetail != null) return;
    setState(() {
      _gymSelectionRevision++;
      _gymId = gymId;
      _gymDetail = null;
      _routeSetId = null;
      _gymDetailError = null;
    });
    await _loadGymDetail(gymId);
  }

  Future<void> _openGymPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_gyms.isEmpty && !_loadingGyms) await _loadGyms();
    if (!mounted || _gyms.isEmpty) {
      if (_gymLoadError != null) _notice('岩馆列表没有加载出来，请重试');
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => WanpanGymPickerSheet(
        gyms: _gyms,
        selectedGymId: _gymId,
        selectionStore: widget.selectionStore,
      ),
    );
    if (selected != null && mounted) await _selectGym(selected);
  }

  Future<void> _showImageSourcePicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                subtitle: const Text('选择一张正面、清晰的线路墙照片'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('现在拍摄'),
                subtitle: const Text('尽量让整条线路完整入镜'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null && mounted) await _chooseImage(source);
  }

  Future<void> _chooseImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        imageQuality: 88,
        requestFullMetadata: false,
      );
      if (image == null) return;
      final size = await (widget.imageSizeReader ?? _readImageSize)(image.path);
      if (!mounted) return;
      setState(() {
        _cover = image;
        _coverSize = size;
        _points = const [];
        _pointType = RoutePointType.start;
      });
    } on PlatformException catch (error) {
      if (mounted) _notice(error.message ?? '没有读取到照片，请重试');
    } catch (_) {
      if (mounted) _notice('这张照片无法打开，请换一张试试');
    }
  }

  void _removeImage() {
    if (_cover == null || _submitting) return;
    HapticFeedback.selectionClick();
    setState(() {
      _cover = null;
      _coverSize = null;
      _points = const [];
      _pointType = RoutePointType.start;
    });
  }

  Future<void> _showVideoSourcePicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.video_library_rounded),
                title: const Text('从相册选择视频'),
                subtitle: const Text('支持 MP4 / MOV，最长 5 分钟'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_rounded),
                title: const Text('现在拍摄'),
                subtitle: const Text('记录这条新线路的第一次完攀'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null && mounted) await _chooseVideo(source);
  }

  Future<void> _chooseVideo(ImageSource source) async {
    try {
      final video = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5),
      );
      if (video == null || !mounted) return;
      setState(() => _video = video);
      HapticFeedback.selectionClick();
    } on PlatformException catch (error) {
      if (mounted) _notice(error.message ?? '没有读取到视频，请重试');
    } catch (_) {
      if (mounted) _notice('这个视频无法打开，请换一个试试');
    }
  }

  void _removeVideo() {
    if (_video == null || _submitting) return;
    HapticFeedback.selectionClick();
    setState(() => _video = null);
  }

  Future<Size> _readImageSize(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      return size;
    } finally {
      codec.dispose();
    }
  }

  void _addPoint(Offset normalized) {
    HapticFeedback.selectionClick();
    setState(() {
      _points = [
        ..._points,
        RoutePoint(x: normalized.dx, y: normalized.dy, type: _pointType),
      ];
      if (_pointType == RoutePointType.start) {
        _pointType = RoutePointType.hold;
      }
    });
  }

  void _undoPoint() {
    if (_points.isEmpty) return;
    setState(() => _points = _points.sublist(0, _points.length - 1));
  }

  void _clearPoints() {
    if (_points.isEmpty) return;
    setState(() {
      _points = const [];
      _pointType = RoutePointType.start;
    });
  }

  String? _validationMessage() {
    if (!widget.session.isAuthenticated) return '请先完成登录，再发布线路';
    if (_gymId == null) return '先选择这条线路所在的岩馆';
    if (_loadingGymDetail) return '正在读取岩馆信息，请稍候';
    if (_gymDetail == null) return '岩馆信息没有加载出来，请重试';
    if (_cover != null && _coverSize == null) return '线路照片还未读取完成，请稍候';
    if (_points.isNotEmpty) {
      if (!_points.any((point) => point.type == RoutePointType.start)) {
        return '请补充起点，或清空标点后直接发布';
      }
      if (!_points.any((point) => point.type == RoutePointType.finish)) {
        return '请补充终点，或清空标点后直接发布';
      }
    }
    if (_colorController.text.trim().isEmpty) return '请填写线路颜色';
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final validationMessage = _validationMessage();
    if (validationMessage != null) {
      _notice(validationMessage);
      return;
    }

    final selectedCover = _cover;
    final authorId = widget.session.user?.id;
    final selectedVideo = _video;
    final name = _nameController.text;
    final color = _colorController.text;
    final caption = _captionController.text.trim();
    final visibility = _visibility;
    final gymId = _gymId!;
    final routeSetId = _routeSetId;
    final grade = _grade;
    final points = selectedCover == null
        ? const <RoutePoint>[]
        : List<RoutePoint>.unmodifiable(_points);
    final videoStart = selectedCover == null ? 0.0 : .44;
    final videoUploadStart = selectedCover == null ? .18 : .56;

    setState(() {
      _submitting = true;
      _progress = 0;
      _stage = selectedCover != null
          ? '正在上传线路照片…'
          : selectedVideo != null
          ? '正在压缩完攀视频…'
          : '正在发布线路…';
    });
    try {
      String? coverUrl;
      if (selectedCover != null) {
        coverUrl = await _submissionRepository.uploadCover(
          selectedCover.path,
          onProgress: (progress) {
            if (mounted) {
              setState(
                () =>
                    _progress = progress * (selectedVideo == null ? .82 : .42),
              );
            }
          },
        );
      }
      if (!mounted) return;

      String? videoUrl;
      if (widget.session.user?.id != authorId) {
        throw const ApiException(
          code: 'UPLOAD_SESSION_CHANGED',
          message: '登录账号已切换，请重新提交',
        );
      }
      if (selectedVideo != null) {
        setState(() {
          _stage = '正在上传首条完攀视频…';
          _progress = videoStart;
        });
        videoUrl = await _submissionRepository.uploadVideo(
          selectedVideo.path,
          onPhaseChanged: (phase) {
            if (!mounted) return;
            setState(() {
              _stage = phase == VideoUploadPhase.preparing
                  ? '正在压缩完攀视频…'
                  : '正在上传首条完攀视频…';
              _progress = phase == VideoUploadPhase.preparing
                  ? videoStart
                  : videoUploadStart;
            });
          },
          onProgress: (progress) {
            if (!mounted) return;
            final preparing = _stage == '正在压缩完攀视频…';
            setState(
              () => _progress = preparing
                  ? videoStart + progress * (videoUploadStart - videoStart)
                  : videoUploadStart + progress * (.90 - videoUploadStart),
            );
          },
        );
        if (!mounted) return;
      }

      setState(() {
        _stage = selectedVideo == null ? '正在发布线路…' : '正在发布线路与首条完攀…';
        _progress = .92;
      });
      if (widget.session.user?.id != authorId) {
        throw const ApiException(
          code: 'UPLOAD_SESSION_CHANGED',
          message: '登录账号已切换，请重新提交',
        );
      }
      await _submissionRepository.create(
        RouteSubmissionDraft(
          clientRequestId: _clientRequestId,
          gymId: gymId,
          routeSetId: routeSetId,
          name: name,
          grade: grade,
          color: color,
          coverUrl: coverUrl,
          points: points,
          videoUrl: videoUrl,
          caption: selectedVideo == null ? null : caption,
          visibility: visibility,
        ),
      );
      if (!mounted) return;
      WanpanNotice.dismiss(context);
      setState(() {
        _progress = 1;
        _submitting = false;
        _stage = '';
        _published = true;
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException
          ? error.message
          : error is VideoPreparationException
          ? error.message
          : '发布没有完成，请稍后重试';
      _notice(message);
    } finally {
      if (mounted && !_published) {
        setState(() {
          _submitting = false;
          _progress = 0;
          _stage = '';
        });
      }
    }
  }

  void _notice(String message) {
    WanpanNotice.show(context, message);
  }

  void _handleSuccessAnimationPresented(bool animated) {
    if (_successHapticPlayed) return;
    _successHapticPlayed = true;
    unawaited(
      _motionSoundPlayer.play(
        WanpanMotionSoundCue.routePublished,
        animated: animated,
      ),
    );
    if (!animated) {
      unawaited(_playSuccessHaptic());
      return;
    }
    // The route seal lands at frame 37 in the 60 fps publication animation.
    _successHapticTimer = Timer(
      const Duration(milliseconds: 617),
      () => unawaited(_playSuccessHaptic()),
    );
  }

  Future<void> _playSuccessHaptic() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Publication is already complete. Haptics must never change its result.
    }
  }

  Gym? get _selectedGym {
    final detailGym = _gymDetail?.gym;
    if (detailGym != null) return detailGym;
    return _gyms.where((gym) => gym.id == _gymId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    if (_published) {
      return _RoutePublishedSuccessView(
        onAnimationPresented: _handleSuccessAnimationPresented,
        onDone: () => Navigator.of(context).pop(true),
      );
    }
    return _buildSubmissionForm(context);
  }

  Widget _buildSubmissionForm(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      appBar: AppBar(title: const Text('发布新线路')),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            WanpanSpacing.page,
            WanpanSpacing.sm,
            WanpanSpacing.page,
            MediaQuery.viewInsetsOf(context).bottom + WanpanSpacing.xl,
          ),
          children: [
            _SelectionField(
              key: const Key('route-submission-gym'),
              label: _selectedGym?.name ?? '选择岩馆',
              description: _selectedGym == null
                  ? '先确认线路所在门店'
                  : [
                      _selectedGym!.city,
                      ?_selectedGym!.displayDistrict,
                      _selectedGym!.address,
                    ].join(' · '),
              loading: _loadingGyms && _selectedGym == null,
              onTap: _submitting ? null : _openGymPicker,
            ),
            if (_gymLoadError != null && _gyms.isEmpty) ...[
              const SizedBox(height: 8),
              _InlineError(message: '岩馆列表没有加载出来', onRetry: _loadGyms),
            ],
            if (_loadingGymDetail) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ] else if (_gymDetailError != null) ...[
              const SizedBox(height: 8),
              _InlineError(
                message: '岩馆信息没有加载出来',
                onRetry: _gymId == null ? null : () => _loadGymDetail(_gymId!),
              ),
            ],
            const SizedBox(height: 24),
            const _SectionTitle(number: '1', title: '线路信息'),
            const SizedBox(height: 10),
            WanpanCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: WanpanGradePicker(
                          value: _grade,
                          onChanged: _submitting
                              ? null
                              : (value) => setState(() => _grade = value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: _colorController,
                          enabled: !_submitting,
                          maxLength: 24,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '线路颜色',
                            hintText: '例如：珊瑚橙',
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final color in _suggestedColors) ...[
                          ActionChip(
                            label: Text(color),
                            onPressed: _submitting
                                ? null
                                : () {
                                    _colorController.text = color;
                                    setState(() {});
                                  },
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    enabled: !_submitting,
                    maxLength: 80,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '线路名称（选填）',
                      hintText: '例如：橙色动态线',
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const _SectionTitle(number: '2', title: '拍照并标记线路点（选填）'),
            const SizedBox(height: 6),
            Text(
              '可以跳过。添加照片后，也可选择标记线路起点和终点。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (_cover == null || _coverSize == null)
              _PhotoPlaceholder(
                onTap: _submitting ? null : _showImageSourcePicker,
              )
            else ...[
              _RoutePointEditor(
                file: File(_cover!.path),
                imageSize: _coverSize!,
                points: _points,
                selectedType: _pointType,
                enabled: !_submitting,
                onPointAdded: _addPoint,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _submitting ? null : _showImageSourcePicker,
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('更换照片'),
                  ),
                  TextButton.icon(
                    onPressed: _submitting ? null : _removeImage,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('移除照片'),
                  ),
                  Text(
                    '${_points.length} 个点',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: RoutePointType.values
                    .map(
                      (type) => ChoiceChip(
                        avatar: Icon(type.icon, size: 17),
                        label: Text(type.label),
                        selected: _pointType == type,
                        onSelected: _submitting
                            ? null
                            : (_) {
                                HapticFeedback.selectionClick();
                                setState(() => _pointType = type);
                              },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton(
                    onPressed: _submitting || _points.isEmpty
                        ? null
                        : _undoPoint,
                    child: const Text('撤销上一步'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _submitting || _points.isEmpty
                        ? null
                        : _clearPoints,
                    child: const Text('清空标点'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            const _SectionTitle(number: '3', title: '首条完攀（选填）'),
            const SizedBox(height: 6),
            Text(
              '可单独添加视频，作为这条线路的第一条完攀内容。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: WanpanMotion.duration(context, WanpanMotion.exit),
              switchInCurve: WanpanMotion.curve(context),
              switchOutCurve: WanpanMotion.curve(context),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _video == null
                  ? _VideoPlaceholder(
                      key: const ValueKey('video-placeholder'),
                      onTap: _submitting ? null : _showVideoSourcePicker,
                    )
                  : widget.localVideoPreviewBuilder?.call(File(_video!.path)) ??
                        _LocalVideoPreview(
                          key: ValueKey(_video!.path),
                          file: File(_video!.path),
                          enabled: !_submitting,
                          onReplace: _showVideoSourcePicker,
                          onRemove: _removeVideo,
                        ),
            ),
            if (_video != null) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _captionController,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: '视频配文（选填）',
                  hintText: '例如：第一条尝试，最后一步终于稳住了！',
                ),
              ),
              const SizedBox(height: 10),
              _VisibilityPicker(
                value: _visibility,
                enabled: !_submitting,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  setState(() => _visibility = value);
                },
              ),
            ],
            const SizedBox(height: 26),
            if (_submitting) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _stage,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Text(
                    '${(_progress * 100).round()}%',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress, minHeight: 6),
              const SizedBox(height: 16),
            ],
            WanpanButton(
              label: _submitting ? '正在发布…' : '发布新线路',
              loading: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    ),
  );
}

class _RoutePublishedSuccessView extends StatefulWidget {
  const _RoutePublishedSuccessView({
    required this.onAnimationPresented,
    required this.onDone,
  });

  final WanpanLottiePresented onAnimationPresented;
  final VoidCallback onDone;

  @override
  State<_RoutePublishedSuccessView> createState() =>
      _RoutePublishedSuccessViewState();
}

class _RoutePublishedSuccessViewState
    extends State<_RoutePublishedSuccessView> {
  bool _showDone = false;

  void _handleAnimationCompleted(bool _) {
    if (_showDone || !mounted) return;
    setState(() => _showDone = true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.scale(
              key: const ValueKey('route-published-stage-scale'),
              scale: 1.35,
              child: LayoutBuilder(
                builder: (context, constraints) => WanpanLottieStage(
                  asset: AppAssets.routePublishedAnimation,
                  semanticLabel: '黑猫用笔画完线路记录并点亮勾选',
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  fit: BoxFit.contain,
                  onPresented: widget.onAnimationPresented,
                  onCompleted: _handleAnimationCompleted,
                  fallback: const WanpanMascot(
                    asset: AppAssets.routeMapCat,
                    width: 320,
                    height: 320,
                    radius: 48,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSwitcher(
                duration: WanpanMotion.duration(
                  context,
                  WanpanMotion.enter,
                  reduced: Duration.zero,
                ),
                switchInCurve: WanpanMotion.curve(context),
                switchOutCurve: WanpanMotion.curve(context),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _showDone
                    ? Padding(
                        key: const ValueKey('route-published-done'),
                        padding: const EdgeInsets.fromLTRB(
                          WanpanSpacing.page,
                          0,
                          WanpanSpacing.page,
                          WanpanSpacing.xl,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: WanpanButton(
                            label: '完成并返回',
                            icon: const Icon(Icons.check_rounded),
                            onPressed: widget.onDone,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('route-published-waiting'),
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.number, required this.title});

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: WanpanColors.coral,
          shape: BoxShape.circle,
        ),
        child: Text(
          number,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    ],
  );
}

class _SelectionField extends StatelessWidget {
  const _SelectionField({
    super.key,
    required this.label,
    required this.description,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WanpanCard(
    onTap: onTap,
    semanticLabel: '选择岩馆',
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WanpanColors.coralSoft,
            borderRadius: BorderRadius.circular(15),
          ),
          child: loading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Icon(
                  Icons.location_on_rounded,
                  color: WanpanColors.coralStrong,
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right_rounded, color: WanpanColors.muted),
      ],
    ),
  );
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WanpanCard(
    onTap: onTap,
    semanticLabel: '拍摄或选择线路照片',
    color: WanpanColors.surface.withValues(alpha: .76),
    borderColor: WanpanColors.coral.withValues(alpha: .28),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: WanpanColors.grapeSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add_a_photo_outlined,
              color: WanpanColors.grape,
              size: 27,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '拍摄或选择线路照片',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text(
            '选填，不添加照片也可以发布',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WanpanCard(
    onTap: onTap,
    semanticLabel: '添加首条完攀视频',
    color: WanpanColors.surface.withValues(alpha: .78),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WanpanColors.surface,
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(
            Icons.video_call_rounded,
            color: WanpanColors.grape,
            size: 27,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('添加完攀视频', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                '支持 MP4 / MOV，最长 5 分钟',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const Icon(Icons.add_rounded, color: WanpanColors.grape, size: 30),
      ],
    ),
  );
}

class _LocalVideoPreview extends StatefulWidget {
  const _LocalVideoPreview({
    required this.file,
    required this.enabled,
    required this.onReplace,
    required this.onRemove,
    super.key,
  });

  final File file;
  final bool enabled;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  State<_LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<_LocalVideoPreview>
    with WidgetsBindingObserver {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.file(widget.file);
    _controller.addListener(_syncPlaybackState);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _ready) _controller.pause();
  }

  void _syncPlaybackState() {
    final playing = _controller.value.isPlaying;
    if (mounted && playing != _playing) setState(() => _playing = playing);
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _togglePlayback() async {
    if (!_ready || !widget.enabled) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      if (_controller.value.position >= _controller.value.duration) {
        await _controller.seekTo(Duration.zero);
      }
      await _controller.play();
      HapticFeedback.selectionClick();
    }
    if (mounted) setState(() => _playing = _controller.value.isPlaying);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _failed
        ? Container(
            height: 180,
            color: WanpanColors.surfaceSoft,
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_off_outlined, color: WanpanColors.muted),
                SizedBox(height: 8),
                Text('暂时无法预览，可更换视频'),
              ],
            ),
          )
        : !_ready
        ? const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          )
        : AspectRatio(
            aspectRatio: _controller.value.aspectRatio
                .clamp(.72, 1.8)
                .toDouble(),
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(_controller),
                  Semantics(
                    button: true,
                    label: _playing ? '暂停视频预览' : '播放视频预览',
                    onTap: _togglePlayback,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTap: _togglePlayback,
                      child: AnimatedContainer(
                        duration: WanpanMotion.duration(
                          context,
                          WanpanMotion.press,
                        ),
                        color: Colors.black.withValues(
                          alpha: _playing ? 0 : .18,
                        ),
                        alignment: Alignment.center,
                        child: AnimatedOpacity(
                          opacity: _playing ? 0 : 1,
                          duration: WanpanMotion.duration(
                            context,
                            WanpanMotion.press,
                          ),
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .92),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: WanpanColors.ink,
                              size: 34,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 8,
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: widget.enabled,
                      colors: const VideoProgressColors(
                        playedColor: WanpanColors.coral,
                        bufferedColor: Color(0x99FFFFFF),
                        backgroundColor: Color(0x55FFFFFF),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 5),
                    ),
                  ),
                ],
              ),
            ),
          );

    return WanpanCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WanpanRadii.large),
        child: Column(
          children: [
            preview,
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: WanpanColors.success,
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(child: Text('视频已选择，可点击画面预览')),
                  TextButton(
                    onPressed: widget.enabled ? widget.onReplace : null,
                    child: const Text('更换'),
                  ),
                  IconButton(
                    tooltip: '移除视频',
                    onPressed: widget.enabled ? widget.onRemove : null,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibilityPicker extends StatelessWidget {
  const _VisibilityPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final description = switch (value) {
      'friends' => '仅你和已添加的岩友可在朋友圈看到',
      'private' => '只有你自己能看到这条完攀',
      _ => '所有人都可以在广场看到这条完攀',
    };
    return WanpanCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('谁可以看', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: 'public',
                  icon: Icon(Icons.public_rounded, size: 18),
                  label: Text('同步广场'),
                ),
                ButtonSegment(
                  value: 'friends',
                  icon: Icon(Icons.people_alt_rounded, size: 18),
                  label: Text('仅岩友'),
                ),
                ButtonSegment(
                  value: 'private',
                  icon: Icon(Icons.lock_outline_rounded, size: 18),
                  label: Text('仅自己'),
                ),
              ],
              selected: {value},
              onSelectionChanged: enabled
                  ? (selection) => onChanged(selection.first)
                  : null,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _RoutePointEditor extends StatelessWidget {
  const _RoutePointEditor({
    required this.file,
    required this.imageSize,
    required this.points,
    required this.selectedType,
    required this.enabled,
    required this.onPointAdded,
  });

  final File file;
  final Size imageSize;
  final List<RoutePoint> points;
  final RoutePointType selectedType;
  final bool enabled;
  final ValueChanged<Offset> onPointAdded;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = imageSize.width / imageSize.height;
    return ClipRRect(
      borderRadius: BorderRadius.circular(WanpanRadii.large),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = width / aspectRatio;
          final displaySize = Size(width, height);
          return SizedBox.fromSize(
            size: displaySize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: enabled
                  ? (details) {
                      final point = Offset(
                        (details.localPosition.dx / displaySize.width).clamp(
                          0,
                          1,
                        ),
                        (details.localPosition.dy / displaySize.height).clamp(
                          0,
                          1,
                        ),
                      );
                      onPointAdded(point);
                    }
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    file,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                  ColoredBox(color: Colors.black.withValues(alpha: .04)),
                  for (var index = 0; index < points.length; index++)
                    Positioned(
                      left: points[index].x * width - 15,
                      top: points[index].y * height - 15,
                      child: _PointMarker(
                        point: points[index],
                        number: index + 1,
                      ),
                    ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xC917191C),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '点击添加${selectedType.label}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PointMarker extends StatelessWidget {
  const _PointMarker({required this.point, required this.number});

  final RoutePoint point;
  final int number;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: point.type.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4717191C),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        switch (point.type) {
          RoutePointType.start => 'S',
          RoutePointType.hold => '$number',
          RoutePointType.finish => 'T',
        },
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4F1),
      borderRadius: BorderRadius.circular(WanpanRadii.small),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: WanpanColors.danger),
        const SizedBox(width: 9),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

extension on RoutePointType {
  String get label => switch (this) {
    RoutePointType.start => '起点',
    RoutePointType.hold => '途经点',
    RoutePointType.finish => '终点',
  };

  IconData get icon => switch (this) {
    RoutePointType.start => Icons.flag_circle_outlined,
    RoutePointType.hold => Icons.radio_button_checked_rounded,
    RoutePointType.finish => Icons.sports_score_rounded,
  };

  Color get color => switch (this) {
    RoutePointType.start => WanpanColors.success,
    RoutePointType.hold => WanpanColors.coral,
    RoutePointType.finish => WanpanColors.ink,
  };
}
