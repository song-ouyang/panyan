const { request } = require('../../utils/api');

Page({
  data: {
    brand: null,
    stores: [],
    initialLoading: true,
    refreshing: false,
    error: '',
    skeletons: [1, 2, 3]
  },

  onLoad({ id }) {
    this.id = id;
    this._disposed = false;
    this.loadSequence = 0;
    this._shownOnce = false;
    this.load();
  },

  onShow() {
    if (!this._shownOnce) {
      this._shownOnce = true;
      return;
    }
    this.load();
  },

  onPullDownRefresh() {
    Promise.resolve(this.load())
      .then(() => wx.stopPullDownRefresh(), () => wx.stopPullDownRefresh());
  },

  onUnload() {
    this._disposed = true;
    this.loadSequence += 1;
  },

  async load() {
    const sequence = ++this.loadSequence;
    const hasContent = Boolean(this.data.brand);
    const loadingPatch = { error: '' };
    if (hasContent) loadingPatch.refreshing = true;
    else loadingPatch.initialLoading = true;
    this.setData(loadingPatch);

    try {
      const brand = await request(`/gyms/brands/${this.id}/stores`);
      if (this._disposed || sequence !== this.loadSequence) return;

      const stores = Array.isArray(brand.stores) ? brand.stores : [];
      this.setData({
        brand,
        stores,
        initialLoading: false,
        refreshing: false,
        error: ''
      });

      if (stores.length === 1) {
        wx.redirectTo({ url: `/pages/gym/index?id=${stores[0].id}` });
      }
    } catch (error) {
      if (this._disposed || sequence !== this.loadSequence) return;
      this.setData({
        initialLoading: false,
        refreshing: false,
        error: error.message || '门店加载失败'
      });
    }
  },

  retry() {
    this.load();
  },

  open(e) {
    wx.navigateTo({ url: `/pages/gym/index?id=${e.currentTarget.dataset.id}` });
  }
});
