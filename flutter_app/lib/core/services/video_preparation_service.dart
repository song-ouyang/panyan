import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:v_video_compressor/v_video_compressor.dart';

class PreparedVideo {
  const PreparedVideo({
    required this.path,
    required this.filename,
    required this.mimeType,
    required this.originalBytes,
    required this.size,
    required this.wasCompressed,
  });

  final String path;
  final String filename;
  final String mimeType;
  final int originalBytes;
  final int size;
  final bool wasCompressed;
}

class VideoPreparationException implements Exception {
  const VideoPreparationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class VideoMetadata {
  const VideoMetadata({
    required this.width,
    required this.height,
    required this.duration,
  });

  final int width;
  final int height;
  final Duration duration;
}

/// The encoder writes only [destinationPath] and never deletes the source.
abstract class VideoEncoder {
  Future<VideoMetadata> inspect(String sourcePath);

  Future<void> encode(
    String sourcePath,
    String destinationPath, {
    required VideoMetadata metadata,
    void Function(double)? onProgress,
  });
}

/// Native Media3 / AVFoundation encoding; no FFmpeg runtime is bundled.
class NativeVideoEncoder implements VideoEncoder {
  NativeVideoEncoder() {
    VVideoCompressor.configureLogging(const VVideoLogConfig.disabled());
  }

  final _compressor = VVideoCompressor();

  @override
  Future<VideoMetadata> inspect(String sourcePath) async {
    final info = await _compressor.getVideoInfo(sourcePath);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.durationMillis <= 0) {
      throw const VideoPreparationException('无法读取视频，请重新选择视频');
    }
    return VideoMetadata(
      width: info.width,
      height: info.height,
      duration: Duration(milliseconds: info.durationMillis),
    );
  }

  @override
  Future<void> encode(
    String sourcePath,
    String destinationPath, {
    required VideoMetadata metadata,
    void Function(double)? onProgress,
  }) async {
    final longest = math.max(metadata.width, metadata.height);
    final shortest = math.min(metadata.width, metadata.height);
    final scale = math.min(1.0, math.min(1920 / longest, 1080 / shortest));
    // Even dimensions satisfy native encoders without cropping or upscaling.
    int scaled(int value) => math.max(2, (value * scale / 2).floor() * 2);
    final destination = File(destinationPath);
    final outputDirectory = destination.parent;
    await outputDirectory.create(recursive: true);
    final result = await _compressor.compressVideo(
      sourcePath,
      VVideoCompressionConfig.high(
        // Both native implementations treat outputPath as a directory and
        // generate a unique MP4 filename inside it.
        outputPath: outputDirectory.path,
        deleteOriginal: false,
        saveToGallery: false,
        fallbackToOriginalIfNotSmaller: false,
        includeAudio: true,
        includeMetadata: false,
        copyMetadata: false,
        advanced: VVideoAdvancedConfig(
          customWidth: scaled(metadata.width),
          customHeight: scaled(metadata.height),
          videoCodec: VVideoCodec.h264,
          audioCodec: VAudioCodec.aac,
          // A target, not a guaranteed bitrate: iOS uses a file-length budget.
          videoBitrate: 3000000,
          frameRate: 30,
        ),
      ),
      onProgress: onProgress,
    );
    if (result == null || result.usedOriginalFile) {
      throw const VideoPreparationException('视频压缩失败，请重试或重新选择视频');
    }
    final generated = File(result.compressedFilePath);
    if (await generated.parent.resolveSymbolicLinks() !=
            await outputDirectory.resolveSymbolicLinks() ||
        generated.absolute.path == File(sourcePath).absolute.path) {
      throw const VideoPreparationException('视频压缩失败，请重试或重新选择视频');
    }
    if (generated.absolute.path != destination.absolute.path) {
      await generated.rename(destination.path);
    }
  }
}

/// Creates a durable, content-addressed upload source before network upload.
///
/// Call [release] in the uploader's finally block. Releasing keeps the cached
/// bytes for retries; active files are never evicted. Inactive caches expire
/// after seven days and are evicted oldest-first above a 512 MiB soft budget.
class VideoPreparationService {
  VideoPreparationService({
    VideoEncoder? encoder,
    Future<Directory> Function()? cacheDirectory,
    DateTime Function()? now,
    this.cacheMaxBytes = 512 * 1024 * 1024,
    this.cacheMaxAge = const Duration(days: 7),
  }) : _encoder = encoder ?? NativeVideoEncoder(),
       _cacheDirectory = cacheDirectory ?? _defaultCacheDirectory,
       _now = now ?? DateTime.now;

