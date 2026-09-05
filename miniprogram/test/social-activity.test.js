const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const api = require('../utils/api');
const cache = require('../utils/page-cache');
const token = id => `header.${Buffer.from(JSON.stringify({ sub: id })).toString('base64url')}.signature`;
const event = id => ({ currentTarget: { dataset: { id } } });
const tick = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve; let reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
const post = (id = 'post-1', extra = {}) => ({ id, nickname: '岩友', caption: '今天的新进步', image_urls: [], liked: false, like_count: 0, favorited: false, sent_at: '2026-09-06T08:00:00.000Z', comments: [], ...extra });

function setup(t) {
  const original = { wx: global.wx, Page: global.Page, request: api.request };
  const pages = [];
  const calls = [];
  const toasts = [];
  const navigation = [];
  const state = { userId: 'me', saved: post(), respond: null };
  const response = (url, options = {}) => {
    if (url.startsWith('/sends/feed?')) return { items: [structuredClone(state.saved)] };
    if (url === '/sends/post-1') return structuredClone(state.saved);
    if (url.startsWith('/users/me/comments')) return { items: [{ id: 'comment-1', content: '自己的评论', moderation_status: 'approved', created_at: '2026-09-06T08:00:00Z', post: structuredClone(state.saved) }], nextCursor: null };
    if (url.startsWith('/users/me/favorites')) return { items: state.saved.favorited ? [structuredClone(state.saved)] : [], nextCursor: null };
    if (url.startsWith('/users/me/likes')) return { items: state.saved.liked ? [structuredClone(state.saved)] : [], nextCursor: null };
    if (url.endsWith('/favorite')) { state.saved.favorited = options.method === 'POST'; return { favorited: state.saved.favorited }; }
    if (url.endsWith('/like')) { state.saved.liked = options.method === 'POST'; state.saved.like_count = state.saved.liked ? 1 : 0; return { liked: state.saved.liked }; }
    throw new Error(`Unexpected request ${url}`);
  };
  state.respond = response;
  api.request = async (url, options = {}) => { calls.push({ url, options }); return state.respond(url, options); };
  global.wx = {
    getStorageSync: () => token(state.userId),
    base64ToArrayBuffer: encoded => { const bytes = Buffer.from(encoded, 'base64'); return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength); },
    showToast(value) { toasts.push(value); },
    navigateTo(value) { navigation.push(value); },
    setNavigationBarTitle() {}, stopPullDownRefresh() {}, vibrateShort() {}
  };
  const socialPath = require.resolve('../utils/social-state');
  delete require.cache[socialPath];
  const social = require(socialPath);
  const makePage = name => {
    let definition;
    global.Page = value => { definition = value; };
    const modulePath = require.resolve(`../pages/${name}/index`);
    delete require.cache[modulePath];
    require(modulePath);
    const page = {
      ...definition, data: structuredClone(definition.data),
      setData(patch, callback) {
        for (const [key, value] of Object.entries(patch)) {
          const keys = key.replace(/\[(\d+)\]/g, '.$1').split('.');
          let target = this.data;
          for (const part of keys.slice(0, -1)) target = target[part];
          target[keys.at(-1)] = value;
        }
        if (callback) callback();
      }
    };
    pages.push(page);
    return page;
  };
  t.after(() => {
    pages.forEach(page => page.onUnload && page.onUnload());
    cache.invalidatePrefix('feed:');
    api.request = original.request; global.wx = original.wx; global.Page = original.Page;
    delete require.cache[socialPath];
  });
  const feed = async () => { const page = makePage('feed'); page.onLoad(); await page.onShow(); return page; };
  const detail = async () => { const page = makePage('post'); await page.onLoad({ id: 'post-1' }); return page; };
  const activity = async type => { const page = makePage('activity'); page.onLoad({ type }); await page.onShow(); return page; };
  return { state, calls, toasts, navigation, social, makePage, feed, detail, activity, response };
}

test('我的四入口使用真实页面，并注册评论收藏点赞共用页', t => {
  const context = setup(t);
  const page = context.makePage('profile');
  page.posts();
  for (const type of ['comments', 'favorites', 'likes']) page.activity({ currentTarget: { dataset: { type } } });
  assert.deepEqual(context.navigation.map(item => item.url), ['/pages/my-posts/index', '/pages/activity/index?type=comments', '/pages/activity/index?type=favorites', '/pages/activity/index?type=likes']);
  const template = fs.readFileSync(path.join(__dirname, '../pages/profile/index.wxml'), 'utf8');
  for (const label of ['我的动态', '我的评论', '我的收藏', '我的点赞']) assert.ok(template.includes(label));
  assert.ok(require('../app.json').pages.includes('pages/activity/index'));
});

