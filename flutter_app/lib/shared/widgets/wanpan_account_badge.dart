import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../app_assets.dart';

/// Every collection cell and celebration draws the same approved artwork.
class WanpanAccountBadge extends StatefulWidget {
  const WanpanAccountBadge({
    required this.level,
    this.size = 120,
    this.dimmed = false,
    super.key,
  });
  final int level;
  final double size;
  final bool dimmed;
  @override
  State<WanpanAccountBadge> createState() => _WanpanAccountBadgeState();
}

class _WanpanAccountBadgeState extends State<WanpanAccountBadge> {
  ImageStream? _stream;
  ImageInfo? _image;
  late final ImageStreamListener _listener = ImageStreamListener((image, _) {
    if (!mounted) {
      image.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = image);
    old?.dispose();
  }, onError: (_, _) {});
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = const AssetImage(AppAssets.accountBadges)
        .resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: widget.level == 0 ? '第一枚徽章待解锁' : '账户 Lv.${widget.level} 徽章',
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: widget.level < 1 || widget.level > 10 || _image == null
            ? Icon(
                widget.level == 0
                    ? Icons.lock_outline_rounded
                    : Icons.workspace_premium_outlined,
                size: widget.size * .5,
                color: WanpanColors.muted,
              )
            : Opacity(
                opacity: widget.dimmed ? .38 : 1,
                child: CustomPaint(
                  painter: _BadgePainter(_image!.image, widget.level),
                ),
              ),
      ),
    ),
  );
}

class _BadgePainter extends CustomPainter {
  _BadgePainter(this.image, this.level);
  final ui.Image image;
  final int level;
  static const _xs = [
    22.0,
    312.0,
    603.0,
    899.0,
    1201.0,
    20.0,
    312.0,
    600.0,
    897.0,
    1196.0,
  ];
  // Coordinates use the same 300×300 sprite space as the mini-program mask.
  // The top contour of Lv.10 deliberately includes both protruding cat ears.
  static const _catEarOutline = <Offset>[
    Offset(150, 0),
    Offset(179, 3),
    Offset(207, 12),
    Offset(220, 18),
    Offset(240, 3),
    Offset(265, 3),
    Offset(272, 16),
    Offset(271, 48),
    Offset(269, 60),
    Offset(280, 75),
    Offset(295, 111),
    Offset(300, 150),
    Offset(295, 189),
    Offset(280, 225),
    Offset(256, 256),
    Offset(225, 280),
    Offset(189, 295),
    Offset(150, 300),
    Offset(111, 295),
    Offset(75, 280),
    Offset(44, 256),
    Offset(20, 225),
    Offset(5, 189),
    Offset(0, 150),
    Offset(5, 111),
    Offset(20, 75),
    Offset(39, 64),
    Offset(40, 20),
    Offset(46, 4),
    Offset(65, 3),
    Offset(91, 18),
    Offset(111, 5),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final mask = level == 10
        ? (Path()..addPolygon(
            _catEarOutline
                .map(
                  (point) => Offset(
                    point.dx * size.width / 300,
                    point.dy * size.height / 300,
                  ),
                )
                .toList(growable: false),
            true,
          ))
        : (Path()..addOval(Offset.zero & size));
    canvas.save();
    canvas.clipPath(mask, doAntiAlias: true);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(_xs[level - 1], level <= 5 ? 225 : 588, 300, 300),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BadgePainter oldDelegate) =>
      image != oldDelegate.image || level != oldDelegate.level;
}
