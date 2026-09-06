import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/shared/app_assets.dart';
import 'package:wanpan_diary/shared/motion/wanpan_motion_sound.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all four motion sounds are bundled PCM WAV files with a reduced-motion cue', () async {
    const appAssets = {
      WanpanMotionSoundCue.sendSuccess: AppAssets.sendSuccessSound,
      WanpanMotionSoundCue.routePublished: AppAssets.routePublishedSound,
      WanpanMotionSoundCue.gradeMilestone: AppAssets.gradeMilestoneSound,
      WanpanMotionSoundCue.rankingEncouragement:
          AppAssets.rankingEncouragementSound,
    };

    for (final cue in WanpanMotionSoundCue.values.where(
      (cue) => cue != WanpanMotionSoundCue.badgeEarned,
    )) {
      final asset = cue.asset;
      expect(asset, appAssets[cue]);
      final bytes = await rootBundle.load(asset);
      expect(
        ascii.decode(bytes.buffer.asUint8List(0, 4)),
        'RIFF',
        reason: asset,
      );
      expect(
        ascii.decode(bytes.buffer.asUint8List(8, 4)),
        'WAVE',
        reason: asset,
      );
      expect(bytes.getUint16(22, Endian.little), 1, reason: asset);
      expect(bytes.getUint32(24, Endian.little), 44100, reason: asset);
      expect(bytes.getUint16(34, Endian.little), 16, reason: asset);

      final byteRate = bytes.getUint32(28, Endian.little);
      final dataSize = bytes.getUint32(40, Endian.little);
      final duration = Duration(
        microseconds: (dataSize * Duration.microsecondsPerSecond) ~/ byteRate,
      );
      expect(
        duration,
        greaterThan(cue.staticOffset + const Duration(milliseconds: 120)),
        reason: '$asset must include an audible reduced-motion tail',
      );
    }
  });

  test('every motion sound contains only the selected D rising pair', () async {
    const pairStarts = {
      WanpanMotionSoundCue.sendSuccess: Duration(milliseconds: 450),
      WanpanMotionSoundCue.routePublished: Duration(milliseconds: 683),
      WanpanMotionSoundCue.gradeMilestone: Duration(milliseconds: 633),
      WanpanMotionSoundCue.rankingEncouragement: Duration(milliseconds: 400),
    };
    List<int>? selectedDPattern;

    for (final cue in WanpanMotionSoundCue.values.where(
      (cue) => cue != WanpanMotionSoundCue.badgeEarned,
    )) {
      final bytes = await rootBundle.load(cue.asset);
      final sampleRate = bytes.getUint32(24, Endian.little);
      final dataSize = bytes.getUint32(40, Endian.little);
      final byteRate = bytes.getUint32(28, Endian.little);
      final duration = Duration(
        microseconds: (dataSize * Duration.microsecondsPerSecond) ~/ byteRate,
      );
      const dataOffset = 44;

      int peakBetween(Duration start, Duration end) {
        final firstSample =
            (start.inMicroseconds * sampleRate) ~/
            Duration.microsecondsPerSecond;
        final lastSample =
            (end.inMicroseconds * sampleRate) ~/ Duration.microsecondsPerSecond;
        var peak = 0;
        for (
          var sample = firstSample;
          sample < lastSample && dataOffset + sample * 2 + 1 < dataSize + 44;
          sample += 1
        ) {
          final value = bytes
              .getInt16(dataOffset + sample * 2, Endian.little)
              .abs();
          if (value > peak) peak = value;
        }
        return peak;
      }

      final pairStart = pairStarts[cue]!;
      expect(
        cue.staticOffset,
        pairStart,
        reason: '${cue.asset} reduced-motion playback must start at D',
      );
      final firstEnd = pairStart + const Duration(milliseconds: 52);
      final gapStart = pairStart + const Duration(milliseconds: 53);
      final gapEnd = pairStart + const Duration(milliseconds: 60);
      final secondStart = pairStart + const Duration(milliseconds: 61);
      final pairEnd = pairStart + const Duration(milliseconds: 120);
      expect(
        peakBetween(Duration.zero, pairStart),
        0,
        reason: '${cue.asset} must be silent before D starts',
      );
      expect(
        peakBetween(pairStart, firstEnd),
        greaterThan(1000),
        reason: '${cue.asset} must contain the first D note',
      );
      expect(
        peakBetween(gapStart, gapEnd),
        0,
        reason: '${cue.asset} must keep D\'s short pause',
      );
      expect(
        peakBetween(secondStart, pairEnd),
        greaterThan(1000),
        reason: '${cue.asset} must contain the second D note',
      );
      expect(
        peakBetween(pairEnd, duration),
        0,
        reason: '${cue.asset} must not add any sound after D',
      );

      double positiveCrossingFrequency(Duration start, Duration end) {
        final firstSample =
            (start.inMicroseconds * sampleRate) ~/
            Duration.microsecondsPerSecond;
        final lastSample =
            (end.inMicroseconds * sampleRate) ~/ Duration.microsecondsPerSecond;
        var crossings = 0;
        var previous = bytes.getInt16(
          dataOffset + firstSample * 2,
          Endian.little,
        );
        for (var sample = firstSample + 1; sample < lastSample; sample += 1) {
          final current = bytes.getInt16(
            dataOffset + sample * 2,
            Endian.little,
          );
          if (previous <= 0 && current > 0) crossings += 1;
          previous = current;
        }
        final seconds = (lastSample - firstSample) / sampleRate;
        return crossings / seconds;
      }

      expect(
        positiveCrossingFrequency(
          pairStart + const Duration(milliseconds: 6),
          pairStart + const Duration(milliseconds: 36),
        ),
        inInclusiveRange(640, 680),
        reason: '${cue.asset} first D note must remain E5',
      );
      expect(
        positiveCrossingFrequency(
          pairStart + const Duration(milliseconds: 67),
          pairStart + const Duration(milliseconds: 91),
        ),
        inInclusiveRange(1020, 1075),
        reason: '${cue.asset} second D note must remain C6',
      );

      final firstSample =
          (pairStart.inMicroseconds * sampleRate) ~/
          Duration.microsecondsPerSecond;
      final patternLength =
          (const Duration(milliseconds: 120).inMicroseconds * sampleRate) ~/
          Duration.microsecondsPerSecond;
      final pattern = List<int>.generate(
        patternLength,
        (sample) => bytes.getInt16(
          dataOffset + (firstSample + sample) * 2,
          Endian.little,
        ),
      );
      selectedDPattern ??= pattern;
      expect(
        pattern,
        orderedEquals(selectedDPattern),
        reason: '${cue.asset} must use D without another tone or texture',
      );
    }
  });

  test('legacy filenames contain the selected D pair', () async {
    const aliases = {
      AppAssets.sendSuccessSound: 'assets/sounds/success.wav',
      AppAssets.gradeMilestoneSound: 'assets/sounds/milestone.wav',
    };
    for (final entry in aliases.entries) {
      final current = await rootBundle.load(entry.key);
      final legacy = await rootBundle.load(entry.value);
      expect(
        legacy.buffer.asUint8List(),
        orderedEquals(current.buffer.asUint8List()),
        reason: '${entry.value} must use the selected D pair too',
      );
    }
  });
}
