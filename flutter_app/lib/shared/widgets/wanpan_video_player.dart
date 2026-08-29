import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app/wanpan_theme.dart';
import '../motion/wanpan_motion.dart';

class WanpanVideoPlayer extends StatefulWidget {
  const WanpanVideoPlayer({required this.url, super.key});

  final String url;

  @override
  State<WanpanVideoPlayer> createState() => _WanpanVideoPlayerState();
}

class _WanpanVideoPlayerState extends State<WanpanVideoPlayer>
    with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didUpdateWidget(covariant WanpanVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _controller.dispose();
    _ready = false;
    _failed = false;
    _initialize();
  }

  Future<void> _initialize() async {
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await _controller.initialize();
      await _controller.setLooping(false);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _ready) {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      if (_controller.value.position >= _controller.value.duration) {
        await _controller.seekTo(Duration.zero);
      }
      await _controller.play();
      HapticFeedback.selectionClick();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _ready && _controller.value.aspectRatio > 0
        ? _controller.value.aspectRatio.clamp(.62, 1.8)
        : 4 / 3;
    return ClipRRect(
      borderRadius: BorderRadius.circular(WanpanRadii.large),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ColoredBox(
          color: WanpanColors.ink,
          child: _failed
              ? const _VideoMessage(
                  icon: Icons.videocam_off_outlined,
                  label: '视频暂时无法播放',
                )
              : !_ready
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final playing = _controller.value.isPlaying;
                    return Semantics(
                      button: true,
                      label: playing ? '暂停视频' : '播放视频',
                      onTap: _toggle,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTap: _toggle,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(child: VideoPlayer(_controller)),
                            AnimatedOpacity(
                              opacity: playing ? 0 : 1,
                              duration: WanpanMotion.duration(
                                context,
                                WanpanMotion.exit,
                              ),
                              child: Center(
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    color: Color(0xB317191C),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 38,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 10,
                              child: VideoProgressIndicator(
                                _controller,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: WanpanColors.coral,
                                  bufferedColor: Color(0x99FFFFFF),
                                  backgroundColor: Color(0x55FFFFFF),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _VideoMessage extends StatelessWidget {
  const _VideoMessage({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 42),
        const SizedBox(height: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colors.white70),
        ),
      ],
    ),
  );
}
