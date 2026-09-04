import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  createGymCatalog,
  deriveBrandName,
  deriveCanonicalVenueId,
} from './mock_gym_directory.mjs';

const publicGymDirectory = JSON.parse(
  readFileSync(new URL('../../../data/gyms.public-verified.json', import.meta.url), 'utf8'),
);
const catalog = createGymCatalog(publicGymDirectory, {
  publicBaseUrl: 'http://127.0.0.1:3001',
});

function bananaSummary(options) {
  const summaries = catalog
    .getDirectory(options)
    .items.filter((item) => item.brand_name === '香蕉攀岩');
  assert.equal(summaries.length, 1, 'Banana must be represented by one brand');
  return summaries[0];
}

test('aggregates nationwide Banana aliases into 34 physical stores', () => {
  const rawBanana = publicGymDirectory.gyms.filter(
    (gym) => deriveBrandName(gym.name, gym.brandName) === '香蕉攀岩',
  );
  assert.equal(rawBanana.length, 57);

  const banana = bananaSummary();
  assert.equal(banana.store_count, 34);

  const detail = catalog.getBrandDetail(banana.brand_id);
  assert.equal(detail.stores.length, 34);
  assert.equal(rawBanana.length - detail.stores.length, 23);
});

test('returns four deduplicated Chengdu Banana stores with official labels', () => {
  const banana = bananaSummary({ city: '成都' });
  assert.equal(banana.city, '成都');
  assert.deepEqual(banana.cities, ['成都']);
  assert.equal(banana.store_count, 4);

  const detail = catalog.getBrandDetail(banana.brand_id, { city: '成都' });
  assert.deepEqual(
    detail.stores.map((store) => store.name).sort(),
    [
      'BANANA+ COSMO店',
      '香蕉攀岩 凯德天府店',
      '香蕉攀岩 悠方店',
      '香蕉攀岩 环贸ICD店',
    ].sort(),
  );
  assert.equal(detail.stores.filter((store) => /凯德天府/iu.test(store.name)).length, 1);
  assert.equal(detail.stores.filter((store) => /环贸ICD/iu.test(store.name)).length, 1);
  assert.equal(detail.stores.filter((store) => /COSMO/iu.test(store.name)).length, 1);
});

test('uses official climbing-go display data for every overlapping Banana venue', () => {
  const officialGyms = publicGymDirectory.gyms.filter(
    (gym) => gym.source?.name === '香蕉攀岩公开门店服务（climbing-go）',
  );
  const banana = bananaSummary();
  const detail = catalog.getBrandDetail(banana.brand_id);

  for (const official of officialGyms) {
    const store = detail.stores.find(
      (candidate) => candidate.city === official.city && candidate.name === official.name,
    );
    assert.ok(store, `missing official venue: ${official.city} ${official.name}`);
    assert.equal(store.address, official.address);
    assert.equal(store.source_name, official.source.name);
  }
});

test('matches real directory city/q aggregation semantics', () => {
  const cityMatch = bananaSummary({ city: ' 成都 ', q: '凯德天府' });
  assert.equal(cityMatch.store_count, 4, 'q selects the brand, city scopes its count');

  const nationwideMatch = bananaSummary({ q: '凯德天府' });
  assert.equal(nationwideMatch.store_count, 34);

  assert.equal(catalog.getDirectory({ city: '成都', q: '不存在的门店' }).items.length, 0);
  assert.equal(bananaSummary({ city: '成都', q: '   ' }).store_count, 4);
});

test('normalizes the reviewed Shenzhen Banana alias', () => {
  const official = {
    name: '香蕉攀岩 后海汇店',
    city: '深圳',
  };
  const alias = {
    name: '香蕉攀岩(深圳湾后海汇店)',
    city: '深圳',
  };
  assert.equal(deriveCanonicalVenueId(official), deriveCanonicalVenueId(alias));
});

test('merges an explicit canonicalVenueId regardless of source identity', () => {
  const synthetic = createGymCatalog({
    gyms: [
      {
        name: '测试攀岩馆（旧称店）',
        brandName: '测试攀岩',
        canonicalVenueId: 'cn:test:shared-venue',
        province: '测试省',
        city: '测试市',
        district: '旧区',
        address: '旧地址',
        description: '旧来源',
        source: { name: '攀岩么公开岩馆接口', url: 'https://example.com/old', external_id: 'old' },
      },
      {
        name: '测试攀岩馆新名称',
        brandName: '测试攀岩',
        canonicalVenueId: 'cn:test:shared-venue',
        province: '测试省',
        city: '测试市',
        district: '新区',
        address: '新地址',
        description: '高优先级来源',
        source: { name: '高德地图', url: 'https://example.com/new', external_id: 'new' },
      },
    ],
  });

  const summary = synthetic.getDirectory().items[0];
  assert.equal(summary.store_count, 1);
  const [store] = synthetic.getBrandDetail(summary.brand_id).stores;
  assert.equal(store.name, '测试攀岩馆新名称');
  assert.equal(store.canonical_venue_id, 'cn:test:shared-venue');
});
