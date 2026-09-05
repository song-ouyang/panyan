import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/services/friend_code.dart';

const _userId = 'c680ed27-1709-4f39-8576-33fa9d6934b1';
const _officialOrigin = AppConfig.defaultShareBaseUrl;

void main() {
  final code = FriendCode(shareBaseUrl: _officialOrigin);

  test('好友码只携带公开用户 ID，普通扫码仍进入官网下载区', () {
    final uri = code.encode(_userId);

    expect(uri.toString(), '$_officialOrigin/?friend=$_userId#download');
    expect(uri.origin, _officialOrigin);
    expect(uri.queryParameters, {'friend': _userId});
    expect(uri.fragment, 'download');
    expect(code.parse(uri.toString()), _userId);
  });

  test('生成和解析将大写 UUID 规范为小写', () {
    expect(
      code.encode(_userId.toUpperCase()).queryParameters['friend'],
      _userId,
    );
    expect(
      code.parse('$_officialOrigin/?friend=${_userId.toUpperCase()}#download'),
      _userId,
    );
  });

  test('编码拒绝昵称、手机号、非 UUID 和带额外内容的 ID', () {
    for (final invalidId in [
      '',
      '岩友小白',
      '13800000000',
      'someone',
      _userId.replaceAll('-', ''),
      '${_userId}0',
      '${_userId.substring(0, 35)}g',
      ' $_userId',
      '$_userId\n',
      '$_userId&token=private',
    ]) {
      expect(
        () => code.encode(invalidId),
        throwsArgumentError,
        reason: invalidId,
      );
    }
  });

  test('解析拒绝外部域名、协议、凭据、端口和非约定路径', () {
    final host = Uri.parse(_officialOrigin).host;
    for (final raw in [
      'https://example.com/?friend=$_userId#download',
      'https://$host.evil.example/?friend=$_userId#download',
      'https://evil.$host/?friend=$_userId#download',
      'http://$host/?friend=$_userId#download',
      'https://$host:8443/?friend=$_userId#download',
      'https://user@$host/?friend=$_userId#download',
      'https://$host@evil.example/?friend=$_userId#download',
      '//$host/?friend=$_userId#download',
      '/?friend=$_userId#download',
      '$_officialOrigin/friends?friend=$_userId#download',
      '$_officialOrigin/share/user/$_userId#download',
      'wanpan://friends/$_userId',
      'javascript:alert(1)',
    ]) {
      expect(code.parse(raw), isNull, reason: raw);
    }
  });

  test('解析拒绝重复参数、额外令牌、缺少下载锚点和畸形内容', () {
    for (final raw in [
      '',
      _userId,
      '$_officialOrigin/#download',
      '$_officialOrigin/?friend=$_userId',
      '$_officialOrigin/?friend=$_userId#other',
      '$_officialOrigin/?friend=$_userId&friend=$_userId#download',
      '$_officialOrigin/?friend=$_userId&token=private#download',
      '$_officialOrigin/?friend=$_userId&redirect=https://example.com#download',
      '$_officialOrigin/?friend=$_userId&other=#download',
      '$_officialOrigin/?Friend=$_userId#download',
      '$_officialOrigin/?friend=#download',
      '$_officialOrigin/?friend=${_userId}0#download',
      '$_officialOrigin/?friend=$_userId%0A#download',
      '$_officialOrigin/?friend=not-a-user#download',
      '$_officialOrigin/?friend=%FF#download',
      '$_officialOrigin/?friend=%E0%A4%A#download',
      '$_officialOrigin/?friend=${'a' * 2100}#download',
      'https://[invalid/?friend=$_userId#download',
    ]) {
      expect(code.parse(raw), isNull, reason: raw);
    }
  });

  test('使用配置的官网源，不能跨官网解析其他构建的好友码', () {
    final alternate = FriendCode(shareBaseUrl: 'https://wanpan.example/');
    final uri = alternate.encode(_userId);

    expect(uri.toString(), 'https://wanpan.example/?friend=$_userId#download');
    expect(alternate.parse(uri.toString()), _userId);
    expect(code.parse(uri.toString()), isNull);
    expect(alternate.parse(code.encode(_userId).toString()), isNull);
  });
}
