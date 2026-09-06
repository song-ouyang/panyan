const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const token = user => `header.${Buffer.from(JSON.stringify({ sub: user })).toString('base64url')}.signature`;
const snapshot = (revision = 1) => ({ revision, currentLevel: 2, levelName: '渐入佳境', climbingDays: 3, uniqueRoutes: 8, nextLevel: { level: 3, name: '岩馆常客', days: 7, routes: 25 }, remainingDays: 4, remainingRoutes: 17 });
const presentation = revision => ({ id: 'award', fromLevel: 0, toLevel: 2, newBadgeCount: 2, badgeKeys: ['account-level-01', 'account-level-02'], levelName: '渐入佳境', growthRevision: revision });

function harness(responder = async () => ({})) {
  const previousWx = global.wx;
  const previousPage = global.Page;
  const storage = new Map([['token', token('one')]]);
  const requests = [];
  const navigations = [];
  const audio = [];
  global.wx = {
    getStorageSync: key => storage.get(key),
    setStorageSync: (key, value) => storage.set(key, JSON.parse(JSON.stringify(value))),
    removeStorageSync: key => storage.delete(key),
    base64ToArrayBuffer: encoded => { const b = Buffer.from(encoded, 'base64'); return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength); },
    getSystemInfoSync: () => ({ reduceMotionEnabled: true }),
    navigateTo: options => { navigations.push(options.url); if (options.success) options.success(); },
    showToast() {}, vibrateShort() {},
    createInnerAudioContext() { const item = { destroyCount: 0, played: false, destroy() { this.destroyCount += 1; }, play() { this.played = true; }, onEnded(fn) { this.ended = fn; }, onError(fn) { this.error = fn; } }; audio.push(item); return item; }
  };
  for (const item of ['api', 'social-state', 'growth', 'motion', 'sound']) delete require.cache[require.resolve(`../utils/${item}`)];
  const api = require('../utils/api');
  api.request = async (endpoint, options = {}) => { requests.push({ endpoint, options: JSON.parse(JSON.stringify(options)) }); return responder(endpoint, options); };
  const growth = require('../utils/growth');
  return { api, growth, storage, requests, navigations, audio, cleanup() { global.wx = previousWx; global.Page = previousPage; } };
}

test('guests see no fabricated level and never consume an account reward', async () => {
  const h = harness();
  try { h.storage.delete('token'); assert.equal(await h.growth.load(), null); assert.equal(await h.growth.badges(), null); assert.equal(await h.growth.consume(), null); assert.equal(h.requests.length, 0); }
  finally { h.cleanup(); }
});

test('growth revisions never regress and stale badge statuses cannot overwrite a newer snapshot', async () => {
  const h = harness(async endpoint => endpoint.endsWith('/badges') ? { growth: snapshot(8), badges: [] } : snapshot(8));
  try {
    h.growth.accept(h.growth.session(), snapshot(10));
    assert.equal((await h.growth.load()).revision, 10);
    assert.equal(await h.growth.badges(), null);
    const progress = h.growth.progress(snapshot());
    assert.equal(progress.daysPercent, 3 / 7 * 100);
    assert.equal(progress.routesPercent, 32);
    assert.equal(h.growth.progress({ ...snapshot(), nextLevel: null }).routesPercent, 100);
  } finally { h.cleanup(); }
});

test('account switch discards late growth and consumed presentation responses', async () => {
  let resolve;
  const h = harness(() => new Promise(done => { resolve = done; }));
  try {
    const pending = h.growth.load(); h.storage.set('token', token('two')); resolve(snapshot(2)); assert.equal(await pending, null);
    const award = h.growth.consume(); h.storage.set('token', token('three')); resolve({ growth: snapshot(3), shouldPresent: true, presentation: presentation(3) });
    assert.equal(await award, null); assert.equal(h.growth.presentation(), null);
  } finally { h.cleanup(); }
});

test('one pending consume per session, stale revision never celebrates', async () => {
  let resolve;
  const h = harness(() => new Promise(done => { resolve = done; }));
  try {
    const pending = h.growth.consume(); assert.equal(await h.growth.consume(), null); assert.equal(h.requests.length, 1);
    h.growth.accept(h.growth.session(), snapshot(4));
    resolve({ growth: snapshot(3), shouldPresent: true, presentation: presentation(3) });
    assert.equal(await pending, null); assert.equal(h.growth.presentation(), null);
  } finally { h.cleanup(); }
});

test('highest badge presentation navigates once', async () => {
  const h = harness(async () => ({ growth: snapshot(5), shouldPresent: true, presentation: presentation(5) }));
  try { assert.equal(await h.growth.presentPending(), true); assert.deepEqual(h.navigations, ['/growth/pages/earned/index']); assert.equal(h.growth.presentation().newBadgeCount, 2); }
  finally { h.cleanup(); }
});

