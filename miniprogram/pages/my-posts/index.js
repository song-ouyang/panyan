const { request } = require('../../utils/api');
const { invalidate } = require('../../utils/page-cache');
const { haptic } = require('../../utils/motion');

const STATUS_LABELS = {
  approved: '已发布',
  pending: '审核中',
  rejected: '未通过'
};

const VISIBILITY_LABELS = {
  public: '公开',
  friends: '岩友可见',
  private: '仅自己'
};

Page({
  data: {
    items: [],
    loading: true,
    refreshing: false,
    error: '',
    deletingId: '',
    skeletonRows: [1, 2, 3]
  },

  onLoad() {
    this._disposed = false;
    this.loadSequence = 0;
  },

  onShow() {
    this._disposed = false;
    this.load({ background: Boolean(this.data.items.length) });
  },

  onHide() {
    this.loadSequence = (this.loadSequence || 0) + 1;
  },

  onUnload() {
    this._disposed = true;
    this.loadSequence = (this.loadSequence || 0) + 1;
  },

  normalizeItems(data) {
    return (data && Array.isArray(data.items) ? data.items : []).map(item => {
      const imageUrls = Array.isArray(item.image_urls) ? item.image_urls : [];
      const isMoment = !item.route_id;
      return {
        ...item,
        image_urls: imageUrls,
        isMoment,
        typeLabel: isMoment ? '图片动态' : '完攀打卡',
        title: isMoment ? (item.caption || '分享了攀岩日常') : `${item.gym_name || '岩馆'} · ${item.route_name || '线路'}`,
        detail: isMoment
          ? (imageUrls.length ? `${imageUrls.length}张照片` : '文字动态')
          : `${item.grade || '--'} · 尝试${Number(item.attempts) || 1}次`,
        statusLabel: STATUS_LABELS[item.moderation_status] || '处理中',
        visibilityLabel: VISIBILITY_LABELS[item.visibility] || '仅自己',
        sentAtText: this.formatDate(item.sent_at)
      };
    });
  },

  formatDate(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const pad = number => String(number).padStart(2, '0');
    return `${date.getFullYear()}.${pad(date.getMonth() + 1)}.${pad(date.getDate())}`;
  },

  load({ background = false } = {}) {
    const sequence = (this.loadSequence || 0) + 1;
    this.loadSequence = sequence;
    const hasItems = this.data.items.length > 0;
    if (!background || !hasItems) {
      this.setData({ loading: !hasItems, refreshing: hasItems, error: '' });
    } else if (this.data.error) {
      this.setData({ error: '' });
    }

    return request('/users/me/sends')
      .then(data => {
        if (this._disposed || sequence !== this.loadSequence) return data;
        this.setData({
          items: this.normalizeItems(data),
          loading: false,
          refreshing: false,
          error: ''
        });
        return data;
      })
      .catch(error => {
        if (this._disposed || sequence !== this.loadSequence) return null;
        this.setData({
          loading: false,
          refreshing: false,
          error: error.message || '我的动态加载失败'
        });
        return null;
      });
  },

  retry() {
    return this.load();
  },

  onPullDownRefresh() {
    return this.load({ background: true })
      .finally(() => wx.stopPullDownRefresh());
  },

  open(e) {
    const id = e.currentTarget.dataset.id;
    if (id) wx.navigateTo({ url: `/pages/post/index?id=${id}` });
  },

  remove(e) {
    const id = e.currentTarget.dataset.id;
    if (!id || this.data.deletingId) return;
    wx.showModal({
      title: '删除动态',
      content: '图片或视频、点赞和评论将一并删除，无法恢复。',
      confirmText: '删除',
      confirmColor: '#c94c3f',
      success: async result => {
        if (!result.confirm || this._disposed) return;
        this.setData({ deletingId: id });
        try {
          await request(`/sends/${id}`, { method: 'DELETE' });
          if (this._disposed) return;
          invalidate('feed:public');
          haptic('warning');
          this.setData({
            items: this.data.items.filter(item => item.id !== id),
            deletingId: ''
          });
          wx.showToast({ title: '已删除' });
        } catch (error) {
          if (this._disposed) return;
          this.setData({ deletingId: '' });
          wx.showToast({ title: error.message || '删除失败，请重试', icon: 'none' });
        }
      }
    });
  }
});
