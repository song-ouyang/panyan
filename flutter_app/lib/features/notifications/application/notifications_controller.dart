import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/models/notification_models.dart';
import '../../../core/models/user_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../auth/application/session_controller.dart';

class NotificationsController extends ChangeNotifier
    with WidgetsBindingObserver {
  NotificationsController({
    required ApiClient api,
    required this._session,
    this.pollInterval = const Duration(seconds: 30),
  }) : _api = api,
       _repository = NotificationRepository(api),
       _profiles = ProfileRepository(api);

  final ApiClient _api;
  final SessionController _session;
  final NotificationRepository _repository;
  final ProfileRepository _profiles;
  final Duration pollInterval;
  List<AppNotificationItem> _items = const [];
  List<UserSummary> _requests = const [];
  final Set<String> _accepting = {};
  int _unreadCount = 0;
  bool _loading = false;
  bool _refreshing = false;
  bool _started = false;
  bool _disposed = false;
  String? _error;
  String? _sessionToken;
  int _revision = 0;
  Timer? _timer;

  List<AppNotificationItem> get items => List.unmodifiable(_items);
  List<UserSummary> get requests => List.unmodifiable(_requests);
  int get unreadCount => _unreadCount;
  bool get loading => _loading;
  String? get error => _error;
  bool isAccepting(String userId) => _accepting.contains(userId);

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _session.addListener(_handleSessionChanged);
    _api.socialActivity.addListener(_handleSocialChanged);
    WidgetsBinding.instance.addObserver(this);
    _handleSessionChanged();
  }

  void _handleSessionChanged() {
    final token = _session.isAuthenticated ? _session.token : null;
    if (token == _sessionToken) return;
    _sessionToken = token;
    ++_revision;
    _items = const [];
    _requests = const [];
    _accepting.clear();
    _unreadCount = 0;
    _error = null;
    _loading = false;
    _refreshing = false;
    notifyListeners();
    _updatePolling();
    if (token != null) unawaited(refresh());
  }

  void _handleSocialChanged() => unawaited(refresh());

  void _updatePolling() {
    _timer?.cancel();
    _timer = null;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_started ||
        !_session.isAuthenticated ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    _timer = Timer.periodic(pollInterval, (_) {
      if (!_refreshing) unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    _timer = null;
    if (state == AppLifecycleState.resumed) {
      _updatePolling();
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (_disposed || !_session.isAuthenticated) return;
    final token = _session.token;
    final revision = ++_revision;
    _refreshing = true;
    _loading = _items.isEmpty && _requests.isEmpty;
    _error = null;
    notifyListeners();
    try {
      final (inbox, requests) = await (
        _repository.getInbox(),
        _profiles.getFriendRequests(),
      ).wait;
      if (!_isCurrent(token) || revision != _revision) return;
      _items = inbox.items;
      _unreadCount = inbox.unread;
      _requests = requests;
    } catch (_) {
      if (!_isCurrent(token) || revision != _revision) return;
      _error = '消息暂时没有加载出来，请重试';
    } finally {
      if (_isCurrent(token) && revision == _revision) {
        _loading = false;
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(String? token) =>
      !_disposed && _session.isAuthenticated && token == _session.token;

  Future<void> markRead(AppNotificationItem item) async {
    if (!item.isUnread || !_session.isAuthenticated || _disposed) return;
    final token = _session.token;
    await _repository.markRead(item.id);
    if (!_isCurrent(token)) return;
    _applyRead({item.id});
  }

  Future<void> markAllRead() async {
    if (!_session.isAuthenticated || _disposed) return;
    final token = _session.token;
    final ids = _items
        .where((item) => item.isUnread)
        .map((item) => item.id)
        .toSet();
    await _repository.markAllRead();
    if (!_isCurrent(token)) return;
    _applyRead(ids);
  }

  void _applyRead(Set<String> ids) {
    // Invalidate any inbox snapshot requested before the successful read write.
    ++_revision;
    _refreshing = false;
    _loading = false;
    final changed = _items
        .where((item) => item.isUnread && ids.contains(item.id))
        .length;
    final now = DateTime.now();
    _items = [
      for (final item in _items)
        ids.contains(item.id) ? item.asRead(now) : item,
    ];
    _unreadCount = (_unreadCount - changed).clamp(0, 100);
    notifyListeners();
  }

  Future<void> acceptFriendRequest(String userId) async {
    if (!_session.isAuthenticated || _disposed || !_accepting.add(userId)) {
      return;
    }
    final token = _session.token;
    notifyListeners();
    try {
      final status = await _profiles.acceptFriendRequest(userId);
      if (!_isCurrent(token)) return;
      if (status != 'accepted') {
        throw StateError('Friend request was not accepted');
      }
      _requests = _requests.where((user) => user.id != userId).toList();
      await refresh();
    } finally {
      if (_isCurrent(token)) {
        _accepting.remove(userId);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    _timer?.cancel();
    if (_started) {
      _session.removeListener(_handleSessionChanged);
      _api.socialActivity.removeListener(_handleSocialChanged);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
