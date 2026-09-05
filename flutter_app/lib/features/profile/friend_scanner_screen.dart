import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/wanpan_theme.dart';
import '../../core/services/friend_code.dart';
import '../../shared/widgets/wanpan_pressable.dart';

/// Finds a public user ID. The caller owns profile lookup and friend requests.
class FriendScannerScreen extends StatefulWidget {
  const FriendScannerScreen({
    super.key,
    required this.codec,
    required this.currentUserId,
    this.onScanned,
    this.pickImage,
  });

  final FriendCode codec;
  final String currentUserId;
  final ValueChanged<String>? onScanned;
  final Future<XFile?> Function()? pickImage;

  @override
  State<FriendScannerScreen> createState() => _FriendScannerScreenState();
}

class _FriendScannerScreenState extends State<FriendScannerScreen>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  StreamSubscription<BarcodeCapture>? _subscription;
  Future<void> _cameraQueue = Future<void>.value();
  bool _foreground = true;
  bool _closed = false;
  bool _completed = false;
  bool _pickingImage = false;
  String? _feedback;
  MobileScannerException? _cameraFailure;

  bool get _isCurrent =>
      mounted && !_closed && (ModalRoute.of(context)?.isCurrent ?? false);

  bool get _canScan =>
      _isCurrent && _foreground && !_completed && !_pickingImage;

  @override
  void initState() {
    super.initState();
    _foreground = switch (WidgetsBinding.instance.lifecycleState) {
      null || AppLifecycleState.resumed => true,
      _ => false,
    };
    WidgetsBinding.instance.addObserver(this);
    _subscription = _controller.barcodes.listen(
      (capture) {
        if (_canScan) unawaited(_acceptCapture(capture));
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_canScan) _showFeedback('暂时没有识别成功，请重新对准好友二维码');
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_closed) unawaited(_syncCamera());
    });
  }

  /// Serialize native operations: a permission prompt may finish after a pop,
  /// app pause, or album selection. Recheck intent after start before keeping
  /// the camera alive, and only dispose after pending native work completes.
  Future<void> _syncCamera() {
    _cameraQueue = _cameraQueue.then((_) async {
      if (_closed) return;
      try {
        if (_canScan) {
          if (_cameraFailure != null) {
            setState(() => _cameraFailure = null);
          }
          await _controller.start();
        }
        if (!_canScan) await _controller.stop();
      } catch (_) {
        if (_canScan) {
          setState(() {
            _cameraFailure = const MobileScannerException(
              errorCode: MobileScannerErrorCode.genericError,
            );
          });
        }
      }
    });
    return _cameraQueue;
  }

  void _showFeedback(String message) {
    if (!_isCurrent || _completed || _feedback == message) return;
    setState(() => _feedback = message);
  }

  Future<bool> _acceptCapture(BarcodeCapture? capture) async {
    if (!_isCurrent || _completed) return false;
    var foundOwnCode = false;
    for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
      if (barcode.format != BarcodeFormat.qrCode) continue;
      final rawValue = barcode.rawValue;
      final userId = rawValue == null ? null : widget.codec.parse(rawValue);
      if (userId == null) continue;
      if (userId == widget.currentUserId.toLowerCase()) {
        foundOwnCode = true;
        continue;
      }

      // Lock synchronously before awaiting stop, so a second frame cannot pop
      // the next route or trigger a second friend lookup.
      setState(() {
        _completed = true;
        _feedback = '识别成功，正在打开岩友资料';
      });
      await _syncCamera();
      if (mounted && _isCurrent) {
        final onScanned = widget.onScanned;
        if (onScanned != null) {
          onScanned(userId);
        } else {
          Navigator.of(context).pop<String>(userId);
        }
      }
      return true;
    }
    _showFeedback(
      foundOwnCode ? '这是你自己的好友二维码，试试扫描朋友的吧' : '没有找到完攀好友二维码，请重新对准或换张图片',
    );
    return false;
  }

  Future<void> _pickFromAlbum() async {
    if (!_isCurrent || _completed || _pickingImage) return;
    setState(() {
      _pickingImage = true;
      _feedback = null;
    });
    try {
      await _syncCamera();
      if (!_isCurrent || _completed) return;
      final image =
          await (widget.pickImage?.call() ??
              ImagePicker().pickImage(source: ImageSource.gallery));
      if (!_isCurrent || _completed || image == null) return;
      final capture = await _controller.analyzeImage(
        image.path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (_isCurrent) await _acceptCapture(capture);
    } on UnsupportedError {
      _showFeedback('当前设备暂不支持从相册识别，请使用相机扫码');
    } catch (_) {
      _showFeedback('暂时无法识别这张图片，请重试或使用相机扫码');
    } finally {
      if (mounted && !_closed) {
        setState(() => _pickingImage = false);
        if (!_completed) unawaited(_syncCamera());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // The system permission dialog can produce inactive/resumed while start
    // is still pending. The queue prevents overlapping native operations.
    unawaited(_syncCamera());
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(
      _cameraQueue.then((_) async {
        try {
          await _controller.stop();
        } catch (_) {
          // Still release the native controller if the device was removed.
        }
        try {
          await _controller.dispose();
        } catch (_) {
          // Native cleanup cannot update a screen which has already closed.
        }
      }),
    );
    super.dispose();
  }

  Widget _cameraError(BuildContext context, MobileScannerException error) {
    final (title, explanation) = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => (
        '需要相机权限',
        '请在系统设置中允许完攀日记使用相机，再回来重试。也可以从相册识别好友二维码。',
      ),
      MobileScannerErrorCode.unsupported => (
        '当前设备没有可用相机',
        '可以从相册选择朋友发来的好友二维码。',
      ),
      _ => ('相机暂时不可用', '请重试，或从相册选择好友二维码。'),
    };
    return ColoredBox(
      color: WanpanColors.surfaceSoft,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 40,
                color: WanpanColors.inkSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                explanation,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              WanpanButton(
                label: '重试相机',
                style: WanpanButtonStyle.secondary,
                onPressed: _pickingImage || _completed
                    ? null
                    : () => unawaited(_syncCamera()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('扫一扫添加好友')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '将朋友的完攀好友二维码放入画面',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(WanpanRadii.large),
                      child: SizedBox(
                        key: const Key('friend-scanner-preview'),
                        height: math.min(
                          500,
                          math.max(280, constraints.maxHeight * .62),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MobileScanner(
                              controller: _controller,
                              useAppLifecycleState: false,
                              errorBuilder: _cameraError,
                              placeholderBuilder: (_) => const ColoredBox(
                                color: WanpanColors.ink,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: WanpanColors.coral,
                                  ),
                                ),
                              ),
                              overlayBuilder: (_, constraints) => Center(
                                child: Container(
                                  width: constraints.maxWidth * .74,
                                  height:
                                      math.min(
                                        constraints.maxWidth,
                                        constraints.maxHeight,
                                      ) *
                                      .74,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: WanpanColors.coral,
                                      width: 3,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                              ),
                            ),
                            if (_cameraFailure case final error?)
                              _cameraError(context, error),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _feedback ?? '识别后查看岩友资料，再发送好友申请',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: WanpanColors.inkSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    WanpanButton(
                      label: '从相册选择二维码',
                      style: WanpanButtonStyle.secondary,
                      icon: const Icon(Icons.photo_library_outlined),
                      loading: _pickingImage,
                      onPressed: _completed || _pickingImage
                          ? null
                          : _pickFromAlbum,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
