const { request } = require('../../utils/api');
Page({
  data: { post: null, content: '', sending: false },
  onLoad({ id }) { this.id = id; this.load(); },
  async load() { this.setData({ post: await request(`/sends/${this.id}`) }); },
  input(e) { this.setData({ content: e.detail.value }); },
  async sendComment() {
    const content = this.data.content.trim();
    if (!content || this.data.sending) return;
    this.setData({ sending: true });
    try { await request(`/sends/${this.id}/comments`, { method: 'POST', data: { content } }); this.setData({ content: '', sending: false }); this.load(); }
    catch (error) { this.setData({ sending: false }); wx.showToast({ title: error.message, icon: 'none' }); }
  },
  async like() { await request(`/sends/${this.id}/like`, { method: this.data.post.liked ? 'DELETE' : 'POST' }); this.load(); },
  report() { wx.showActionSheet({ itemList: ['垃圾广告','不友善内容','危险攀爬行为','侵犯隐私','虚假信息','其他'], success: async ({ tapIndex }) => { const reasons = ['spam','abuse','unsafe','privacy','false_info','other']; await request('/reports', { method: 'POST', data: { targetType: 'send', targetId: this.id, reason: reasons[tapIndex] } }); wx.showToast({ title: '已提交举报' }); } }); },
  onShareAppMessage() { const p = this.data.post || {}; return { title: `${p.nickname || '岩友'}完攀了${p.grade || ''}线路`, path: `/pages/post/index?id=${this.id}` }; }
});
