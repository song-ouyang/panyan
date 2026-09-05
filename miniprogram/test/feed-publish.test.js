const test = require('node:test');
const assert = require('node:assert/strict');

const api = require('../utils/api');
const cache = require('../utils/page-cache');

async function publish(status, { camelCase = false, images = [] } = {}) {
  const requests = [];
  const timers = [];
  api.request = async (path, options) => {
    requests.push({ path, options });
    return {
      id: 'new-moment',
      ...(status == null ? {} : { [camelCase ? 'moderationStatus' : 'moderation_status']: status })
    };
  };
  api.upload = async (path, progress) => {
    progress(100);
    return { url: `https://cdn.example.com/${path}` };
  };
  let definition;
  global.Page = value => { definition = value; };
  global.wx = { vibrateShort() {} };
  delete require.cache[require.resolve('../pages/feed/index')];
  require('../pages/feed/index');
  const refreshes = [];
  const page = {
    ...definition,
    data: { ...definition.data, draft: '今天的新进步', draftImages: images },
    setData(patch) { Object.assign(this.data, patch); },
    dismissComposer() {},
    load(options) { refreshes.push(options); }
  };
  cache.write('feed:public', { items: [{ id: 'old' }] });
  const originalTimeout = global.setTimeout;
  const originalClear = global.clearTimeout;
  global.setTimeout = callback => { timers.push(callback); return timers.length; };
  global.clearTimeout = () => {};
  try {
    await page.publish();
    while (timers.length) timers.shift()();
  } finally {
    global.setTimeout = originalTimeout;
    global.clearTimeout = originalClear;
    delete global.Page;
    delete global.wx;
  }
  return { page, requests, refreshes, cached: cache.read('feed:public') };
}

test('approved文字动态直接发表并跳过广场旧缓存刷新', async () => {
  const result = await publish('approved');
  assert.equal(result.page.data.publishStage, '已发表');
  assert.equal(result.page.data.publishResult, 'approved');
  assert.equal(result.page.pendingNewItemId, 'new-moment');
  assert.equal(result.cached, null);
  assert.deepEqual(result.refreshes, [{ force: true, background: true }]);
});

test('图片动态上传完再发表，兼容camelCase状态', async () => {
  const result = await publish('approved', {
    camelCase: true, images: [{ tempFilePath: 'one.jpg' }, { tempFilePath: 'two.jpg' }]
  });
  assert.deepEqual(result.requests[0].options.data.imageUrls, [
    'https://cdn.example.com/one.jpg', 'https://cdn.example.com/two.jpg'
  ]);
  assert.equal(result.page.data.publishStage, '已发表');
  assert.equal(result.refreshes.length, 1);
});

for (const [status, resultValue, label] of [
  ['pending', 'pending', '已提交审核'],
  ['rejected', 'rejected', '未通过'],
  [null, 'submitted', '已提交']
]) {
  test(`${status}响应不误报为已发表，也不将内容插入广场`, async () => {
    const result = await publish(status);
    assert.equal(result.page.data.publishResult, resultValue);
    assert.equal(result.page.data.publishStage, label);
    assert.equal(result.page.pendingNewItemId, '');
    assert.equal(result.refreshes.length, 0);
    assert.notEqual(result.cached, null);
  });
}
