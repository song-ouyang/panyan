# video_thumbnail 0.5.6 compatibility copy

This directory contains the runtime sources and package metadata from the
official [`video_thumbnail` 0.5.6 release](https://pub.dev/packages/video_thumbnail/versions/0.5.6),
published by the [upstream project](https://github.com/justsoft/video_thumbnail).
The original MIT license is retained in `LICENSE`.

Source archive: <https://pub.dev/api/archives/video_thumbnail-0.5.6.tar.gz>

Archive SHA-256:
`181a0c205b353918954a881f53a3441476b9e301641688a581e0c13f00dc588b`

## Local changes

Replace the two `jcenter()` repository declarations in `android/build.gradle`
with `mavenCentral()`. Gradle 9 removed `jcenter()`; the original package otherwise
fails during Android project configuration. The application uses a relative
path dependency so clean checkouts and CI use the same fix without modifying
the global pub cache.

Raise this library's `compileSdkVersion` from 33 to 34. The app's current AndroidX
dependencies require API 34 during AAR metadata checks. The application's
`targetSdk` and `minSdk`, and this library's `minSdk`, are unchanged.

Dart APIs, Android/iOS frame extraction, native plugin identifiers, and the iOS
podspec behavior are unchanged. Upstream trailing whitespace and the extra
blank line at the end of the podspec are normalized for repository checks. Upstream examples, tests, and standalone Android build
wrapper files are omitted because the app's Flutter/Gradle build owns them.

When updating, compare against the official release, preserve its license,
review whether this compatibility patch is still needed, and verify both
Android compilation and iOS compilation before removing the path dependency.
