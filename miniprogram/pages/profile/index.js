const { request } = require('../../utils/api');
Page({
  data: { me: null, growth: [], byGrade: [], byGym: [], cycles: [], unread: 0, max: 1, loading: true, error: '', month: '', monthLabel: '', calendar: [], dashboard: null, selectedDay: null },
  onLoad() { this.load(); },
  onShow() { if (this.hasLoaded) this.load(); },
  currentMonth() { const now = new Date(); return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`; },
  buildCalendar(month, records) {
    const [year, monthNumber] = month.split('-').map(Number);
    const firstWeekday = new Date(year, monthNumber - 1, 1).getDay();
    const daysInMonth = new Date(year, monthNumber, 0).getDate();
    const previousDays = new Date(year, monthNumber - 1, 0).getDate();
    const recordMap = {};
    records.forEach(item => { if (!recordMap[item.day]) recordMap[item.day] = { day: item.day, sends: 0, details: [] }; recordMap[item.day].sends += item.sends; recordMap[item.day].details.push(item); });
    const calendar = [];
    for (let index = 0; index < 42; index += 1) {
      const current = index - firstWeekday + 1;
      let number = current; let muted = false; let date = '';
      if (current < 1) { number = previousDays + current; muted = true; }
      else if (current > daysInMonth) { number = current - daysInMonth; muted = true; }
      else date = `${month}-${String(current).padStart(2, '0')}`;
      const record = recordMap[date];
      calendar.push({ number, muted, date, active: Boolean(record), sends: record ? record.sends : 0, details: record ? record.details : [] });
    }
    return calendar;
  },
  async loadDashboard(month) {
    const dashboard = await request(`/users/me/month-dashboard?month=${month}`);
    const calendar = this.buildCalendar(month, dashboard.days);
    this.setData({ month, monthLabel: `${Number(month.slice(0, 4))}年${Number(month.slice(5))}月`, dashboard, calendar, selectedDay: null });
  },
  async load() {
    if (this.loadingPromise) return this.loadingPromise;
    this.setData({ loading: true, error: '' });
    this.loadingPromise = (async () => { try {
      const month = this.data.month || this.currentMonth();
      const [me, growth, summary, cycleData, notifications, dashboard] = await Promise.all([request('/users/me'), request('/users/me/growth'), request('/users/me/growth-summary'), request('/users/me/cycle-summary'), request('/notifications'), request(`/users/me/month-dashboard?month=${month}`)]);
      const byGrade = Array.isArray(summary.byGrade) ? summary.byGrade : [];
      const byGym = Array.isArray(summary.byGym) ? summary.byGym : [];
      const cycleItems = Array.isArray(cycleData.items) ? cycleData.items : [];
      const dashboardDays = Array.isArray(dashboard.days) ? dashboard.days : [];
      const max = Math.max(1, ...byGrade.map(x => x.sends));
      const cycleMap = {};
      cycleItems.forEach(item => { const key = item.route_set_id; if (!cycleMap[key]) cycleMap[key] = { id: key, gymName: item.gym_name, setName: item.route_set_name, startsOn: item.starts_on, grades: [] }; cycleMap[key].grades.push({ grade: item.grade, sends: item.sends }); });
      this.setData({ me, growth: Array.isArray(growth.items) ? growth.items : [], byGrade, byGym, cycles: Object.values(cycleMap), unread: notifications.unread || 0, max, loading: false, month, monthLabel: `${Number(month.slice(0, 4))}年${Number(month.slice(5))}月`, dashboard, calendar: this.buildCalendar(month, dashboardDays) });
    } catch (error) {
      console.error('[profile] load failed', error);
      this.setData({ loading: false, error: error.message || '成长记录加载失败，请点击重试' });
    } finally {
      this.hasLoaded = true;
      this.loadingPromise = null;
    } })();
    return this.loadingPromise;
  },
  retry() { this.load(); },
  async changeMonth(offset) { const [year, month] = this.data.month.split('-').map(Number); const date = new Date(year, month - 1 + offset, 1); const next = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`; await this.loadDashboard(next); },
  previousMonth() { this.changeMonth(-1); },
  nextMonth() { this.changeMonth(1); },
  selectDay(e) { const item = e.currentTarget.dataset.item; if (!item.muted) this.setData({ selectedDay: item.active ? item : null }); },
  meetups() { wx.navigateTo({ url: '/pages/meetups/index' }); },
  friends() { wx.navigateTo({ url: '/pages/friends/index' }); },
  edit() { wx.navigateTo({ url: '/pages/profile-edit/index' }); },
  submissions() { wx.navigateTo({ url: '/pages/submissions/index' }); },
  admin() { wx.navigateTo({ url: '/pages/admin/index' }); },
  notifications() { wx.navigateTo({ url: '/pages/notifications/index' }); },
  posts() { wx.navigateTo({ url: '/pages/my-posts/index' }); },
  settings() { wx.navigateTo({ url: '/pages/settings/index' }); }
});