  final VideoEncoder _encoder;
  final Future<Directory> Function() _cacheDirectory;
  final DateTime Function() _now;
  final int cacheMaxBytes;
  final Duration cacheMaxAge;

  // The native plugin exposes one progress handler. Serialize preparation
  // across repository instances while already-prepared videos upload freely.
  static Future<void> _tail = Future.value();
  static final Map<String, int> _leases = {};
  static const _profile = 'h264-1080p-3mbps-v1';

  static Future<Directory> _defaultCacheDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/prepared_videos');
  }

  Future<PreparedVideo> prepare(
    String sourcePath, {
    void Function(double)? onProgress,
  }) {
    final completed = Completer<PreparedVideo>();
    _tail = _tail.then((_) async {
      try {
        completed.complete(await _prepare(sourcePath, onProgress));
      } catch (error, stack) {
        completed.completeError(error, stack);
      }
    });
    return completed.future;
  }

  void release(PreparedVideo video) {
    final count = _leases[video.path] ?? 0;
    if (count <= 1) {
      _leases.remove(video.path);
    } else {
      _leases[video.path] = count - 1;
    }
  }

  Future<PreparedVideo> _prepare(
    String sourcePath,
    void Function(double)? onProgress,
  ) async {
    Directory? staging;
    try {
      onProgress?.call(0);
      final source = File(sourcePath);
      final originalBytes = await source.length();
      if (originalBytes == 0) {
        throw const VideoPreparationException('视频文件为空，请重新选择视频');
      }
      final sourceHash = await _hash(source);
      if (await source.length() != originalBytes) {
        throw const VideoPreparationException('视频文件发生变化，请重新选择后上传');
      }
      final root = await _cacheDirectory();
      await root.create(recursive: true);
      final entry = Directory('${root.path}/$_profile-$sourceHash');
      await _prune(root, protectedDirectory: entry.path);
      final cached = await _readCache(entry, originalBytes);
      if (cached != null) {
        onProgress?.call(1);
        return _retain(cached);
      }
      if (_leases.keys.any((path) => File(path).parent.path == entry.path)) {
        throw const VideoPreparationException('该视频正在上传，请等待当前上传结束后重试');
      }
      final metadata = await _encoder.inspect(source.path);
      if (metadata.width <= 0 ||
          metadata.height <= 0 ||
          metadata.duration.inMilliseconds <= 0) {
        throw const VideoPreparationException('无法读取视频，请重新选择视频');
      }
      staging = await root.createTemp('.preparing-');
      var chosen = source;
      var wasCompressed = false;
      final extension = source.path.toLowerCase().endsWith('.mov')
          ? 'mov'
          : 'mp4';
      var filename = 'video.$extension';
      // Small, already efficient files avoid a lossy re-encode. Larger files
      // are always offered to the encoder, even when their bitrate is low.
      final bitrate = originalBytes * 8000 / metadata.duration.inMilliseconds;
      final alreadyCompact =
          originalBytes <= 8 * 1024 * 1024 &&
          math.max(metadata.width, metadata.height) <= 1920 &&
          math.min(metadata.width, metadata.height) <= 1080 &&
          bitrate <= 3200000;
      if (!alreadyCompact) {
        final output = File('${staging.path}/encoded.mp4');
        await _encoder.encode(
          source.path,
          output.path,
          metadata: metadata,
          onProgress: (value) {
            if (value.isFinite) {
              onProgress?.call(value.clamp(0, .99));
            }
          },
        );
        final outputBytes = await output.length();
        if (outputBytes <= 0) {
          throw const VideoPreparationException('视频压缩失败，请重新选择视频');
        }
        final outputInfo = await _encoder.inspect(output.path);
        final durationDifference = (outputInfo.duration - metadata.duration)
            .inMilliseconds
            .abs();
        if (durationDifference >
            math.max(1000, metadata.duration.inMilliseconds * .02)) {
          throw const VideoPreparationException('压缩后的视频不完整，请重试');
        }
        if (outputBytes < originalBytes) {
          chosen = output;
          filename = 'video.mp4';
          wasCompressed = true;
        }
      }
      final stagedVideo = wasCompressed
          ? await chosen.rename('${staging.path}/$filename')
          : await chosen.copy('${staging.path}/$filename');
      // Detect source replacement during preparation rather than reuse the
      // wrong multipart session for a different video with the same name.
      if (await _hash(source) != sourceHash) {
        throw const VideoPreparationException('视频文件发生变化，请重新选择后上传');
      }
      final size = await stagedVideo.length();
      final mimeType = filename.endsWith('.mov')
          ? 'video/quicktime'
          : 'video/mp4';
      await File('${staging.path}/metadata.json').writeAsString(
        jsonEncode({
          'filename': filename,
          'mimeType': mimeType,
          'originalBytes': originalBytes,
          'size': size,
          'wasCompressed': wasCompressed,
          'sha256': await _hash(stagedVideo),
        }),
        flush: true,
      );
      await File('${staging.path}/metadata.json').setLastModified(_now());
      final encoderOutput = File('${staging.path}/encoded.mp4');
      if (await encoderOutput.exists()) await encoderOutput.delete();
      if (await entry.exists()) await entry.delete(recursive: true);
      await staging.rename(entry.path);
      staging = null;
      final result = PreparedVideo(
        path: '${entry.path}/$filename',
        filename: filename,
        mimeType: mimeType,
        originalBytes: originalBytes,
        size: size,
        wasCompressed: wasCompressed,
      );
      _retain(result);
      await _prune(root, protectedDirectory: entry.path);
      onProgress?.call(1);
      return result;
    } on VideoPreparationException {
      rethrow;
    } on FileSystemException {
      throw const VideoPreparationException('无法准备视频，请检查手机剩余空间并重新选择视频');
    } catch (_) {
      throw const VideoPreparationException('视频压缩失败，请重试或重新选择视频');
    } finally {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  static Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  PreparedVideo _retain(PreparedVideo video) {
    _leases.update(video.path, (value) => value + 1, ifAbsent: () => 1);
    return video;
  }

  Future<PreparedVideo?> _readCache(Directory entry, int originalBytes) async {
    try {
      final record = File('${entry.path}/metadata.json');
      final json = jsonDecode(await record.readAsString()) as Map;
      final filename = json['filename'];
      if (filename != 'video.mp4' && filename != 'video.mov') return null;
      final file = File('${entry.path}/$filename');
      final size = await file.length();
      if (json['originalBytes'] != originalBytes ||
          json['size'] != size ||
          size <= 0 ||
          size > originalBytes ||
          json['sha256'] != await _hash(file)) {
        return null;
      }
      await record.setLastModified(_now());
      return PreparedVideo(
        path: file.path,
        filename: filename as String,
        mimeType: filename == 'video.mov' ? 'video/quicktime' : 'video/mp4',
        originalBytes: originalBytes,
        size: size,
        wasCompressed: json['wasCompressed'] as bool,
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _prune(
    Directory root, {
    required String protectedDirectory,
  }) async {
    final candidates = <({Directory directory, DateTime accessed, int size})>[];
    var total = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!name.startsWith('$_profile-') && !name.startsWith('.preparing-')) {
        continue;
      }
      var bytes = 0;
      await for (final file in entity.list(followLinks: false)) {
        if (file is File) bytes += await file.length();
      }
      total += bytes;
      if (entity.path == protectedDirectory ||
          _leases.keys.any((path) => File(path).parent.path == entity.path)) {
        continue;
      }
      final record = File('${entity.path}/metadata.json');
      final accessed = await record.exists()
          ? await record.lastModified()
          : (await entity.stat()).modified;
      candidates.add((directory: entity, accessed: accessed, size: bytes));
    }
    candidates.sort((a, b) => a.accessed.compareTo(b.accessed));
    for (final item in candidates) {
      if (total > cacheMaxBytes ||
          _now().difference(item.accessed) > cacheMaxAge) {
        await item.directory.delete(recursive: true);
        total -= item.size;
      }
    }
  }
}
