const { request } = require('../../utils/api');
Page({
  data: { user: null, months: [], loading: true },
  onLoad({ id }) { this.userId = id; this.load(); },
  async load() {
    const user = await request(`/users/${this.userId}/public`);
    const map = {};
    user.monthly.forEach(item => {
      if (!map[item.month]) map[item.month] = { month: item.month, gyms: {} };
      if (!map[item.month].gyms[item.gym_name]) map[item.month].gyms[item.gym_name] = { name: item.gym_name, grades: [] };
      map[item.month].gyms[item.gym_name].grades.push({ grade: item.grade, sends: item.sends });
    });
    const months = Object.values(map).map(month => ({ ...month, gyms: Object.values(month.gyms) }));
    this.setData({ user, months, loading: false });
    wx.setNavigationBarTitle({ title: user.nickname });
  },
  async addFriend() { await request(`/users/${this.userId}/friend-request`, { method: 'POST' }); this.setData({ 'user.friendship': 'sent' }); wx.showToast({ title: '申请已发送' }); }
});
