const { request } = require('../../utils/api');
Page({
  data: { items: [], loading: true },
  onShow() { this.load(); },
  async load() { const data = await request('/notifications'); this.setData({ items: data.items, loading: false }); if (data.unread) await request('/notifications/read-all', { method: 'POST' }); },
  async open(e) { const item = e.currentTarget.dataset.item; if (item.target_path) wx.navigateTo({ url: item.target_path }); }
});
