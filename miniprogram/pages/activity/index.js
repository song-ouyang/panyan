const { request } = require('../../utils/api');
const social = require('../../utils/social-state');

const TYPES = {
  comments: { title: '我的评论', empty: '还没有评论', hint: '在动态里分享你的想法，评论会记录在这里' },
  favorites: { title: '我的收藏', empty: '还没有收藏', hint: '看到想留住的动态，点一下收藏就能在这里找到' },
  likes: { title: '我的点赞', empty: '还没有点赞', hint: '给喜欢的动态点个赞，在这里随时回看' }
};

Page({
  data: { type: 'comments', title: '我的评论', items: [], loading: true, loadingMore: false, error: '', nextCursor: null, busyId: '' },

  onLoad({ type } = {}) {
    this._disposed = false;
    this._sequence = 0;
    const selected = Object.prototype.hasOwnProperty.call(TYPES, type) ? type : 'comments';
    this.setData({ type: selected, ...TYPES[selected] });
    wx.setNavigationBarTitle({ title: TYPES[selected].title });
  },
  onShow() { this._disposed = false; return this.load(); },
  onHide() { this._sequence = (this._sequence || 0) + 1; },
  onUnload() { this._disposed = true; this._sequence = (this._sequence || 0) + 1; },

  syncAccount(userId) {
    if (this._userId === userId) return;
    this._userId = userId;
    this.setData({ items: [], nextCursor: null, busyId: '', loading: true, loadingMore: false, error: '' });
  },

  normalize(items) {
    return items.flatMap(item => {
      const post = this.data.type === 'comments' ? item.post : item;
      if (!post || typeof post.id !== 'string') return [];
      const date = new Date(this.data.type === 'comments' ? item.created_at : item.activity_at || post.sent_at);
      const dateText = Number.isNaN(date.getTime()) ? '' : `${date.getFullYear()}.${String(date.getMonth() + 1).padStart(2, '0')}.${String(date.getDate()).padStart(2, '0')}`;
      return [{
        id: item.id,
        postId: post.id,
        content: item.content || '',
        moderation_status: item.moderation_status,
        dateText,
        post: { ...post, image_urls: Array.isArray(post.image_urls) ? post.image_urls : [] }
      }];
    });
  },

  async load({ more = false } = {}) {
    if (more && (this.data.loading || this.data.loadingMore || !this.data.nextCursor)) return;
    const sequence = (this._sequence || 0) + 1;
    this._sequence = sequence;
    this.syncAccount(social.currentUserId());
    const cursor = more ? this.data.nextCursor : null;
    this.setData({ loading: !more && !this.data.items.length, loadingMore: more, error: '' });
    let userId;
    try {
      userId = await social.identity();
      if (this._disposed || sequence !== this._sequence) return;
      this.syncAccount(userId);
      const revision = social.currentRevision();
      const data = await request(`/users/me/${this.data.type}?limit=20${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`, { expectedUserId: userId });
      if (this._disposed || sequence !== this._sequence) return;
      if (!social.isCurrent(userId)) { this.syncAccount(social.currentUserId()); return; }
      if (revision !== social.currentRevision()) return this.load();
      if (!data || !Array.isArray(data.items) || (data.nextCursor != null && typeof data.nextCursor !== 'string')) throw new Error('记录加载失败，请重试');
      const next = this.normalize(data.items);
      const merged = more ? [...this.data.items, ...next] : next;
      const seen = new Set();
      this.setData({
        items: merged.filter(item => !seen.has(item.id) && seen.add(item.id)),
        nextCursor: data.nextCursor || null, loading: false, loadingMore: false, error: ''
      });
    } catch (error) {
      if (this._disposed || sequence !== this._sequence) return;
      if (userId && !social.isCurrent(userId)) this.syncAccount(social.currentUserId());
      this.setData({ loading: false, loadingMore: false, error: error.message || '记录加载失败，请重试' });
    }
  },
  retry() { return this.load(); },
  loadMore() { return this.load({ more: true }); },
  onReachBottom() { return this.loadMore(); },
  onPullDownRefresh() { return this.load().finally(() => wx.stopPullDownRefresh()); },
  open(e) {
    if (!social.isCurrent(this._userId)) { this.syncAccount(social.currentUserId()); return this.load(); }
    const id = e.currentTarget.dataset.id;
    if (id) wx.navigateTo({ url: `/pages/post/index?id=${encodeURIComponent(id)}` });
  },

  async remove(e) {
    if (!['favorites', 'likes'].includes(this.data.type) || this.data.busyId || this._disposed) return;
    const userId = this._userId;
    if (!social.isCurrent(userId)) { this.syncAccount(social.currentUserId()); return this.load(); }
    const id = e.currentTarget.dataset.id;
    if (!this.data.items.some(item => item.postId === id)) return;
    this.setData({ busyId: id });
    try {
      await social.setInteraction(id, this.data.type === 'favorites' ? 'favorite' : 'like', false, userId);
      if (this._disposed || !social.isCurrent(userId)) return;
      this._sequence = (this._sequence || 0) + 1;
      this.setData({ items: this.data.items.filter(item => item.postId !== id), loading: false, loadingMore: false });
    } catch (error) {
      if (!this._disposed && social.isCurrent(userId)) wx.showToast({ title: error.message || '操作失败，请重试', icon: 'none' });
    } finally {
      if (!this._disposed) {
        if (!social.isCurrent(userId)) this.syncAccount(social.currentUserId());
        else this.setData({ busyId: '' });
      }
    }
  }
});
