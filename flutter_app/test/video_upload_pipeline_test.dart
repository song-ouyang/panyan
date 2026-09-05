import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';
import 'package:wanpan_diary/core/repositories/checkin_repository.dart';
import 'package:wanpan_diary/core/repositories/route_submission_repository.dart';
import 'package:wanpan_diary/core/services/resumable_video_uploader.dart';
import 'package:wanpan_diary/core/services/video_preparation_service.dart';

class _Preparation extends VideoPreparationService {
  Object? error;
  int releases = 0;
  @override
  Future<PreparedVideo> prepare(
    String sourcePath, {
    void Function(double)? onProgress,
  }) async {
    if (error != null) throw error!;
    expect(sourcePath, '/phone/original.mov');
    onProgress?.call(1);
    return const PreparedVideo(
      path: '/cache/compressed.mp4',
      filename: 'compressed.mp4',
      mimeType: 'video/mp4',
      originalBytes: 200000000,
      size: 2000000,
      wasCompressed: true,
    );
  }

  @override
  void release(PreparedVideo video) {
    releases++;
  }
}

class _Uploader extends ResumableVideoUploader {
  _Uploader(super.api);
  final paths = <String>[];
  ApiException? error;
  @override
  Future<String> upload(
    String path, {
    String? filename,
    String? mimeType,
    void Function(double)? onProgress,
  }) async {
    paths.add(path);
    expect(filename, 'compressed.mp4');
    expect(mimeType, 'video/mp4');
    if (error != null) throw error!;
    onProgress?.call(1);
    return 'https://oss.example.com/compressed.mp4';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiClient api;
  late _Preparation preparation;
  late _Uploader uploader;
  late CheckinRepository repository;
  setUp(() {
    api = ApiClient(
      config: const AppConfig(
        environment: AppEnvironment.production,
        apiBaseUrl: 'https://api.example.com/api',
        enableDevelopmentLogin: false,
      ),
      accessTokenProvider: () => 'test-token',
    );
    preparation = _Preparation();
    uploader = _Uploader(api);
    repository = CheckinRepository(
      api,
      videoPreparation: preparation,
      videoUploader: uploader,
    );
  });
  tearDown(() => api.dispose());

  test(
    'checkin uploads only prepared MP4 including videos smaller than a part',
    () async {
      final phases = <VideoUploadPhase>[];
      await repository.uploadVideo(
        '/phone/original.mov',
        onPhaseChanged: phases.add,
      );
      expect(uploader.paths, ['/cache/compressed.mp4']);
      expect(phases, [VideoUploadPhase.preparing, VideoUploadPhase.uploading]);
      expect(preparation.releases, 1);
    },
  );

  test(
    'route publication shares the same compression and upload pipeline',
    () async {
      final routes = RouteSubmissionRepository(
        api,
        mediaRepository: repository,
      );
      await routes.uploadVideo(
        '/phone/original.mov',
        filename: 'original.mov',
        mimeType: 'video/quicktime',
      );
      expect(uploader.paths, ['/cache/compressed.mp4']);
    },
  );

  test('compression failure does not start a network upload', () async {
    preparation.error = const VideoPreparationException('视频压缩失败');
    await expectLater(
      repository.uploadVideo('/phone/original.mov'),
      throwsA(isA<VideoPreparationException>()),
    );
    expect(uploader.paths, isEmpty);
  });

  test('upload failure keeps original error and releases cache lease without proxy fallback', () async {
    uploader.error = const ApiException(message: 'offline', statusCode: 503);
    await expectLater(
      repository.uploadVideo('/phone/original.mov'),
      throwsA(same(uploader.error)),
    );
    expect(uploader.paths, ['/cache/compressed.mp4']);
    expect(preparation.releases, 1);
  });

  test(
    'production never falls back to local uploads when OSS is misconfigured',
    () async {
      uploader.error = const ApiException(
        code: 'OSS_NOT_CONFIGURED',
        message: 'OSS 分片上传尚未配置',
        statusCode: 503,
      );
      await expectLater(
        repository.uploadVideo('/phone/original.mov'),
        throwsA(same(uploader.error)),
      );
      expect(preparation.releases, 1);
    },
  );
}
