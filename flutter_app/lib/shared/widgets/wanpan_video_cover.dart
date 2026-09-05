import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../../core/services/video_cover_cache.dart';

/// A static video frame; the surrounding post card owns navigation/playback.
class WanpanVideoCover extends StatefulWidget {
  const WanpanVideoCover({super.key, required this.url, this.cache});

  final String url;
  final VideoCoverCache? cache;

  @override
  State<WanpanVideoCover> createState() => _WanpanVideoCoverState();
}

class _WanpanVideoCoverState extends State<WanpanVideoCover> {
  late Future<Uint8List?> _cover;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WanpanVideoCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cache != widget.cache) _load();
  }

  void _load() {
    _cover = (widget.cache ?? VideoCoverCache.shared)
        .load(widget.url)
        .timeout(const Duration(seconds: 20), onTimeout: () => null);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '完攀视频封面，点击查看视频',
    child: ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WanpanRadii.medium),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: FutureBuilder<Uint8List?>(
            key: ValueKey(widget.url),
            future: _cover,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              final ready = bytes != null && bytes.isNotEmpty;
              final loading = snapshot.connectionState != ConnectionState.done;
              return Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: WanpanColors.surfaceSoft,
                    child: ready
                        ? Image.memory(
                            bytes,
                            key: const Key('video-cover-image'),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(
                                Icons.videocam_outlined,
                                color: WanpanColors.muted,
                                size: 40,
                              ),
                            ),
                          )
                        : null,
                  ),
                  Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: ready
                            ? const Color(0xB3171A1E)
                            : WanpanColors.coral,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                  if (!ready)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 16,
                      child: Text(
                        loading ? '封面加载中…' : '点击查看完攀视频',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
