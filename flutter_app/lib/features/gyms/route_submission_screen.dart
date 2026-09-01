import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/models/route_submission_models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/repositories/gym_repository.dart';
import '../../core/repositories/route_submission_repository.dart';
import '../auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_card.dart';
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
  });

  final ApiClient api;
  final SessionController session;
  final String? initialGymId;
  final GymRepository? gymRepository;
  final RouteSubmissionRepository? submissionRepository;
  final ImagePicker? imagePicker;
  final LocalRouteVideoPreviewBuilder? localVideoPreviewBuilder;
  final RouteImageSizeReader? imageSizeReader;

  @override
  State<RouteSubmissionScreen> createState() => _RouteSubmissionScreenState();
}

class _RouteSubmissionScreenState extends State<RouteSubmissionScreen> {
  static const _grades = <String>[
    'V0',
    'V1',
    'V2',
    'V3',
    'V4',
    'V5',
    'V6',
    'V7',
    'V8',
    'V9',
    'V10',
    'V11',
    'V12',
    'V13',
    'V14',
    'V15',
    'V16',
    'V17',
  ];
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
  final _wallZoneController = TextEditingController();
  final _routeSearchController = TextEditingController();
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
  List<ClimbingRoute> _existingRoutes = const [];
  bool _loadingRoutes = false;
  Object? _routesLoadError;
  String _routeQuery = '';
  int _routesRequestId = 0;

  XFile? _cover;
  Size? _coverSize;
  List<RoutePoint> _points = const [];
  RoutePointType _pointType = RoutePointType.start;
  XFile? _video;
  String _visibility = 'public';

  bool _submitting = false;
  double _progress = 0;
  String _stage = '';

