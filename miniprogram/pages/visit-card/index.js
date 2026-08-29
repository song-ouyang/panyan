const { request } = require('../../utils/api');

Page({
  data: { card: null, gym: null, visits: 1, title: '岩友分享次卡', note: '', expiresOn: '', loading: true, saving: false, error: '' },
  async onLoad(query) {
    this.id = query.id;
    this.gymId = query.gymId;
    try {
      if (this.id) this.setData({ card: await request(`/visit-cards/${this.id}`), loading: false });
      else this.setData({ gym: await request(`/gyms/${this.gymId}`), loading: false });
    } catch (error) { this.setData({ loading: false, error: error.message || '加载失败' }); }
  },
  input(e) { this.setData({ [e.currentTarget.dataset.field]: e.detail.value }); },
  async create() {
    if (this.data.saving) return;
    this.setData({ saving: true, error: '' });
    try {
      const card = await request('/visit-cards', { method: 'POST', data: { gymId: this.gymId, title: this.data.title, visits: Number(this.data.visits), note: this.data.note || null, expiresOn: this.data.expiresOn || null } });
      this.id = card.id; this.setData({ card, saving: false });
      wx.showToast({ title: '次卡已创建' });
    } catch (error) { this.setData({ saving: false, error: error.message || '创建失败' }); }
  },
  async claim() {
    try { const card = await request(`/visit-cards/${this.id}/claim`, { method: 'POST' }); this.setData({ card }); wx.showToast({ title: '已领取' }); } catch (error) { wx.showToast({ title: error.message || '领取失败', icon: 'none' }); }
  },
  onShareAppMessage() { return this.data.card ? { title: `${this.data.card.gym_name} · ${this.data.card.title}`, path: `/pages/visit-card/index?id=${this.data.card.id}` } : {}; }
});
