const { request, upload } = require('../../utils/api');
const { read, write, loadOnce, invalidate } = require('../../utils/page-cache');
const { haptic } = require('../../utils/motion');
const social = require('../../utils/social-state');

// Exit is intentionally faster than the 240ms entrance so dismissing feels immediate.
const COMPOSER_ANIMATION_MS = 180;
const PUBLISH_SUCCESS_HOLD_MS = 320;
const PUBLISH_PENDING_HOLD_MS = 700;
const NEW_ITEM_ENTER_MS = 240;
const FEED_CACHE_KEY = 'feed:public';
const FEED_CACHE_TTL_MS = 30000;

Page({
  data: {
    items: [],
    scope: 'square',
    skeletonRows: [1, 2, 3],
    likePulseId: '',
    loading: true,
    refreshing: false,
    error: '',
    composerMounted: false,
    composerVisible: false,
    composerFocused: false,
    draft: '',
    draftImages: [],
    publishing: false,
    publishComplete: false,
    publishResult: '',
    publishStage: '',
    publishError: '',
    uploadProgress: 0,
    enteringItemId: ''
  },

  onLoad() {
    this.feedRequestSeq = 0;
    this._pendingInteractions = {};
  },

  onShow() {
    this._disposed = false;
    this.syncAccount(social.currentUserId());
    return this.load({ background: true });
  },

  onHide() {
    this.feedRequestSeq = (this.feedRequestSeq || 0) + 1;
    this.loadingPromise = null;
    clearTimeout(this.likePulseTimer);
  },

  onUnload() {
    this._disposed = true;
    this.feedRequestSeq = (this.feedRequestSeq || 0) + 1;
    this.loadingPromise = null;
    this._composerTransitionVersion = (this._composerTransitionVersion || 0) + 1;
    clearTimeout(this.composerEnterTimer);
    clearTimeout(this.composerExitTimer);
    clearTimeout(this.likePulseTimer);
    clearTimeout(this.publishSuccessTimer);
    clearTimeout(this.postPublishRefreshTimer);
    clearTimeout(this.newItemEnterTimer);
  },

  syncAccount(userId) {
    if (userId === this._userId) return;
    this._userId = userId;
    this._pendingInteractions = {};
    this.setData({ items: [], likePulseId: '', loading: true, refreshing: false, error: '' });
  },

  normalizeFeed(data) {
    return (data && Array.isArray(data.items) ? data.items : []).map(item => ({
      ...item,
      liked: item.liked === true,
      favorited: item.favorited === true,
      likePending: Boolean(this._pendingInteractions && this._pendingInteractions[`like:${item.id}`]),
      favoritePending: Boolean(this._pendingInteractions && this._pendingInteractions[`favorite:${item.id}`]),
      image_urls: Array.isArray(item.image_urls) ? item.image_urls : [],
      sent_at_text: this.relativeTime(item.sent_at)
    }));
  },

  applyFeed(data) {
    if (this._disposed) return;
    const items = this.normalizeFeed(data);
    const pendingNewItemId = this.pendingNewItemId;
    const enteringItemId = pendingNewItemId && items.some(item => item.id === pendingNewItemId)
      ? pendingNewItemId
      : '';
    // A just-published item gets at most one entrance, never a delayed replay.
    if (pendingNewItemId) this.pendingNewItemId = '';
    this.setData({
      items,
      enteringItemId,
      loading: false,
      refreshing: false,
      error: ''
    });
    if (enteringItemId) {
      clearTimeout(this.newItemEnterTimer);
      this.newItemEnterTimer = setTimeout(() => {
        if (!this._disposed && this.data.enteringItemId === enteringItemId) {
          this.setData({ enteringItemId: '' });
        }
      }, NEW_ITEM_ENTER_MS);
    }
  },

  async load(options = {}) {
    const { force = false, background = false } = options;
    const requestSeq = (this.feedRequestSeq || 0) + 1;
    this.feedRequestSeq = requestSeq;
    this.syncAccount(social.currentUserId());
    const scope = this.data.scope || 'square';
    let userId;
    try {
      userId = await social.identity();
      if (this._disposed || requestSeq !== this.feedRequestSeq) return;
      this.syncAccount(userId);
      const revision = social.currentRevision();
      const key = `feed:${userId}:${scope}`;
      if (force) invalidate(key);
      const cached = force ? null : read(key, FEED_CACHE_TTL_MS);
      if (cached) this.applyFeed(cached.value);
      if (cached && cached.fresh) return cached.value;
      const hasItems = this.data.items.length > 0;
      this.setData({ loading: !hasItems, refreshing: hasItems && !background, error: '' });
      const data = await loadOnce(key, () => request(`/sends/feed?scope=${scope}`, { expectedUserId: userId }));
      if (this._disposed || requestSeq !== this.feedRequestSeq || scope !== (this.data.scope || 'square')) return;
      if (!social.isCurrent(userId)) { this.syncAccount(social.currentUserId()); return; }
      if (revision !== social.currentRevision()) return this.load({ force: true, background: true });
      write(key, data);
      this.applyFeed(data);
      return data;
    } catch (error) {
      if (this._disposed || requestSeq !== this.feedRequestSeq) return;
      if (userId && !social.isCurrent(userId)) this.syncAccount(social.currentUserId());
      this.setData({ loading: false, refreshing: false, error: error.message || '动态加载失败，请稍后重试' });
    }
  },

  changeScope(e) {
    const scope = e.currentTarget.dataset.scope;
    if (!['square', 'friends'].includes(scope) || scope === this.data.scope) return;
    this.setData({ scope, items: [], loading: true, error: '' });
    return this.load();
  },

  retry() { this.load({ force: true }); },

  onPullDownRefresh() {
    return this.load({ force: true })
      .finally(() => wx.stopPullDownRefresh());
  },

  relativeTime(value) {
    const diff = Math.max(0, Date.now() - new Date(value).getTime());
    if (diff < 60000) return '刚刚';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}分钟前`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}小时前`;
    return `${Math.floor(diff / 86400000)}天前`;
  },

  like(e) { return this.interact(e, 'like'); },
  favorite(e) { return this.interact(e, 'favorite'); },

  async interact(e, kind) {
    const id = e.currentTarget.dataset.id;
    const item = this.data.items.find(candidate => candidate.id === id);
    const userId = this._userId;
    const scope = this.data.scope || 'square';
    if (!item || this._disposed) return;
    if (!social.isCurrent(userId)) { this.syncAccount(social.currentUserId()); return this.load(); }
    if (!this._pendingInteractions) this._pendingInteractions = {};
    const pending = this._pendingInteractions;
    const key = `${kind}:${id}`;
    if (pending[key]) return;
    pending[key] = true;
    const field = kind === 'like' ? 'liked' : 'favorited';
    const busy = kind === 'like' ? 'likePending' : 'favoritePending';
    const selected = !item[field];
    this.setData({ items: this.data.items.map(row => row.id === id ? { ...row, [busy]: true } : row) });
    try {
      await social.setInteraction(id, kind, selected, userId);
      if (this._disposed || !social.isCurrent(userId)) return;
      if (scope !== (this.data.scope || 'square')) return this.load({ force: true, background: true });
      this.feedRequestSeq = (this.feedRequestSeq || 0) + 1;
      this.setData({
        items: this.data.items.map(row => row.id === id ? {
          ...row, [field]: selected,
          ...(kind === 'like' ? { like_count: Math.max(0, (Number(row.like_count) || 0) + (selected ? 1 : -1)) } : {})
        } : row),
        loading: false, refreshing: false, likePulseId: kind === 'like' && selected ? id : ''
      });
      if (selected) haptic('selection');
      clearTimeout(this.likePulseTimer);
      this.likePulseTimer = setTimeout(() => { if (!this._disposed) this.setData({ likePulseId: '' }); }, 240);
    } catch (error) {
      if (!this._disposed && social.isCurrent(userId)) wx.showToast({ title: error.message || '操作失败，请重试', icon: 'none' });
    } finally {
      delete pending[key];
      if (!this._disposed) {
        if (!social.isCurrent(userId)) this.syncAccount(social.currentUserId());
        else this.setData({ items: this.data.items.map(row => row.id === id ? { ...row, [busy]: false } : row) });
      }
    }
  },

  openComposer() {
    if (this._disposed) return;
    clearTimeout(this.composerExitTimer);
    clearTimeout(this.composerEnterTimer);
    const wasMounted = this.data.composerMounted;
    const transitionVersion = (this._composerTransitionVersion || 0) + 1;
    this._composerTransitionVersion = transitionVersion;
    this.setData({
      composerMounted: true,
      publishComplete: false,
      publishResult: '',
      publishError: ''
    }, () => {
      if (this._disposed || transitionVersion !== this._composerTransitionVersion) return;
      if (wasMounted) {
        this.setData({ composerVisible: true, composerFocused: true });
        return;
      }
      this.composerEnterTimer = setTimeout(() => {
        if (this._disposed || transitionVersion !== this._composerTransitionVersion) return;
        this.setData({ composerVisible: true, composerFocused: true });
      }, 20);
    });
  },

  closeComposer() {
    if (this.data.publishing) {
      wx.showToast({ title: '照片正在上传，请稍候', icon: 'none' });
      return;
    }
    if (this.data.publishComplete) return;
    this.dismissComposer(false);
  },

  dismissComposer(clearDraft, force = false) {
    if (this.data.publishing && !force) return;
    clearTimeout(this.composerEnterTimer);
    clearTimeout(this.composerExitTimer);
    const transitionVersion = (this._composerTransitionVersion || 0) + 1;
    this._composerTransitionVersion = transitionVersion;
    this.setData({ composerVisible: false, composerFocused: false });
    this.composerExitTimer = setTimeout(() => {
      if (this._disposed || transitionVersion !== this._composerTransitionVersion || this.data.composerVisible) return;
      const next = { composerMounted: false };
      if (clearDraft) {
        Object.assign(next, {
          draft: '',
          draftImages: [],
          publishComplete: false,
          publishResult: '',
          publishStage: '',
          publishError: '',
          uploadProgress: 0
        });
      }
      this.setData(next);
    }, COMPOSER_ANIMATION_MS);
  },

  draftInput(e) {
    if (this.data.publishing || this.data.publishComplete) return;
    this.setData({ draft: e.detail.value, publishError: '' });
  },

  chooseImages() {
    if (this.data.publishing || this.data.publishComplete) return;
    wx.chooseMedia({
      count: 9 - this.data.draftImages.length,
      mediaType: ['image'],
      sourceType: ['album', 'camera'],
      success: ({ tempFiles }) => {
        if (this._disposed || this.data.publishing || this.data.publishComplete) return;
        this.setData({
          draftImages: this.data.draftImages.concat(tempFiles).slice(0, 9),
          publishError: ''
        });
      }
    });
  },

  removeImage(e) {
    if (this.data.publishing || this.data.publishComplete) return;
    const images = this.data.draftImages.slice();
    images.splice(Number(e.currentTarget.dataset.index), 1);
    this.setData({ draftImages: images, publishError: '' });
  },

  previewImage(e) {
    wx.previewImage({ current: e.currentTarget.dataset.current, urls: e.currentTarget.dataset.urls });
  },

  async publish() {
    if (this.data.publishing) return;
    const caption = this.data.draft.trim();
    const images = this.data.draftImages.slice();
    if (!caption && !images.length) {
      this.setData({ publishError: '写点内容，或选择一张照片' });
      return;
    }

    this.setData({
      publishing: true,
      publishComplete: false,
      publishResult: '',
      publishError: '',
      publishStage: images.length ? '正在上传照片' : '正在发表',
      uploadProgress: 0
    });

    try {
      const imageUrls = [];
      for (let index = 0; index < images.length; index += 1) {
        let fileProgress = 0;
        const result = await upload(images[index].tempFilePath, progress => {
          if (this._disposed) return;
          fileProgress = Math.max(fileProgress, Number(progress) || 0);
          const totalProgress = Math.round(((index + fileProgress / 100) / images.length) * 100);
          if (totalProgress !== this.data.uploadProgress) {
            this.setData({ uploadProgress: totalProgress });
          }
        });
        if (this._disposed) return;
        imageUrls.push(result.url);
        this.setData({ uploadProgress: Math.round(((index + 1) / images.length) * 100) });
      }

      this.setData({ publishStage: '正在发表' });
      const created = await request('/sends/moments', {
        method: 'POST',
        data: { caption, imageUrls, visibility: this.data.scope === 'friends' ? 'friends' : 'public' }
      });

      if (this._disposed) return;
      const moderationStatus = created && (created.moderationStatus || created.moderation_status);
      // The server owns visibility. Only explicitly published items enter the feed.
      const approved = moderationStatus === 'approved';
      const result = ['approved', 'pending', 'rejected'].includes(moderationStatus)
        ? moderationStatus
        : 'submitted';
      const resultLabel = {
        approved: '已发表', pending: '已提交审核', rejected: '未通过', submitted: '已提交'
      }[result];
      this.pendingNewItemId = approved && created && created.id ? created.id : '';
      this.setData({
        publishing: false,
        publishComplete: true,
        publishResult: result,
        publishStage: resultLabel,
        uploadProgress: 100
      });
      if (approved) {
        invalidate(FEED_CACHE_KEY);
        social.changed();
        haptic('success');
      }
      clearTimeout(this.publishSuccessTimer);
      this.publishSuccessTimer = setTimeout(() => {
        if (this._disposed) return;
        this.dismissComposer(true, true);
        if (!approved) return;
        this.postPublishRefreshTimer = setTimeout(() => {
          if (!this._disposed) this.load({ force: true, background: true });
        }, COMPOSER_ANIMATION_MS);
      }, approved ? PUBLISH_SUCCESS_HOLD_MS : PUBLISH_PENDING_HOLD_MS);
    } catch (error) {
      if (this._disposed) return;
      this.setData({
        publishing: false,
        publishStage: '',
        publishError: error.message || '发表失败，请重试'
      });
    }
  },

  blockBackgroundScroll() {},

  preview(e) { wx.navigateTo({ url: `/pages/route/index?id=${e.currentTarget.dataset.id}` }); },

  openPost(e) { wx.navigateTo({ url: `/pages/post/index?id=${e.currentTarget.dataset.id}` }); },

  openUser(e) {
    const id = e.currentTarget.dataset.id;
    if (id) wx.navigateTo({ url: `/pages/public-profile/index?id=${id}` });
  },

  onShareAppMessage() { return { title: '完攀日记广场', path: '/pages/feed/index' }; }
});
