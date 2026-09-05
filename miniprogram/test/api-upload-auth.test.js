const test = require('node:test');
const assert = require('node:assert/strict');

const token = user => `header.${Buffer.from(JSON.stringify({ sub: user, role: 'user' })).toString('base64url')}.signature`;

function setup(responder) {
  const previousWx = global.wx;
  const apiPath = require.resolve('../utils/api');
  const storage = new Map([['token', token('user-one')]]);
  const calls = [];
  global.wx = {
    getStorageSync: key => storage.get(key),
    setStorageSync: (key, value) => storage.set(key, value),
    removeStorageSync: key => storage.delete(key),
    login: ({ success }) => success({ code: 'wechat-code' }),
    base64ToArrayBuffer: encoded => {
      const bytes = Buffer.from(encoded, 'base64');
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    },
    request(options) { calls.push(options); responder(options, storage); }
  };
  delete require.cache[apiPath];
  return {
    api: require(apiPath), calls, storage,
    cleanup() { global.wx = previousWx; delete require.cache[apiPath]; }
  };
}

test('upload request stops before sending when the selected account changed', async () => {
  const context = setup(() => { throw new Error('must not send'); });
  try {
    context.storage.set('token', token('user-two'));
    await assert.rejects(context.api.request('/uploads/multipart/init', { expectedUserId: 'user-one' }), { code: 'UPLOAD_IDENTITY_CHANGED' });
    assert.equal(context.calls.length, 0);
  } finally { context.cleanup(); }
});

test('401 login refresh cannot continue the prior account upload as a different account', async () => {
  const context = setup(({ url, success }) => {
    if (url.endsWith('/auth/wechat')) return success({ statusCode: 200, data: { token: token('user-two') } });
    success({ statusCode: 401, data: { message: 'expired' } });
  });
  try {
    await assert.rejects(context.api.request('/uploads/multipart/complete', { method: 'POST', expectedUserId: 'user-one' }), { code: 'UPLOAD_IDENTITY_CHANGED' });
    assert.equal(context.calls.filter(call => call.url.endsWith('/complete')).length, 1);
  } finally { context.cleanup(); }
});

test('same-account token refresh continues uploading normally', async () => {
  let protectedCalls = 0;
  const context = setup(({ url, success }) => {
    if (url.endsWith('/auth/wechat')) return success({ statusCode: 200, data: { token: token('user-one') } });
    protectedCalls += 1;
    success(protectedCalls === 1 ? { statusCode: 401, data: {} } : { statusCode: 200, data: { url: 'https://oss/video.mp4' } });
  });
  try {
    const result = await context.api.request('/uploads/multipart/complete', { method: 'POST', expectedUserId: 'user-one' });
    assert.equal(result.url, 'https://oss/video.mp4');
    assert.equal(protectedCalls, 2);
  } finally { context.cleanup(); }
});

test('account changes while an API request is in flight stop result reuse', async () => {
  const context = setup(({ success }, storage) => {
    storage.set('token', token('user-two'));
    success({ statusCode: 200, data: { url: 'https://oss/video.mp4' } });
  });
  try {
    await assert.rejects(context.api.request('/uploads/multipart/complete', { expectedUserId: 'user-one' }), { code: 'UPLOAD_IDENTITY_CHANGED' });
  } finally { context.cleanup(); }
});

test('API errors preserve status, explicit upload expiry code, and Retry-After for the resumable uploader', async () => {
  const context = setup(({ success }) => success({ statusCode: 404, header: { 'Retry-After': '3' }, data: { message: 'missing', code: 'UPLOAD_NOT_FOUND' } }));
  try {
    await assert.rejects(context.api.request('/uploads/multipart/status'), { statusCode: 404, code: 'UPLOAD_NOT_FOUND', retryAfterMs: 3000 });
  } finally { context.cleanup(); }
});

function checkinPage(api, uploadVideo) {
  const originalUpload = api.uploadVideo;
  const originalPage = global.Page;
  const pagePath = require.resolve('../pages/checkin/index');
  let definition;
  try {
    api.uploadVideo = uploadVideo;
    global.Page = value => { definition = value; };
    delete require.cache[pagePath];
    require(pagePath);
  } finally {
    api.uploadVideo = originalUpload;
    global.Page = originalPage;
    delete require.cache[pagePath];
  }
  const page = {
    ...definition,
    data: { ...definition.data, videoPath: '/original.mp4', videoSize: 80 },
    setData(patch, done) { Object.assign(this.data, patch); if (done) done(); },
    async transitionPhase(phase, extra = {}) { this.setData({ phase, ...extra }); },
    beginResultMotion() {}
  };
  global.wx.showToast = () => {};
  page.onLoad({ routeId: 'route-one' });
  return page;
}

test('check-in save retry cannot publish the previous account video after switching accounts', async () => {
  let uploads = 0;
  const context = setup(({ success }) => success({ statusCode: 503, data: { message: 'save unavailable' } }));
  try {
    const page = checkinPage(context.api, async () => {
      uploads += 1;
      return { url: 'https://oss/user-one/video.mp4', ownerId: 'user-one' };
    });
    await page.submit();
    assert.equal(page.cachedVideoOwnerId, 'user-one');
    assert.equal(page.data.saveFailed, true);
    assert.equal(context.calls.filter(call => call.url.endsWith('/sends')).length, 1);
    context.storage.set('token', token('user-two'));
    await page.submit();
    assert.equal(uploads, 1);
    assert.match(page.data.submitError, /登录账号已变化/);
    assert.equal(context.calls.filter(call => call.url.endsWith('/sends')).length, 1);

    global.wx.chooseMedia = ({ success }) => success({ tempFiles: [{ tempFilePath: '/next.mp4', size: 20 }] });
    page.chooseVideo();
    assert.equal(page.cachedVideoUrl, '');
    assert.equal(page.cachedVideoOwnerId, '');
  } finally { context.cleanup(); }
});

test('check-in account switch during the saving transition is rejected before publication', async () => {
  const context = setup(() => { throw new Error('must not publish'); });
  try {
    const page = checkinPage(context.api, async () => ({ url: 'https://oss/user-one/video.mp4', ownerId: 'user-one' }));
    page.transitionPhase = async function (phase, extra = {}) {
      this.setData({ phase, ...extra });
      if (phase === 'saving') context.storage.set('token', token('user-two'));
    };
    await page.submit();
    assert.equal(context.calls.length, 0);
    assert.match(page.data.submitError, /登录账号已变化/);
  } finally { context.cleanup(); }
});
