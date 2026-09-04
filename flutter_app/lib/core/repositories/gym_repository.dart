import '../json/json_helpers.dart';
import '../models/feed_models.dart';
import '../models/gym_models.dart';
import '../network/api_client.dart';

class GymRepository {
  const GymRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<GymDirectoryItem>> getDirectory({
    String? city,
    String? query,
  }) async {
    final json = await _apiClient.getJson(
      '/gyms/directory',
      queryParameters: _withoutNulls({'city': city, 'q': query}),
    );
    return jsonModelList(json['items'], GymDirectoryItem.fromJson);
  }

  Future<List<Gym>> getGyms({String? city, String? query}) async {
    final json = await _apiClient.getJson(
      '/gyms',
      queryParameters: _withoutNulls({'city': city, 'q': query}),
    );
    return jsonModelList(json['items'], Gym.fromJson);
  }

  Future<GymBrandDetail> getBrandStores(String brandId, {String? city}) async =>
      GymBrandDetail.fromJson(
        await _apiClient.getJson(
          '/gyms/brands/$brandId/stores',
          queryParameters: _withoutNulls({'city': city}),
        ),
      );

  Future<GymDetail> getGym(String gymId) async =>
      GymDetail.fromJson(await _apiClient.getJson('/gyms/$gymId'));

  Future<List<ClimbingRoute>> getRoutes(
    String gymId, {
    String? grade,
    String? routeSetId,
  }) async {
    final json = await _apiClient.getJson(
      '/gyms/$gymId/routes',
      queryParameters: _withoutNulls({'grade': grade, 'setId': routeSetId}),
    );
    return jsonModelList(json['items'], ClimbingRoute.fromJson);
  }

  Future<ClimbingRoute> getRoute(String routeId) async =>
      ClimbingRoute.fromJson(await _apiClient.getJson('/routes/$routeId'));

  Future<RouteLeaderboard> getRouteLeaderboard(String routeId) async =>
      RouteLeaderboard.fromJson(
        await _apiClient.getJson('/routes/$routeId/leaderboard'),
      );

  Map<String, dynamic> _withoutNulls(Map<String, dynamic> source) =>
      Map<String, dynamic>.fromEntries(
        source.entries.where(
          (entry) => entry.value != null && entry.value.toString().isNotEmpty,
        ),
      );
}
