import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/location/city_location_service.dart';

/// Keeps an explicit city choice (including 全国) ahead of late GPS results.
class HomeCityController extends ChangeNotifier {
  HomeCityController({
    this._locationService = const CityLocationService(),
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final CityLocationService _locationService;
  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<SharedPreferences>? _preferences;
  Future<void>? _initialization;
  Future<void> _pendingWrite = Future.value();
  String? _city;
  bool _isLocating = false;
  CityLocationException? _locationError;
  int _selectionRevision = 0;
  bool _disposed = false;

  String? get city => _city;
  bool get isLocating => _isLocating;
  CityLocationException? get locationError => _locationError;

  Future<SharedPreferences> _loadPreferences() =>
      _preferences ??= _preferencesLoader();

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    final revision = _selectionRevision;
    var manual = false;
    try {
      final preferences = await _loadPreferences();
      if (_disposed || revision != _selectionRevision) return;
      final saved = preferences.getString('home_city_selection')?.trim();
      _city = saved == null || saved.isEmpty ? null : saved;
      manual = preferences.getBool('home_city_manual') ?? false;
      _notify();
    } catch (_) {
      // A storage failure must not prevent browsing or selecting a city.
    }
    if (!_disposed && revision == _selectionRevision && !manual) {
      await locate();
    }
  }

  Future<void> locate() async {
    if (_disposed || _isLocating) return;
    final revision = ++_selectionRevision;
    _isLocating = true;
    _locationError = null;
    _notify();
    try {
      final city = (await _locationService.locateCity()).trim();
      if (_disposed || revision != _selectionRevision) return;
      if (city.isEmpty) {
        throw const CityLocationException('暂时无法识别所在城市，请手动选择。');
      }
      _city = city;
      _isLocating = false;
      final saved = _save(city, manual: false);
      await saved;
    } on CityLocationException catch (error) {
      if (_disposed || revision != _selectionRevision) return;
      _isLocating = false;
      _locationError = error;
      _notify();
    } catch (_) {
      if (_disposed || revision != _selectionRevision) return;
      _isLocating = false;
      _locationError = const CityLocationException('定位暂时不可用，请重试或手动选择城市。');
      _notify();
    }
  }

  Future<void> selectManually(String? city) async {
    if (_disposed) return;
    ++_selectionRevision;
    final value = city?.trim();
    _city = value == null || value.isEmpty ? null : value;
    _isLocating = false;
    _locationError = null;
    await _save(_city, manual: true);
  }

  Future<bool> openLocationSettings() async {
    final error = _locationError;
    if (error == null ||
        (!error.canOpenAppSettings && !error.canOpenLocationSettings)) {
      return false;
    }
    try {
      return await _locationService.openSettings(
        appSettings: error.canOpenAppSettings,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _save(String? city, {required bool manual}) {
    final revision = _selectionRevision;
    // Serialize writes so a slower earlier choice cannot win after a restart.
    return _pendingWrite = _pendingWrite.then((_) async {
      try {
        final preferences = await _loadPreferences();
        final savedCity = preferences.setString(
          'home_city_selection',
          city ?? '',
        );
        final savedRevision = preferences.setInt(
          'home_city_selection_revision',
          (preferences.getInt('home_city_selection_revision') ?? 0) + 1,
        );
        // SharedPreferences updates its cache synchronously. Notify after
        // that update so immediately opening a gym picker sees this city.
        if (revision == _selectionRevision) _notify();
        await Future.wait([savedCity, savedRevision]);
        await preferences.setBool('home_city_manual', manual);
      } catch (_) {
        // The selection remains usable for this session without local storage.
        if (revision == _selectionRevision) _notify();
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_selectionRevision;
    super.dispose();
  }
}
