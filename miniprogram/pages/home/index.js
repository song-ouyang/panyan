const { request } = require('../../utils/api');
Page({
  data: { me: null, gyms: [], meetups: [], loading: true },
  onShow() { this.load(); },
  async load() {
    try {
      const [me, gyms, meetups] = await Promise.all([request('/users/me'), request('/gyms'), request('/meetups')]);
      this.setData({ me, gyms: gyms.items.slice(0, 3), meetups: meetups.items.slice(0, 2), loading: false });
    } catch (error) { this.setData({ loading: false }); }
  },
  openGym(e) { wx.navigateTo({ url: `/pages/gym/index?id=${e.currentTarget.dataset.id}` }); },
  goGyms() { wx.switchTab({ url: '/pages/gyms/index' }); },
  goMeetups() { wx.navigateTo({ url: '/pages/meetups/index' }); }
});
