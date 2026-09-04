const { request } = require('../../utils/api');
const pageCache = require('../../utils/page-cache');
const {
  brandPageUrl,
  presentDirectoryItems,
  selectedCity
} = require('../../utils/gym-directory');

const CITIES_CACHE_KEY = 'gyms:cities';
const MEETUPS_CACHE_KEY = 'gyms:meetups-preview';
const CITIES_TTL = 10 * 60 * 1000;
const DIRECTORY_TTL = 60 * 1000;
const MEETUPS_TTL = 30 * 1000;

function directoryCacheKey(city, query) {
  return `gyms:directory:${city || 'all'}:${query || ''}`;
}

Page({
  data: {
    items: [],
    meetups: [],
    cities: ['全部城市'],
    cityIndex: 0,
    q: '',
    loading: true,
    error: '',
    skeletons: [1, 2, 3]
  },

  onLoad() {
    this.destroyed = false;
    this.loadSequence = 0;
    const cityCache = pageCache.read(CITIES_CACHE_KEY, CITIES_TTL);
    if (cityCache) this.setData(cityCache.value);
  },

  onShow() {
    this.destroyed = false;
    this.load();
  },

  onHide() {
    this.loadSequence = (this.loadSequence || 0) + 1;
    if (this.searchTimer) clearTimeout(this.searchTimer);
  },

  onPullDownRefresh() {
    Promise.resolve(this.load({ force: true }))
      .then(() => wx.stopPullDownRefresh(), () => wx.stopPullDownRefresh());
  },

  onUnload() {
    this.destroyed = true;
    this.loadSequence = (this.loadSequence || 0) + 1;
    if (this.searchTimer) clearTimeout(this.searchTimer);
  },

  onInput(e) {
    this.setData({ q: e.detail.value });
    if (this.searchTimer) clearTimeout(this.searchTimer);
    this.searchTimer = setTimeout(() => this.load(), 250);
  },

  clearSearch() {
    if (this.searchTimer) clearTimeout(this.searchTimer);
    this.setData({ q: '' });
    this.load();
  },

  search() {
    if (this.searchTimer) clearTimeout(this.searchTimer);
    this.load();
  },

  async load({ force = false } = {}) {
    const sequence = (this.loadSequence || 0) + 1;
    this.loadSequence = sequence;

    try {
      let { cities, cityIndex } = this.data;
      if (cities.length === 1) {
        const cityCache = pageCache.read(CITIES_CACHE_KEY, CITIES_TTL);
        if (cityCache && !force) {
          ({ cities, cityIndex } = cityCache.value);
        } else {
          const all = await pageCache.loadOnce(CITIES_CACHE_KEY, () => request('/gyms'));
          cities = ['全部城市', ...new Set((all.items || []).map(item => item.city).filter(Boolean))];
          const preferred = cities.indexOf('深圳');
          cityIndex = preferred > 0 ? preferred : 0;
          pageCache.write(CITIES_CACHE_KEY, { cities, cityIndex });
        }
      }

      const city = cities[cityIndex];
      const query = this.data.q.trim();
      const params = [`q=${encodeURIComponent(query)}`];
      if (city && city !== '全部城市') params.push(`city=${encodeURIComponent(city)}`);

      const cacheKey = directoryCacheKey(city, query);
      const directoryCache = pageCache.read(cacheKey, DIRECTORY_TTL);
      const meetupCache = pageCache.read(MEETUPS_CACHE_KEY, MEETUPS_TTL);
      const cachedPatch = {};

      if (directoryCache) cachedPatch.items = presentDirectoryItems(directoryCache.value);
      if (meetupCache) cachedPatch.meetups = meetupCache.value;
      if (cities !== this.data.cities) {
        cachedPatch.cities = cities;
        cachedPatch.cityIndex = cityIndex;
      }
      if (Object.keys(cachedPatch).length) {
        cachedPatch.loading = false;
        cachedPatch.error = '';
        if (!this.destroyed && sequence === this.loadSequence) this.setData(cachedPatch);
      } else if (!this.data.items.length) {
        this.setData({ loading: true, error: '' });
      } else if (this.data.error) {
        this.setData({ error: '' });
      }

      const directoryFresh = directoryCache && directoryCache.fresh;
      const meetupsFresh = meetupCache && meetupCache.fresh;
      if (!force && directoryFresh && meetupsFresh) return;

      const directoryTask = !force && directoryFresh
        ? Promise.resolve(presentDirectoryItems(directoryCache.value))
        : pageCache.loadOnce(cacheKey, () => request(`/gyms/directory?${params.join('&')}`))
          .then(data => pageCache.write(cacheKey, presentDirectoryItems(data.items)));
      const meetupTask = !force && meetupsFresh
        ? Promise.resolve(meetupCache.value)
        : pageCache.loadOnce(MEETUPS_CACHE_KEY, () => request('/meetups'))
          .then(data => pageCache.write(
            MEETUPS_CACHE_KEY,
            Array.isArray(data.items) ? data.items.slice(0, 2) : [],
          ));

      const [items, meetupState] = await Promise.all([
        directoryTask,
        meetupTask
          .then(value => ({ ok: true, value }))
          .catch(error => ({ ok: false, error })),
      ]);
      // Each request writes its cache before this visibility check. A quick tab switch
      // therefore keeps useful network work without touching the hidden page tree.
      if (this.destroyed || sequence !== this.loadSequence) return;

      const nextData = { loading: false, error: '' };
      if (force || !directoryFresh) nextData.items = items;
      if (meetupState.ok && (force || !meetupsFresh)) nextData.meetups = meetupState.value;
      this.setData(nextData);
      if (!meetupState.ok) console.warn('[gyms] meetups preview unavailable', meetupState.error);
    } catch (error) {
      if (this.destroyed || sequence !== this.loadSequence) return;
      console.error('[gyms] load failed', error);
      this.setData({
        loading: false,
        error: error.message || '岩馆列表加载失败'
      });
    }
  },

  retry() { this.load({ force: true }); },

  chooseCity(e) {
    const cityIndex = Number(e.detail.value);
    pageCache.write(CITIES_CACHE_KEY, { cities: this.data.cities, cityIndex });
    this.setData({ cityIndex });
    this.load();
  },

  open(e) {
    const city = selectedCity(this.data.cities, this.data.cityIndex);
    wx.navigateTo({
      url: brandPageUrl(e.currentTarget.dataset.id, city)
    });
  },

  goMeetups() {
    wx.navigateTo({ url: '/pages/meetups/index' });
  }
});
