const { request } = require('../../utils/api');
Page({
  data: { brand: null, stores: [], loading: true },
  onLoad({ id }) { this.id = id; this.load(); },
  async load() { const brand = await request(`/gyms/brands/${this.id}/stores`); this.setData({ brand, stores: brand.stores, loading: false }); if (brand.stores.length === 1) wx.redirectTo({ url: `/pages/gym/index?id=${brand.stores[0].id}` }); },
  open(e) { wx.navigateTo({ url: `/pages/gym/index?id=${e.currentTarget.dataset.id}` }); }
});
