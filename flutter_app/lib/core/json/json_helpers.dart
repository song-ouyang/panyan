typedef JsonMap = Map<String, dynamic>;

JsonMap jsonMap(Object? value, {String field = 'response'}) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('$field must be a JSON object');
}

List<dynamic> jsonList(Object? value, {String field = 'items'}) {
  if (value == null) return const [];
  if (value is List) return value;
  throw FormatException('$field must be a JSON array');
}

String jsonString(Object? value, {String field = 'value'}) {
  if (value is String) return value;
  throw FormatException('$field must be a string');
}

String? jsonNullableString(Object? value) => value is String ? value : null;

int jsonInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double? jsonNullableDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool jsonBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

DateTime? jsonDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

List<String> jsonStringList(Object? value) =>
    jsonList(value).whereType<String>().toList(growable: false);

List<T> jsonModelList<T>(Object? value, T Function(JsonMap json) fromJson) =>
    jsonList(value)
        .map((item) => fromJson(jsonMap(item)))
        .toList(growable: false);
