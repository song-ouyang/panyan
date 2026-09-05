import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../motion/wanpan_motion.dart';
import 'wanpan_cat_mark.dart';

/// App-wide transient feedback, above routes and sheets without a modal barrier.
abstract final class WanpanNotice {
  static final _active = Expando<_NoticeEntry>();

  static void show(BuildContext context, String message) {
    if (!context.mounted || message.trim().isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _active[overlay]?.remove();
    final notice = _NoticeEntry(overlay, message);
    _active[overlay] = notice;
    overlay.insert(notice.entry);
  }

  /// Clear obsolete feedback immediately, for example when a retry succeeds.
  static void dismiss(BuildContext context) {
    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) _active[overlay]?.remove();
  }
}

class _NoticeEntry {
  _NoticeEntry(this.overlay, String message) {
    entry = OverlayEntry(
      builder: (_) => _Notice(message: message, onRemoved: remove),
    );
  }

  final OverlayState overlay;
  late final OverlayEntry entry;
  bool _removed = false;

  void remove() {
    if (_removed) return;
    _removed = true;
    if (identical(WanpanNotice._active[overlay], this)) {
      WanpanNotice._active[overlay] = null;
    }
    entry
      ..remove()
      ..dispose();
  }
}

class _Notice extends StatefulWidget {
  const _Notice({required this.message, required this.onRemoved});

  final String message;
  final VoidCallback onRemoved;

  @override
  State<_Notice> createState() => _NoticeState();
}

class _NoticeState extends State<_Notice> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  late final _animation = CurvedAnimation(
    parent: _controller,
    curve: WanpanMotion.easeOut,
    reverseCurve: Curves.easeIn,
  );
  Timer? _timer;
  bool _started = false;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = WanpanMotion.duration(
      context,
      WanpanMotion.selection,
    );
    _controller.reverseDuration = WanpanMotion.duration(
      context,
      WanpanMotion.exit,
    );
    if (_started) return;
    _started = true;
    _controller.forward();
    _timer = Timer(
      MediaQuery.accessibleNavigationOf(context)
          ? const Duration(seconds: 8)
          : const Duration(seconds: 3),
      _dismiss,
    );
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    try {
      await _controller.reverse().orCancel;
      if (mounted) widget.onRemoved();
    } on TickerCanceled {
      // A newer notice replaced this one, or the app overlay was disposed.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    _controller.dispose();
    widget.onRemoved();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final notice = FadeTransition(
      opacity: _animation,
      child: Material(
        key: const Key('wanpan-top-notice'),
        color: WanpanColors.mintSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: WanpanColors.mint),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 5, 7),
          child: Row(
            children: [
              const WanpanCatMark(size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF285A3C),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '关闭提示',
                onPressed: _dismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: const Color(0xFF34744B),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
        ),
      ),
    );
    return Positioned(
      top: media.viewPadding.top + 12,
      left: 20 + media.viewPadding.left,
      right: 20 + media.viewPadding.right,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SlideTransition(
            position: WanpanMotion.reduceMotion(context)
                ? const AlwaysStoppedAnimation(Offset.zero)
                : Tween(
                    begin: const Offset(0, -1.15),
                    end: Offset.zero,
                  ).animate(_animation),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(22)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x142B5B3A),
                    blurRadius: 16,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: notice,
            ),
          ),
        ),
      ),
    );
  }
}