  @override
  void initState() {
    super.initState();
    _gymRepository = widget.gymRepository ?? GymRepository(widget.api);
    _submissionRepository =
        widget.submissionRepository ?? RouteSubmissionRepository(widget.api);
    _picker = widget.imagePicker ?? ImagePicker();
    _clientRequestId = _newUuidV4();
    final initialGymId = widget.initialGymId?.trim();
    if (initialGymId != null && initialGymId.isNotEmpty) {
      _gymId = initialGymId;
      _loadGymDetail(initialGymId);
      _loadExistingRoutes(initialGymId);
    }
    _loadGyms();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _colorController.dispose();
    _wallZoneController.dispose();
    _routeSearchController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadGyms() async {
    if (mounted) {
      setState(() {
        _loadingGyms = true;
        _gymLoadError = null;
      });
    }
    try {
      final gyms = await _gymRepository.getGyms();
      if (!mounted) return;
      setState(() => _gyms = gyms);
    } catch (error) {
      if (mounted) setState(() => _gymLoadError = error);
    } finally {
      if (mounted) setState(() => _loadingGyms = false);
    }
  }

  Future<void> _loadGymDetail(String gymId) async {
    setState(() {
      _loadingGymDetail = true;
      _gymDetailError = null;
    });
    try {
      final detail = await _gymRepository.getGym(gymId);
      if (!mounted || _gymId != gymId) return;
      final activeSet = detail.routeSets.where((set) => set.active).firstOrNull;
      setState(() {
        _gymDetail = detail;
        _routeSetId = activeSet?.id;
      });
    } catch (error) {
      if (mounted && _gymId == gymId) {
        setState(() => _gymDetailError = error);
      }
    } finally {
      if (mounted && _gymId == gymId) {
        setState(() => _loadingGymDetail = false);
      }
    }
  }

  Future<void> _selectGym(String gymId) async {
    if (gymId == _gymId && _gymDetail != null) return;
    setState(() {
      _gymId = gymId;
      _gymDetail = null;
      _routeSetId = null;
      _gymDetailError = null;
      _existingRoutes = const [];
      _routesLoadError = null;
      _routeQuery = '';
      _routeSearchController.clear();
    });
    await Future.wait([_loadGymDetail(gymId), _loadExistingRoutes(gymId)]);
  }

  Future<void> _loadExistingRoutes(String gymId) async {
    final requestId = ++_routesRequestId;
    setState(() {
      _loadingRoutes = true;
      _routesLoadError = null;
    });
    try {
      final routes = await _gymRepository.getRoutes(gymId);
      if (!mounted || _gymId != gymId || requestId != _routesRequestId) return;
      setState(() => _existingRoutes = routes);
    } catch (error) {
      if (mounted && _gymId == gymId && requestId == _routesRequestId) {
        setState(() => _routesLoadError = error);
      }
    } finally {
      if (mounted && _gymId == gymId && requestId == _routesRequestId) {
        setState(() => _loadingRoutes = false);
      }
    }
  }

  List<ClimbingRoute> get _filteredExistingRoutes {
    final query = _routeQuery.trim().toLowerCase();
    if (query.isEmpty) return _existingRoutes.take(5).toList(growable: false);
    return _existingRoutes
        .where((route) {
          final searchable = <String>[
            route.name,
            route.grade,
            route.color,
            if (route.wallZone != null) route.wallZone!,
            if (route.routeSetName != null) route.routeSetName!,
            if (route.setterName != null) route.setterName!,
          ].join(' ').toLowerCase();
          return searchable.contains(query);
        })
        .take(8)
        .toList(growable: false);
  }

  Future<void> _openExistingRoute(ClimbingRoute route) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final created = await context.push<bool>(
      '/routes/${route.id}/checkin',
      extra: {'grade': route.grade, 'name': route.name},
    );
    if (created == true && mounted && _gymId != null) {
      await _loadExistingRoutes(_gymId!);
    }
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
      builder: (context) => _GymPickerSheet(gyms: _gyms, selectedGymId: _gymId),
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
    if (_loadingGymDetail) return '正在读取岩馆线路周期，请稍候';
    if (_gymDetail == null) return '岩馆信息没有加载出来，请重试';
    if (_cover == null || _coverSize == null) return '先拍摄或选择线路照片';
    if (!_points.any((point) => point.type == RoutePointType.start)) {
      return '请在线路照片上标记起点';
    }
    if (!_points.any((point) => point.type == RoutePointType.finish)) {
      return '请在线路照片上标记终点';
    }
    if (_points.length < 2) return '请至少标记两个线路点';
    if (_nameController.text.trim().isEmpty) return '请填写线路名称';
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

    final selectedCover = _cover!;
    final selectedVideo = _video;
    final name = _nameController.text;
    final color = _colorController.text;
    final wallZone = _wallZoneController.text;
    final caption = _captionController.text.trim();
    final visibility = _visibility;
    final gymId = _gymId!;
    final routeSetId = _routeSetId;
    final grade = _grade;
    final points = List<RoutePoint>.unmodifiable(_points);

    setState(() {
      _submitting = true;
      _progress = 0;
      _stage = '正在上传线路照片…';
    });
    try {
      final coverUrl = await _submissionRepository.uploadCover(
        selectedCover.path,
        onProgress: (progress) {
          if (mounted) {
            setState(
              () => _progress = progress * (selectedVideo == null ? .82 : .42),
            );
          }
        },
      );
      if (!mounted) return;

      String? videoUrl;
      if (selectedVideo != null) {
        setState(() {
          _stage = '正在上传首条完攀视频…';
          _progress = .44;
        });
        final filename = selectedVideo.name.trim().isEmpty
            ? File(selectedVideo.path).uri.pathSegments.last
            : selectedVideo.name.trim();
        final mimeType = filename.toLowerCase().endsWith('.mov')
            ? 'video/quicktime'
            : 'video/mp4';
        videoUrl = await _submissionRepository.uploadVideo(
          selectedVideo.path,
          filename: filename,
          mimeType: mimeType,
          onProgress: (progress) {
            if (mounted) setState(() => _progress = .44 + progress * .46);
          },
        );
        if (!mounted) return;
      }

      setState(() {
        _stage = selectedVideo == null ? '正在发布线路…' : '正在发布线路与首条完攀…';
        _progress = .92;
      });
      final result = await _submissionRepository.create(
        RouteSubmissionDraft(
          clientRequestId: _clientRequestId,
          gymId: gymId,
          routeSetId: routeSetId,
          name: name,
          grade: grade,
          color: color,
          wallZone: wallZone,
          coverUrl: coverUrl,
          points: points,
          videoUrl: videoUrl,
          caption: selectedVideo == null ? null : caption,
          visibility: visibility,
        ),
      );
      if (!mounted) return;
      setState(() => _progress = 1);
      await HapticFeedback.mediumImpact();
      _notice(_successMessage(result, hasVideo: selectedVideo != null));
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException ? error.message : '发布没有完成，请稍后重试';
      _notice(message);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _progress = 0;
          _stage = '';
        });
      }
    }
  }

  String _successMessage(RouteSubmission result, {required bool hasVideo}) {
    if (!hasVideo) return '线路已发布';
    return switch (result.videoModerationStatus) {
      'approved' => '线路和首条完攀已发布',
      'pending' => '线路已发布，视频审核后展示',
      'rejected' => '线路已发布，视频未通过内容审核',
      _ => '线路已发布，视频将按内容规则展示',
    };
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Gym? get _selectedGym {
    final detailGym = _gymDetail?.gym;
    if (detailGym != null) return detailGym;
    return _gyms.where((gym) => gym.id == _gymId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) => PopScope(
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
            WanpanCard(
              color: WanpanColors.coralSoft.withValues(alpha: .62),
              borderColor: Colors.transparent,
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: 116,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned(
                      left: 18,
                      top: 24,
                      child: Icon(
                        Icons.gesture_rounded,
                        color: WanpanColors.coral,
                        size: 30,
                      ),
                    ),
                    Positioned(
                      left: 62,
                      right: 106,
                      top: 20,
                      child: Text(
                        '把新线路留给更多岩友',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Positioned(
                      left: 62,
                      right: 92,
                      top: 50,
                      child: Text(
                        '先搜索馆内已有线路；没找到时，拍照标点即可直接发布新线路。',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Positioned(
                      right: -25,
                      top: -31,
                      width: 140,
                      height: 124,
                      child: Image.asset(
                        AppAssets.profilePeekCat,
                        cacheWidth: 460,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),
            const _SectionTitle(number: '1', title: '选择岩馆与线路墙'),
            const SizedBox(height: 10),
            _SelectionField(
              label: _selectedGym?.name ?? '选择岩馆',
              description: _selectedGym == null
                  ? '先确认线路所在门店'
                  : [
                      _selectedGym!.city,
                      if (_selectedGym!.district != null)
                        _selectedGym!.district!,
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
                message: '线路周期没有加载出来',
                onRetry: _gymId == null ? null : () => _loadGymDetail(_gymId!),
              ),
            ] else if (_gymDetail != null) ...[
              const SizedBox(height: 16),
              Text('线路墙 / 周期', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              _RouteSetPicker(
                routeSets: _gymDetail!.routeSets,
                selectedId: _routeSetId,
                enabled: !_submitting,
                onChanged: (value) => setState(() => _routeSetId = value),
              ),
            ],
            if (_gymId != null) ...[
              const SizedBox(height: 22),
              _ExistingRoutesPanel(
                controller: _routeSearchController,
                routes: _filteredExistingRoutes,
                totalCount: _existingRoutes.length,
                query: _routeQuery,
                loading: _loadingRoutes,
                hasError: _routesLoadError != null,
                enabled: !_submitting,
                onQueryChanged: (value) =>
                    setState(() => _routeQuery = value.trim()),
                onRouteTap: _openExistingRoute,
                onRetry: () => _loadExistingRoutes(_gymId!),
              ),
            ],
            const SizedBox(height: 30),
            const _SectionTitle(number: '2', title: '拍照并标记线路点'),
            const SizedBox(height: 6),
            Text(
              '照片尽量正对岩壁。标点坐标会跟随原图保存。',
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
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _submitting ? null : _showImageSourcePicker,
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('更换照片'),
                  ),
                  const Spacer(),
                  Text(
                    '${_points.length} 个点',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ],
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
                  onPressed: _submitting || _points.isEmpty ? null : _undoPoint,
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
            const SizedBox(height: 24),
            const _SectionTitle(number: '3', title: '首条完攀（选填）'),
            const SizedBox(height: 6),
            Text(
              '视频会放在线路图下方，也会成为这条线路的第一条完攀内容。',
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
            const SizedBox(height: 24),
            const _SectionTitle(number: '4', title: '补充线路信息'),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              enabled: !_submitting,
              maxLength: 80,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '线路名称',
                hintText: '例如：橙色动态线',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_grade),
              initialValue: _grade,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '难度'),
              items: _grades
                  .map(
                    (grade) =>
                        DropdownMenuItem(value: grade, child: Text(grade)),
                  )
                  .toList(growable: false),
              onChanged: _submitting
                  ? null
                  : (value) {
                      if (value != null) setState(() => _grade = value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
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
              controller: _wallZoneController,
              enabled: !_submitting,
              maxLength: 40,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: '墙面区域（选填）',
                hintText: '例如：A区斜墙',
                counterText: '',
              ),
            ),
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
            const SizedBox(height: 10),
            Text(
              _video == null ? '提交后线路会立即发布。' : '线路会立即发布；视频按内容规则处理后展示。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
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

class _ExistingRoutesPanel extends StatelessWidget {
  const _ExistingRoutesPanel({
    required this.controller,
    required this.routes,
    required this.totalCount,
    required this.query,
    required this.loading,
    required this.hasError,
    required this.enabled,
    required this.onQueryChanged,
    required this.onRouteTap,
    required this.onRetry,
  });

  final TextEditingController controller;
  final List<ClimbingRoute> routes;
  final int totalCount;
  final String query;
  final bool loading;
  final bool hasError;
  final bool enabled;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ClimbingRoute> onRouteTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => WanpanCard(
    color: WanpanColors.grapeSoft.withValues(alpha: .42),
    borderColor: WanpanColors.grape.withValues(alpha: .28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WanpanColors.surface,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.bolt_rounded, color: WanpanColors.grape),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '先找馆内已有线路',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '搜到后直接点击，发布这条线路的完攀',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: controller,
          enabled: enabled,
          onChanged: onQueryChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: '搜索线路名、颜色、难度或墙区',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    onPressed: enabled
                        ? () {
                            controller.clear();
                            onQueryChanged('');
                          }
                        : null,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        if (loading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 2),
        ] else if (hasError) ...[
          const SizedBox(height: 10),
          _InlineError(message: '已有线路没有加载出来', onRetry: onRetry),
        ] else if (totalCount == 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '馆内还没有已发布线路，\n可以直接在下方新建。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              SizedBox(
                width: 146,
                height: 92,
                child: Image.asset(
                  AppAssets.routeMapCat,
                  cacheWidth: 520,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ],
          ),
        ] else if (routes.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '没有匹配的线路，继续在下方发布新线路。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ] else ...[
          const SizedBox(height: 10),
          for (var index = 0; index < routes.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _ExistingRouteTile(
              route: routes[index],
              onTap: enabled ? () => onRouteTap(routes[index]) : null,
            ),
          ],
          if (query.isEmpty && totalCount > routes.length) ...[
            const SizedBox(height: 9),
            Text(
              '还有 ${totalCount - routes.length} 条，输入关键词可快速找到。',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(
              Icons.add_circle_outline_rounded,
              size: 17,
              color: WanpanColors.inkSecondary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '没找到？继续完成下方步骤，新线路提交后立即发布。',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ExistingRouteTile extends StatelessWidget {
  const _ExistingRouteTile({required this.route, required this.onTap});

  final ClimbingRoute route;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      route.color,
      if (route.wallZone?.trim().isNotEmpty == true) route.wallZone!.trim(),
      if (route.routeSetName?.trim().isNotEmpty == true)
        route.routeSetName!.trim(),
    ].join(' · ');
    return WanpanPressable(
      onTap: onTap,
      semanticLabel: '直接记录${route.name}的完攀',
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      enableHaptics: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          border: Border.all(color: WanpanColors.border),
          borderRadius: BorderRadius.circular(WanpanRadii.medium),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WanpanColors.coralSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                route.grade,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: WanpanColors.coralStrong,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.video_call_outlined,
              color: WanpanColors.coralStrong,
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteSetPicker extends StatelessWidget {
  const _RouteSetPicker({
    required this.routeSets,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  final List<RouteSet> routeSets;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (routeSets.isEmpty) {
      return Text(
        '这个岩馆暂无线路周期，将作为独立线路发布。',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('暂不选择'),
            selected: selectedId == null,
            onSelected: enabled ? (_) => onChanged(null) : null,
          ),
          for (final set in routeSets) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('${set.name}${set.active ? ' · 当前' : ''}'),
              selected: selectedId == set.id,
              onSelected: enabled ? (_) => onChanged(set.id) : null,
            ),
          ],
        ],
      ),
    );
  }
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
    child: SizedBox(
      height: 248,
      child: Stack(
        children: [
          Positioned(
            right: -22,
            bottom: -30,
            width: 166,
            height: 214,
            child: Image.asset(
              AppAssets.routeReviewCat,
              cacheWidth: 420,
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
            ),
          ),
          Align(
            alignment: const Alignment(-.42, .02),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  '支持多张，稍后可标记多个线路点',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
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

class _GymPickerSheet extends StatefulWidget {
  const _GymPickerSheet({required this.gyms, required this.selectedGymId});

  final List<Gym> gyms;
  final String? selectedGymId;

  @override
  State<_GymPickerSheet> createState() => _GymPickerSheetState();
}

class _GymPickerSheetState extends State<_GymPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final gyms = widget.gyms
        .where(
          (gym) =>
              query.isEmpty ||
              gym.name.toLowerCase().contains(query) ||
              gym.city.toLowerCase().contains(query) ||
              (gym.district?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 58,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        '选择岩馆',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    Positioned(
                      left: 18,
                      top: -70,
                      width: 126,
                      height: 94,
                      child: Image.asset(
                        AppAssets.profilePeekCat,
                        cacheWidth: 420,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: '搜索岩馆、城市或区域',
                  fillColor: WanpanColors.surface,
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: WanpanColors.coral,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.all(
                      Radius.circular(WanpanRadii.medium),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: gyms.isEmpty
                    ? const Center(child: Text('没有找到匹配的岩馆'))
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: gyms.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final gym = gyms[index];
                          final selected = gym.id == widget.selectedGymId;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            tileColor: selected
                                ? WanpanColors.coralSoft.withValues(alpha: .48)
                                : Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                WanpanRadii.medium,
                              ),
                            ),
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: WanpanColors.surface,
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(color: WanpanColors.border),
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: WanpanColors.sky,
                              ),
                            ),
                            title: Text(
                              gym.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            subtitle: Text(
                              [
                                gym.city,
                                if (gym.district != null) gym.district!,
                                gym.address,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? Container(
                                    width: 40,
                                    height: 40,
                                    decoration: const BoxDecoration(
                                      color: WanpanColors.coral,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.pop(context, gym.id),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 104,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: WanpanColors.sunflowerSoft.withValues(alpha: .38),
                  borderRadius: BorderRadius.circular(WanpanRadii.medium),
                  border: Border.all(
                    color: WanpanColors.sunflower.withValues(alpha: .35),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 18,
                      top: 20,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.stars_rounded,
                            color: WanpanColors.sunflower,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '小贴士',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '找不到你的岩馆？\n可以直接拍照标点，添加为新岩馆。',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: -20,
                      bottom: -24,
                      width: 130,
                      height: 100,
                      child: Image.asset(
                        AppAssets.profilePeekCat,
                        cacheWidth: 420,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
