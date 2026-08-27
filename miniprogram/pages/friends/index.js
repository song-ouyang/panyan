const { request } = require('../../utils/api');
const { haptic } = require('../../utils/motion');
Page({
  data: { friends: [], requests: [], results: [], q: '' },
  onShow() { this.load(); },
  async load() { const [friends, requests] = await Promise.all([request('/users/me/friends'), request('/users/me/friend-requests')]); this.setData({ friends: friends.items, requests: requests.items }); },
  input(e) { this.setData({ q: e.detail.value }); },
  async search() { const data = await request(`/users/search?q=${encodeURIComponent(this.data.q)}`); this.setData({ results: data.items }); },
  async add(e) { await request(`/users/${e.currentTarget.dataset.id}/friend-request`, { method: 'POST' }); haptic('success'); wx.showToast({ title: '申请已发送' }); this.search(); },
  async accept(e) { await request(`/users/${e.currentTarget.dataset.id}/friend-accept`, { method: 'POST' }); haptic('success'); wx.showToast({ title: '已成为岩友' }); this.load(); },
  remove(e) { wx.showModal({ title: '删除岩友', content: '删除后双方将不再是岩友。', success: async res => { if (!res.confirm) return; await request(`/users/${e.currentTarget.dataset.id}/friend`, { method: 'DELETE' }); haptic('warning'); this.load(); } }); }
});
