import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:v_video_compressor/v_video_compressor.dart';
import 'package:v_video_compressor/v_video_compressor_platform_interface.dart';
import 'package:wanpan_diary/core/services/video_preparation_service.dart';

class _Platform extends VVideoCompressorPlatform {
  VVideoCompressionConfig? receivedConfig;
  bool returnOriginal = false;
  bool fail = false;

  @override
  Future<VVideoCompressionResult?> compressVideo(
    String videoPath,
    VVideoCompressionConfig config, {
    void Function(double)? onProgress,
  }) async {
    receivedConfig = config;
    if (fail) return null;
    final output = File('${config.outputPath}/native-generated.mp4');
    if (!returnOriginal) await output.writeAsBytes(List.filled(40, 7));
    return VVideoCompressionResult(
      originalVideo: VVideoInfo(
        path: videoPath,
        name: 'source.mov',
        fileSizeBytes: 100,
        durationMillis: 10000,
        width: 2160,
        height: 3840,
      ),
      compressedFilePath: returnOriginal ? videoPath : output.path,
      originalSizeBytes: 100,
      compressedSizeBytes: 40,
      compressionRatio: .4,
      timeTaken: 100,
      quality: config.quality,
      originalResolution: '2160x3840',
      compressedResolution: '1080x1920',
      spaceSaved: 60,
      usedOriginalFile: returnOriginal,
    );
  }
}

void main() {
  late VVideoCompressorPlatform previous;
  late _Platform platform;
  late Directory temp;
  late String destination;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('native-video-encoder-test-');
    destination = '${temp.path}/encoded.mp4';
    previous = VVideoCompressorPlatform.instance;
    platform = _Platform();
    VVideoCompressorPlatform.instance = platform;
  });

  tearDown(() async {
    VVideoCompressorPlatform.instance = previous;
    await temp.delete(recursive: true);
  });

  test(
    'requests portrait-safe H264 output, audio and no source deletion',
    () async {
      await NativeVideoEncoder().encode(
        '/source.mov',
        destination,
        metadata: const VideoMetadata(
          width: 2160,
          height: 3840,
          duration: Duration(seconds: 10),
        ),
      );
      final config = platform.receivedConfig!;
      expect(config.isValid(), isTrue);
      expect(config.deleteOriginal, isFalse);
      expect(config.saveToGallery, isFalse);
      expect(config.includeAudio, isTrue);
      expect(config.fallbackToOriginalIfNotSmaller, isFalse);
      expect(config.advanced!.videoCodec, VVideoCodec.h264);
      expect(config.advanced!.customWidth, 1080);
      expect(config.advanced!.customHeight, 1920);
      expect(config.advanced!.videoBitrate, 3000000);
      expect(config.advanced!.frameRate, 30);
      expect(config.outputPath, temp.path);
      expect(await File(destination).length(), 40);
      expect(await File('${temp.path}/native-generated.mp4').exists(), isFalse);
    },
  );

  test('does not upscale a small source', () async {
    await NativeVideoEncoder().encode(
      '/source.mov',
      destination,
      metadata: const VideoMetadata(
        width: 640,
        height: 480,
        duration: Duration(seconds: 10),
      ),
    );
    expect(platform.receivedConfig!.advanced!.customWidth, 640);
    expect(platform.receivedConfig!.advanced!.customHeight, 480);
  });

  test('turns plugin null/fallback responses into visible failures', () async {
    final encoder = NativeVideoEncoder();
    const metadata = VideoMetadata(
      width: 1920,
      height: 1080,
      duration: Duration(seconds: 10),
    );
    platform.fail = true;
    await expectLater(
      encoder.encode('/source.mov', destination, metadata: metadata),
      throwsA(isA<VideoPreparationException>()),
    );
    platform.fail = false;
    platform.returnOriginal = true;
    await expectLater(
      encoder.encode('/source.mov', destination, metadata: metadata),
      throwsA(isA<VideoPreparationException>()),
    );
  });
}
