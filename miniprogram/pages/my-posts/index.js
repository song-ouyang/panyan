const { request } = require('../../utils/api');
Page({
  data: { items: [], loading: true },
  onShow() { this.load(); },
  async load() { const data = await request('/users/me/sends'); this.setData({ items: data.items, loading: false }); },
  open(e) { wx.navigateTo({ url: `/pages/post/index?id=${e.currentTarget.dataset.id}` }); },
  remove(e) { const id = e.currentTarget.dataset.id; wx.showModal({ title: '删除打卡', content: '动态、视频地址、点赞和评论将一并删除，无法恢复。', confirmText: '删除', confirmColor: '#c33', success: async res => { if (!res.confirm) return; await request(`/sends/${id}`, { method: 'DELETE' }); wx.showToast({ title: '已删除' }); this.load(); } }); }
});
