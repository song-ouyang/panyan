import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/services/video_preparation_service.dart';

class _Encoder implements VideoEncoder {
  int encodes = 0;
  int inspections = 0;
  int active = 0;
  int maxActive = 0;
  int outputSize = 40;
  bool fail = false;
  bool incomplete = false;
  VideoMetadata metadata = const VideoMetadata(
    width: 3840,
    height: 2160,
    duration: Duration(seconds: 10),
  );
  Future<void> Function()? duringEncode;

  @override
  Future<VideoMetadata> inspect(String sourcePath) async {
    inspections++;
    if (incomplete && sourcePath.endsWith('encoded.mp4')) {
      return const VideoMetadata(
        width: 1920,
        height: 1080,
        duration: Duration(seconds: 2),
      );
    }
    return metadata;
  }

  @override
  Future<void> encode(
    String sourcePath,
    String destinationPath, {
    required VideoMetadata metadata,
    void Function(double)? onProgress,
  }) async {
    encodes++;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      onProgress?.call(.3);
      await duringEncode?.call();
      if (fail) throw StateError('codec unavailable');
      await File(destinationPath).writeAsBytes(List.filled(outputSize, 7));
      onProgress?.call(1);
    } finally {
      active--;
    }
  }
}

void main() {
  late Directory temp;
  late Directory cache;
  late File source;
  late _Encoder encoder;
  late VideoPreparationService service;
  final retained = <(VideoPreparationService, PreparedVideo)>[];

  Future<PreparedVideo> prepare([String? path]) async {
    final video = await service.prepare(path ?? source.path);
    retained.add((service, video));
    return video;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('video-preparation-test-');
    cache = Directory('${temp.path}/cache');
    source = await File('${temp.path}/source.mov')
        .writeAsBytes(List.generate(100, (i) => i));
    encoder = _Encoder();
    service = VideoPreparationService(
      encoder: encoder,
      cacheDirectory: () async => cache,
    );
  });

  tearDown(() async {
    for (final (owner, video) in retained) {
      owner.release(video);
    }
    retained.clear();
    await temp.delete(recursive: true);
  });

  test(
    'persists smaller MP4, keeps original and reuses after restart/reselect',
    () async {
      final progress = <double>[];
      final prepared = await service.prepare(
        source.path,
        onProgress: progress.add,
      );
      retained.add((service, prepared));
      expect(prepared.filename, 'video.mp4');
      expect(prepared.mimeType, 'video/mp4');
      expect(prepared.size, 40);
      expect(prepared.originalBytes, 100);
      expect(prepared.wasCompressed, isTrue);
      expect(await source.length(), 100);
      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(await File(prepared.path).readAsBytes(), List.filled(40, 7));

      final reselected = await source.copy('${temp.path}/new-picker-path.mov');
      service = VideoPreparationService(
        encoder: encoder,
        cacheDirectory: () async => cache,
      );
      final resumed = await prepare(reselected.path);
      expect(resumed.path, prepared.path);
      expect(encoder.encodes, 1);
      expect(encoder.inspections, 2);
    },
  );

  test('hashes full file even when path, size and timestamp match', () async {
    final first = await prepare();
    final modified = await source.lastModified();
    final bytes = await source.readAsBytes();
    bytes[50] = 233;
    await source.writeAsBytes(bytes);
    await source.setLastModified(modified);
    final second = await prepare();
    expect(second.path, isNot(first.path));
    expect(encoder.encodes, 2);
  });

  test('retains the smaller original MOV if encoding grows the file', () async {
    encoder.outputSize = 150;
    final video = await prepare();
    expect(video.wasCompressed, isFalse);
    expect(video.size, 100);
    expect(video.mimeType, 'video/quicktime');
    expect(video.filename, 'video.mov');
    expect(await File(video.path).readAsBytes(), await source.readAsBytes());
    expect(await source.exists(), isTrue);
  });

  test(
    'small efficient videos skip lossy recompression but get durable copies',
    () async {
      encoder.metadata = const VideoMetadata(
        width: 1280,
        height: 720,
        duration: Duration(seconds: 10),
      );
      final video = await prepare();
      expect(video.wasCompressed, isFalse);
      expect(encoder.encodes, 0);
      expect(video.path, isNot(source.path));
      expect(await File(video.path).length(), 100);
    },
  );

  test('compression failure never silently falls back to raw video', () async {
    encoder.fail = true;
    await expectLater(
      service.prepare(source.path),
      throwsA(isA<VideoPreparationException>()),
    );
    expect(await source.length(), 100);
    expect(await cache.list().toList(), isEmpty);
    encoder.fail = false;
    expect((await prepare()).wasCompressed, isTrue);
  });

  test('rejects incomplete encoded videos and cleans partial cache', () async {
    encoder.incomplete = true;
    await expectLater(
      service.prepare(source.path),
      throwsA(
        isA<VideoPreparationException>().having(
          (error) => error.message,
          'message',
          contains('不完整'),
        ),
      ),
    );
    expect(await cache.list().toList(), isEmpty);
  });

  test('detects a source modified while the encoder runs', () async {
    encoder.duringEncode = () => source.writeAsBytes(List.filled(100, 9));
    await expectLater(
      service.prepare(source.path),
      throwsA(
        isA<VideoPreparationException>().having(
          (error) => error.message,
          'message',
          contains('发生变化'),
        ),
      ),
    );
    expect(await cache.list().toList(), isEmpty);
  });

  test('serializes native encoder across service instances', () async {
    final other = await File('${temp.path}/other.mov')
        .writeAsBytes(List.filled(100, 19));
    encoder.duringEncode = () async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    };
    final anotherService = VideoPreparationService(
      encoder: encoder,
      cacheDirectory: () async => cache,
    );
    final results = await Future.wait([
      service.prepare(source.path),
      anotherService.prepare(other.path),
    ]);
    retained.add((service, results.first));
    retained.add((anotherService, results.last));
    expect(encoder.encodes, 2);
    expect(encoder.maxActive, 1);
  });

  test('cleans inactive caches while preserving every active upload', () async {
    service = VideoPreparationService(
      encoder: encoder,
      cacheDirectory: () async => cache,
      cacheMaxBytes: 1,
    );
    final first = await prepare();
    final secondFile = await File('${temp.path}/second.mov')
        .writeAsBytes(List.filled(100, 16));
    final second = await prepare(secondFile.path);
    expect(await File(first.path).exists(), isTrue);
    service.release(first);
    await prepare(secondFile.path);
    expect(await File(first.path).exists(), isFalse);
    expect(await File(second.path).exists(), isTrue);
    expect(await source.exists(), isTrue);
  });

  test(
    'invalid cached content is re-encoded after releasing its lease',
    () async {
      final first = await prepare();
      await File(first.path).writeAsBytes(List.filled(40, 2));
      await expectLater(
        service.prepare(source.path),
        throwsA(isA<VideoPreparationException>()),
      );
      expect(encoder.encodes, 1);
      service.release(first);
      final repaired = await prepare();
      expect(encoder.encodes, 2);
      expect(await File(repaired.path).readAsBytes(), List.filled(40, 7));
    },
  );
}
