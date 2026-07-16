const { request } = require('../../utils/api');
Page({
  data: { items: [], allItems: [], meetups: [], cities: ['全部城市'], cityIndex: 0, q: '', loading: true },
  onShow() { this.load(); },
  onInput(e) { this.setData({ q: e.detail.value }); },
  clearSearch() { this.setData({ q: '' }); this.load(); },
  search() { this.load(); },
  async load() {
    const city = this.data.cities[this.data.cityIndex];
    const params = [`q=${encodeURIComponent(this.data.q)}`];
    if (city && city !== '全部城市') params.push(`city=${encodeURIComponent(city)}`);
    const [data, meetupData] = await Promise.all([request(`/gyms/directory?${params.join('&')}`), request('/meetups')]);
    if (this.data.cities.length === 1) {
      const all = await request('/gyms');
      const cities = ['全部城市', ...new Set(all.items.map(item => item.city).filter(Boolean))];
      const preferred = cities.indexOf('深圳');
      this.setData({ cities, cityIndex: preferred > 0 ? preferred : 0, allItems: all.items });
      if (preferred > 0) return this.load();
    }
    this.setData({ items: data.items, meetups: meetupData.items.slice(0, 2), loading: false });
  },
  chooseCity(e) { this.setData({ cityIndex: Number(e.detail.value), loading: true }); this.load(); },
  open(e) { wx.navigateTo({ url: `/pages/brand/index?id=${e.currentTarget.dataset.id}` }); },
  goMeetups() { wx.navigateTo({ url: '/pages/meetups/index' }); }
});
