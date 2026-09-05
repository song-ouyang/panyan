const { request } = require('../../utils/api');
const { haptic } = require('../../utils/motion');
const social = require('../../utils/social-state');

const LIKE_CONFIRM_MS = 240;
const COMMENT_ENTER_MS = 220;

Page({
  data: {
    post: null,
    content: '',
    sending: false,
    likePending: false,
    favoritePending: false,
    error: '',
    likePulse: false,
    enteringCommentId: ''
  },

  onLoad({ id }) {
    this.id = id; this._disposed = false; this._sequence = 0;
    this._pendingInteractions = {}; return this.load();
  },
  onShow() {
    if (!this._shownOnce) { this._shownOnce = true; return; }
    return this.load();
  },
  onHide() { this._sequence = (this._sequence || 0) + 1; },

  onUnload() {
    this._disposed = true;
    this._sequence = (this._sequence || 0) + 1;
    clearTimeout(this.likePulseTimer);
    clearTimeout(this.commentEnterTimer);
  },

  syncAccount(userId) {
    if (userId === this._userId) return;
    this._userId = userId;
    this._pendingInteractions = {};
    this.setData({ post: null, content: '', sending: false, likePending: false, favoritePending: false, error: '' });
  },

  async load() {
    const sequence = (this._sequence || 0) + 1;
    this._sequence = sequence;
    this.syncAccount(social.currentUserId());
    let userId;
    try {
      userId = await social.identity();
      if (this._disposed || sequence !== this._sequence) return;
      this.syncAccount(userId);
      const revision = social.currentRevision();
      const post = await request(`/sends/${encodeURIComponent(this.id)}`, { expectedUserId: userId });
      if (this._disposed || sequence !== this._sequence) return;
      if (!social.isCurrent(userId)) { this.syncAccount(social.currentUserId()); return; }
      if (revision !== social.currentRevision()) return this.load();
      this.setData({ post: { ...post, liked: post.liked === true, favorited: post.favorited === true,
        image_urls: Array.isArray(post.image_urls) ? post.image_urls : [], comments: Array.isArray(post.comments) ? post.comments : [] }, error: '' });
    } catch (error) {
      if (this._disposed || sequence !== this._sequence) return;
      if (userId && !social.isCurrent(userId)) this.syncAccount(social.currentUserId());
      const unavailable = [401, 403, 404].includes(error.statusCode);
      this.setData({ ...(unavailable ? { post: null } : {}), error: error.message || '动态加载失败，请重试' });
    }
  },
  retry() { return this.load(); },
  onPullDownRefresh() { return this.load().finally(() => wx.stopPullDownRefresh()); },
  previewImage(e) { wx.previewImage({ current: e.currentTarget.dataset.url, urls: this.data.post.image_urls }); },

  input(e) { this.setData({ content: e.detail.value }); },

  async sendComment() {
    const content = this.data.content.trim();
    const userId = this._userId;
    if (!social.isCurrent(userId)) { this.syncAccount(social.currentUserId()); return this.load(); }
    if (!content || this.data.sending || !this.data.post) return;
    this._sequence = (this._sequence || 0) + 1;
    const temporaryId = `local-${Date.now()}`;
    const currentComments = Array.isArray(this.data.post.comments) ? this.data.post.comments : [];
    this.setData({
      'post.comments': currentComments.concat({
        id: temporaryId,
        content,
        nickname: '我',
        avatar_url: '',
        pending: true
      }),
      content: '',
      sending: true,
      enteringCommentId: temporaryId
    });
    haptic('selection');
    clearTimeout(this.commentEnterTimer);
    this.commentEnterTimer = setTimeout(() => {
      if (!this._disposed && this.data.enteringCommentId === temporaryId) {
        this.setData({ enteringCommentId: '' });
      }
    }, COMMENT_ENTER_MS);
    try {
      const created = await request(`/sends/${this.id}/comments`, { method: 'POST', data: { content }, expectedUserId: userId });
      if (this._disposed) return;
      if (!social.isCurrent(userId)) { this.syncAccount(social.currentUserId()); return; }
      if (!created || typeof created.id !== 'string') throw new Error('评论未保存，请重试');
      social.changed();
      this._sequence = (this._sequence || 0) + 1;
      const current = this.data.post.comments || [];
      const comments = current.filter(comment => comment.id !== temporaryId && comment.id !== created.id)
        .concat({ nickname: '我', ...created, content, pending: false });
      this.setData({
        'post.comments': comments,
        'post.comment_count': (Number(this.data.post.comment_count) || 0) + (created.moderation_status === 'approved' ? 1 : 0),
        sending: false
      });
    } catch (error) {
      if (!this._disposed && social.isCurrent(userId) && this.data.post) {
        this.setData({
          'post.comments': this.data.post.comments.filter(comment => comment.id !== temporaryId),
          content: this.data.content || content,
          sending: false,
          enteringCommentId: ''
        });
        wx.showToast({ title: error.message || '评论发送失败', icon: 'none' });
      } else if (!this._disposed && !social.isCurrent(userId)) this.syncAccount(social.currentUserId());
    }
  },

  like() { return this.interact('like'); },
  favorite() { return this.interact('favorite'); },

  async interact(kind) {
    const post = this.data.post;
    const userId = this._userId;
    if (!post || this._disposed) return;
    if (!social.isCurrent(userId)) { this.syncAccount(social.currentUserId()); return this.load(); }
    const pending = this._pendingInteractions || (this._pendingInteractions = {});
    if (pending[kind]) return;
    pending[kind] = true;
    const field = kind === 'like' ? 'liked' : 'favorited';
    const busy = kind === 'like' ? 'likePending' : 'favoritePending';
    const selected = !post[field];
    this.setData({ [busy]: true });
    try {
      await social.setInteraction(this.id, kind, selected, userId);
      if (this._disposed || !social.isCurrent(userId) || !this.data.post) return;
      this._sequence = (this._sequence || 0) + 1;
      this.setData({
        [`post.${field}`]: selected,
        ...(kind === 'like' ? { 'post.like_count': Math.max(0, (Number(this.data.post.like_count) || 0) + (selected ? 1 : -1)), likePulse: selected } : {})
      });
      if (selected) haptic('selection');
      clearTimeout(this.likePulseTimer);
      this.likePulseTimer = setTimeout(() => { if (!this._disposed) this.setData({ likePulse: false }); }, LIKE_CONFIRM_MS);
    } catch (error) {
      if (!this._disposed && social.isCurrent(userId)) wx.showToast({ title: error.message || '操作失败，请重试', icon: 'none' });
    } finally {
      delete pending[kind];
      if (!this._disposed) {
        if (!social.isCurrent(userId)) this.syncAccount(social.currentUserId());
        else this.setData({ [busy]: false });
      }
    }
  },

  report() {
    wx.showActionSheet({
      itemList: ['垃圾广告', '不友善内容', '危险攀爬行为', '侵犯隐私', '虚假信息', '其他'],
      success: async ({ tapIndex }) => {
        const reasons = ['spam', 'abuse', 'unsafe', 'privacy', 'false_info', 'other'];
        await request('/reports', { method: 'POST', data: { targetType: 'send', targetId: this.id, reason: reasons[tapIndex] } });
        wx.showToast({ title: '已提交举报' });
      }
    });
  },

  onShareAppMessage() {
    const post = this.data.post || {};
    return { title: `${post.nickname || '岩友'}完攀了${post.grade || ''}线路`, path: `/pages/post/index?id=${this.id}` };
  }
});
