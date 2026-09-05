import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/gym_models.dart';

/// The most recently chosen store and the independently selected directory area.
class GymSelectionStore {
  GymSelectionStore({required this.preferences});

  static const _storageKey = 'gym_selection_v1';

  final SharedPreferences preferences;

  static Future<GymSelectionStore> load() async =>
      GymSelectionStore(preferences: await SharedPreferences.getInstance());

  String? get gymId => _read()['gymId'] as String?;

  /// True also for an explicit 全国 selection, represented by a null region.
  bool get hasRegion => _regionState().containsKey('region');

  ({String province, String city})? get region {
    final value = _regionState()['region'];
    if (value is! Map<String, dynamic>) return null;
    return (
      province: value['province'] as String,
      city: value['city'] as String,
    );
  }

  Future<void> rememberGym(Gym gym) {
    final id = gym.id.trim();
    if (id.isEmpty) throw ArgumentError.value(gym.id, 'gym.id');
    final state = _read()..['gymId'] = id;
    final city = gym.city.trim();
    if (city.isNotEmpty && city != '待核验') {
      state['region'] = {'province': gym.province.trim(), 'city': city};
    } else {
      state['region'] = null;
    }
    return _write(_withHomeCityBaseline(state));
  }

  Future<void> rememberRegion({
    required String? province,
    required String? city,
  }) {
    final state = _read();
    if (province == null && city == null) {
      state['region'] = null;
    } else {
      final value = city?.trim();
      if (value == null || value.isEmpty || value == '待核验') {
        throw ArgumentError.value(city, 'city');
      }
      state['region'] = {'province': province?.trim() ?? '', 'city': value};
    }
    return _write(_withHomeCityBaseline(state));
  }

  Future<void> clearGym() => _write(_read()..remove('gymId'));

  String get _homeCity =>
      preferences.getString('home_city_selection')?.trim() ?? '';

  int get _homeCityRevision =>
      preferences.getInt('home_city_selection_revision') ?? 0;

  Map<String, dynamic> _regionState() {
    final state = _read();
    if (preferences.containsKey('home_city_selection') &&
        (state['homeCity'] != _homeCity ||
            state['homeCityRevision'] != _homeCityRevision)) {
      // Older installs have no baseline. Their saved 全国 must not hide the
      // city already selected on the home screen. A city-only region is
      // resolved against the actual gym directory by the picker.
      state['region'] = _homeCity.isEmpty
          ? null
          : {'province': '', 'city': _homeCity};
    }
    return state;
  }

  Map<String, dynamic> _withHomeCityBaseline(Map<String, dynamic> state) {
    if (preferences.containsKey('home_city_selection')) {
      state['homeCity'] = _homeCity;
      state['homeCityRevision'] = _homeCityRevision;
    }
    return state;
  }

  Map<String, dynamic> _read() {
    final stored = preferences.get(_storageKey);
    if (stored is! String) return {};
    try {
      final state = jsonDecode(stored);
      if (state is! Map<String, dynamic>) return {};
      final id = state['gymId'];
      if (id != null && (id is! String || id.trim().isEmpty)) return {};
      final region = state['region'];
      if (region != null &&
          (region is! Map<String, dynamic> ||
              region['province'] is! String ||
              region['city'] is! String ||
              (region['city'] as String).trim().isEmpty ||
              region['city'] == '待核验')) {
        return {};
      }
      return state;
    } on FormatException {
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> state) async {
    // Read and update the preferences cache without an intervening await, so
    // stores sharing these preferences always merge the latest fields.
    final saved = await preferences.setString(_storageKey, jsonEncode(state));
    if (!saved) throw StateError('Unable to save gym selection');
  }
}
