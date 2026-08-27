const { request } = require('../../utils/api');
const { haptic } = require('../../utils/motion');

const LIKE_CONFIRM_MS = 240;
const COMMENT_ENTER_MS = 220;

Page({
  data: {
    post: null,
    content: '',
    sending: false,
    likePending: false,
    likePulse: false,
    enteringCommentId: ''
  },

  onLoad({ id }) { this.id = id; this._disposed = false; this.load(); },

  onUnload() {
    this._disposed = true;
    clearTimeout(this.likePulseTimer);
    clearTimeout(this.commentEnterTimer);
  },

  async load() {
    try {
      const post = await request(`/sends/${this.id}`);
      if (!this._disposed) this.setData({ post });
    } catch (error) {
      if (!this._disposed) wx.showToast({ title: error.message || '动态加载失败', icon: 'none' });
    }
  },

  input(e) { this.setData({ content: e.detail.value }); },

  async sendComment() {
    const content = this.data.content.trim();
    if (!content || this.data.sending || !this.data.post) return;
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
      const created = await request(`/sends/${this.id}/comments`, { method: 'POST', data: { content } });
      if (this._disposed) return;
      const comments = this.data.post.comments.map(comment => (
        comment.id === temporaryId
          ? { ...comment, ...created, content, pending: false }
          : comment
      ));
      this.setData({
        'post.comments': comments,
        sending: false
      });
    } catch (error) {
      if (!this._disposed) {
        this.setData({
          'post.comments': this.data.post.comments.filter(comment => comment.id !== temporaryId),
          content: this.data.content || content,
          sending: false,
          enteringCommentId: ''
        });
        wx.showToast({ title: error.message || '评论发送失败', icon: 'none' });
      }
    }
  },

  async like() {
    if (!this.data.post || this.data.likePending) return;
    const previousLiked = Boolean(this.data.post.liked);
    const previousCount = Number(this.data.post.like_count) || 0;
    const nextLiked = !previousLiked;
    const nextCount = Math.max(0, previousCount + (nextLiked ? 1 : -1));
    this.setData({
      'post.liked': nextLiked,
      'post.like_count': nextCount,
      likePending: true,
      likePulse: nextLiked
    });
    if (nextLiked) {
      haptic('selection');
      clearTimeout(this.likePulseTimer);
      this.likePulseTimer = setTimeout(() => {
        if (!this._disposed) this.setData({ likePulse: false });
      }, LIKE_CONFIRM_MS);
    }
    try {
      await request(`/sends/${this.id}/like`, { method: nextLiked ? 'POST' : 'DELETE' });
      if (!this._disposed) this.setData({ likePending: false });
    } catch (error) {
      if (!this._disposed) {
        this.setData({
          'post.liked': previousLiked,
          'post.like_count': previousCount,
          likePending: false,
          likePulse: false
        });
        wx.showToast({ title: error.message || '操作失败，请重试', icon: 'none' });
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
