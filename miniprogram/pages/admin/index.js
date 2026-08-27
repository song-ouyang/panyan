const { request } = require('../../utils/api');
const { haptic } = require('../../utils/motion');
Page({
  data: { tab: 'routes', routes: [], sends: [], comments: [], reports: [], loading: true },
  onShow() { this.load(); },
  tab(e) { const tab = e.currentTarget.dataset.tab; if (tab === this.data.tab) return; haptic('selection'); this.setData({ tab }); },
  async load() { const [routes, moderation] = await Promise.all([request('/submissions/pending'), request('/admin/moderation')]); this.setData({ routes: routes.items, sends: moderation.sends, comments: moderation.comments, reports: moderation.reports, loading: false }); },
  reviewRoute(e) { const { id, action } = e.currentTarget.dataset; const text = action === 'approve' ? '通过并发布这条线路？' : '拒绝这条线路投稿？'; wx.showModal({ title: '线路审核', content: text, editable: action === 'reject', placeholderText: '可填写审核说明', success: async res => { if (!res.confirm) return; await request(`/submissions/${id}/review`, { method: 'POST', data: { action, note: res.content || '' } }); haptic(action === 'approve' ? 'success' : 'warning'); wx.showToast({ title: action === 'approve' ? '已发布' : '已拒绝' }); this.load(); } }); },
  reviewContent(e) { const { id, type, action } = e.currentTarget.dataset; wx.showModal({ title: action === 'approve' ? '确认通过' : '确认拒绝', content: action === 'reject' ? '拒绝后内容不会进入公共区域。' : '通过后内容将正常展示。', success: async res => { if (!res.confirm) return; await request(`/admin/moderation/${id}`, { method: 'POST', data: { targetType: type, action } }); haptic(action === 'approve' ? 'success' : 'warning'); wx.showToast({ title: action === 'approve' ? '已通过' : '已处理' }); this.load(); } }); }
});
