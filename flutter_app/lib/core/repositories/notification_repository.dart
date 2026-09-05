import '../models/notification_models.dart';
import '../network/api_client.dart';

class NotificationRepository {
  const NotificationRepository(this._api);

  final ApiClient _api;

  Future<NotificationInbox> getInbox() async =>
      NotificationInbox.fromJson(await _api.getJson('/notifications'));

  Future<void> markRead(String id) async {
    await _api.postJson('/notifications/${Uri.encodeComponent(id)}/read');
  }

  Future<void> markAllRead() async {
    await _api.postJson('/notifications/read-all');
  }
}
