const { request } = require('../../utils/api');
Page({
  data: { gym: null, routes: [], grades: ['全部','V0','V1','V2','V3','V4','V5','V6','V7'], grade: '全部', setId: '' },
  onLoad({ id }) { this.id = id; this.load(); },
  async load() { const gym = await request(`/gyms/${this.id}`); const active = gym.routeSets.find(item => item.active); const setId = active ? active.id : ''; this.setData({ gym, setId }); await this.loadRoutes(this.data.grade, setId); },
  async loadRoutes(grade, setId) { const params = []; if (grade !== '全部') params.push(`grade=${grade}`); if (setId) params.push(`setId=${setId}`); const routes = await request(`/gyms/${this.id}/routes${params.length ? `?${params.join('&')}` : ''}`); this.setData({ routes: routes.items }); },
  async chooseGrade(e) { const grade = e.currentTarget.dataset.grade; this.setData({ grade }); await this.loadRoutes(grade, this.data.setId); },
  async chooseSet(e) { const setId = e.currentTarget.dataset.id; this.setData({ setId }); await this.loadRoutes(this.data.grade, setId); },
  open(e) { wx.navigateTo({ url: `/pages/route/index?id=${e.currentTarget.dataset.id}` }); },
  submitRoute() { wx.navigateTo({ url: `/pages/route-submit/index?gymId=${this.id}` }); }
});
