import '../json/json_helpers.dart';
import 'feed_models.dart';

class GymDirectoryItem {
  const GymDirectoryItem({
    required this.brandId,
    required this.brandName,
    required this.storeCount,
    required this.routeCount,
    required this.verified,
    this.city,
    this.cities = const [],
    this.logoUrl,
  });

  factory GymDirectoryItem.fromJson(JsonMap json) {
    final city = jsonNullableString(json['city']);
    final parsedCities = jsonStringList(json['cities']);
    return GymDirectoryItem(
      city: city,
      cities: parsedCities.isEmpty && city != null ? [city] : parsedCities,
      brandId: jsonString(json['brand_id'], field: 'brand_id'),
      brandName: jsonString(json['brand_name'], field: 'brand_name'),
      logoUrl: jsonNullableString(json['logo_url']),
      storeCount: jsonInt(json['store_count']),
      routeCount: jsonInt(json['route_count']),
      verified: jsonBool(json['verified']),
    );
  }

  final String? city;
  final List<String> cities;
  final String brandId;
  final String brandName;
  final String? logoUrl;
  final int storeCount;
  final int routeCount;
  final bool verified;

  List<String> get availableCities => cities.isNotEmpty
      ? cities
      : city == null
      ? const []
      : [city!];

  bool hasCity(String value) => availableCities.contains(value);

  String get areaLabel {
    if (city != null) return city!;
    if (availableCities.length == 1) return availableCities.single;
    if (availableCities.isNotEmpty) return '${availableCities.length} 个城市';
    return '全国';
  }
}

class Gym {
  const Gym({
    required this.id,
    required this.name,
    required this.city,
    required this.province,
    required this.address,
    required this.verified,
    this.district,
    this.brandId,
    this.brandName,
    this.latitude,
    this.longitude,
    this.coverUrl,
    this.description,
    this.routeCount = 0,
  });

  factory Gym.fromJson(JsonMap json) => Gym(
    id: jsonString(json['id'], field: 'id'),
    name: jsonString(json['name'], field: 'name'),
    city: jsonString(json['city'], field: 'city'),
    province: jsonNullableString(json['province']) ?? '',
    district: jsonNullableString(json['district']),
    brandId: jsonNullableString(json['brand_id']),
    brandName: jsonNullableString(json['brand_name']),
    address: jsonString(json['address'], field: 'address'),
    latitude: jsonNullableDouble(json['latitude']),
    longitude: jsonNullableDouble(json['longitude']),
    coverUrl: jsonNullableString(json['cover_url']),
    description: jsonNullableString(json['description']),
    verified: jsonBool(json['verified']),
    routeCount: jsonInt(json['route_count']),
  );

  final String id;
  final String name;
  final String city;
  final String province;
  final String? district;
  final String? brandId;
  final String? brandName;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? coverUrl;
  final String? description;
  final bool verified;
  final int routeCount;

  /// Directory imports use this value as a workflow placeholder, not a real
  /// district. Keep the source data intact while hiding it from customer UI.
  String? get displayDistrict {
    final value = district?.trim();
    if (value == null || value.isEmpty || value == '待核验') return null;
    return value;
  }

  String get locationLabel => <String>[
    city.trim(),
    ?displayDistrict,
    address.trim(),
  ].where((part) => part.isNotEmpty).join(' · ');
}

class RouteSet {
  const RouteSet({
    required this.id,
    required this.gymId,
    required this.name,
    required this.startsOn,
    required this.active,
    this.endsOn,
  });

  factory RouteSet.fromJson(JsonMap json) => RouteSet(
    id: jsonString(json['id'], field: 'id'),
    gymId: jsonString(json['gym_id'], field: 'gym_id'),
    name: jsonString(json['name'], field: 'name'),
    startsOn: jsonDateTime(json['starts_on']),
    endsOn: jsonDateTime(json['ends_on']),
    active: jsonBool(json['active']),
  );

  final String id;
  final String gymId;
  final String name;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final bool active;
}

class GymDetail {
  const GymDetail({required this.gym, required this.routeSets});

  factory GymDetail.fromJson(JsonMap json) => GymDetail(
    gym: Gym.fromJson(json),
    routeSets: jsonModelList(json['routeSets'], RouteSet.fromJson),
  );

  final Gym gym;
  final List<RouteSet> routeSets;
}

class GymBrandDetail {
  const GymBrandDetail({
    required this.id,
    required this.name,
    required this.stores,
    this.logoUrl,
    this.description,
  });

  factory GymBrandDetail.fromJson(JsonMap json) => GymBrandDetail(
    id: jsonString(json['id'], field: 'id'),
    name: jsonString(json['name'], field: 'name'),
    logoUrl:
        jsonNullableString(json['logo_url']) ??
        jsonNullableString(json['cover_url']),
    description: jsonNullableString(json['description']),
    stores: jsonModelList(json['stores'], Gym.fromJson),
  );

  final String id;
  final String name;
  final String? logoUrl;
  final String? description;
  final List<Gym> stores;

  Map<String, List<Gym>> get storesByCity {
    final grouped = <String, List<Gym>>{};
    for (final store in stores) {
      grouped.putIfAbsent(store.city, () => <Gym>[]).add(store);
    }
    return Map<String, List<Gym>>.unmodifiable(
      grouped.map<String, List<Gym>>(
        (city, cityStores) =>
            MapEntry(city, List<Gym>.unmodifiable(cityStores)),
      ),
    );
  }
}

class ClimbingRoute {
  const ClimbingRoute({
    required this.id,
    required this.gymId,
    required this.name,
    required this.grade,
    required this.color,
    required this.published,
    this.routeSetId,
    this.wallZone,
    this.coverUrl,
    this.setterName,
    this.points = const [],
    this.sendCount = 0,
    this.gymName,
    this.gymAddress,
    this.routeSetName,
    this.featuredSend,
  });

  factory ClimbingRoute.fromJson(JsonMap json) {
    final featured = json['featuredSend'] ?? json['featured_send'];
    return ClimbingRoute(
      id: jsonString(json['id'], field: 'id'),
      gymId: jsonString(json['gym_id'], field: 'gym_id'),
      routeSetId: jsonNullableString(json['route_set_id']),
      name: jsonString(json['name'], field: 'name'),
      grade: jsonString(json['grade'], field: 'grade'),
      color: jsonString(json['color'], field: 'color'),
      wallZone: jsonNullableString(json['wall_zone']),
      coverUrl: jsonNullableString(json['cover_url']),
      setterName: jsonNullableString(json['setter_name']),
      points: jsonList(json['points']),
      published: jsonBool(json['published'], fallback: true),
      sendCount: jsonInt(json['send_count']),
      gymName: jsonNullableString(json['gym_name']),
      gymAddress: jsonNullableString(json['gym_address']),
      routeSetName: jsonNullableString(json['route_set_name']),
      featuredSend: featured == null
          ? null
          : FeedPost.fromJson(jsonMap(featured)),
    );
  }

  final String id;
  final String gymId;
  final String? routeSetId;
  final String name;
  final String grade;
  final String color;
  final String? wallZone;
  final String? coverUrl;
  final String? setterName;
  final List<dynamic> points;
  final bool published;
  final int sendCount;
  final String? gymName;
  final String? gymAddress;
  final String? routeSetName;
  final FeedPost? featuredSend;
}
