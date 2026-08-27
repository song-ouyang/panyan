const { request } = require('../../utils/api');
const { read, write, loadOnce, invalidate } = require('../../utils/page-cache');
const { afterPaint } = require('../../utils/motion');

const RANKING_CACHE_TTL_MS = 45000;
const ROUTES_CACHE_KEY = 'ranking:routes';
const REGIONS_CACHE_KEY = 'ranking:regions';

const SCOPES = [
  { key: 'national', label: '全国' },
  { key: 'province', label: '省' },
  { key: 'city', label: '市' }
];

Page({
  data: {
    tab: 'users',
    scope: 'national',
    scopes: SCOPES,
    items: [],
    podium: [],
    rest: [],
    routes: [],
    regions: [],
    provinces: [],
    cities: [],
    provinceIndex: 0,
    cityIndex: 0,
    myRank: null,
    scoring: null,
    scoringText: '积分按本月有效完攀与获赞实时累计',
    rankingState: 'loading',
    rankingError: '',
    routesState: 'loading',
    routesError: '',
    regionsState: 'loading',
    routesMounted: false,
    podiumReveal: true
  },

  onLoad() {
    this.rankingRequestSeq = 0;
    this.routesRequestSeq = 0;
    this.regionsRequestSeq = 0;
    this._disposed = false;
    this._revealedPodiumKeys = Object.create(null);
  },

  onShow() {
    this._disposed = false;
    this.loadRegions({ background: true });
    this.loadRoutes({ background: true });
    this.loadUsers({ background: true });
  },

  onHide() {
    this.rankingRequestSeq += 1;
    this.routesRequestSeq += 1;
    this.regionsRequestSeq += 1;
    if (this._podiumRevealTimer) {
      clearTimeout(this._podiumRevealTimer);
      this._podiumRevealTimer = null;
    }
    if (!this.data.podiumReveal && this.data.podium.length) this.setData({ podiumReveal: true });
  },

  onUnload() {
    this._disposed = true;
    this.rankingRequestSeq += 1;
    this.routesRequestSeq += 1;
    this.regionsRequestSeq += 1;
    if (this._podiumRevealTimer) clearTimeout(this._podiumRevealTimer);
  },

  onPullDownRefresh() {
    return Promise.all([
      this.loadRegions({ force: true }),
      this.loadRoutes({ force: true }),
      this.loadUsers({ force: true })
    ]).finally(() => wx.stopPullDownRefresh());
  },

  rankingQuery() {
    const { scope, provinces, cities, provinceIndex, cityIndex } = this.data;
    const params = [`scope=${scope}`];
    if (scope !== 'national' && provinces[provinceIndex]) {
      params.push(`province=${encodeURIComponent(provinces[provinceIndex])}`);
    }
    if (scope === 'city' && cities[cityIndex]) {
      params.push(`city=${encodeURIComponent(cities[cityIndex])}`);
    }
    return params.join('&');
  },

  formatScoring(scoring) {
    if (!scoring) return '积分按本月有效完攀与获赞实时累计';
    return `完攀 +${scoring.completion} · 难度每级 +${scoring.gradeStep} · Flash +${scoring.flash} · 获赞 +${scoring.like}`;
  },

  invalidateRankingRequest() {
    this.rankingRequestSeq = (this.rankingRequestSeq || 0) + 1;
  },

  rankingCacheKey(query = this.rankingQuery()) {
    return `ranking:users:${query}`;
  },

  applyUsers(data, cacheKey) {
    if (this._disposed) return;
    const items = Array.isArray(data && data.items) ? data.items : [];
    const scoring = data && data.scoring ? data.scoring : null;
    const shouldRevealPodium = Boolean(items.length && !this._revealedPodiumKeys[cacheKey]);
    if (shouldRevealPodium) this._revealedPodiumKeys[cacheKey] = true;
    this._displayedRankingKey = cacheKey;
    this.setData({
      items,
      podium: [items[1], items[0], items[2]].filter(Boolean),
      rest: items.slice(3),
      myRank: data && data.myRank ? data.myRank : null,
      scoring,
      scoringText: this.formatScoring(scoring),
      rankingState: items.length ? 'ready' : 'empty',
      rankingError: '',
      podiumReveal: !shouldRevealPodium
    }, () => {
      if (!shouldRevealPodium || this._disposed) return;
      if (this._podiumRevealTimer) clearTimeout(this._podiumRevealTimer);
      this._podiumRevealTimer = afterPaint(() => {
        this._podiumRevealTimer = null;
        if (!this._disposed && this._displayedRankingKey === cacheKey) {
          this.setData({ podiumReveal: true });
        }
      });
    });
  },

  loadUsers(options = {}) {
    const { force = false, background = false } = options;
    const requestSeq = (this.rankingRequestSeq || 0) + 1;
    this.rankingRequestSeq = requestSeq;
    const query = this.rankingQuery();
    const cacheKey = this.rankingCacheKey(query);
    const cached = force ? null : read(cacheKey, RANKING_CACHE_TTL_MS);
    if (cached && this._displayedRankingKey !== cacheKey) this.applyUsers(cached.value, cacheKey);
    if (cached && cached.fresh) return Promise.resolve(cached.value);

    const hasVisibleRanking = this._displayedRankingKey === cacheKey
      && (this.data.rankingState === 'ready' || this.data.rankingState === 'empty');
    if (!background || !hasVisibleRanking) {
      this.setData({
        rankingState: hasVisibleRanking ? this.data.rankingState : 'loading',
        rankingError: ''
      });
    }

    if (force) invalidate(cacheKey);
    const loader = () => request(`/rankings?${query}`);
    const task = force ? loader() : loadOnce(cacheKey, loader);
    return task.then(data => {
      // Always preserve a completed response, even if the tab was hidden while it arrived.
      // The next onShow can paint from memory immediately instead of requesting again.
      write(cacheKey, data);
      if (this._disposed || requestSeq !== this.rankingRequestSeq) return data;
      this.applyUsers(data, cacheKey);
      return data;
    }).catch(error => {
      if (this._disposed || requestSeq !== this.rankingRequestSeq) return null;
      this.setData({
        rankingState: hasVisibleRanking ? this.data.rankingState : 'error',
        rankingError: error.message || '榜单暂时没有加载成功'
      });
      return null;
    });
  },

  applyRoutes(data) {
    if (this._disposed) return;
    const routes = Array.isArray(data && data.items) ? data.items : [];
    this.setData({
      routes,
      routesState: routes.length ? 'ready' : 'empty',
      routesError: ''
    });
  },

  loadRoutes(options = {}) {
    const { force = false, background = false } = options;
    const requestSeq = (this.routesRequestSeq || 0) + 1;
    this.routesRequestSeq = requestSeq;
    const cached = force ? null : read(ROUTES_CACHE_KEY, RANKING_CACHE_TTL_MS);
    if (cached && !this.data.routes.length) this.applyRoutes(cached.value);
    if (cached && cached.fresh) return Promise.resolve(cached.value);

    const hasVisibleRoutes = this.data.routesState === 'ready' || this.data.routesState === 'empty';
    if (!background || !hasVisibleRoutes) {
      this.setData({
        routesState: hasVisibleRoutes ? this.data.routesState : 'loading',
        routesError: ''
      });
    }

    if (force) invalidate(ROUTES_CACHE_KEY);
    const loader = () => request('/rankings/routes');
    const task = force ? loader() : loadOnce(ROUTES_CACHE_KEY, loader);
    return task.then(data => {
      write(ROUTES_CACHE_KEY, data);
      if (this._disposed || requestSeq !== this.routesRequestSeq) return data;
      this.applyRoutes(data);
      return data;
    }).catch(error => {
      if (this._disposed || requestSeq !== this.routesRequestSeq) return null;
      this.setData({
        routesState: hasVisibleRoutes ? this.data.routesState : 'error',
        routesError: error.message || '热门线路暂时没有加载成功'
      });
      return null;
    });
  },

  applyRegions(data) {
    if (this._disposed) return false;
    const regions = Array.isArray(data && data.items) ? data.items : [];
    const provinces = [...new Set(regions.map(item => item.province).filter(Boolean))];
    const previousProvince = this.data.provinces[this.data.provinceIndex];
    const matchedProvinceIndex = provinces.indexOf(previousProvince);
    const provinceIndex = matchedProvinceIndex >= 0 ? matchedProvinceIndex : 0;
    const province = provinces[provinceIndex];
    const previousCity = this.data.cities[this.data.cityIndex];
    const cities = [...new Set(
      regions
        .filter(item => item.province === province)
        .map(item => item.city)
        .filter(Boolean)
    )];
    const matchedCityIndex = cities.indexOf(previousCity);
    const nextData = {
      regions,
      provinces,
      cities,
      provinceIndex,
      cityIndex: matchedCityIndex >= 0 ? matchedCityIndex : 0,
      regionsState: provinces.length ? 'ready' : 'empty'
    };
    let resetScope = false;
    if (!provinces.length && this.data.scope !== 'national') {
      this.invalidateRankingRequest();
      nextData.scope = 'national';
      nextData.rankingState = 'loading';
      resetScope = true;
    }
    this.setData(nextData);
    return resetScope;
  },

  loadRegions(options = {}) {
    const { force = false, background = false } = options;
    const requestSeq = (this.regionsRequestSeq || 0) + 1;
    this.regionsRequestSeq = requestSeq;
    const cached = force ? null : read(REGIONS_CACHE_KEY, RANKING_CACHE_TTL_MS);
    if (cached && !this.data.regions.length) this.applyRegions(cached.value);
    if (cached && cached.fresh) return Promise.resolve(cached.value);

    const hasVisibleRegions = this.data.regionsState === 'ready' || this.data.regionsState === 'empty';
    if (!background || !hasVisibleRegions) {
      this.setData({ regionsState: hasVisibleRegions ? this.data.regionsState : 'loading' });
    }

    if (force) invalidate(REGIONS_CACHE_KEY);
    const loader = () => request('/rankings/regions');
    const task = force ? loader() : loadOnce(REGIONS_CACHE_KEY, loader);
    return task.then(data => {
      write(REGIONS_CACHE_KEY, data);
      if (this._disposed || requestSeq !== this.regionsRequestSeq) return data;
      const resetScope = this.applyRegions(data);
      if (resetScope) this.loadUsers({ background: true });
      return data;
    }).catch(() => {
      if (this._disposed || requestSeq !== this.regionsRequestSeq) return null;
      if (!hasVisibleRegions) this.setData({ regionsState: 'error' });
      return null;
    });
  },

  tab(e) {
    const tab = e.currentTarget.dataset.tab;
    if ((tab !== 'users' && tab !== 'routes') || tab === this.data.tab) return;
    this.setData({
      tab,
      routesMounted: this.data.routesMounted || tab === 'routes'
    });
  },

  scope(e) {
    const scope = e.currentTarget.dataset.scope;
    if (!SCOPES.some(item => item.key === scope) || scope === this.data.scope) return;
    if (scope !== 'national' && this.data.regionsState !== 'ready') {
      if (this.data.regionsState === 'error') this.loadRegions();
      wx.showToast({
        title: this.data.regionsState === 'loading' ? '地区正在加载' : '暂无可用地区',
        icon: 'none'
      });
      return;
    }

    this.invalidateRankingRequest();
    this.setData({ scope, rankingError: '' });
    this.loadUsers({ background: true });
  },

  chooseProvince(e) {
    const provinceIndex = Number(e.detail.value);
    const province = this.data.provinces[provinceIndex];
    const cities = [...new Set(
      this.data.regions
        .filter(item => item.province === province)
        .map(item => item.city)
        .filter(Boolean)
    )];
    this.invalidateRankingRequest();
    this.setData({
      provinceIndex,
      cities,
      cityIndex: 0,
      rankingError: ''
    });
    this.loadUsers({ background: true });
  },

  chooseCity(e) {
    this.invalidateRankingRequest();
    this.setData({
      cityIndex: Number(e.detail.value),
      rankingError: ''
    });
    this.loadUsers({ background: true });
  },

  retryUsers() {
    this.loadUsers({ force: true });
  },

  retryRoutes() {
    this.loadRoutes({ force: true });
  },

  retryRegions() {
    this.loadRegions({ force: true });
  },

  openRoute(e) {
    wx.navigateTo({ url: `/pages/route/index?id=${e.currentTarget.dataset.id}` });
  },

  openUser(e) {
    wx.navigateTo({ url: `/pages/public-profile/index?id=${e.currentTarget.dataset.id}` });
  }
});
