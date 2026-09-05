import 'package:wanpan_diary/shared/motion/wanpan_motion_sound.dart';

final class MotionSoundPlayback {
  const MotionSoundPlayback(this.cue, {required this.animated});

  final WanpanMotionSoundCue cue;
  final bool animated;
}

final class FakeMotionSoundPlayer implements WanpanMotionSoundPlayer {
  final Set<WanpanMotionSoundCue> preloaded = {};
  final List<MotionSoundPlayback> plays = [];
  int stopCount = 0;
  bool disposed = false;

  @override
  Future<void> preload(Iterable<WanpanMotionSoundCue> cues) async {
    preloaded.addAll(cues);
  }

  @override
  Future<void> play(WanpanMotionSoundCue cue, {required bool animated}) async {
    plays.add(MotionSoundPlayback(cue, animated: animated));
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
