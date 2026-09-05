const { request } = require('./api');
const { invalidatePrefix } = require('./page-cache');

let revision = 0;

function currentUserId() {
  try {
    const token = wx.getStorageSync('token');
    const encoded = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const bytes = new Uint8Array(wx.base64ToArrayBuffer(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, '=')));
    const payload = JSON.parse(Array.from(bytes, byte => String.fromCharCode(byte)).join(''));
    return typeof payload.sub === 'string' ? payload.sub : '';
  } catch (_) { return ''; }
}

async function identity() {
  let userId = currentUserId();
  if (!userId) {
    const me = await request('/users/me');
    userId = me && me.id;
    if (!userId || userId !== currentUserId()) throw new Error('登录账号已变化，请重新打开页面');
  }
  return userId;
}

function isCurrent(userId) { return Boolean(userId) && userId === currentUserId(); }
function currentRevision() { return revision; }

function changed() {
  revision += 1;
  invalidatePrefix('feed:');
  invalidatePrefix('ranking:users:');
  invalidatePrefix('ranking:routes');
}

async function setInteraction(id, kind, selected, userId) {
  if (!['like', 'favorite'].includes(kind) || !isCurrent(userId)) {
    throw new Error('登录账号已变化，请重新打开页面');
  }
  try {
    const result = await request(`/sends/${encodeURIComponent(id)}/${kind}`, {
      method: selected ? 'POST' : 'DELETE', expectedUserId: userId
    });
    const field = kind === 'like' ? 'liked' : 'favorited';
    if (!result || result[field] !== selected) throw new Error('操作没有保存，请重试');
    if (!isCurrent(userId)) throw new Error('登录账号已变化，请重新打开页面');
    changed();
    return selected;
  } catch (error) {
    if (error.code === 'UPLOAD_IDENTITY_CHANGED') throw new Error('登录账号已变化，请重新打开页面');
    throw error;
  }
}

module.exports = { currentUserId, identity, isCurrent, currentRevision, changed, setInteraction };
