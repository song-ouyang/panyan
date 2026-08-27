const { request } = require('../../utils/api');
const { haptic } = require('../../utils/motion');

Page({
  data: {
    gym: null,
    routes: [],
    grades: ['全部', 'V0', 'V1', 'V2', 'V3', 'V4', 'V5', 'V6', 'V7'],
    grade: '全部',
    setId: '',
    initialLoading: true,
    refreshing: false,
    routesRefreshing: false,
    error: '',
    routesError: '',
    skeletons: [1, 2, 3]
  },

  onLoad({ id }) {
    this.id = id;
    this._disposed = false;
    this.gymLoadSequence = 0;
    this.routesLoadSequence = 0;
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
    this.gymLoadSequence += 1;
    this.routesLoadSequence += 1;
  },

  async load() {
    const sequence = ++this.gymLoadSequence;
    const hasContent = Boolean(this.data.gym);
    const loadingPatch = { error: '' };
    if (hasContent) loadingPatch.refreshing = true;
    else loadingPatch.initialLoading = true;
    this.setData(loadingPatch);

    try {
      const gym = await request(`/gyms/${this.id}`);
      if (this._disposed || sequence !== this.gymLoadSequence) return;

      const routeSets = Array.isArray(gym.routeSets) ? gym.routeSets : [];
      const selectedStillExists = routeSets.some(item => item.id === this.data.setId);
      const active = routeSets.find(item => item.active);
      const setId = selectedStillExists ? this.data.setId : (active ? active.id : '');

      this.setData({
        gym,
        setId,
        initialLoading: false,
        error: ''
      });
      await this.loadRoutes(this.data.grade, setId);
      if (!this._disposed && sequence === this.gymLoadSequence) {
        this.setData({ refreshing: false });
      }
    } catch (error) {
      if (this._disposed || sequence !== this.gymLoadSequence) return;
      this.setData({
        initialLoading: false,
        refreshing: false,
        error: error.message || '岩馆加载失败'
      });
    }
  },

  async loadRoutes(grade, setId) {
    const sequence = ++this.routesLoadSequence;
    const params = [];
    if (grade !== '全部') params.push(`grade=${encodeURIComponent(grade)}`);
    if (setId) params.push(`setId=${encodeURIComponent(setId)}`);

    this.setData({ routesRefreshing: true, routesError: '' });
    try {
      const routes = await request(`/gyms/${this.id}/routes${params.length ? `?${params.join('&')}` : ''}`);
      if (this._disposed || sequence !== this.routesLoadSequence) return;
      this.setData({
        routes: Array.isArray(routes.items) ? routes.items : [],
        routesRefreshing: false,
        routesError: ''
      });
    } catch (error) {
      if (this._disposed || sequence !== this.routesLoadSequence) return;
      this.setData({
        routesRefreshing: false,
        routesError: error.message || '线路加载失败'
      });
    }
  },

  retry() {
    this.load();
  },

  retryRoutes() {
    this.loadRoutes(this.data.grade, this.data.setId);
  },

  chooseGrade(e) {
    const grade = e.currentTarget.dataset.grade;
    if (grade === this.data.grade) return;
    haptic('selection');
    this.setData({ grade });
    this.loadRoutes(grade, this.data.setId);
  },

  chooseSet(e) {
    const setId = e.currentTarget.dataset.id;
    if (setId === this.data.setId) return;
    haptic('selection');
    this.setData({ setId });
    this.loadRoutes(this.data.grade, setId);
  },

  open(e) {
    wx.navigateTo({ url: `/pages/route/index?id=${e.currentTarget.dataset.id}` });
  },

  submitRoute() {
    wx.navigateTo({ url: `/pages/route-submit/index?gymId=${this.id}` });
  }
});
