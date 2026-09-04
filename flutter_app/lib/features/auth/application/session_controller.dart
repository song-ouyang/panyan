// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../../../core/json/json_helpers.dart';
import '../../../core/models/user_models.dart';
import '../../../core/network/api_exception.dart';
import '../data/auth_repository.dart';
import '../data/session_token_store.dart';
import '../domain/auth_session.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required SharedPreferences preferences,
    required AppConfig config,
    SessionTokenStore? tokenStore,
  }) : _preferences = preferences,
       _config = config,
       _tokenStore = tokenStore ?? const SecureSessionTokenStore() {
    _restoreUser();
  }

  static const _legacyTokenKey = 'auth.token';
  static const _userKey = 'auth.user';

  final SharedPreferences _preferences;
  final AppConfig _config;
  final SessionTokenStore _tokenStore;

  String? _token;
  UserSummary? _user;
  bool _isInitializing = true;
  bool _profileNeedsCompletion = false;
  bool _clearing = false;
  Future<void> _sessionMutation = Future<void>.value();

  String? get token => _token;
  UserSummary? get user => _user;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isInitializing => _isInitializing;
  bool get profileNeedsCompletion => _profileNeedsCompletion;
  bool get canUseDevelopmentLogin =>
      !_config.isProduction && _config.enableDevelopmentLogin;

  Future<void> initialize(AuthRepository authRepository) async {
    try {
      await _restoreTokenWithLegacyMigration();
      if (_token == null) return;

      try {
        final currentUser = await authRepository.validateSession();
        _user = currentUser;
        _profileNeedsCompletion = !currentUser.profileCompleted;
        await _persistUser(currentUser);
      } on ApiException catch (error) {
        if (error.isUnauthorized || _user == null) {
          await _clearSession(notify: false);
        }
        // Preserve an existing offline session for transient network failures.
      } catch (_) {
        if (_user == null) await _clearSession(notify: false);
        rethrow;
      }
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> signInWithDevelopmentAccount(
    AuthRepository authRepository,
  ) async {
    if (!canUseDevelopmentLogin) {
      throw const ApiException(
        code: 'DEV_LOGIN_DISABLED',
        message: '开发登录未启用，且正式环境永远禁用。',
      );
    }
    await acceptSession(
      await authRepository.signInWithWechatCode('dev:flutter'),
    );
  }

  Future<void> acceptSession(AuthSession session) =>
      _queueSessionMutation(() async {
        await _tokenStore.write(session.token);
        await _persistUser(session.user);
        await _preferences.remove(_legacyTokenKey);
        _token = session.token;
        _user = session.user;
        _profileNeedsCompletion = session.needsProfile;
        notifyListeners();
      });

  Future<void> updateUser(UserSummary user) => _queueSessionMutation(() async {
    _user = user;
    _profileNeedsCompletion = !user.profileCompleted;
    await _persistUser(user);
    notifyListeners();
  });

  Future<void> signOut() => _queueSessionMutation(_clearSession);

  Future<void> handleUnauthorized() => _queueSessionMutation(() async {
    if (_token == null || _clearing) return;
    await _clearSession();
  });

  /// Clears only the session whose bearer token was rejected by the server.
  ///
  /// A delayed 401 from an older request must not sign out a user who has
  /// already completed a newer login. Session mutations are serialized so an
  /// in-flight secure-storage write cannot race an older token deletion.
  Future<void> handleUnauthorizedResponse(String rejectedAccessToken) =>
      _queueSessionMutation(() async {
        if (_token != rejectedAccessToken || _clearing) return;
        await _clearSession();
      });

  void _restoreUser() {
    final storedUser = _preferences.getString(_userKey);
    if (storedUser == null) return;
    try {
      _user = UserSummary.fromJson(
        jsonMap(jsonDecode(storedUser), field: _userKey),
      );
      _profileNeedsCompletion = !_user!.profileCompleted;
    } on FormatException {
      _user = null;
      _preferences.remove(_userKey);
    }
  }

  Future<void> _restoreTokenWithLegacyMigration() async {
    _token = await _tokenStore.read();
    final legacyToken = _preferences.getString(_legacyTokenKey);
    if (_token == null && legacyToken?.isNotEmpty == true) {
      _token = legacyToken;
      await _tokenStore.write(legacyToken!);
    }
    if (legacyToken != null) await _preferences.remove(_legacyTokenKey);
    if (_token == null) {
      _user = null;
      await _preferences.remove(_userKey);
    }
  }

  Future<void> _persistUser(UserSummary user) =>
      _preferences.setString(_userKey, jsonEncode(user.toJson()));

  Future<void> _queueSessionMutation(Future<void> Function() mutation) {
    final next = _sessionMutation.then((_) => mutation());
    _sessionMutation = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }

  Future<void> _clearSession({bool notify = true}) async {
    if (_clearing) return;
    _clearing = true;
    try {
      _token = null;
      _user = null;
      _profileNeedsCompletion = false;
      await Future.wait([
        _tokenStore.delete(),
        _preferences.remove(_legacyTokenKey),
        _preferences.remove(_userKey),
      ]);
    } finally {
      _clearing = false;
      if (notify) notifyListeners();
    }
  }
}
