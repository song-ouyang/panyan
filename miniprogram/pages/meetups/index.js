const { request } = require('../../utils/api');
const { read, write, loadOnce, invalidate } = require('../../utils/page-cache');
const { haptic } = require('../../utils/motion');

const CREATE_ENTER_DELAY_MS = 20;
const CREATE_EXIT_MS = 180;
const CREATE_SUCCESS_HOLD_MS = 320;
const JOIN_CONFIRM_MS = 420;
const MEETUPS_CACHE_TTL_MS = 30000;
const MEETUPS_META_CACHE_KEY = 'meetups:meta';

Page({
  data: {
    items: [],
    gyms: [],
    me: null,
    loading: true,
    error: '',
    submitting: false,
    createComplete: false,
    joiningIds: {},
    joiningSuccessIds: {},
    createMounted: false,
    createVisible: false,
    tab: 'all',
    gymIndex: -1,
    title: '',
    date: '',
    minDate: '',
    time: '19:30',
    maxPeople: 4,
    note: ''
  },

  onLoad() {
    const now = new Date();
    this.loadSequence = 0;
    this._disposed = false;
    this.setData({
      minDate: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`
    });
  },

  onShow() {
    this._disposed = false;
    this.load({ background: true });
  },

  onHide() {
    this.loadSequence += 1;
    clearTimeout(this.createEnterTimer);
    clearTimeout(this.createSuccessTimer);
    Object.values(this.joinSuccessTimers || {}).forEach(clearTimeout);
  },

  onUnload() {
    this._disposed = true;
    this.loadSequence += 1;
    clearTimeout(this.createEnterTimer);
    clearTimeout(this.createExitTimer);
    clearTimeout(this.createSuccessTimer);
    Object.values(this.joinSuccessTimers || {}).forEach(clearTimeout);
  },

  meetupsCacheKey(tab = this.data.tab) {
    return `meetups:list:${tab}`;
  },

  normalizeMeetups(data) {
    return (data && Array.isArray(data.items) ? data.items : []).map(item => ({
      ...item,
      starts_at_text: this.formatDate(item.starts_at),
      expired: new Date(item.starts_at).getTime() <= Date.now(),
      full: item.member_count >= item.max_people
    }));
  },

  applyMeetups(data, cacheKey) {
    if (this._disposed) return;
    this._displayedMeetupsKey = cacheKey;
    this.setData({
      items: this.normalizeMeetups(data),
      loading: false,
      error: ''
    });
  },

  applyMeetupMeta(data) {
    if (this._disposed || !data) return;
    this.setData({
      gyms: data.gyms && Array.isArray(data.gyms.items) ? data.gyms.items : [],
      me: data.me || null
    });
  },

  invalidateMeetups() {
    invalidate(this.meetupsCacheKey('all'));
    invalidate(this.meetupsCacheKey('mine'));
  },

  load(options = {}) {
    const { force = false, background = false } = options;
    const sequence = ++this.loadSequence;
    const tab = this.data.tab;
    const path = tab === 'mine' ? '/meetups?mine=true' : '/meetups';
    const cacheKey = this.meetupsCacheKey(tab);
    const listCache = force ? null : read(cacheKey, MEETUPS_CACHE_TTL_MS);
    const metaCache = force ? null : read(MEETUPS_META_CACHE_KEY, MEETUPS_CACHE_TTL_MS);

    if (listCache && this._displayedMeetupsKey !== cacheKey) {
      this.applyMeetups(listCache.value, cacheKey);
    }
    if (metaCache && (!this.data.gyms.length || !this.data.me)) {
      this.applyMeetupMeta(metaCache.value);
    }
    if (listCache && listCache.fresh && metaCache && metaCache.fresh) {
      return Promise.resolve([listCache.value, metaCache.value]);
    }

    const hasVisibleList = this._displayedMeetupsKey === cacheKey;
    if (!hasVisibleList) {
      this.setData({ items: [], loading: true, error: '' });
    } else if (!background) {
      this.setData({ error: '' });
    }

    if (force) {
      invalidate(cacheKey);
      invalidate(MEETUPS_META_CACHE_KEY);
    }
    const listLoader = () => request(path);
    const metaLoader = () => Promise.all([request('/gyms'), request('/users/me')])
      .then(([gyms, me]) => ({ gyms, me }));
    const listTask = listCache && listCache.fresh
      ? Promise.resolve(listCache.value)
      : (force ? listLoader() : loadOnce(cacheKey, listLoader));
    const metaTask = metaCache && metaCache.fresh
      ? Promise.resolve(metaCache.value)
      : (force ? metaLoader() : loadOnce(MEETUPS_META_CACHE_KEY, metaLoader));

    return Promise.all([listTask, metaTask])
      .then(([meetups, meta]) => {
        if (this._disposed || sequence !== this.loadSequence) return null;
        write(cacheKey, meetups);
        write(MEETUPS_META_CACHE_KEY, meta);
        this.applyMeetups(meetups, cacheKey);
        this.applyMeetupMeta(meta);
        return [meetups, meta];
      })
      .catch(error => {
        if (this._disposed || sequence !== this.loadSequence) return null;
        this.setData({
          loading: false,
          error: error.message || '约爬加载失败，请稍后重试'
        });
        return null;
      });
  },

  retry() { this.load({ force: true }); },

  onPullDownRefresh() {
    return this.load({ force: true })
      .finally(() => wx.stopPullDownRefresh());
  },

  formatDate(value) {
    const date = new Date(value);
    const weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return `${date.getMonth() + 1}月${date.getDate()}日 ${weekdays[date.getDay()]} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  },

  changeTab(e) {
    const tab = e.currentTarget.dataset.tab;
    if (tab === this.data.tab) return;
    this.setData({ tab, error: '' });
    this.load({ background: true });
  },

  toggle() {
    if (this.data.createVisible) this.closeCreate(false);
    else this.openCreate();
  },

  openCreate() {
    clearTimeout(this.createEnterTimer);
    clearTimeout(this.createExitTimer);
    if (this.data.createMounted) {
      this.setData({ createVisible: true, createComplete: false });
      return;
    }
    this.setData({ createMounted: true, createVisible: false, createComplete: false });
    this.createEnterTimer = setTimeout(() => {
      if (this._disposed) return;
      this.setData({ createVisible: true });
    }, CREATE_ENTER_DELAY_MS);
  },

  closeCreate(resetForm = false, force = false) {
    if ((this.data.submitting || this.data.createComplete) && !force) return;
    clearTimeout(this.createEnterTimer);
    clearTimeout(this.createExitTimer);
    this.setData({ createVisible: false });
    this.createExitTimer = setTimeout(() => {
      if (this._disposed || this.data.createVisible) return;
      const next = { createMounted: false };
      if (resetForm) {
        Object.assign(next, {
          title: '',
          date: '',
          time: '19:30',
          maxPeople: 4,
          note: '',
          gymIndex: -1
        });
      }
      this.setData(next);
    }, CREATE_EXIT_MS);
  },

  dismissCreate() { this.closeCreate(false); },

  blockBackgroundScroll() {},

  bind(e) { this.setData({ [e.currentTarget.dataset.key]: e.detail.value }); },
  gym(e) { this.setData({ gymIndex: Number(e.detail.value) }); },
  date(e) { this.setData({ date: e.detail.value }); },
  time(e) { this.setData({ time: e.detail.value }); },

  changePeople(e) {
    const next = Math.min(50, Math.max(2, this.data.maxPeople + Number(e.currentTarget.dataset.step)));
    this.setData({ maxPeople: next });
  },

  async create() {
    if (this.data.submitting) return;
    const gym = this.data.gyms[this.data.gymIndex];
    const title = this.data.title.trim();
    if (!title || title.length < 2) return wx.showToast({ title: '请填写约爬主题', icon: 'none' });
    if (!gym) return wx.showToast({ title: '请选择岩馆', icon: 'none' });
    if (!this.data.date) return wx.showToast({ title: '请选择日期', icon: 'none' });

    const startsAt = new Date(`${this.data.date}T${this.data.time}:00+08:00`);
    if (startsAt.getTime() <= Date.now()) return wx.showToast({ title: '约爬时间必须晚于现在', icon: 'none' });

    this.setData({ submitting: true, createComplete: false });
    try {
      await request('/meetups', {
        method: 'POST',
        data: {
          gymId: gym.id,
          title,
          startsAt: startsAt.toISOString(),
          maxPeople: Number(this.data.maxPeople),
          note: this.data.note.trim()
        }
      });
      this.setData({ submitting: false, createComplete: true });
      haptic('success');
      this.invalidateMeetups();
      clearTimeout(this.createSuccessTimer);
      this.createSuccessTimer = setTimeout(() => {
        if (this._disposed) return;
        this.closeCreate(true, true);
        this.setData({ tab: 'mine' }, () => this.load({ force: true, background: true }));
      }, CREATE_SUCCESS_HOLD_MS);
    } catch (error) {
      this.setData({ submitting: false });
      wx.showToast({ title: error.message || '发布失败', icon: 'none' });
    }
  },

  async join(e) {
    const id = e.currentTarget.dataset.id;
    if (!id || this.data.joiningIds[id]) return;
    const index = this.data.items.findIndex(item => item.id === id);
    if (index < 0) return;
    const previous = {
      joined: Boolean(this.data.items[index].joined),
      memberCount: Number(this.data.items[index].member_count) || 0,
      full: Boolean(this.data.items[index].full)
    };
    const nextCount = Math.min(
      Number(this.data.items[index].max_people) || 0,
      previous.memberCount + 1
    );
    const joiningIds = { ...this.data.joiningIds, [id]: true };
    this.setData({
      joiningIds,
      [`items[${index}].joined`]: true,
      [`items[${index}].member_count`]: nextCount,
      [`items[${index}].full`]: nextCount >= Number(this.data.items[index].max_people)
    });
    try {
      await request(`/meetups/${id}/join`, { method: 'POST' });
      if (this._disposed) return;
      const nextJoiningIds = { ...this.data.joiningIds };
      const joiningSuccessIds = { ...this.data.joiningSuccessIds, [id]: true };
      delete nextJoiningIds[id];
      this.setData({ joiningIds: nextJoiningIds, joiningSuccessIds });
      haptic('success');
      this.invalidateMeetups();
      if (!this.joinSuccessTimers) this.joinSuccessTimers = {};
      clearTimeout(this.joinSuccessTimers[id]);
      this.joinSuccessTimers[id] = setTimeout(() => {
        if (this._disposed) return;
        const successIds = { ...this.data.joiningSuccessIds };
        delete successIds[id];
        delete this.joinSuccessTimers[id];
        this.setData({ joiningSuccessIds: successIds });
      }, JOIN_CONFIRM_MS);
    } catch (error) {
      const rollbackIndex = this.data.items.findIndex(item => item.id === id);
      const nextJoiningIds = { ...this.data.joiningIds };
      delete nextJoiningIds[id];
      const rollback = { joiningIds: nextJoiningIds };
      if (rollbackIndex >= 0) {
        rollback[`items[${rollbackIndex}].joined`] = previous.joined;
        rollback[`items[${rollbackIndex}].member_count`] = previous.memberCount;
        rollback[`items[${rollbackIndex}].full`] = previous.full;
      }
      if (!this._disposed) this.setData(rollback);
      wx.showToast({ title: error.message || '加入失败', icon: 'none' });
    } finally {
      const nextJoiningIds = { ...this.data.joiningIds };
      delete nextJoiningIds[id];
      if (!this._disposed) this.setData({ joiningIds: nextJoiningIds });
    }
  },

  leave(e) {
    if (this.data.joiningIds[e.currentTarget.dataset.id]) return;
    wx.showModal({
      title: '退出约爬',
      content: '确定退出这次约爬吗？',
      success: async res => {
        if (!res.confirm) return;
        try {
          await request(`/meetups/${e.currentTarget.dataset.id}/join`, { method: 'DELETE' });
          wx.showToast({ title: '已退出' });
          this.invalidateMeetups();
          this.load({ force: true, background: true });
        } catch (error) {
          wx.showToast({ title: error.message || '退出失败', icon: 'none' });
        }
      }
    });
  },

  cancel(e) {
    wx.showModal({
      title: '取消约爬',
      content: '取消后会通知已经加入的岩友，确定继续吗？',
      confirmColor: '#d9533e',
      success: async res => {
        if (!res.confirm) return;
        try {
          await request(`/meetups/${e.currentTarget.dataset.id}`, { method: 'DELETE' });
          wx.showToast({ title: '已取消' });
          this.invalidateMeetups();
          this.load({ force: true, background: true });
        } catch (error) {
          wx.showToast({ title: error.message || '取消失败', icon: 'none' });
        }
      }
    });
  }
});
