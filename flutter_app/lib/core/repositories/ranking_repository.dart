import '../json/json_helpers.dart';
import '../models/ranking_models.dart';
import '../network/api_client.dart';

class RankingRepository {
  const RankingRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<RankingRegion>> getRegions() async {
    final json = await _apiClient.getJson('/rankings/regions');
    return jsonModelList(json['items'], RankingRegion.fromJson);
  }

  Future<List<RankedRoute>> getRankedRoutes({
    String? gymId,
    String? routeSetId,
  }) async {
    final json = await _apiClient.getJson(
      '/rankings/routes',
      queryParameters: _withoutNulls({'gymId': gymId, 'setId': routeSetId}),
    );
    return jsonModelList(json['items'], RankedRoute.fromJson);
  }

  Future<RankingBoard> getRanking({
    RankingScope scope = RankingScope.national,
    String? province,
    String? city,
    String? gymId,
    String? routeSetId,
  }) async => RankingBoard.fromJson(
    await _apiClient.getJson(
      '/rankings',
      queryParameters: _withoutNulls({
        'scope': scope.name,
        'province': province,
        'city': city,
        'gymId': gymId,
        'setId': routeSetId,
      }),
    ),
  );

  Map<String, dynamic> _withoutNulls(Map<String, dynamic> source) =>
      Map<String, dynamic>.fromEntries(
        source.entries.where((entry) => entry.value != null),
      );
}
