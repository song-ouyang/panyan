import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _SmsApiClient extends ApiClient {
  _SmsApiClient(this.response)
    : super(config: _config, accessTokenProvider: () => null);

  final Map<String, dynamic> response;
  String? requestedPath;
  Object? requestedData;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    requestedPath = path;
    requestedData = data;
    return response;
  }
}

void main() {
  test('短信发送仅在服务端明确确认 sent=true 时成功', () async {
    final acceptedApi = _SmsApiClient({'sent': true});
    await AuthRepository(acceptedApi).sendSmsCode(phone: '13800138000');
    expect(acceptedApi.requestedPath, '/auth/sms/send');
    expect(acceptedApi.requestedData, {'phone': '13800138000'});

    final rejectedApi = _SmsApiClient({'sent': false});
    await expectLater(
      AuthRepository(rejectedApi).sendSmsCode(phone: '13800138000'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'SMS_SEND_INCOMPLETE',
        ),
      ),
    );
  });
}
