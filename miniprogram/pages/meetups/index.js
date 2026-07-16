const { request } = require('../../utils/api');

Page({
  data: { items: [], gyms: [], me: null, loading: true, submitting: false, showCreate: false, tab: 'all', gymIndex: -1, title: '', date: '', minDate: '', time: '19:30', maxPeople: 4, note: '' },
  onLoad() { const now = new Date(); this.setData({ minDate: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}` }); },
  onShow() { this.load(); },
  async load() {
    this.setData({ loading: true });
    try {
      const path = this.data.tab === 'mine' ? '/meetups?mine=true' : '/meetups';
      const [meetups, gyms, me] = await Promise.all([request(path), request('/gyms'), request('/users/me')]);
      const items = (meetups.items || []).map(item => ({ ...item, starts_at_text: this.formatDate(item.starts_at), expired: new Date(item.starts_at).getTime() <= Date.now(), full: item.member_count >= item.max_people }));
      this.setData({ items, gyms: gyms.items || [], me, loading: false });
    } catch (error) { this.setData({ loading: false }); wx.showToast({ title: error.message || '约爬加载失败', icon: 'none' }); }
  },
  formatDate(value) { const date = new Date(value); const weekdays = ['周日','周一','周二','周三','周四','周五','周六']; return `${date.getMonth() + 1}月${date.getDate()}日 ${weekdays[date.getDay()]} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`; },
  changeTab(e) { this.setData({ tab: e.currentTarget.dataset.tab, items: [] }); this.load(); },
  toggle() { this.setData({ showCreate: !this.data.showCreate }); },
  bind(e) { this.setData({ [e.currentTarget.dataset.key]: e.detail.value }); },
  gym(e) { this.setData({ gymIndex: Number(e.detail.value) }); },
  date(e) { this.setData({ date: e.detail.value }); },
  time(e) { this.setData({ time: e.detail.value }); },
  changePeople(e) { const next = Math.min(50, Math.max(2, this.data.maxPeople + Number(e.currentTarget.dataset.step))); this.setData({ maxPeople: next }); },
  async create() {
    if (this.data.submitting) return;
    const gym = this.data.gyms[this.data.gymIndex];
    const title = this.data.title.trim();
    if (!title || title.length < 2) return wx.showToast({ title: '请填写约爬主题', icon: 'none' });
    if (!gym) return wx.showToast({ title: '请选择岩馆', icon: 'none' });
    if (!this.data.date) return wx.showToast({ title: '请选择日期', icon: 'none' });
    const startsAt = new Date(`${this.data.date}T${this.data.time}:00+08:00`);
    if (startsAt.getTime() <= Date.now()) return wx.showToast({ title: '约爬时间必须晚于现在', icon: 'none' });
    this.setData({ submitting: true });
    try {
      await request('/meetups', { method: 'POST', data: { gymId: gym.id, title, startsAt: startsAt.toISOString(), maxPeople: Number(this.data.maxPeople), note: this.data.note.trim() } });
      this.setData({ showCreate: false, submitting: false, tab: 'mine', title: '', date: '', time: '19:30', maxPeople: 4, note: '', gymIndex: -1 });
      wx.showToast({ title: '约爬已发布', icon: 'success' });
      this.load();
    } catch (error) { this.setData({ submitting: false }); wx.showToast({ title: error.message || '发布失败', icon: 'none' }); }
  },
  async join(e) { try { await request(`/meetups/${e.currentTarget.dataset.id}/join`, { method: 'POST' }); wx.showToast({ title: '已加入', icon: 'success' }); this.load(); } catch (error) { wx.showToast({ title: error.message || '加入失败', icon: 'none' }); } },
  leave(e) { wx.showModal({ title: '退出约爬', content: '确定退出这次约爬吗？', success: async res => { if (res.confirm) { try { await request(`/meetups/${e.currentTarget.dataset.id}/join`, { method: 'DELETE' }); wx.showToast({ title: '已退出' }); this.load(); } catch (error) { wx.showToast({ title: error.message || '退出失败', icon: 'none' }); } } } }); },
  cancel(e) { wx.showModal({ title: '取消约爬', content: '取消后会通知已经加入的岩友，确定继续吗？', confirmColor: '#ff4b4b', success: async res => { if (res.confirm) { try { await request(`/meetups/${e.currentTarget.dataset.id}`, { method: 'DELETE' }); wx.showToast({ title: '已取消' }); this.load(); } catch (error) { wx.showToast({ title: error.message || '取消失败', icon: 'none' }); } } } }); }
});
