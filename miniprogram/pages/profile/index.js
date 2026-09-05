const { request } = require('../../utils/api');
const pageCache = require('../../utils/page-cache');
const { afterPaint } = require('../../utils/motion');

const PROFILE_CACHE_KEY = 'profile:overview';
const PROFILE_TTL = 60 * 1000;
const DASHBOARD_TTL = 60 * 1000;

function dashboardCacheKey(month) {
  return `profile:dashboard:${month}`;
}

Page({
  data: {
    me: null,
    growth: [],
    byGrade: [],
    byGym: [],
    cycles: [],
    unread: 0,
    max: 1,
    loading: true,
    error: '',
    month: '',
    monthLabel: '',
    calendar: [],
    dashboard: null,
    dashboardLoading: false,
    dashboardError: '',
    monthChanging: false,
    selectedDay: null,
    dayDetailMounted: false,
    dayDetailVisible: false,
    showMore: false,
    moreMounted: false,
    moreVisible: false,
    progressReveal: true,
  },

  onLoad() {
    this.destroyed = false;
    this._pageRequestId = 0;
    this._dashboardRequestId = 0;
    this._revealedDashboardMonths = Object.create(null);
    const overviewCache = pageCache.read(PROFILE_CACHE_KEY, PROFILE_TTL);
    if (overviewCache) this.setData({ ...overviewCache.value, loading: false, error: '' });

    const month = this.currentMonth();
    const dashboardCache = pageCache.read(dashboardCacheKey(month), DASHBOARD_TTL);
    if (dashboardCache) this.applyDashboard(month, dashboardCache.value);
  },

  onShow() {
    this.destroyed = false;
    this.load();
  },

  onHide() {
    this._pageRequestId += 1;
    this._dashboardRequestId += 1;
    this.loadingPromise = null;
    if (this._progressRevealTimer) {
      clearTimeout(this._progressRevealTimer);
      this._progressRevealTimer = null;
    }
    if (!this.data.progressReveal && this.data.dashboard) this.setData({ progressReveal: true });
  },

  onPullDownRefresh() {
    Promise.resolve(this.load({ force: true }))
      .then(() => wx.stopPullDownRefresh(), () => wx.stopPullDownRefresh());
  },

  onUnload() {
    this.destroyed = true;
    this._pageRequestId += 1;
    this._dashboardRequestId += 1;
    if (this._dayDetailTimer) clearTimeout(this._dayDetailTimer);
    if (this._moreTimer) clearTimeout(this._moreTimer);
    if (this._progressRevealTimer) clearTimeout(this._progressRevealTimer);
  },

  currentMonth() {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  },

  monthLabel(month) {
    return `${Number(month.slice(0, 4))}年${Number(month.slice(5))}月`;
  },

  buildCalendar(month, records = []) {
    const [year, monthNumber] = month.split('-').map(Number);
    const firstWeekday = new Date(year, monthNumber - 1, 1).getDay();
    const daysInMonth = new Date(year, monthNumber, 0).getDate();
    const previousDays = new Date(year, monthNumber - 1, 0).getDate();
    const recordMap = {};

    records.forEach((item) => {
      if (!recordMap[item.day]) recordMap[item.day] = { day: item.day, sends: 0, details: [] };
      recordMap[item.day].sends += item.sends;
      recordMap[item.day].details.push({
        ...item,
        key: `${item.day}-${item.gym_name}-${item.grade}`,
      });
    });

    const calendar = [];
    for (let index = 0; index < 42; index += 1) {
      const current = index - firstWeekday + 1;
      let number = current;
      let muted = false;
      let date = '';
      if (current < 1) {
        number = previousDays + current;
        muted = true;
      } else if (current > daysInMonth) {
        number = current - daysInMonth;
        muted = true;
      } else {
        date = `${month}-${String(current).padStart(2, '0')}`;
      }
      const record = recordMap[date];
      calendar.push({
        key: date || `${month}-slot-${index}`,
        number,
        muted,
        date,
        active: Boolean(record),
        sends: record ? record.sends : 0,
        details: record ? record.details : [],
      });
    }
    return calendar;
  },

  normalizeCycles(cycleItems = []) {
    const cycleMap = {};
    cycleItems.forEach((item) => {
      const key = item.route_set_id;
      if (!cycleMap[key]) {
        cycleMap[key] = {
          id: key,
          gymName: item.gym_name,
          setName: item.route_set_name,
          startsOn: item.starts_on,
          grades: [],
        };
      }
      cycleMap[key].grades.push({ grade: item.grade, sends: item.sends });
    });
    return Object.values(cycleMap);
  },

  queueProgressReveal(month) {
    if (this._progressRevealTimer) clearTimeout(this._progressRevealTimer);
    this._progressRevealTimer = afterPaint(() => {
      this._progressRevealTimer = null;
      if (!this.destroyed && this.data.month === month) this.setData({ progressReveal: true });
    });
  },

  applyDashboard(month, dashboard) {
    const days = Array.isArray(dashboard.days) ? dashboard.days : [];
    const totalSends = Math.max(0, Number(dashboard.summary && dashboard.summary.sends) || 0);
    const safeDashboard = {
      ...dashboard,
      summary: { ...(dashboard.summary || {}), sends: totalSends },
      byGrade: (Array.isArray(dashboard.byGrade) ? dashboard.byGrade : []).map(item => ({
        ...item,
        percentage: totalSends ? Math.min(100, Math.max(0, (Number(item.sends) || 0) / totalSends * 100)) : 0,
      })),
    };
    if (!this._revealedDashboardMonths) this._revealedDashboardMonths = Object.create(null);
    const shouldRevealProgress = Boolean(
      safeDashboard.byGrade.length && !this._revealedDashboardMonths[month]
    );
    if (shouldRevealProgress) this._revealedDashboardMonths[month] = true;
    this._targetMonth = month;
    this.setData({
      month,
      monthLabel: this.monthLabel(month),
      dashboard: safeDashboard,
      calendar: this.buildCalendar(month, days),
      selectedDay: null,
      dayDetailMounted: false,
      dayDetailVisible: false,
      dashboardError: '',
      progressReveal: !shouldRevealProgress,
    }, () => {
      if (!shouldRevealProgress || this.destroyed) return;
      this.queueProgressReveal(month);
    });
  },

  async loadDashboard(month, { force = false } = {}) {
    const requestId = ++this._dashboardRequestId;
    const cacheKey = dashboardCacheKey(month);
    const dashboardCache = pageCache.read(cacheKey, DASHBOARD_TTL);
    if (dashboardCache) this.applyDashboard(month, dashboardCache.value);
    if (!force && dashboardCache && dashboardCache.fresh) return;

    if (!dashboardCache) this.setData({ dashboardLoading: true, dashboardError: '', monthChanging: true });
    try {
      const dashboard = await pageCache.loadOnce(
        cacheKey,
        () => request(`/users/me/month-dashboard?month=${month}`),
      );
      pageCache.write(cacheKey, dashboard);
      if (this.destroyed || requestId !== this._dashboardRequestId) return;
      this.applyDashboard(month, dashboard);
    } catch (error) {
      if (this.destroyed || requestId !== this._dashboardRequestId) return;
      console.error('[profile] dashboard load failed', error);
      this.setData({ dashboardError: error.message || '本月记录加载失败，请稍后重试' });
    } finally {
      if (requestId === this._dashboardRequestId) {
        if (!this.destroyed) this.setData({ dashboardLoading: false, monthChanging: false });
      }
    }
  },

  async load({ force = false } = {}) {
    if (this.loadingPromise) return this.loadingPromise;
    const requestId = ++this._pageRequestId;
    const dashboardRequestId = ++this._dashboardRequestId;
    const month = this.data.month || this.currentMonth();
    const overviewCache = pageCache.read(PROFILE_CACHE_KEY, PROFILE_TTL);
    const dashboardKey = dashboardCacheKey(month);
    const dashboardCache = pageCache.read(dashboardKey, DASHBOARD_TTL);

    if (overviewCache && !this.data.me) {
      this.setData({ ...overviewCache.value, loading: false, error: '' });
    }
    if (dashboardCache && (!this.data.dashboard || this.data.month !== month)) {
      this.applyDashboard(month, dashboardCache.value);
    }
    if (!force && overviewCache && overviewCache.fresh && dashboardCache && dashboardCache.fresh) return;

    if (!this.data.me) this.setData({ loading: true, error: '', dashboardError: '' });
    else if (this.data.error || this.data.dashboardError) this.setData({ error: '', dashboardError: '' });

    this.loadingPromise = (async () => {
      try {
        const dashboardResult = (!force && dashboardCache && dashboardCache.fresh
          ? Promise.resolve(dashboardCache.value)
          : pageCache.loadOnce(
            dashboardKey,
            () => request(`/users/me/month-dashboard?month=${month}`),
          ).then(value => pageCache.write(dashboardKey, value)))
          .then(value => ({ ok: true, value }))
          .catch(error => ({ ok: false, error }));
        const overviewTask = !force && overviewCache && overviewCache.fresh
          ? Promise.resolve(overviewCache.value)
          : pageCache.loadOnce(PROFILE_CACHE_KEY, async () => {
            const [me, growth, summary, cycleData, notifications] = await Promise.all([
              request('/users/me'),
              request('/users/me/growth'),
              request('/users/me/growth-summary'),
              request('/users/me/cycle-summary'),
              request('/notifications'),
            ]);
            const byGrade = Array.isArray(summary.byGrade) ? summary.byGrade : [];
            const byGym = Array.isArray(summary.byGym) ? summary.byGym : [];
            const cycleItems = Array.isArray(cycleData.items) ? cycleData.items : [];
            return {
              me,
              growth: Array.isArray(growth.items) ? growth.items : [],
              byGrade,
              byGym,
              cycles: this.normalizeCycles(cycleItems),
              unread: notifications.unread || 0,
              max: Math.max(1, ...byGrade.map(item => item.sends)),
            };
          }).then(value => pageCache.write(PROFILE_CACHE_KEY, value));
        const [overview, dashboardState] = await Promise.all([overviewTask, dashboardResult]);
        if (this.destroyed || requestId !== this._pageRequestId) return;

        const nextData = { loading: false };
        let shouldRevealProgress = false;
        if (force || !overviewCache || !overviewCache.fresh || !this.data.me) {
          Object.assign(nextData, overview);
        }

        if (dashboardRequestId === this._dashboardRequestId && dashboardState.ok) {
          const dashboard = dashboardState.value;
          const totalSends = Math.max(0, Number(dashboard.summary && dashboard.summary.sends) || 0);
          nextData.month = month;
          nextData.monthLabel = this.monthLabel(month);
          nextData.dashboard = {
            ...dashboard,
            summary: { ...(dashboard.summary || {}), sends: totalSends },
            byGrade: (Array.isArray(dashboard.byGrade) ? dashboard.byGrade : []).map(item => ({
              ...item,
              percentage: totalSends ? Math.min(100, Math.max(0, (Number(item.sends) || 0) / totalSends * 100)) : 0,
            })),
          };
          if (!this._revealedDashboardMonths) this._revealedDashboardMonths = Object.create(null);
          shouldRevealProgress = Boolean(
            nextData.dashboard.byGrade.length && !this._revealedDashboardMonths[month]
          );
          if (shouldRevealProgress) this._revealedDashboardMonths[month] = true;
          nextData.progressReveal = !shouldRevealProgress;
          nextData.calendar = this.buildCalendar(month, Array.isArray(dashboard.days) ? dashboard.days : []);
          nextData.dashboardError = '';
          this._targetMonth = month;
        } else if (dashboardRequestId === this._dashboardRequestId) {
          nextData.month = month;
          nextData.monthLabel = this.monthLabel(month);
          nextData.dashboardError = dashboardState.error.message || '本月记录加载失败，请点击重试';
        }
        this.setData(nextData, () => {
          if (shouldRevealProgress && !this.destroyed) this.queueProgressReveal(month);
        });
      } catch (error) {
        if (this.destroyed || requestId !== this._pageRequestId) return;
        console.error('[profile] load failed', error);
        this.setData({
          loading: false,
          error: this.data.me ? '' : (error.message || '成长记录加载失败，请点击重试'),
        });
      } finally {
        if (requestId === this._pageRequestId) {
          this.loadingPromise = null;
        }
      }
    })();
    return this.loadingPromise;
  },

  retry() {
    this.load({ force: true });
  },

  retryDashboard() {
    this.loadDashboard(this.data.month || this.currentMonth(), { force: true });
  },

  changeMonth(offset) {
    const baseMonth = this._targetMonth || this.data.month;
    if (!baseMonth) return;
    const [year, month] = baseMonth.split('-').map(Number);
    const date = new Date(year, month - 1 + offset, 1);
    const next = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
    this._targetMonth = next;
    this.loadDashboard(next);
  },

  previousMonth() {
    this.changeMonth(-1);
  },

  nextMonth() {
    this.changeMonth(1);
  },

  selectDay(e) {
    const item = e.currentTarget.dataset.item;
    if (!item || item.muted || !item.active) return;
    if (this._dayDetailTimer) clearTimeout(this._dayDetailTimer);
    if (this.data.selectedDay && this.data.selectedDay.date === item.date) {
      this.setData({ dayDetailVisible: false });
      this._dayDetailTimer = setTimeout(() => {
        this.setData({ selectedDay: null, dayDetailMounted: false });
      }, 160);
      return;
    }
    if (this.data.dayDetailMounted) {
      this.setData({ selectedDay: item, dayDetailVisible: true });
      return;
    }
    this.setData({ selectedDay: item, dayDetailMounted: true, dayDetailVisible: false });
    this._dayDetailTimer = setTimeout(() => this.setData({ dayDetailVisible: true }), 20);
  },

  toggleMore() {
    if (this._moreTimer) clearTimeout(this._moreTimer);
    if (this.data.showMore) {
      this.setData({ showMore: false, moreVisible: false });
      this._moreTimer = setTimeout(() => this.setData({ moreMounted: false }), 160);
      return;
    }
    this.setData({ showMore: true, moreMounted: true, moreVisible: false });
    this._moreTimer = setTimeout(() => this.setData({ moreVisible: true }), 20);
  },

  meetups() { wx.navigateTo({ url: '/pages/meetups/index' }); },
  friends() { wx.navigateTo({ url: '/pages/friends/index' }); },
  edit() { wx.navigateTo({ url: '/pages/profile-edit/index' }); },
  submissions() { wx.navigateTo({ url: '/pages/submissions/index' }); },
  admin() { wx.navigateTo({ url: '/pages/admin/index' }); },
  notifications() { wx.navigateTo({ url: '/pages/notifications/index' }); },
  posts() { wx.navigateTo({ url: '/pages/my-posts/index' }); },
  activity(e) {
    const type = e.currentTarget.dataset.type;
    if (['comments', 'favorites', 'likes'].includes(type)) wx.navigateTo({ url: `/pages/activity/index?type=${type}` });
  },
  settings() { wx.navigateTo({ url: '/pages/settings/index' }); },
});