test('hiding before consume response suppresses automatic navigation', async () => {
  let resolve;
  let visible = true;
  const h = harness(() => new Promise(done => { resolve = done; }));
  try {
    const pending = h.growth.presentPending(() => visible);
    visible = false;
    resolve({ growth: snapshot(5), shouldPresent: true, presentation: presentation(5) });
    assert.equal(await pending, false); assert.equal(h.navigations.length, 0);
  } finally { h.cleanup(); }
});

function pageDefinition(relativePath) {
  let definition;
  global.Page = value => { definition = value; };
  delete require.cache[require.resolve(relativePath)];
  require(relativePath);
  return { ...definition, data: { ...definition.data }, setData(patch, done) { Object.assign(this.data, patch); if (done) done(); } };
}

test('profile only loads a compact level; historical celebration starts after entering badge details', async () => {
  const h = harness(async endpoint => {
    if (endpoint.endsWith('/growth-level')) return snapshot(7);
    if (endpoint.endsWith('/badges')) return { growth: snapshot(7), badges: [{ level: 2, badgeKey: 'account-level-02', name: '渐入佳境', status: 'earned' }] };
    return { shouldPresent: true, growth: snapshot(7), presentation: presentation(7) };
  });
  try {
    const profile = pageDefinition('../pages/profile/index');
    profile._visible = true;
    await profile.loadAccountGrowth();
    assert.equal(profile.data.accountGrowth.currentLevel, 2);
    assert.equal(profile.data.accountRingColor, '#66BADD');
    assert.deepEqual(h.requests.map(item => item.endpoint), ['/users/me/growth-level']);
    assert.equal(h.navigations.length, 0);
    profile.badges();
    assert.deepEqual(h.navigations, ['/growth/pages/badges/index']);
    const collection = pageDefinition('../growth/pages/badges/index');
    collection.onLoad(); collection._visible = true; await collection.load();
    assert.deepEqual(h.requests.map(item => item.endpoint), ['/users/me/growth-level', '/users/me/badges', '/users/me/growth-presentations/consume']);
    assert.equal(h.navigations[1], '/growth/pages/earned/index');
    const markup = fs.readFileSync(path.resolve(__dirname, '../pages/profile/index.wxml'), 'utf8');
    assert.equal(markup.includes('account-level-entry'), false);
    assert.equal(/<account-badge[\s>]/.test(markup), false);
    assert.equal((markup.match(/catchtap="badges"/g) || []).length, 2);
    assert.ok(markup.includes('me.avatar_url'));
  } finally { h.cleanup(); }
});

test('account switch resets the compact level ring and prevents details from consuming the previous account history', async () => {
  let resolve;
  const h = harness(() => new Promise(done => { resolve = done; }));
  try {
    const profile = pageDefinition('../pages/profile/index');
    profile._visible = true;
    const loading = profile.loadAccountGrowth();
    h.storage.set('token', token('two')); resolve(snapshot(8)); await loading;
    assert.equal(profile.data.accountGrowth, null); assert.equal(profile.data.accountRingColor, '#E9DCC7');
    const collection = pageDefinition('../growth/pages/badges/index');
    collection.onLoad(); collection._visible = true;
    const details = collection.load();
    h.storage.set('token', token('three')); resolve({ growth: snapshot(9), badges: [] }); await details;
    assert.equal(collection.data.growth, null); assert.equal(collection.data.guest, true);
    assert.equal(h.requests.some(item => item.endpoint.endsWith('/consume')), false);
    assert.equal(h.navigations.length, 0);
  } finally { h.cleanup(); }
});

test('earned detail replays locally with reduced motion; revoked badge cannot replay', async () => {
  let revoked = false;
  const h = harness(async () => ({ growth: snapshot(6), badges: [{ level: 2, badgeKey: 'account-level-02', name: '渐入佳境', status: revoked ? 'revoked' : 'earned' }] }));
  try {
    let definition;
    global.Page = value => { definition = value; };
    delete require.cache[require.resolve('../growth/pages/earned/index')];
    require('../growth/pages/earned/index');
    const page = { ...definition, data: { ...definition.data }, setData(patch, done) { Object.assign(this.data, patch); if (done) done(); } };
    page.onLoad({ replayLevel: '2' }); page._visible = true; await page.load();
    assert.equal(page.data.reduced, true); assert.equal(page.data.badge.status, 'earned');
    page.replay(); await new Promise(resolve => setTimeout(resolve, 5));
    assert.equal(page.data.animate, false); assert.equal(h.requests.length, 1); assert.equal(h.requests[0].endpoint, '/users/me/badges');
    revoked = true; await page.load(); assert.equal(page.data.badge, null); assert.match(page.data.error, /成长记录已更新/);
    page.onUnload();
  } finally { h.cleanup(); }
});

