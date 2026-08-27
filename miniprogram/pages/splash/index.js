const { request, upload } = require('../../utils/api');
const { afterPaint, haptic, motionDuration } = require('../../utils/motion');

const STARTUP_BUDGET_MS = 420;
const FIRST_PROFILE_CHECK_BUDGET_MS = 1200;
const PROFILE_EXIT_MS = 220;

Page({
  data: {
    preparing: true,
    prepared: false,
    introVisible: false,
    showProfile: false,
    profileMounted: false,
    profileVisible: false,
    profileError: '',
    nickname: '',
    avatarUrl: '',
    saving: false,
  },
  onReady() {
    this.readyAt = Date.now();
    this.introTimer = afterPaint(() => {
      if (!this._disposed) this.setData({ introVisible: true });
    });
    this.profileKnownAtLaunch = Boolean(
      wx.getStorageSync('profileSetupComplete') || wx.getStorageSync('profilePromptSkipped')
    );
    this.scheduleStartup(
      this.profileKnownAtLaunch ? STARTUP_BUDGET_MS : FIRST_PROFILE_CHECK_BUDGET_MS,
      this.profileKnownAtLaunch
    );
    this.prepare();
  },
  onUnload() {
    this._disposed = true;
    if (this.timer) clearTimeout(this.timer);
    if (this.introTimer) clearTimeout(this.introTimer);
    if (this.profileTimer) clearTimeout(this.profileTimer);
    if (this.dismissTimer) clearTimeout(this.dismissTimer);
    if (this.startupTimer) clearTimeout(this.startupTimer);
  },
  scheduleStartup(delay, autoEnter = false) {
    if (this.startupTimer) clearTimeout(this.startupTimer);
    this.startupTimer = setTimeout(() => this.releaseStartup(autoEnter), Math.max(0, delay));
  },
  releaseStartup(autoEnter = false) {
    if (this._disposed || this.entered || this.data.showProfile || this.data.prepared) return;
    this.setData({ preparing: false, prepared: true }, () => {
      if (autoEnter) this.enter();
    });
  },
  async prepare() {
    try {
      const me = await request('/users/me');
      if (this._disposed || this.entered) return;
      const incomplete = !me.avatar_url || !me.nickname || me.nickname === '岩友';
      if (incomplete && !wx.getStorageSync('profilePromptSkipped')) {
        wx.removeStorageSync('profileSetupComplete');
        if (this.startupTimer) clearTimeout(this.startupTimer);
        this.setData({ preparing: false, prepared: true, showProfile: true, profileMounted: true, nickname: me.nickname === '岩友' ? '' : me.nickname, avatarUrl: me.avatar_url || '' });
        this.profileTimer = afterPaint(() => {
          if (!this._disposed && !this.entered) this.setData({ profileVisible: true });
        });
        return;
      }
      if (!incomplete) wx.setStorageSync('profileSetupComplete', true);
    } catch (error) { console.error('[splash] profile check failed', error); }
    if (this._disposed || this.entered) return;
    const elapsed = Date.now() - this.readyAt;
    this.scheduleStartup(STARTUP_BUDGET_MS - elapsed, Boolean(wx.getStorageSync('profileSetupComplete')));
  },
  chooseAvatar(e) { this.setData({ avatarUrl: e.detail.avatarUrl, profileError: '' }); },
  nickname(e) { this.setData({ nickname: e.detail.value, profileError: '' }); },
  async saveProfile() {
    if (!this.data.nickname.trim()) return this.setData({ profileError: '请输入昵称' });
    if (!this.data.avatarUrl) return this.setData({ profileError: '请选择头像' });
    this.setData({ saving: true, profileError: '' });
    try {
      let avatarUrl = this.data.avatarUrl;
      if (!/^https?:/.test(avatarUrl)) avatarUrl = (await upload(avatarUrl)).url;
      if (this._disposed) return;
      await request('/users/me', { method: 'PATCH', data: { nickname: this.data.nickname.trim(), avatarUrl, bio: null } });
      if (this._disposed) return;
      wx.setStorageSync('profileSetupComplete', true);
      wx.removeStorageSync('profilePromptSkipped');
      haptic('success');
      wx.showToast({ title: '欢迎加入', icon: 'success' });
      this.setData({ saving: false });
      this.dismissProfile(() => this.enter());
    } catch (error) {
      if (!this._disposed) this.setData({ saving: false, profileError: error.message || '资料保存失败，请重试' });
    }
  },
  dismissProfile(afterDismiss) {
    if (this.dismissTimer) clearTimeout(this.dismissTimer);
    if (this.profileTimer) clearTimeout(this.profileTimer);
    this.setData({ showProfile: false, profileVisible: false });
    this.dismissTimer = setTimeout(() => {
      if (this._disposed) return;
      this.setData({ profileMounted: false });
      if (afterDismiss) afterDismiss();
    }, motionDuration(PROFILE_EXIT_MS, 140));
  },
  skip() {
    if (this.data.saving) return;
    wx.removeStorageSync('profileSetupComplete');
    wx.setStorageSync('profilePromptSkipped', true);
    this.dismissProfile(() => this.enter());
  },
  enter() {
    if (this._disposed || this.entered || this.data.preparing || !this.data.prepared || this.data.showProfile) return;
    this.entered = true;
    if (this.timer) clearTimeout(this.timer);
    wx.switchTab({ url: '/pages/gyms/index' });
  }
});
