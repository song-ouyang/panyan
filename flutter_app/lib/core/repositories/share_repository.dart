import '../config/app_config.dart';
import '../json/json_helpers.dart';
import '../network/api_client.dart';

class ShareRepository {
  ShareRepository(this._api)
    : _baseUrl = AppConfig.validateShareBaseUrl(_api.config.shareBaseUrl);

  final ApiClient _api;
  final String _baseUrl;

  Uri routeUrl(String routeId) => _url(['share', 'route', routeId]);

  Uri monthlyUrl(String token) {
    _validateToken(token);
    return _url(['share', 'monthly', token]);
  }

  Future<String?> getMonthlyToken(String month) async {
    _validateMonth(month);
    final json = await _api.getJson(
      '/shares/monthly',
      queryParameters: {'month': month},
    );
    return _readToken(json, month);
  }

  Future<String> createMonthlyShare(String month) async {
    _validateMonth(month);
    final json = await _api.postJson('/shares/monthly', data: {'month': month});
    final token = _readToken(json, month);
    if (token == null) throw const FormatException('Missing share token');
    return token;
  }

  Future<void> revokeMonthlyShare(String token) async {
    _validateToken(token);
    await _api.deleteJson('/shares/monthly/$token');
  }

  Uri _url(List<String> segments) =>
      Uri.parse(_baseUrl).replace(pathSegments: segments);

  String? _readToken(JsonMap json, String month) {
    if (json['month'] != month) {
      throw const FormatException('Share month does not match requested month');
    }
    final token = json['token'];
    if (token == null) return null;
    if (token is! String) throw const FormatException('Invalid share token');
    _validateToken(token);
    return token;
  }

  void _validateToken(String token) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const FormatException('Invalid share token');
    }
  }

  void _validateMonth(String month) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      throw const FormatException('Invalid share month');
    }
  }
}
