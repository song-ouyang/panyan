import 'dart:async';

import 'package:flutter/material.dart';

import 'app/wanpan_bootstrap.dart';
import 'core/config/app_config.dart';
import 'shared/app_assets.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  await _warmWelcomeArtwork();
  runApp(WanpanBootstrap(config: AppConfig.fromEnvironment()));
  binding.allowFirstFrame();
}

/// Keep the native welcome visible until Flutter can paint the same cat.
Future<void> _warmWelcomeArtwork() async {
  final stream = const AssetImage(AppAssets.homeHeroCat)
      .resolve(ImageConfiguration.empty);
  final ready = Completer<void>();
  final listener = ImageStreamListener(
    (image, _) {
      image.dispose();
      if (!ready.isCompleted) ready.complete();
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!ready.isCompleted) ready.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  try {
    await ready.future.timeout(const Duration(seconds: 2));
  } catch (error) {
    debugPrint('Welcome artwork preload failed: $error');
  } finally {
    stream.removeListener(listener);
  }
}
