function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, character => {
    const value = Math.floor(Math.random() * 16);
    return (character === 'x' ? value : (value & 3) | 8).toString(16);
  });
}

function key(userId, kind, targetId) { return `completion-draft:v1:${userId}:${kind}:${targetId}`; }

function open(userId, kind, targetId) {
  if (!userId) throw new Error('请先登录后再记录');
  const storageKey = key(userId, kind, targetId);
  const stored = wx.getStorageSync(storageKey);
  if (stored && stored.userId === userId && stored.clientRequestId) return stored;
  const draft = { userId, kind, targetId, clientRequestId: uuid(), body: null };
  wx.setStorageSync(storageKey, draft);
  return draft;
}

function save(draft, patch) {
  const next = { ...draft, ...patch };
  wx.setStorageSync(key(draft.userId, draft.kind, draft.targetId), next);
  return next;
}

function clear(draft) {
  if (!draft) return;
  const storageKey = key(draft.userId, draft.kind, draft.targetId);
  const current = wx.getStorageSync(storageKey);
  if (current && current.clientRequestId === draft.clientRequestId) wx.removeStorageSync(storageKey);
}

module.exports = { open, save, clear, uuid };
