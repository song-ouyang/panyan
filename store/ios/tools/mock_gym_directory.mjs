const OFFICIAL_BANANA_SOURCE = '香蕉攀岩公开门店服务（climbing-go）';

const canonicalBrands = [
  [/(?:banana\+|香蕉(?:攀岩|抱石))/iu, '香蕉攀岩'],
  [/bloc\s*1/iu, 'BLOC1 Climbing'],
  [/丘山攀岩/u, '丘山攀岩'],
  [/tnt\s*攀岩/iu, 'TNT攀岩'],
  [/dome\s*攀岩/iu, 'DOME攀岩'],
];

const bananaVenueAliases = new Map([
  ['深圳:深圳湾后海汇', '后海汇'],
]);

function optionalFilter(value) {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}

function compactVenueIdentity(value) {
  return value
    .normalize('NFKC')
    .toLocaleLowerCase('zh-CN')
    .replace(/[^\p{L}\p{N}]/gu, '');
}

function searchable(value) {
  return String(value ?? '')
    .normalize('NFKC')
    .toLocaleLowerCase('zh-CN');
}

function compareText(left, right) {
  return String(left ?? '').localeCompare(String(right ?? ''), 'zh-CN', {
    sensitivity: 'base',
  });
}

/**
 * Mirrors server/src/db/seed_support.ts without importing server build output
 * into the standalone App Store screenshot server.
 */
export function deriveBrandName(storeName, explicit) {
  const normalized = (explicit ?? storeName).replace(/\s+/gu, ' ').trim();
  if (!normalized) return storeName.trim();
  if (explicit) return normalized;

  for (const [pattern, brand] of canonicalBrands) {
    if (pattern.test(normalized)) return brand;
  }

  const withoutParenthesizedStore = normalized.replace(
    /\s*[（(][^（）()]+(?:店|校区|馆)[）)]\s*$/u,
    '',
  );
  const middleDot = withoutParenthesizedStore.match(/^(.+?)[·・](.+)$/u);
  if (middleDot?.[1] && /(?:店|校区|馆)$/u.test(middleDot[2] ?? '')) {
    return middleDot[1].trim();
  }
  return withoutParenthesizedStore || normalized;
}

/**
 * Returns the reviewed cross-source venue identity used by the real seed.
 * Explicit canonicalVenueId values always win, for every brand.
 */
export function deriveCanonicalVenueId(
  item,
  resolvedBrandName = deriveBrandName(item.name, item.brandName),
) {
  const explicit = item.canonicalVenueId?.trim();
  if (explicit) return explicit;
  if (resolvedBrandName !== '香蕉攀岩') return undefined;

  let venue = compactVenueIdentity(item.name);
  for (const brandToken of ['banana', '香蕉攀岩', '香蕉抱石']) {
    venue = venue.split(brandToken).join('');
  }
  venue = venue
    .replace(/(?:攀岩馆|抱石馆|攀岩|抱石|店|馆)$/u, '')
    .replace(/(?:购物中心|商都)$/u, '');

  const city = compactVenueIdentity(item.city).replace(/市$/u, '');
  venue = bananaVenueAliases.get(`${city}:${venue}`) ?? venue;
  if (venue.length < 2) return undefined;
  return `directory:banana:${city}:${venue}`;
}

function sourcePriority(sourceName) {
  if (sourceName === OFFICIAL_BANANA_SOURCE) return 100;
  if (sourceName === '高德地图') return 80;
  if (sourceName === '攀岩么公开岩馆接口') return 60;
  return sourceName ? 40 : 0;
}

function exactIdentityPart(value) {
  return String(value ?? '').trim().toLocaleLowerCase('zh-CN');
}

function recordIdentities(item, brandName) {
  const identities = [];
  const canonicalVenueId = deriveCanonicalVenueId(item, brandName);
  if (canonicalVenueId) identities.push(`canonical:${canonicalVenueId}`);

  const externalId = item.source?.external_id?.trim();
  if (externalId) {
    identities.push(`source:${item.source?.name ?? ''}:${externalId}`);
  }

  identities.push(
    [
      'exact',
      exactIdentityPart(item.name),
      exactIdentityPart(item.city),
      exactIdentityPart(item.address),
    ].join(':'),
  );
  return identities;
}

/**
 * Applies the same identities as the seed before the mock creates brands.
 * The winning row supplies display data; higher-quality public sources win.
 */
export function dedupeGymRecords(rawGyms) {
  const candidates = rawGyms.map((item, rawIndex) => {
    const brandName = deriveBrandName(item.name, item.brandName);
    const canonicalVenueId = deriveCanonicalVenueId(item, brandName);
    return { item, rawIndex, brandName, canonicalVenueId };
  });
  const parents = candidates.map((_, index) => index);
  const identityOwners = new Map();

  function find(index) {
    let root = index;
    while (parents[root] !== root) root = parents[root];
    while (parents[index] !== index) {
      const parent = parents[index];
      parents[index] = root;
      index = parent;
    }
    return root;
  }

  function union(left, right) {
    const leftRoot = find(left);
    const rightRoot = find(right);
    if (leftRoot === rightRoot) return;
    if (leftRoot < rightRoot) parents[rightRoot] = leftRoot;
    else parents[leftRoot] = rightRoot;
  }

  candidates.forEach((candidate, index) => {
    for (const identity of recordIdentities(candidate.item, candidate.brandName)) {
      const owner = identityOwners.get(identity);
      if (owner === undefined) identityOwners.set(identity, index);
      else union(index, owner);
    }
  });

  const groups = new Map();
  candidates.forEach((candidate, index) => {
    const root = find(index);
    const group = groups.get(root);

    if (!group) {
      groups.set(root, { winner: candidate, members: [candidate] });
      return;
    }

    group.members.push(candidate);
    if (
      sourcePriority(candidate.item.source?.name) >
      sourcePriority(group.winner.item.source?.name)
    ) {
      group.winner = candidate;
    }
  });

  return {
    records: [...groups.values()].map(({ winner, members }) => ({
      ...winner,
      canonicalVenueId:
        winner.canonicalVenueId ??
        members.find((candidate) => candidate.canonicalVenueId)?.canonicalVenueId,
      aliases: members.map(({ item }) => item),
    })),
    aliasesMerged: rawGyms.length - groups.size,
  };
}

