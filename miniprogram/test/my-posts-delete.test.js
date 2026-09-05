const test = require('node:test');
const assert = require('node:assert/strict');

const api = require('../utils/api');
const cache = require('../utils/page-cache');

const relatedKeys = [
  'feed:public',
  'profile:overview',
  'profile:dashboard:2026-09',
  'profile:dashboard:2026-08',
  'ranking:users:scope=national',
  'ranking:users:scope=city&city=深圳',
  'ranking:routes'
];
const unrelatedKeys = ['ranking:regions', 'gyms:directory'];

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function harness(t, { request = async () => ({ deleted: true }), status = 'approved' } = {}) {
  const originalRequest = api.request;
  const originalPage = global.Page;
  const originalWx = global.wx;
  const modulePath = require.resolve('../pages/my-posts/index');
  const requests = [];
  const modals = [];
  const toasts = [];
  let definition;
  api.request = (path, options) => {
    requests.push({ path, options });
    return request(path, options);
  };
  global.Page = value => { definition = value; };
  global.wx = {
    getStorageSync: () => `header.${Buffer.from(JSON.stringify({ sub: 'me' })).toString('base64url')}.signature`,
    base64ToArrayBuffer: encoded => {
      const bytes = Buffer.from(encoded, 'base64');
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    },
    showModal(options) { modals.push(options); },
    showToast(options) { toasts.push(options); },
    vibrateShort() {}
  };
  delete require.cache[modulePath];
  require(modulePath);
  const page = {
    ...definition,
    data: {
      ...definition.data,
      loading: false,
      items: [{ id: 'mine', moderation_status: status }, { id: 'keep' }]
    },
    setData(patch) { Object.assign(this.data, patch); }
  };
  page.onLoad();
  [...relatedKeys, ...unrelatedKeys].forEach(key => cache.write(key, { cached: true }));
  t.after(() => {
    api.request = originalRequest;
    global.Page = originalPage;
    global.wx = originalWx;
    delete require.cache[modulePath];
    [...relatedKeys, ...unrelatedKeys].forEach(key => cache.invalidate(key));
  });
  const tap = (id = 'mine') => page.remove({ currentTarget: { dataset: { id } } });
  const respond = (confirm = true) => {
    const modal = modals.at(-1);
    const result = modal.success({ confirm });
    modal.complete();
    return result;
  };
  return { page, tap, respond, requests, modals, toasts };
}

test('取消确认不会删除动态或清除缓存', async t => {
  const state = harness(t);
  state.tap();
  assert.equal(state.modals[0].title, '删除动态');
  assert.doesNotMatch(state.modals[0].content, /图片或视频.*删除|媒体文件.*删除/);
  await state.respond(false);
  assert.equal(state.requests.length, 0);
  assert.deepEqual(state.page.data.items.map(item => item.id), ['mine', 'keep']);
  assert.ok(cache.read('feed:public'));
  state.tap();
  assert.equal(state.modals.length, 2);
});

for (const status of ['approved', 'pending', 'rejected']) {
  test(`可删除自己的${status}动态并使动态、统计和榜单重新读取`, async t => {
    const state = harness(t, { status });
    state.tap();
    await state.respond();
    assert.deepEqual(state.requests, [{ path: '/sends/mine', options: { method: 'DELETE', expectedUserId: 'me' } }]);
    assert.deepEqual(state.page.data.items.map(item => item.id), ['keep']);
    assert.equal(state.page.data.deletingId, '');
    relatedKeys.forEach(key => assert.equal(cache.read(key), null, key));
    unrelatedKeys.forEach(key => assert.ok(cache.read(key), key));
    assert.equal(state.toasts.at(-1).title, '已删除');
  });
}

test('重复点击只打开一次确认且只发送一次删除请求', async t => {
  const save = deferred();
  const state = harness(t, { request: () => save.promise });
  state.tap();
  state.tap();
  assert.equal(state.modals.length, 1);
  const deleting = state.respond();
  state.tap();
  state.tap('keep');
  assert.equal(state.modals.length, 1);
  assert.equal(state.requests.length, 1);
  assert.equal(state.page.data.deletingId, 'mine');
  save.resolve({ deleted: true });
  await deleting;
});

test('删除失败保留动态和缓存，恢复按钮以便重试', async t => {
  const state = harness(t, { request: async () => { throw new Error('网络暂时不可用'); } });
  state.tap();
  await state.respond();
  assert.deepEqual(state.page.data.items.map(item => item.id), ['mine', 'keep']);
  assert.equal(state.page.data.deletingId, '');
  relatedKeys.forEach(key => assert.ok(cache.read(key), key));
  assert.deepEqual(state.toasts.at(-1), { title: '网络暂时不可用', icon: 'none' });
  state.tap();
  assert.equal(state.modals.length, 2);
});

test('删除接口只有明确deleted:true才能移除动态，异常成功回包允许重试', async t => {
  let response;
  const state = harness(t, { request: async () => response });
  for (response of [{ deleted: false }, {}, { deleted: 'true' }]) {
    state.tap();
    await state.respond();
    assert.deepEqual(state.page.data.items.map(item => item.id), ['mine', 'keep']);
    assert.equal(state.page.data.deletingId, '');
    relatedKeys.forEach(key => assert.ok(cache.read(key), key));
    assert.equal(state.toasts.at(-1).title, '动态未删除，请稍后重试');
  }
  assert.equal(state.requests.length, 3);
});

test('删除成功后，删除前发出的列表请求不能回填已删除记录', async t => {
  const loading = deferred();
  const state = harness(t, {
    request: (path, options) => options?.method === 'DELETE'
      ? Promise.resolve({ deleted: true })
      : loading.promise
  });
  const oldLoad = state.page.load();
  assert.equal(state.page.data.refreshing, true);
  state.tap();
  await state.respond();
  loading.resolve({ items: [{ id: 'mine' }, { id: 'keep' }] });
  await oldLoad;
  assert.deepEqual(state.page.data.items.map(item => item.id), ['keep']);
  assert.equal(state.page.data.refreshing, false);
  assert.equal(state.page.data.loading, false);
});

test('删除请求完成前离开页面，仍失效关联缓存但不更新已销毁页面', async t => {
  const save = deferred();
  const state = harness(t, { request: () => save.promise });
  state.tap();
  const deleting = state.respond();
  state.page.onUnload();
  state.page.setData = () => assert.fail('不得更新已销毁页面');
  save.resolve({ deleted: true });
  await deleting;
  relatedKeys.forEach(key => assert.equal(cache.read(key), null, key));
  assert.equal(state.toasts.length, 0);
});
