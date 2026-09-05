import '../json/json_helpers.dart';

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.type,
    required this.title,
    this.content,
    this.targetPath,
    this.createdAt,
    this.readAt,
  });

  factory AppNotificationItem.fromJson(JsonMap json) => AppNotificationItem(
    id: jsonString(json['id'], field: 'id'),
    type: jsonString(json['type'], field: 'type'),
    title: jsonString(json['title'], field: 'title'),
    content: jsonNullableString(json['content']),
    targetPath: jsonNullableString(json['target_path']),
    createdAt: jsonDateTime(json['created_at']),
    readAt: jsonDateTime(json['read_at']),
  );

  final String id;
  final String type;
  final String title;
  final String? content;
  final String? targetPath;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  // Notifications are shared with the mini-program. Only translate destinations
  // supported by this app; never open arbitrary server-provided URLs.
  String? get route {
    if (type == 'friend_request' || type == 'friend_accepted') {
      return '/friends';
    }
    final uri = Uri.tryParse(targetPath ?? '');
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    switch (uri.path) {
      case '/pages/friends/index':
        return '/friends';
      case '/pages/my-submissions/index':
      case '/submissions/mine':
        return '/route-submissions';
      case '/pages/my-posts/index':
        return '/profile/calendar';
      case '/pages/post/index':
        String? id;
        try {
          id = uri.queryParameters['id'];
        } on FormatException {
          return null;
        }
        if (id == null || !_uuid.hasMatch(id)) return null;
        return '/posts/$id';
      default:
        return null;
    }
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  AppNotificationItem asRead(DateTime time) => AppNotificationItem(
    id: id,
    type: type,
    title: title,
    content: content,
    targetPath: targetPath,
    createdAt: createdAt,
    readAt: readAt ?? time,
  );
}

class NotificationInbox {
  const NotificationInbox({required this.items, required this.unread});

  factory NotificationInbox.fromJson(JsonMap json) => NotificationInbox(
    items: jsonModelList(json['items'], AppNotificationItem.fromJson),
    unread: jsonInt(json['unread']).clamp(0, 100),
  );

  final List<AppNotificationItem> items;
  final int unread;
}