function storeMatchesQuery(store, brandName, query) {
  if (!query) return true;
  const needle = searchable(query);
  return [brandName, store.name, store.address, store.district].some((value) =>
    searchable(value).includes(needle),
  );
}

function storeSort(left, right) {
  return (
    compareText(left.city, right.city) ||
    compareText(left.district, right.district) ||
    compareText(left.name, right.name)
  );
}

function toStore(record, brandId) {
  const item = record.item;
  return {
    id: `public-gym-${record.rawIndex + 1}`,
    name: item.name,
    province: item.province,
    city: item.city,
    district: item.district,
    brand_id: brandId,
    address: item.address,
    latitude: item.latitude,
    longitude: item.longitude,
    cover_url: null,
    description: item.description,
    verified: item.verified === true,
    canonical_venue_id: record.canonicalVenueId ?? null,
    source_name: item.source?.name ?? null,
    source_url: item.source?.url ?? null,
    source_external_id: item.source?.external_id ?? null,
    route_count: 0,
  };
}

/**
 * Builds a deterministic, in-memory version of the real gym API contract.
 * All returned values are derived from the supplied public directory only.
 */
export function createGymCatalog(publicGymDirectory, { publicBaseUrl = '' } = {}) {
  const rawGyms = Array.isArray(publicGymDirectory)
    ? publicGymDirectory
    : publicGymDirectory?.gyms;
  if (!Array.isArray(rawGyms)) {
    throw new TypeError('Expected a gym array or { gyms: [...] } directory');
  }

  const { records, aliasesMerged } = dedupeGymRecords(rawGyms);
  const brandsByName = new Map();

  for (const record of records) {
    let brand = brandsByName.get(record.brandName);
    if (!brand) {
      const brandNumber = brandsByName.size + 1;
      const logoName = brandNumber % 2
        ? 'mascot-celebrate.jpg'
        : 'mascot-welcome.jpg';
      brand = {
        id: `public-brand-${brandNumber}`,
        name: record.brandName,
        logo_url: publicBaseUrl ? `${publicBaseUrl}/media/${logoName}` : null,
        description: '公开资料初步核验，等待场馆认领。',
        stores: [],
      };
      brandsByName.set(record.brandName, brand);
    }
    brand.stores.push(toStore(record, brand.id));
  }

  const brands = [...brandsByName.values()];
  for (const brand of brands) brand.stores.sort(storeSort);
  brands.sort((left, right) => compareText(left.name, right.name));

  const stores = brands.flatMap((brand) =>
    brand.stores.map((store) => ({ ...store, brand_name: brand.name })),
  );
  const brandsById = new Map(brands.map((brand) => [brand.id, brand]));
  const storesById = new Map(stores.map((store) => [store.id, store]));

  function getDirectory({ city, q } = {}) {
    const cityFilter = optionalFilter(city);
    const query = optionalFilter(q);
    const matchingBrandIds = new Set();

    for (const brand of brands) {
      if (
        brand.stores.some(
          (store) =>
            (!cityFilter || store.city === cityFilter) &&
            storeMatchesQuery(store, brand.name, query),
        )
      ) {
        matchingBrandIds.add(brand.id);
      }
    }

    return {
      items: brands
        .filter((brand) => matchingBrandIds.has(brand.id))
        .map((brand) => {
          const scopedStores = cityFilter
            ? brand.stores.filter((store) => store.city === cityFilter)
            : brand.stores;
          const cities = [...new Set(scopedStores.map((store) => store.city))].sort(
            compareText,
          );
          return {
            city: cityFilter ? cities[0] ?? null : null,
            cities,
            brand_id: brand.id,
            brand_name: brand.name,
            logo_url: brand.logo_url,
            store_count: scopedStores.length,
            route_count: scopedStores.reduce(
              (total, store) => total + store.route_count,
              0,
            ),
            verified: scopedStores.some((store) => store.verified),
          };
        }),
    };
  }

  function getBrandDetail(brandId, { city } = {}) {
    const brand = brandsById.get(brandId);
    if (!brand) return null;
    const cityFilter = optionalFilter(city);
    return {
      id: brand.id,
      name: brand.name,
      logo_url: brand.logo_url,
      description: brand.description,
      stores: brand.stores
        .filter((store) => !cityFilter || store.city === cityFilter)
        .map((store) => ({ ...store })),
    };
  }

  function getGyms({ city, q } = {}) {
    const cityFilter = optionalFilter(city);
    const query = optionalFilter(q);
    return {
      items: stores
        .filter(
          (store) =>
            (!cityFilter || store.city === cityFilter) &&
            storeMatchesQuery(store, store.brand_name, query),
        )
        .sort(
          (left, right) =>
            Number(right.verified) - Number(left.verified) ||
            compareText(left.brand_name, right.brand_name) ||
            compareText(left.name, right.name),
        )
        .map((store) => ({ ...store })),
    };
  }

  function getGymDetail(gymId) {
    const store = storesById.get(gymId);
    return store ? { ...store, routeSets: [] } : null;
  }

  return {
    aliasesMerged,
    brands,
    stores,
    getDirectory,
    getBrandDetail,
    getGyms,
    getGymDetail,
  };
}
