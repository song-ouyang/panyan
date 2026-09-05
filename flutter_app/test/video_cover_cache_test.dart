import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/services/video_cover_cache.dart';

void main() {
  const firstUrl = 'https://example.invalid/first.mp4';

  test(
    'shares an in-flight extraction and reuses its successful cover',
    () async {
      final extraction = Completer<Uint8List?>();
      var calls = 0;
      final cache = VideoCoverCache(
        loader: (url) {
          expect(url, firstUrl);
          calls++;
          return extraction.future;
        },
      );

      final first = cache.load(firstUrl);
      final second = cache.load(firstUrl);
      expect(second, same(first));
      expect(calls, 1);

      final cover = Uint8List.fromList([1, 2, 3]);
      extraction.complete(cover);
      expect(await first, same(cover));
      expect(await second, same(cover));
      expect(await cache.load(firstUrl), same(cover));
      expect(calls, 1);
    },
  );

  test('propagates extraction failure and allows a successful retry', () async {
    var calls = 0;
    final cover = Uint8List.fromList([4, 5]);
    final cache = VideoCoverCache(
      loader: (_) async {
        calls++;
        if (calls == 1) throw StateError('Frame extraction failed');
        return cover;
      },
    );

    await expectLater(cache.load(firstUrl), throwsA(isA<StateError>()));
    expect(await cache.load(firstUrl), same(cover));
    expect(await cache.load(firstUrl), same(cover));
    expect(calls, 2);
  });

  for (final emptyResult in <Uint8List?>[null, Uint8List(0)]) {
    final description = emptyResult == null ? 'null' : 'empty';
    test(
      'does not cache a $description result and retries extraction',
      () async {
        var calls = 0;
        final cover = Uint8List.fromList([6]);
        final cache = VideoCoverCache(
          loader: (_) async {
            calls++;
            return calls == 1 ? emptyResult : cover;
          },
        );

        expect(await cache.load(firstUrl), same(emptyResult));
        expect(await cache.load(firstUrl), same(cover));
        expect(await cache.load(firstUrl), same(cover));
        expect(calls, 2);
      },
    );
  }

  test('limits extraction to two jobs and deduplicates queued URLs', () async {
    final urls = List.generate(
      6,
      (index) => 'https://example.invalid/$index.mp4',
    );
    final pending = <String, Completer<Uint8List?>>{};
    final started = <String>[];
    var active = 0;
    var peakActive = 0;
    final cache = VideoCoverCache(
      loader: (url) async {
        started.add(url);
        active++;
        if (active > peakActive) peakActive = active;
        final extraction = Completer<Uint8List?>();
        pending[url] = extraction;
        try {
          return await extraction.future;
        } finally {
          active--;
        }
      },
    );

    final results = urls.map(cache.load).toList();
    final duplicate = cache.load(urls.last);
    expect(duplicate, same(results.last));
    expect(started, urls.take(2));
    expect(active, 2);

    // Finish out of order so the queue cannot rely on the first job finishing.
    pending[urls[1]]!.complete(Uint8List.fromList([1]));
    expect(await results[1], [1]);
    expect(started, urls.take(3));
    expect(active, 2);

    pending[urls[0]]!.complete(Uint8List.fromList([0]));
    expect(await results[0], [0]);
    expect(started, urls.take(4));

    for (var index = 2; index < urls.length; index++) {
      pending[urls[index]]!.complete(Uint8List.fromList([index]));
      expect(await results[index], [index]);
      expect(active, lessThanOrEqualTo(2));
    }

    expect(await duplicate, [5]);
    expect(started, urls);
    expect(peakActive, 2);
    expect(active, 0);
  });

  test('evicts the least recently used cover above 48 entries', () async {
    final calls = <String, int>{};
    final cache = VideoCoverCache(
      loader: (url) async {
        calls.update(url, (value) => value + 1, ifAbsent: () => 1);
        return Uint8List.fromList([1]);
      },
    );
    final urls = List.generate(
      49,
      (index) => 'https://example.invalid/$index.mp4',
    );

    for (final url in urls.take(48)) {
      await cache.load(url);
    }
    await cache.load(urls[0]);
    await cache.load(urls[48]);

    // Touching the first entry protects it; the second entry is the oldest.
    for (final url in [urls[0], ...urls.skip(2)]) {
      await cache.load(url);
      expect(calls[url], 1, reason: '$url should remain cached');
    }
    await cache.load(urls[1]);
    expect(calls[urls[1]], 2);
  });

  test(
    'retains exactly 8 MiB and evicts by recency when bytes exceed it',
    () async {
      const secondUrl = 'https://example.invalid/second.mp4';
      const smallUrl = 'https://example.invalid/small.mp4';
      final calls = <String, int>{};
      final cache = VideoCoverCache(
        loader: (url) async {
          calls.update(url, (value) => value + 1, ifAbsent: () => 1);
          return Uint8List(url == smallUrl ? 1 : 4 * 1024 * 1024);
        },
      );

      await cache.load(firstUrl);
      await cache.load(secondUrl);
      await cache.load(secondUrl);
      await cache.load(firstUrl);
      expect(calls, {firstUrl: 1, secondUrl: 1});

      await cache.load(smallUrl);
      await cache.load(firstUrl);
      await cache.load(smallUrl);
      expect(calls[firstUrl], 1);
      expect(calls[smallUrl], 1);
      await cache.load(secondUrl);
      expect(calls[secondUrl], 2);

      // A second eviction must use the remaining byte count, not stale totals.
      await cache.load(smallUrl);
      await cache.load(secondUrl);
      expect(calls[smallUrl], 1);
      expect(calls[secondUrl], 2);
      await cache.load(firstUrl);
      expect(calls[firstUrl], 2);
    },
  );

  test(
    'returns an oversized cover without caching it or evicting others',
    () async {
      const oversizedUrl = 'https://example.invalid/oversized.mp4';
      final calls = <String, int>{};
      final oversizedCover = Uint8List(8 * 1024 * 1024 + 1);
      final smallCover = Uint8List.fromList([7]);
      final cache = VideoCoverCache(
        loader: (url) async {
          calls.update(url, (value) => value + 1, ifAbsent: () => 1);
          return url == oversizedUrl ? oversizedCover : smallCover;
        },
      );

      expect(await cache.load(firstUrl), same(smallCover));
      expect(await cache.load(oversizedUrl), same(oversizedCover));
      expect(await cache.load(oversizedUrl), same(oversizedCover));
      expect(await cache.load(firstUrl), same(smallCover));
      expect(calls, {firstUrl: 1, oversizedUrl: 2});
    },
  );
}
