import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../app_assets.dart';

/// The four short, branded sound cues paired with Wanpan's one-shot scenes.
enum WanpanMotionSoundCue {
  sendSuccess(
    asset: AppAssets.sendSuccessSound,
    staticOffset: Duration(milliseconds: 450),
    volume: .9,
  ),
  routePublished(
    asset: AppAssets.routePublishedSound,
    staticOffset: Duration(milliseconds: 683),
    volume: .8,
  ),
  gradeMilestone(
    asset: AppAssets.gradeMilestoneSound,
    staticOffset: Duration(milliseconds: 633),
    volume: .95,
  ),
  rankingEncouragement(
    asset: AppAssets.rankingEncouragementSound,
    staticOffset: Duration(milliseconds: 400),
    volume: .7,
  );

  const WanpanMotionSoundCue({
    required this.asset,
    required this.staticOffset,
    required this.volume,
  });

  /// Full path used by Flutter's asset bundle.
  final String asset;

  /// Relative path required by [AssetSource].
  String get source => asset.replaceFirst('assets/', '');

  /// The immediate confirmation tail used when motion is reduced or missing.
  final Duration staticOffset;
  final double volume;
}

/// Injectable boundary for feature and gallery tests.
abstract interface class WanpanMotionSoundPlayer {
  Future<void> preload(Iterable<WanpanMotionSoundCue> cues);

  /// Plays one cue, replacing any cue that is still sounding.
  ///
  /// Implementations must treat audio as optional feedback: playback failure
  /// must never change a completed product action into an error.
  Future<void> play(WanpanMotionSoundCue cue, {required bool animated});

  Future<void> stop();

  Future<void> dispose();
}

/// Asset-backed player for the app and the standalone motion laboratory.
///
/// A player is prepared per cue to avoid first-play decoding latency. The
/// shared request generation makes rapid scene changes replace, rather than
/// overlap, the previous sound.
final class WanpanAssetMotionSoundPlayer implements WanpanMotionSoundPlayer {
  static final AudioContext _audioContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    // Ambient follows the Ring/Silent switch and mixes with other app audio.
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  final Map<WanpanMotionSoundCue, AudioPlayer> _players = {};
  final Map<WanpanMotionSoundCue, Future<AudioPlayer?>> _preparations = {};
  AudioPlayer? _activePlayer;
  bool _disposed = false;
  int _requestGeneration = 0;
  Future<void> _operationQueue = Future<void>.value();

  @override
  Future<void> preload(Iterable<WanpanMotionSoundCue> cues) async {
    for (final cue in cues) {
      if (_disposed) return;
      await _prepare(cue);
    }
  }

  @override
  Future<void> play(WanpanMotionSoundCue cue, {required bool animated}) {
    if (_disposed) return Future<void>.value();
    final request = ++_requestGeneration;
    return _enqueue(() async {
      if (_disposed || request != _requestGeneration) return;
      await _stopActive();
      final player = await _prepare(cue);
      if (_disposed || request != _requestGeneration || player == null) return;

      try {
        await player.stop();
        if (!animated && cue.staticOffset > Duration.zero) {
          await player.seek(cue.staticOffset);
        }
        if (_disposed || request != _requestGeneration) return;
        _activePlayer = player;
        await player.resume();
      } catch (error) {
        if (kDebugMode) debugPrint('Wanpan motion sound unavailable: $error');
      }
    });
  }

  Future<AudioPlayer?> _prepare(WanpanMotionSoundCue cue) async {
    if (_disposed) return null;
    final prepared = _players[cue];
    if (prepared != null) return prepared;
    final inFlight = _preparations[cue];
    if (inFlight != null) return inFlight;

    final preparation = _createPlayer(cue);
    _preparations[cue] = preparation;
    final player = await preparation;
    if (identical(_preparations[cue], preparation)) {
      _preparations.remove(cue);
    }
    return player;
  }

  Future<AudioPlayer?> _createPlayer(WanpanMotionSoundCue cue) async {
    final player = AudioPlayer();
    try {
      await player.setAudioContext(_audioContext);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(cue.volume);
      await player.setSource(AssetSource(cue.source));
      if (_disposed) {
        await player.dispose();
        return null;
      }
      _players[cue] = player;
      return player;
    } catch (error) {
      if (kDebugMode) debugPrint('Wanpan motion sound preload failed: $error');
      try {
        await player.dispose();
      } catch (_) {
        // Audio is optional feedback, including during teardown.
      }
      return null;
    }
  }

  @override
  Future<void> stop() {
    if (_disposed) return Future<void>.value();
    _requestGeneration += 1;
    return _enqueue(_stopActive);
  }

  Future<void> _stopActive() async {
    final player = _activePlayer;
    _activePlayer = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {
      // Audio is optional feedback.
    }
  }

  @override
  Future<void> dispose() {
    if (_disposed) return Future<void>.value();
    _disposed = true;
    _requestGeneration += 1;
    return _enqueue(() async {
      final active = _activePlayer;
      _activePlayer = null;
      if (active != null) {
        try {
          await active.stop();
        } catch (_) {
          // Continue releasing the remaining players.
        }
      }

      final pending = _preparations.values.toList(growable: false);
      if (pending.isNotEmpty) await Future.wait(pending);
      final players = _players.values.toSet();
      _players.clear();
      _preparations.clear();
      for (final player in players) {
        try {
          await player.dispose();
        } catch (_) {
          // Teardown must remain best-effort.
        }
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operationQueue.then<void>((_) async {
      try {
        await operation();
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Wanpan motion sound operation failed: $error');
        }
      }
    });
    _operationQueue = next;
    return next;
  }
}
