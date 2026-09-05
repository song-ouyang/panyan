import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';

typedef VideoCoverLoader = Future<Uint8List?> Function(String url);

/// Stores only still images. Listing posts never creates a playing video or
/// downloads a whole video into the application's file cache.
class VideoCoverCache {
  VideoCoverCache({VideoCoverLoader? loader})
    : _loader = loader ?? _extractFrame;

  static final shared = VideoCoverCache();
  static const _maxBytes = 8 * 1024 * 1024;
  static const _maxEntries = 48;
  static const _concurrency = 2;

  final VideoCoverLoader _loader;
  final _images = <String, Uint8List>{};
  final _inFlight = <String, Future<Uint8List?>>{};
  final _queue = Queue<void Function()>();
  int _bytes = 0;
  int _active = 0;

  Future<Uint8List?> load(String url) {
    final cached = _images.remove(url);
    if (cached != null) {
      _images[url] = cached;
      return Future.value(cached);
    }
    final pending = _inFlight[url];
    if (pending != null) return pending;

    final completer = Completer<Uint8List?>();
    _inFlight[url] = completer.future;
    _queue.add(() async {
      try {
        final bytes = await _loader(url);
        if (bytes != null && bytes.isNotEmpty && bytes.length <= _maxBytes) {
          _images[url] = bytes;
          _bytes += bytes.length;
          while (_bytes > _maxBytes || _images.length > _maxEntries) {
            _bytes -= _images.remove(_images.keys.first)!.length;
          }
        }
        completer.complete(bytes);
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _inFlight.remove(url);
        _active--;
        _drain();
      }
    });
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_active < _concurrency && _queue.isNotEmpty) {
      _active++;
      _queue.removeFirst()();
    }
  }

  static Future<Uint8List?> _extractFrame(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return VideoThumbnail.thumbnailData(
      video: uri.toString(),
      imageFormat: ImageFormat.JPEG,
      // Set one dimension so Android preserves the video's aspect ratio too.
      maxHeight: 480,
      timeMs: 0,
      quality: 80,
    );
  }
}
