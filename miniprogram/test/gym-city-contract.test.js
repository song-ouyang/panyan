const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeCity,
  selectedCity,
  brandPageUrl,
  brandStoresPath,
  directoryAreaLabel,
  groupStoresByCity
} = require('../utils/gym-directory');

function loadPage(modulePath, request) {
  const apiPath = require.resolve('../utils/api');
  const pagePath = require.resolve(modulePath);
  const api = require(apiPath);
  api.request = request;

  let definition;
  global.Page = value => { definition = value; };
  delete require.cache[pagePath];
  require(pagePath);
  return definition;
}

function createPage(definition, data = {}) {
  return {
    ...definition,
    data: { ...definition.data, ...data },
    setData(patch) { Object.assign(this.data, patch); }
  };
}

test('main gym path carries the selected city into the brand page', () => {
  const city = selectedCity(['全部城市', '深圳', '成都'], 1);

  assert.equal(city, '深圳');
  assert.equal(
    brandPageUrl('brand/id', city),
    '/pages/brand/index?id=brand%2Fid&city=%E6%B7%B1%E5%9C%B3'
  );
});

test('brand stores request scopes stores to the city', () => {
  assert.equal(
    brandStoresPath('brand/id', '成都 高新区'),
    '/gyms/brands/brand%2Fid/stores?city=%E6%88%90%E9%83%BD%20%E9%AB%98%E6%96%B0%E5%8C%BA'
  );
  assert.equal(normalizeCity('%E6%B7%B1%E5%9C%B3'), '深圳');
});

test('missing or all-cities selection preserves the existing global behavior', () => {
  assert.equal(selectedCity(['全部城市', '深圳'], 0), '');
  assert.equal(selectedCity(['全部城市'], 9), '');
  assert.equal(brandPageUrl('brand-id', '全部城市'), '/pages/brand/index?id=brand-id');
  assert.equal(brandStoresPath('brand-id'), '/gyms/brands/brand-id/stores');
});

test('nationwide directory labels brands once and describes their city coverage', () => {
  assert.equal(directoryAreaLabel({ city: null, cities: ['上海', '深圳', '深圳'] }), '2 个城市');
  assert.equal(directoryAreaLabel({ city: '成都', cities: ['成都'] }), '成都');
  assert.equal(directoryAreaLabel({ city: null, cities: [] }), '全国');
});

test('global brand stores retain server order while grouping stores by city', () => {
  const stores = [
    { id: 'sh-1', city: '上海', name: '上海店' },
    { id: 'sz-1', city: '深圳', name: '南山店' },
    { id: 'sz-2', city: '深圳', name: '宝安店' }
  ];

  assert.deepEqual(groupStoresByCity(stores), [
    { city: '上海', stores: [stores[0]] },
    { city: '深圳', stores: [stores[1], stores[2]] }
  ]);
});

test('gym and brand pages wire the selected city through navigation and loading', async () => {
  const apiPath = require.resolve('../utils/api');
  const originalRequest = require(apiPath).request;
  const originalPage = global.Page;
  const originalWx = global.wx;
  let navigatedTo = '';
  const requestedPaths = [];

  try {
    global.wx = {
      navigateTo({ url }) { navigatedTo = url; },
      redirectTo() {}
    };

    const gymsDefinition = loadPage('../pages/gyms/index', async () => ({}));
    const gymsPage = createPage(gymsDefinition, {
      cities: ['全部城市', '深圳'],
      cityIndex: 1
    });
    gymsPage.open({ currentTarget: { dataset: { id: 'brand-id' } } });
    assert.equal(
      navigatedTo,
      '/pages/brand/index?id=brand-id&city=%E6%B7%B1%E5%9C%B3'
    );

    const brandDefinition = loadPage('../pages/brand/index', async path => {
      requestedPaths.push(path);
      return { id: 'brand-id', name: '测试品牌', stores: [] };
    });
    const brandPage = createPage(brandDefinition);
    brandPage.onLoad({ id: 'brand-id', city: '%E6%B7%B1%E5%9C%B3' });
    await new Promise(resolve => setImmediate(resolve));

    assert.deepEqual(requestedPaths, [
      '/gyms/brands/brand-id/stores?city=%E6%B7%B1%E5%9C%B3'
    ]);
  } finally {
    require(apiPath).request = originalRequest;
    delete require.cache[require.resolve('../pages/gyms/index')];
    delete require.cache[require.resolve('../pages/brand/index')];
    global.Page = originalPage;
    global.wx = originalWx;
  }
});
