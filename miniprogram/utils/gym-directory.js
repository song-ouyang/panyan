const ALL_CITIES_LABEL = '全部城市';

function normalizeCity(city) {
  if (typeof city !== 'string') return '';

  let normalized = city;
  try {
    normalized = decodeURIComponent(city);
  } catch (_) {
    // Keep the original value when a malformed escape sequence comes from an
    // older page link. The request builder below will safely encode it again.
  }

  normalized = normalized.trim();
  return normalized && normalized !== ALL_CITIES_LABEL ? normalized : '';
}

function selectedCity(cities, cityIndex) {
  if (!Array.isArray(cities)) return '';
  return normalizeCity(cities[Number(cityIndex)]);
}

function brandPageUrl(brandId, city) {
  const params = [`id=${encodeURIComponent(brandId || '')}`];
  const normalizedCity = normalizeCity(city);
  if (normalizedCity) params.push(`city=${encodeURIComponent(normalizedCity)}`);
  return `/pages/brand/index?${params.join('&')}`;
}

function brandStoresPath(brandId, city) {
  const path = `/gyms/brands/${encodeURIComponent(brandId || '')}/stores`;
  const normalizedCity = normalizeCity(city);
  return normalizedCity ? `${path}?city=${encodeURIComponent(normalizedCity)}` : path;
}

function directoryAreaLabel(item) {
  const city = normalizeCity(item && item.city);
  if (city) return city;
  const cities = item && Array.isArray(item.cities)
    ? [...new Set(item.cities.map(normalizeCity).filter(Boolean))]
    : [];
  if (cities.length === 1) return cities[0];
  return cities.length ? `${cities.length} 个城市` : '全国';
}

function presentDirectoryItems(items) {
  if (!Array.isArray(items)) return [];
  return items.map(item => ({
    ...item,
    area_label: directoryAreaLabel(item)
  }));
}

function groupStoresByCity(stores) {
  const groups = [];
  const indexes = new Map();
  for (const store of Array.isArray(stores) ? stores : []) {
    const city = normalizeCity(store && store.city) || '其他城市';
    let index = indexes.get(city);
    if (index === undefined) {
      index = groups.length;
      indexes.set(city, index);
      groups.push({ city, stores: [] });
    }
    groups[index].stores.push(store);
  }
  return groups;
}

module.exports = {
  ALL_CITIES_LABEL,
  normalizeCity,
  selectedCity,
  brandPageUrl,
  brandStoresPath,
  directoryAreaLabel,
  presentDirectoryItems,
  groupStoresByCity
};
