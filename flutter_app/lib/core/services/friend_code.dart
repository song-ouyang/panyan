import '../config/app_config.dart';

/// A public user locator, never an authentication or automatic-friending token.
/// External scanners still land on the existing official download section.
class FriendCode {
  FriendCode({required String shareBaseUrl})
    : _origin = Uri.parse(AppConfig.validateShareBaseUrl(shareBaseUrl));

  final Uri _origin;
  static final _userIdPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  Uri encode(String userId) {
    if (!_isUserId(userId)) {
      throw ArgumentError.value(userId, 'userId', 'Expected a user UUID');
    }
    return _origin.replace(
      path: '/',
      queryParameters: {'friend': userId.toLowerCase()},
      fragment: 'download',
    );
  }

  String? parse(String rawValue) {
    if (rawValue.length > 2048) return null;
    final uri = Uri.tryParse(rawValue.trim());
    if (uri == null ||
        uri.scheme != _origin.scheme ||
        uri.host != _origin.host ||
        uri.port != _origin.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/' ||
        uri.fragment != 'download') {
      return null;
    }
    try {
      final parameters = uri.queryParametersAll;
      final ids = parameters['friend'];
      if (parameters.length != 1 || ids == null || ids.length != 1) return null;
      final id = ids.single;
      return _isUserId(id) ? id.toLowerCase() : null;
    } on FormatException {
      return null;
    }
  }

  static bool _isUserId(String value) =>
      value.length == 36 && _userIdPattern.hasMatch(value);
}