test('persisted completion draft reuses UUID and frozen body across restarts; explicit new record gets a new UUID', () => {
  const h = harness();
  try {
    const drafts = require('../utils/completion-draft');
    const original = drafts.open('one', 'checkin', 'route');
    const stored = drafts.save(original, { body: { routeId: 'route', attempts: 2, clientRequestId: original.clientRequestId } });
    const restored = drafts.open('one', 'checkin', 'route');
    assert.deepEqual(restored, stored);
    assert.notEqual(drafts.open('two', 'checkin', 'route').clientRequestId, original.clientRequestId);
    drafts.clear(restored);
    assert.notEqual(drafts.open('one', 'checkin', 'route').clientRequestId, original.clientRequestId);
  } finally { h.cleanup(); }
});

function checkin(h) {
  h.api.uploadVideo = async () => ({ url: 'https://cdn.example/video.mp4', ownerId: 'one' });
  let definition;
  global.Page = value => { definition = value; };
  delete require.cache[require.resolve('../pages/checkin/index')];
  require('../pages/checkin/index');
  const page = { ...definition, data: { ...definition.data, videoPath: '/local.mp4', attempts: 2 }, setData(patch, done) { Object.assign(this.data, patch); if (done) done(); }, async transitionPhase(phase, extra = {}) { this.setData({ phase, ...extra }); }, beginResultMotion() {} };
  page.onLoad({ routeId: 'route' });
  return page;
}

test('check-in response loss retry keeps exact body and UUID; saved success consumes highest badge', async () => {
  let saves = 0;
  const h = harness(async endpoint => {
    if (endpoint === '/sends') { if (++saves === 1) throw new Error('connection lost'); return { sendId: 'saved', moderationStatus: 'approved', growth: snapshot(2) }; }
    return { shouldPresent: true, growth: snapshot(2), presentation: presentation(2) };
  });
  try {
    const page = checkin(h); await page.submit();
    assert.equal(page.data.saveFailed, true);
    const restarted = checkin(h);
    assert.equal(restarted.data.draftLocked, true);
    restarted.attempts({ detail: { value: '99' } });
    await restarted.submit();
    const sent = h.requests.filter(item => item.endpoint === '/sends');
    assert.equal(sent.length, 2); assert.deepEqual(sent[0].options.data, sent[1].options.data);
    assert.equal(sent[1].options.data.operation, 'record'); assert.equal(sent[1].options.data.attempts, 2);
    assert.equal(restarted.data.phase, 'approvedSuccess'); assert.equal(restarted.data.badgePresented, true);
    assert.equal(h.navigations.length, 1);
  } finally { h.cleanup(); }
});

test('unavailable celebration endpoint cannot turn a successful check-in into save failure', async () => {
  const h = harness(async endpoint => { if (endpoint === '/sends') return { sendId: 'saved', moderationStatus: 'approved' }; throw new Error('offline'); });
  try { const page = checkin(h); await page.submit(); assert.equal(page.data.phase, 'approvedSuccess'); assert.equal(page.data.saveFailed, false); assert.equal(page.data.submitting, false); assert.equal(page.data.badgePresented, false); }
  finally { h.cleanup(); }
});

test('badge sound defaults off, uses selected C at matched gain, and old callbacks cannot destroy new playback', () => {
  const h = harness();
  try {
    const sound = require('../utils/sound');
    sound.playFeedback('badge'); assert.equal(h.audio.length, 0);
    sound.setBadgeSoundEnabled(true); sound.playFeedback('badge');
    assert.equal(h.audio[0].src, '/growth/assets/badge-earned.mp3'); assert.equal(h.audio[0].volume, 0.41085); assert.equal(h.audio[0].obeyMuteSwitch, true);
    sound.playFeedback('badge'); h.audio[0].ended(); assert.equal(h.audio[1].destroyCount, 0);
    sound.setBadgeSoundEnabled(false); sound.stopFeedback(); assert.equal(h.audio[1].destroyCount, 1);
    assert.equal(sound.badgeSoundEnabled(), false);
  } finally { h.cleanup(); }
});

test('approved atlas retains ten original crops, rendered by one shared component in the growth subpackage', () => {
  const base = path.resolve(__dirname, '..');
  const app = JSON.parse(fs.readFileSync(path.join(base, 'app.json')));
  assert.ok(app.subPackages.find(item => item.root === 'growth'));
  const atlas = require('../growth/assets/account-levels');
  const source = JSON.parse(fs.readFileSync(path.join(base, 'growth/assets/account-levels.json')));
  assert.deepEqual(atlas, source); assert.equal(atlas.badges.length, 10);
  for (const rect of atlas.badges) { assert.equal(rect.width, 300); assert.equal(rect.height, 300); assert.ok(rect.x + rect.width <= atlas.width); assert.ok(rect.y + rect.height <= atlas.height); }
  assert.ok(fs.existsSync(path.join(base, atlas.image)));
});
