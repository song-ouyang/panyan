import '../json/json_helpers.dart';
import 'feed_models.dart';

class GymDirectoryItem {
  const GymDirectoryItem({
    required this.city,
    required this.brandId,
    required this.brandName,
    required this.storeCount,
    required this.routeCount,
    required this.verified,
    this.logoUrl,
  });

  factory GymDirectoryItem.fromJson(JsonMap json) => GymDirectoryItem(
    city: jsonString(json['city'], field: 'city'),
    brandId: jsonString(json['brand_id'], field: 'brand_id'),
    brandName: jsonString(json['brand_name'], field: 'brand_name'),
    logoUrl: jsonNullableString(json['logo_url']),
    storeCount: jsonInt(json['store_count']),
    routeCount: jsonInt(json['route_count']),
    verified: jsonBool(json['verified']),
  );

  final String city;
  final String brandId;
  final String brandName;
  final String? logoUrl;
  final int storeCount;
  final int routeCount;
  final bool verified;
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
  final String address;
  final double? latitude;
  final double? longitude;
  final String? coverUrl;
  final String? description;
  final bool verified;
  final int routeCount;
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
