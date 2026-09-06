import 'package:flutter/foundation.dart';

import '../../features/auth/application/session_controller.dart';
import '../json/json_helpers.dart';
import '../models/growth_models.dart';
import '../network/api_client.dart';

/// One account-scoped cache per API client. Older responses can never replace
/// a newer revision or escape the login session that initiated the request.
class GrowthRepository extends ChangeNotifier {
  factory GrowthRepository.forSession(
    ApiClient api,
    SessionController session,
  ) => _instances[api] ??= GrowthRepository(api: api, session: session);
  GrowthRepository({required this.api, required this.session}) {
    _token = session.token;
    _userId = session.user?.id;
    session.addListener(_sessionChanged);
    api.climbingActivity.addListener(_activityChanged);
  }
  static final _instances = Expando<GrowthRepository>();
  final ApiClient api;
  final SessionController session;
  String? _token;
  String? _userId;
  int _generation = 0;
  bool _disposed = false;
  bool _consuming = false;
  GrowthSnapshot? _snapshot;
  List<UserBadge> _badges = const [];
  GrowthSnapshot? get snapshot => _snapshot;
  List<UserBadge> get badges => _badges;
  int get sessionGeneration => _generation;
  bool isCurrentSession(int generation) =>
      !_disposed &&
      generation == _generation &&
      session.isAuthenticated &&
      _token == session.token &&
      _userId == session.user?.id;

  void _sessionChanged() {
    if (_token == session.token && _userId == session.user?.id) return;
    _token = session.token;
    _userId = session.user?.id;
    _generation++;
    _snapshot = null;
    _badges = const [];
    _consuming = false;
    notifyListeners();
  }

  void _activityChanged() {
    // Consumers reload at their own lifecycle boundary; no silent background
    // consumption is allowed to take the celebration away from a save screen.
    if (!_disposed) notifyListeners();
  }

  bool acceptSnapshot(GrowthSnapshot? value, {required int generation}) {
    if (value == null || !isCurrentSession(generation)) return false;
    if (_snapshot != null && value.revision < _snapshot!.revision) return false;
    if (_snapshot?.revision != value.revision) {
      // A badge list belongs to one server revision. Never expose previously
      // earned entries as actionable while a newer snapshot is being loaded.
      _badges = const [];
    }
    _snapshot = value;
    notifyListeners();
    return true;
  }

  Future<GrowthSnapshot?> refresh() async {
    final generation = _generation;
    if (!isCurrentSession(generation)) return null;
    final value = GrowthSnapshot.fromJson(
      await api.getJson('/users/me/growth-level'),
    );
    acceptSnapshot(value, generation: generation);
    return isCurrentSession(generation) ? _snapshot : null;
  }

  Future<void> loadBadges() async {
    final generation = _generation;
    if (!isCurrentSession(generation)) return;
    final result = await api.getJson('/users/me/badges');
    final value = GrowthSnapshot.fromJson(jsonMap(result['growth']));
    final badges = jsonModelList(result['badges'], UserBadge.fromJson);
    if (!isCurrentSession(generation) ||
        (_snapshot != null && value.revision < _snapshot!.revision)) {
      return;
    }
    _snapshot = value;
    _badges = badges;
    notifyListeners();
  }

  Future<GrowthPresentation?> consumePresentation() async {
    final generation = _generation;
    if (!isCurrentSession(generation) || _consuming) return null;
    _consuming = true;
    try {
      final result = await api.inSession(
        _token!,
        () => api.postJson(
          '/users/me/growth-presentations/consume',
          data: const {},
        ),
      );
      if (!isCurrentSession(generation)) return null;
      final value = GrowthSnapshot.fromJson(jsonMap(result['growth']));
      if (!acceptSnapshot(value, generation: generation)) return null;
      if (result['shouldPresent'] != true || result['presentation'] == null) {
        return null;
      }
      final presentation = GrowthPresentation.fromJson(
        jsonMap(result['presentation']),
      );
      if (presentation.growthRevision != _snapshot!.revision ||
          presentation.toLevel != _snapshot!.currentLevel ||
          presentation.toLevel < 1) {
        return null;
      }
      return presentation;
    } finally {
      if (isCurrentSession(generation)) _consuming = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    session.removeListener(_sessionChanged);
    api.climbingActivity.removeListener(_activityChanged);
    if (identical(_instances[api], this)) _instances[api] = null;
    super.dispose();
  }

  static void disposeFor(ApiClient api) => _instances[api]?.dispose();
}
