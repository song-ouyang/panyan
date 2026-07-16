const { request } = require('../../utils/api');
Page({
  data: { tab: 'users', scope: 'national', scopes: [{ key: 'national', label: '全国' }, { key: 'province', label: '省' }, { key: 'city', label: '市' }], items: [], podium: [], rest: [], routes: [], regions: [], provinces: [], cities: [], provinceIndex: 0, cityIndex: 0, myRank: null, scoring: null, loading: true },
  onShow() { this.load(); },
  setRanking(items) { const podium = [items[1], items[0], items[2]].filter(Boolean); this.setData({ items, podium, rest: items.slice(3) }); },
  async load() {
    const [regions, routes] = await Promise.all([request('/rankings/regions'), request('/rankings/routes')]);
    const provinces = [...new Set(regions.items.map(item => item.province))];
    const cities = regions.items.filter(item => item.province === provinces[0]).map(item => item.city);
    this.setData({ regions: regions.items, provinces, cities, routes: routes.items });
    await this.loadUsers();
  },
  rankingQuery() {
    const { scope, provinces, cities, provinceIndex, cityIndex } = this.data;
    const params = [`scope=${scope}`];
    if (scope !== 'national' && provinces[provinceIndex]) params.push(`province=${encodeURIComponent(provinces[provinceIndex])}`);
    if (scope === 'city' && cities[cityIndex]) params.push(`city=${encodeURIComponent(cities[cityIndex])}`);
    return params.join('&');
  },
  async loadUsers() { this.setData({ loading: true }); const data = await request(`/rankings?${this.rankingQuery()}`); this.setRanking(data.items); this.setData({ myRank: data.myRank, scoring: data.scoring, loading: false }); },
  tab(e) { this.setData({ tab: e.currentTarget.dataset.tab }); },
  async scope(e) { this.setData({ scope: e.currentTarget.dataset.scope }); await this.loadUsers(); },
  async chooseProvince(e) { const provinceIndex = Number(e.detail.value); const province = this.data.provinces[provinceIndex]; const cities = this.data.regions.filter(item => item.province === province).map(item => item.city); this.setData({ provinceIndex, cities, cityIndex: 0 }); await this.loadUsers(); },
  async chooseCity(e) { this.setData({ cityIndex: Number(e.detail.value) }); await this.loadUsers(); },
  openRoute(e) { wx.navigateTo({ url: `/pages/route/index?id=${e.currentTarget.dataset.id}` }); },
  openUser(e) { wx.navigateTo({ url: `/pages/public-profile/index?id=${e.currentTarget.dataset.id}` }); }
});
