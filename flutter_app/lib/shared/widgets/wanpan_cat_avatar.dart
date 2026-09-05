import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../app_assets.dart';

/// Keeps the avatar's edge aligned with the cat's arms at every display size.
class WanpanCatAvatar extends StatelessWidget {
  const WanpanCatAvatar({
    super.key,
    required this.diameter,
    this.image,
    this.placeholder,
    this.showCameraBadge = false,
  });

  final double diameter;
  final ImageProvider<Object>? image;
  final Widget? placeholder;
  final bool showCameraBadge;

  // Coordinates in the original 1254 px artwork. The circle follows the
  // inner curve of the cat's arms; the crop removes transparent outer space.
  static const _artSize = 1254.0;
  static const _avatar = Rect.fromLTWH(296, 389, 720, 720);
  static const _content = Rect.fromLTWH(72, 80, 1120, 1032);

  @override
  Widget build(BuildContext context) {
    final scale = diameter / _avatar.width;
    final avatarLeft = (_avatar.left - _content.left) * scale;
    final avatarTop = (_avatar.top - _content.top) * scale;
    final badgeSize = diameter * 58 / 164;
    final fallback =
        placeholder ??
        Icon(
          Icons.person_rounded,
          size: diameter * .43,
          color: WanpanColors.coral,
        );

    return SizedBox(
      width: _content.width * scale,
      height: _content.height * scale + (showCameraBadge ? badgeSize * .15 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: avatarLeft,
            top: avatarTop,
            width: diameter,
            height: diameter,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: WanpanColors.coralSoft,
                shape: BoxShape.circle,
              ),
              foregroundDecoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x66F3BBA9)),
              ),
              child: image == null
                  ? Center(child: fallback)
                  : Image(
                      image: ResizeImage.resizeIfNeeded(
                        (diameter * 3).ceil(),
                        (diameter * 3).ceil(),
                        image!,
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(child: fallback),
                    ),
            ),
          ),
          Positioned(
            left: -_content.left * scale,
            top: -_content.top * scale,
            width: _artSize * scale,
            height: _artSize * scale,
            child: IgnorePointer(
              child: Image.asset(
                AppAssets.profilePeekCat,
                cacheWidth: (_artSize * scale * 3).ceil(),
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
            ),
          ),
          if (showCameraBadge)
            Positioned(
              left: avatarLeft + diameter - badgeSize * .85,
              top: avatarTop + diameter - badgeSize * .85,
              width: badgeSize,
              height: badgeSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: WanpanColors.coral,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      offset: Offset(0, 5),
                      blurRadius: 9,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: badgeSize * 28 / 58,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
