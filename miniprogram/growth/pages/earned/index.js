const growth = require('../../../utils/growth');
const { afterPaint, haptic, prefersReducedMotion } = require('../../../utils/motion');
const { playFeedback, stopFeedback, badgeSoundEnabled, setBadgeSoundEnabled } = require('../../../utils/sound');

Page({
  data: { loading: true, error: '', badge: null, count: 1, animate: false, reduced: false, soundEnabled: false, replay: false },
  onLoad(options = {}) { this._replayLevel = Number(options.replayLevel) || 0; this._sequence = 0; this._played = false; },
  onShow() { this._visible = true; this.load(); },
  onHide() { this._visible = false; this._sequence += 1; this.stop(); },
  onUnload() { this._visible = false; this._sequence += 1; this.stop(); growth.clearPresentation(); },
  stop() { if (this._timer) clearTimeout(this._timer); stopFeedback(); },
  async load() {
    const owner = growth.session();
    if (this._ownerToken !== owner.token) { this._played = false; this.setData({ badge: null, error: '', loading: true, animate: false }); }
    this._ownerToken = owner.token;
    const sequence = ++this._sequence;
    const presentation = growth.presentation();
    const level = this._replayLevel || (presentation && presentation.toLevel);
    this.setData({ soundEnabled: badgeSoundEnabled(), reduced: prefersReducedMotion(), replay: Boolean(this._replayLevel) });
    if (!owner.userId || !level) return this.setData({ loading: false, badge: null, error: '徽章已保存在你的徽章册中。' });
    try {
      const result = await growth.badges();
      if (!this._visible || sequence !== this._sequence) return;
      if (!growth.isCurrent(owner)) return this.setData({ loading: false, badge: null, error: '登录账号已变化，请返回重新查看。' });
      if (!this._replayLevel && !growth.presentation()) return this.setData({ loading: false, badge: null, error: '成长记录已更新，请到徽章册查看当前状态。' });
      const badge = result && result.badges.find(item => item.level === level && item.status === 'earned');
      if (!badge) return this.setData({ loading: false, badge: null, error: '成长记录已更新，请到徽章册查看当前状态。' });
      this.setData({ loading: false, badge, error: '', count: presentation ? presentation.newBadgeCount : 1 });
    } catch (_) {
      if (this._visible && sequence === this._sequence) this.setData({ loading: false, badge: growth.isCurrent(owner) ? this.data.badge : null, error: growth.isCurrent(owner) ? '徽章状态暂时没加载出来，请重试。' : '登录账号已变化，请返回重新查看。' });
    }
  },
  badgeReady() { if (!this._played) this.replay(); },
  replay() {
    if (!this.data.badge || !this._visible) return;
    this.stop();
    this._played = true;
    this.setData({ animate: false }, () => {
      this._timer = afterPaint(() => {
        if (!this._visible) return;
        this.setData({ animate: !this.data.reduced });
        haptic('success');
        playFeedback('badge');
      });
    });
  },
  toggleSound(event) {
    const enabled = Boolean(event.detail.value);
    setBadgeSoundEnabled(enabled);
    this.setData({ soundEnabled: enabled });
    if (!enabled) stopFeedback();
  },
  close() {
    this.stop();
    growth.clearPresentation();
    wx.navigateBack({ fail: () => wx.switchTab({ url: '/pages/profile/index' }) });
  },
  collection() { this.stop(); growth.clearPresentation(); wx.redirectTo({ url: '/growth/pages/badges/index' }); }
});
