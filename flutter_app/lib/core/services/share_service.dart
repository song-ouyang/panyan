import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Keep native sharing separate from link publication and screen state.
class ShareService {
  const ShareService();

  Future<ShareResultStatus> share({
    required Uri url,
    required String title,
    required Rect origin,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        uri: url,
        title: title,
        subject: title,
        sharePositionOrigin: origin,
      ),
    );
    return result.status;
  }

  Future<ShareResultStatus> shareImage({
    required Uint8List bytes,
    required String title,
    required String fileName,
    required Rect origin,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png')],
        fileNameOverrides: [fileName],
        title: title,
        subject: title,
        sharePositionOrigin: origin,
      ),
    );
    return result.status;
  }

  Future<void> copy(Uri url) => Clipboard.setData(ClipboardData(text: '$url'));

  Future<void> preview(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw StateError('Cannot open share preview');
    }
  }
}
