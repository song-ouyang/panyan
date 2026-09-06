const growth = require('../../../utils/growth');
const { login } = require('../../../utils/api');

Page({
  data: { loading: true, guest: false, error: '', growth: null, badges: [] },
  onLoad() { this._sequence = 0; },
  onShow() { this._visible = true; this.load(); },
  onHide() { this._visible = false; this._sequence += 1; },
  onUnload() { this._visible = false; this._sequence += 1; },
  async load() {
    const sequence = ++this._sequence;
    const owner = growth.session();
    if (!owner.userId) return this.setData({ guest: true, loading: false, growth: null, badges: [], error: '' });
    if (this._ownerToken !== owner.token) this.setData({ growth: null, badges: [] });
    this._ownerToken = owner.token;
    this.setData({ guest: false, loading: true, error: '' });
    try {
      const result = await growth.badges();
      if (!this._visible || sequence !== this._sequence) return;
      if (!growth.isCurrent(owner)) return this.setData({ guest: true, loading: false, growth: null, badges: [] });
      if (!result) throw new Error('成长记录已更新，请重试');
      this.setData({ loading: false, growth: result.growth, badges: result.badges.map(item => ({ ...item, statusLabel: item.status === 'earned' ? '已获得' : item.status === 'revoked' ? '记录已撤销' : '待解锁', earnedDate: item.earnedAt ? item.earnedAt.slice(0, 10) : '' })) });
      await growth.presentPending(() => this._visible && sequence === this._sequence && growth.isCurrent(owner));
    } catch (error) {
      if (!this._visible || sequence !== this._sequence) return;
      if (!growth.isCurrent(owner)) return this.setData({ guest: true, loading: false, growth: null, badges: [] });
      this.setData({ loading: false, error: error.message || '徽章暂时没加载出来' });
    }
  },
  async signIn() {
    try { await login(); if (this._visible) await this.load(); }
    catch (_) { this.setData({ error: '登录没有完成，请重试' }); }
  },
  onPullDownRefresh() { return this.load().finally(() => wx.stopPullDownRefresh()); },
  openBadge(event) {
    const level = Number(event.currentTarget.dataset.level);
    const badge = this.data.badges.find(item => item.level === level);
    if (!badge) return;
    if (badge.status !== 'earned') {
      wx.showModal({ title: `Lv.${level} ${badge.name}`, content: `${badge.status === 'revoked' ? '相关记录已撤销，重新满足条件后可恢复。' : '同时满足两项条件即可自动获得。'}\n累计有效攀爬 ${badge.days} 天，并完攀 ${badge.routes} 条不同线路。`, showCancel: false });
      return;
    }
    wx.navigateTo({ url: `/growth/pages/earned/index?replayLevel=${level}` });
  }
});