test('广场和朋友圈使用不同scope和当前账号请求，收藏不显示人数', async t => {
  const context = setup(t);
  const page = await context.feed();
  await page.changeScope({ currentTarget: { dataset: { scope: 'friends' } } });
  assert.deepEqual(context.calls.map(call => call.url), ['/sends/feed?scope=square', '/sends/feed?scope=friends']);
  assert.ok(context.calls.every(call => call.options.expectedUserId === 'me'));
  assert.equal(page.data.scope, 'friends');
  for (const name of ['feed', 'post', 'activity']) {
    const template = fs.readFileSync(path.join(__dirname, `../pages/${name}/index.wxml`), 'utf8');
    assert.doesNotMatch(template, /favorite_count|favorites_count/);
  }
});

for (const name of ['feed', 'detail']) {
  test(`${name}收藏等服务端确认才选中、重复点击只发送一次`, async t => {
    const context = setup(t);
    const page = await context[name]();
    const held = deferred();
    context.state.respond = (url, options) => url.endsWith('/favorite') ? held.promise : context.response(url, options);
    const saving = page.favorite(event('post-1'));
    await page.favorite(event('post-1'));
    const shown = name === 'feed' ? page.data.items[0] : page.data.post;
    assert.equal(shown.favorited, false);
    assert.equal(context.calls.filter(call => call.url.endsWith('/favorite')).length, 1);
    held.resolve({ favorited: true });
    await saving;
    assert.equal((name === 'feed' ? page.data.items[0] : page.data.post).favorited, true);
    assert.equal(context.social.currentRevision(), 1);
  });

  test(`${name}收藏失败或异常回包不假收藏，仍能重试`, async t => {
    const context = setup(t);
    const page = await context[name]();
    for (const result of [new Error('网络暂时不可用'), {}, { favorited: 'true' }, { favorited: false }]) {
      context.state.respond = async () => { if (result instanceof Error) throw result; return result; };
      await page.favorite(event('post-1'));
      assert.equal((name === 'feed' ? page.data.items[0] : page.data.post).favorited, false);
    }
    assert.equal(context.toasts.length, 4);
    assert.equal(context.social.currentRevision(), 0);
  });

  test(`${name}成功点赞和取消点赞改变状态及计数`, async t => {
    const context = setup(t);
    const page = await context[name]();
    await page.like(event('post-1'));
    let shown = name === 'feed' ? page.data.items[0] : page.data.post;
    assert.equal(shown.liked, true); assert.equal(shown.like_count, 1);
    await page.like(event('post-1'));
    shown = name === 'feed' ? page.data.items[0] : page.data.post;
    assert.equal(shown.liked, false); assert.equal(shown.like_count, 0);
  });

  test(`${name}收藏过程中切换账号不把旧收藏带到新账号`, async t => {
    const context = setup(t);
    const page = await context[name]();
    const held = deferred();
    context.state.respond = () => held.promise;
    const saving = page.favorite(event('post-1'));
    context.state.userId = 'another';
    held.resolve({ favorited: true }); await saving;
    assert.equal(name === 'feed' ? page.data.items.length : page.data.post, name === 'feed' ? 0 : null);
    assert.equal(context.social.currentRevision(), 0);
  });

  test(`${name}收藏成功后旧GET不能覆盖选中状态`, async t => {
    const context = setup(t);
    const page = await context[name]();
    const held = deferred();
    context.state.respond = (url, options) => url.endsWith('/favorite') ? context.response(url, options) : held.promise;
    const loading = page.load({ force: true }); await tick();
    await page.favorite(event('post-1'));
    held.resolve(name === 'feed' ? { items: [post()] } : post());
    await loading;
    assert.equal((name === 'feed' ? page.data.items[0] : page.data.post).favorited, true);
  });
}

test('我的评论读取comment id并用嵌套post id打开父动态', async t => {
  const context = setup(t);
  const page = await context.activity('comments');
  assert.equal(page.data.items[0].id, 'comment-1');
  assert.equal(page.data.items[0].content, '自己的评论');
  assert.equal(page.data.items[0].postId, 'post-1');
  page.open(event(page.data.items[0].postId));
  assert.equal(context.navigation[0].url, '/pages/post/index?id=post-1');
});

