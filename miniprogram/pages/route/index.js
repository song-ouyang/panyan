const { request } = require('../../utils/api');
Page({
  data: { route: null, leaderboard: [], completionCount: 0 },
  onLoad({ id }) { this.id = id; },
  onShow() { this.load(); },
  async load() {
    const [route, leaderboard] = await Promise.all([request(`/routes/${this.id}`), request(`/routes/${this.id}/leaderboard`)]);
    this.setData({ route, leaderboard: leaderboard.items, completionCount: leaderboard.completionCount });
  },
  checkin() { wx.navigateTo({ url: `/pages/checkin/index?routeId=${this.id}` }); },
  openPost(e) { wx.navigateTo({ url: `/pages/post/index?id=${e.currentTarget.dataset.id}` }); },
  async like(e) { const { id, liked } = e.currentTarget.dataset; await request(`/sends/${id}/like`, { method: liked ? 'DELETE' : 'POST' }); await this.load(); }
});
