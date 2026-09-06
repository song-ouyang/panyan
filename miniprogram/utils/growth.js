const { request } = require('./api');
const social = require('./social-state');

let sessionToken = '';
let snapshot = null;
let pendingPresentation = null;
let consuming = null;

function session() {
  const token = wx.getStorageSync('token') || '';
  if (sessionToken !== token) {
    sessionToken = token;
    snapshot = null;
    pendingPresentation = null;
    consuming = null;
  }
  return { token, userId: social.currentUserId() };
}

function isCurrent(owner) {
  const current = session();
  return Boolean(owner && owner.userId && owner.token === current.token && owner.userId === current.userId);
}

function accept(owner, value) {
  if (!isCurrent(owner) || !value || !Number.isFinite(Number(value.revision))) return null;
  if (!snapshot || Number(value.revision) >= Number(snapshot.revision)) snapshot = value;
  return snapshot;
}

function progress(value) {
  if (!value) return null;
  const next = value.nextLevel;
  return {
    ...value,
    daysPercent: next ? Math.min(100, Math.max(0, value.climbingDays / next.days * 100)) : 100,
    routesPercent: next ? Math.min(100, Math.max(0, value.uniqueRoutes / next.routes * 100)) : 100,
  };
}

async function load() {
  const owner = session();
  if (!owner.userId) return null;
  return accept(owner, await request('/users/me/growth-level', { expectedUserId: owner.userId }));
}

async function badges() {
  const owner = session();
  if (!owner.userId) return null;
  const result = await request('/users/me/badges', { expectedUserId: owner.userId });
  if (!isCurrent(owner)) return null;
  const accepted = accept(owner, result.growth);
  if (!accepted || Number(result.growth.revision) < Number(accepted.revision)) return null;
  return { ...result, growth: progress(accepted) };
}

async function consume() {
  const owner = session();
  if (!owner.userId || consuming) return null;
  const marker = {};
  consuming = marker;
  try {
    const result = await request('/users/me/growth-presentations/consume', { method: 'POST', data: {}, expectedUserId: owner.userId });
    const latest = accept(owner, result.growth);
    const presentation = result.presentation;
    if (!latest || !result.shouldPresent || !presentation || Number(presentation.growthRevision) < Number(latest.revision)) return null;
    pendingPresentation = { owner, presentation };
    return presentation;
  } finally {
    if (consuming === marker) consuming = null;
  }
}

function presentation() {
  const item = pendingPresentation;
  if (!item || !isCurrent(item.owner)) return null;
  if (snapshot && Number(item.presentation.growthRevision) < Number(snapshot.revision)) return null;
  return item.presentation;
}

function clearPresentation() { pendingPresentation = null; }

async function presentPending(canPresent = () => true) {
  try {
    if (!canPresent()) return false;
    const item = await consume();
    if (!item || !canPresent() || !presentation()) return false;
    await new Promise((resolve, reject) => wx.navigateTo({ url: '/growth/pages/earned/index', success: resolve, fail: reject }));
    return true;
  } catch (_) {
    // A celebration failure cannot turn a saved completion into a failed save.
    return false;
  }
}

module.exports = { session, isCurrent, accept, progress, load, badges, consume, presentation, clearPresentation, presentPending };
