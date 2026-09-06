import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../json/json_helpers.dart';

/// A durable request ID and the exact final API payload survive an uncertain
/// response or process restart. Only a confirmed save clears the draft.
class PublicationRequestDraft {
  PublicationRequestDraft._(
    this._preferences,
    this._key,
    this.id,
    this.payload,
  );
  final SharedPreferences _preferences;
  final String _key;
  final String id;
  JsonMap? payload;
  static Future<PublicationRequestDraft> load({
    required String ownerId,
    required String kind,
    required String target,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = 'publication.request.$ownerId.$kind.$target';
    final stored = preferences.getString(key);
    if (stored != null) {
      try {
        final json = jsonMap(jsonDecode(stored));
        return PublicationRequestDraft._(
          preferences,
          key,
          jsonString(json['id'], field: 'id'),
          json['payload'] == null ? null : jsonMap(json['payload']),
        );
      } on FormatException {
        /* Replace an unreadable local draft. */
      }
    }
    final result = PublicationRequestDraft._(preferences, key, _uuid(), null);
    await result._persist();
    return result;
  }

  Future<void> freeze(JsonMap value) async {
    if (payload != null) return;
    payload = Map<String, dynamic>.from(value)..['clientRequestId'] = id;
    try {
      await _persist();
    } catch (_) {
      payload = null;
      rethrow;
    }
  }

  /// Validation/not-found responses are known not to have committed a record.
  /// Reuse the ID after correcting the form; uncertain transport failures never
  /// call this method and retain the exact request for recovery.
  Future<void> unlockAfterRejection() async {
    final previous = payload;
    payload = null;
    try {
      await _persist();
    } catch (_) {
      payload = previous;
      rethrow;
    }
  }

  Future<void> _persist() async {
    if (!await _preferences.setString(
      _key,
      jsonEncode({'id': id, 'payload': payload}),
    )) {
      throw StateError('提交草稿未保存，请重试');
    }
  }

  Future<void> clear() async {
    // A late response from an older draft cannot erase a newer record's key.
    final stored = _preferences.getString(_key);
    if (stored != null && jsonMap(jsonDecode(stored))['id'] == id) {
      await _preferences.remove(_key);
    }
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