for (const type of ['favorites', 'likes']) {
  test(`从我的${type}取消后，返回广场和详情重读一致状态`, async t => {
    const context = setup(t);
    context.state.saved.favorited = true; context.state.saved.liked = true; context.state.saved.like_count = 1;
    const feed = await context.feed();
    const detail = await context.detail();
    const page = await context.activity(type);
    assert.equal(page.data.items.length, 1);
    await page.remove(event('post-1'));
    assert.equal(page.data.items.length, 0);
    await feed.onShow(); await detail.load();
    const field = type === 'favorites' ? 'favorited' : 'liked';
    assert.equal(feed.data.items[0][field], false);
    assert.equal(detail.data.post[field], false);
    assert.equal(cache.read('feed:me:square').value.items[0][field], false);
  });

  test(`${type}取消失败保留列表，旧列表GET不能回填已取消记录`, async t => {
    const context = setup(t);
    context.state.saved.favorited = true; context.state.saved.liked = true;
    const page = await context.activity(type);
    context.state.respond = () => ({});
    await page.remove(event('post-1'));
    assert.equal(page.data.items.length, 1);
    const held = deferred();
    context.state.respond = (url, options) => url.startsWith('/users/me/') ? held.promise : context.response(url, options);
    const loading = page.load(); await tick();
    await page.remove(event('post-1'));
    held.resolve({ items: [post('post-1', { liked: true, favorited: true })], nextCursor: null }); await loading;
    assert.equal(page.data.items.length, 0);
  });
}

test('活动列表按cursor加载更多，分页失败保留列表并允许重试', async t => {
  const context = setup(t);
  let moreFails = true;
  context.state.respond = url => {
    if (url.includes('cursor=')) {
      if (moreFails) throw new Error('请重试');
      return { items: [post('one'), post('two')], nextCursor: null };
    }
    return { items: [post('one')], nextCursor: 'opaque+/=?' };
  };
  const page = await context.activity('favorites');
  await page.loadMore();
  assert.deepEqual(page.data.items.map(item => item.id), ['one']);
  assert.equal(page.data.nextCursor, 'opaque+/=?');
  assert.ok(page.data.error);
  moreFails = false; await page.loadMore();
  assert.deepEqual(page.data.items.map(item => item.id), ['one', 'two']);
  assert.equal(page.data.nextCursor, null);
  assert.ok(context.calls.at(-1).url.endsWith('cursor=opaque%2B%2F%3D%3F'));
});

test('收藏日期取收藏时间，评论保留其审核状态与评论时间', async t => {
  const context = setup(t);
  context.state.respond = () => ({ items: [post('one', { created_at: '2025-01-01T08:00:00Z', activity_at: '2026-09-06T08:00:00Z' })], nextCursor: null });
  const favorites = await context.activity('favorites');
  assert.equal(favorites.data.items[0].dateText, '2026.09.06');
  context.state.respond = () => ({ items: [{ id: 'comment', created_at: '2026-09-05T08:00:00Z', moderation_status: 'pending', content: '我的待审评论', post: post() }], nextCursor: null });
  const comments = await context.activity('comments');
  assert.equal(comments.data.items[0].dateText, '2026.09.05');
  assert.equal(comments.data.items[0].moderation_status, 'pending');
});

test('旧账号活动列表晚回会被丢弃，当前账号重新加载', async t => {
  const context = setup(t);
  context.state.saved.favorited = true;
  const page = await context.activity('favorites');
  const held = deferred(); context.state.respond = () => held.promise;
  const loading = page.load(); await tick();
  context.state.userId = 'another';
  held.resolve({ items: [post('private-old')], nextCursor: null }); await loading;
  assert.deepEqual(page.data.items, []);
  context.state.respond = () => ({ items: [post('new-account')], nextCursor: null });
  await page.onShow();
  assert.equal(page.data.items[0].id, 'new-account');
  assert.equal(context.calls.at(-1).options.expectedUserId, 'another');
});

test('活动页拒绝任意type路径，收藏失败不会在我的收藏中出现', async t => {
  const context = setup(t);
  const page = await context.activity('../../admin');
  assert.equal(page.data.type, 'comments');
  assert.ok(context.calls.every(call => call.url.startsWith('/users/me/comments?')));
  const favorites = await context.activity('favorites');
  assert.deepEqual(favorites.data.items, []);
  assert.equal(favorites.data.loading, false);
});

test('收藏等待中切换广场scope不取消新scope加载', async t => {
  const context = setup(t);
  const page = await context.feed();
  const held = deferred();
  context.state.respond = (url, options) => url.endsWith('/favorite') ? held.promise : context.response(url, options);
  const saving = page.favorite(event('post-1'));
  await page.changeScope({ currentTarget: { dataset: { scope: 'friends' } } });
  context.state.saved.favorited = true; held.resolve({ favorited: true }); await saving;
  assert.equal(page.data.scope, 'friends');
  assert.equal(page.data.loading, false);
  assert.equal(page.data.items[0].favorited, true);
});
