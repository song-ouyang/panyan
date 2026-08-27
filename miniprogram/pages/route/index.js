const { request } = require('../../utils/api');
const { afterPaint, haptic } = require('../../utils/motion');

const CHECKIN_RESULT_KEY = 'lastCheckinResult';

Page({
  data: {
    route: null,
    leaderboard: [],
    completionCount: 0,
    initialLoading: true,
    refreshing: false,
    error: '',
    checkinResult: null,
    checkinResultVisible: false,
    completionPulse: false,
    skeletons: [1, 2, 3]
  },

  onLoad({ id }) {
    this.id = id;
    this._disposed = false;
    this.loadSequence = 0;
    this._shownOnce = false;
  },

  onShow() {
    this._disposed = false;
    this.readCheckinResult();
    this.load();
    this._shownOnce = true;
  },

  onHide() {
    this.loadSequence += 1;
  },

  onPullDownRefresh() {
    Promise.resolve(this.load())
      .then(() => wx.stopPullDownRefresh(), () => wx.stopPullDownRefresh());
  },

  onUnload() {
    this._disposed = true;
    this.loadSequence += 1;
    if (this.resultTimer) clearTimeout(this.resultTimer);
    if (this.completionTimer) clearTimeout(this.completionTimer);
  },

  readCheckinResult() {
    let result;
    try {
      result = wx.getStorageSync(CHECKIN_RESULT_KEY);
    } catch (error) {
      result = null;
    }
    if (!result || String(result.routeId || result.route_id || '') !== String(this.id)) return;

    try { wx.removeStorageSync(CHECKIN_RESULT_KEY); } catch (error) {}
    const moderationStatus = result.moderationStatus || result.moderation_status || result.status;
    const pending = moderationStatus === 'pending';
    this.shouldConfirmCompletion = !pending;
    const checkinResult = {
      title: pending ? '完攀已记录，等待审核' : '这次完攀已经记下',
      description: pending
        ? '审核通过后会进入线路榜和月度积分。'
        : '线路数据已更新，继续看看大家的完攀视频吧。',
      pending
    };
    this.setData({ checkinResult, checkinResultVisible: false }, () => {
      if (this.resultTimer) clearTimeout(this.resultTimer);
      this.resultTimer = afterPaint(() => {
        if (!this._disposed) this.setData({ checkinResultVisible: true });
      });
    });
  },

  dismissCheckinResult() {
    if (!this.data.checkinResult) return;
    this.setData({ checkinResultVisible: false });
    if (this.resultTimer) clearTimeout(this.resultTimer);
    this.resultTimer = setTimeout(() => {
      if (!this._disposed) this.setData({ checkinResult: null });
    }, 160);
  },

  async load() {
    const sequence = ++this.loadSequence;
    const hasContent = Boolean(this.data.route);
    const loadingPatch = { error: '' };
    if (hasContent) loadingPatch.refreshing = true;
    else loadingPatch.initialLoading = true;
    this.setData(loadingPatch);

    try {
      const [route, leaderboard] = await Promise.all([
        request(`/routes/${this.id}`),
        request(`/routes/${this.id}/leaderboard`)
      ]);
      if (this._disposed || sequence !== this.loadSequence) return;
      const nextCompletionCount = Number(leaderboard.completionCount || 0);
      const completionPulse = Boolean(this.shouldConfirmCompletion);
      this.shouldConfirmCompletion = false;
      this.setData({
        route,
        leaderboard: Array.isArray(leaderboard.items) ? leaderboard.items : [],
        completionCount: nextCompletionCount,
        completionPulse,
        initialLoading: false,
        refreshing: false,
        error: ''
      }, () => {
        if (!completionPulse) return;
        if (this.completionTimer) clearTimeout(this.completionTimer);
        this.completionTimer = setTimeout(() => {
          if (!this._disposed) this.setData({ completionPulse: false });
        }, 280);
      });
    } catch (error) {
      if (this._disposed || sequence !== this.loadSequence) return;
      this.setData({
        initialLoading: false,
        refreshing: false,
        error: error.message || '线路加载失败'
      });
    }
  },

  retry() {
    this.load();
  },

  checkin() {
    wx.navigateTo({ url: `/pages/checkin/index?routeId=${this.id}` });
  },

  openPost(e) {
    wx.navigateTo({ url: `/pages/post/index?id=${e.currentTarget.dataset.id}` });
  },

  async like(e) {
    const { id } = e.currentTarget.dataset;
    const index = this.data.leaderboard.findIndex(item => item.id === id);
    if (index < 0 || (this.likeRequests && this.likeRequests[id])) return;
    const item = this.data.leaderboard[index];
    const previousLiked = Boolean(item.liked);
    const previousCount = Number(item.like_count || 0);
    const liked = !previousLiked;
    const likeCount = Math.max(0, previousCount + (liked ? 1 : -1));
    if (!this.likeRequests) this.likeRequests = {};
    this.likeRequests[id] = true;
    this.setData({
      [`leaderboard[${index}].liked`]: liked,
      [`leaderboard[${index}].like_count`]: likeCount
    }, () => {
      if (liked) haptic('selection');
    });
    try {
      await request(`/sends/${id}/like`, { method: liked ? 'POST' : 'DELETE' });
    } catch (error) {
      if (this._disposed) return;
      this.setData({
        [`leaderboard[${index}].liked`]: previousLiked,
        [`leaderboard[${index}].like_count`]: previousCount
      });
      wx.showToast({ title: error.message || '操作失败，请重试', icon: 'none' });
    } finally {
      if (this.likeRequests) delete this.likeRequests[id];
    }
  }
});
